#!/usr/bin/env bash
# Behaviour test for scripts/create-environment.sh's fail-fast preflight.
#
# Runs the real script (and the real import-preexisting-resources.sh and
# lib/read-xcconfig-value.sh it reaches) against PATH-mocked cloud CLIs —
# gcloud, firebase, terraform, node, make — in a hermetic environment: `env -i`
# plus a self-contained PATH that holds only the mocks and symlinks to the few
# system tools the scripts need. There is no /usr/bin or /bin on that PATH, so a
# CLI preinstalled on a runner can never stand in for a mock. Every mock appends
# its argv to a call log.
#
# Each refusal must fire before the first cloud call (empty call log, tfvars
# absent or byte-identical) — or, for the checks that need a cloud read or link
# first (the project lookup, an existing project's state and parent, billing
# enabled), before the first mutation after it. Positive controls prove valid
# inputs still run end to end, so no refusal passes for an unrelated reason.
# Every run gets a private TMPDIR that must be empty when the run ends.
#
# Not yet listed in the Makefile's scripts-test target; until it is,
# scripts/test/write-environment-config.test.sh runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/create-environment.sh"

pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok - $*"; pass=$((pass + 1)); }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
BIN="$SANDBOX/bin"
mkdir -p "$BIN"
CALLS="$SANDBOX/calls"      # one line per mocked CLI invocation
CREATED="$SANDBOX/created"  # project ids the gcloud mock has "created"
CFG="$SANDBOX/sbx.xcconfig"
TFVARS="$SANDBOX/env/sbx.tfvars"
OUT="$SANDBOX/out"
TMPROOT="$SANDBOX/tmp"      # the script's TMPDIR; must be empty after every run
mkdir -p "$TMPROOT"
TOKEN="11111111-2222-4333-8444-555555555555"

# System tools the scripts run, linked one by one so PATH stays self-contained.
for tool in bash awk cat dirname grep mkdir mktemp rm sed tr; do
  real="$(command -v "$tool")"
  [[ "$real" == /* ]] || fail "test host lacks $tool"
  ln -s "$real" "$BIN/$tool"
done

# gcloud answers the calls the bootstrap makes. A project exists once created,
# or from the start with MOCK_PROJECT_EXISTS=1 (state from MOCK_LIFECYCLE, parent
# from MOCK_PARENT_TYPE / MOCK_PARENT_ID). A missing project gets the answer
# gcloud 592 really gives: the same permission error as a project this account
# cannot see. MOCK_DESCRIBE_ERROR makes every project lookup fail another way.
# MOCK_BILLING_ENABLED overrides the billingEnabled read-back (set it empty for
# an empty read). Any unexpected call fails loudly.
cat > "$BIN/gcloud" <<'SH'
#!/usr/bin/env bash
echo "gcloud $*" >> "$CALLS"
args="$*"
case "$args" in
  "projects describe "*)
    denied="ERROR: (gcloud.projects.describe) [ci@example.com] does not have permission to access projects instance"
    case "${MOCK_DESCRIBE_ERROR:-}" in
      "") ;;
      expired)
        echo "ERROR: (gcloud.projects.describe) There was a problem refreshing your current auth tokens: Reauthentication failed. cannot prompt during non-interactive execution." >&2
        exit 1 ;;
      unauthenticated)
        echo "ERROR: (gcloud.projects.describe) UNAUTHENTICATED: Request had invalid authentication credentials. Expected OAuth 2 access token, login cookie or other valid authentication credential." >&2
        exit 1 ;;
      disabled)  # a permission error for this project, with another cause
        echo "$denied [$3] (or it may not exist): Cloud Resource Manager API has not been used in project 123456 before or it is disabled." >&2
        exit 1 ;;
      other-instance)  # the "not visible" answer, but for another project
        echo "$denied [other-proj] (or it may not exist): The caller does not have permission." >&2
        exit 1 ;;
      *) echo "gcloud mock: unknown MOCK_DESCRIBE_ERROR: $MOCK_DESCRIBE_ERROR" >&2; exit 1 ;;
    esac
    if [[ -z "${MOCK_PROJECT_EXISTS:-}" ]] && ! grep -qxF "$3" "$CREATED"; then
      echo "$denied [$3] (or it may not exist): The caller does not have permission. This command is authenticated as ci@example.com which is the active account specified by the [core/account] property" >&2
      exit 1
    fi
    case "$args" in
      *"value(lifecycleState)"*) echo "${MOCK_LIFECYCLE-ACTIVE}" ;;
      *"value(parent.type)"*) echo "${MOCK_PARENT_TYPE:-folder}" ;;
      *"value(parent.id)"*) echo "${MOCK_PARENT_ID:-1234}" ;;
      *"value(projectNumber)"*) echo "123456" ;;
    esac
    ;;
  "projects create "*) echo "$3" >> "$CREATED" ;;
  "billing projects link "*) ;;
  "billing projects describe "*) echo "${MOCK_BILLING_ENABLED-True}" ;;
  "storage buckets describe "*) echo "ERROR: bucket not found" >&2; exit 1 ;;
  "storage buckets create "* | "storage buckets update "*) ;;
  "firestore databases describe "*) exit 1 ;;
  *) echo "gcloud mock: unexpected call: $args" >&2; exit 1 ;;
esac
SH

cat > "$BIN/firebase" <<'SH'
#!/usr/bin/env bash
echo "firebase $*" >> "$CALLS"
case "$1" in
  projects:list | apps:list) echo '{"status":"success","result":[]}' ;;
  projects:addfirebase) ;;
  *) echo "firebase mock: unexpected call: $*" >&2; exit 1 ;;
esac
SH

# terraform's `state list` prints nothing (an empty state); node is reached only
# by the import script's app discovery and finds no app; make records the target.
for tool in terraform node make; do
  cat > "$BIN/$tool" <<SH
#!/usr/bin/env bash
echo "$tool \$*" >> "\$CALLS"
SH
done
chmod +x "$BIN/gcloud" "$BIN/firebase" "$BIN/terraform" "$BIN/node" "$BIN/make"

# Fresh state for a case: the committed xcconfig with the given tier value
# ("absent" omits the key) and no tfvars file.
reset() {
  {
    echo "CATVOX_ENVIRONMENT = sbx"
    if [[ "$1" != "absent" ]]; then echo "CATVOX_ENVIRONMENT_PROTECTED = $1"; fi
  } > "$CFG"
  rm -rf "$(dirname "$TFVARS")"
}

# An existing tfvars file with the given content, plus a pristine copy to
# compare against.
write_tfvars_raw() {
  mkdir -p "$(dirname "$TFVARS")"
  printf '%s\n' "$1" > "$TFVARS"
  cp "$TFVARS" "$TFVARS.before"
}

# An existing tfvars file written the way the script writes it:
# write_tfvars <alert_email> <token|null>.
write_tfvars() {
  local token_value="null"
  if [[ "$2" != "null" ]]; then token_value="\"$2\""; fi
  write_tfvars_raw "$(printf 'app_check_debug_token             = %s\nalert_email           = "%s"' "$token_value" "$1")"
}

# Run with a valid baseline — mutable environment, folder parent, billing, alert
# email — overridden by trailing KEY=value arguments (an empty value unsets the
# variable as far as the script is concerned). Output lands in $OUT.
run() {
  local rc=0
  : > "$CALLS"
  : > "$CREATED"
  env -i PATH="$BIN" TMPDIR="$TMPROOT" CALLS="$CALLS" CREATED="$CREATED" \
    CATVOX_ENVIRONMENT=sbx CATVOX_PROJECT_ID=proj PROJECT_DISPLAY_NAME="CatVox Sandbox" \
    CATVOX_FUNCTION_REGION=us-central1 CATVOX_FIRESTORE_LOCATION=nam5 \
    CATVOX_TF_STATE_BUCKET=catvox-tf-state-proj CATVOX_TF_STATE_PREFIX=catvox/state \
    CATVOX_TF_VARS_FILE="$TFVARS" CATVOX_ENV_CONFIG="$CFG" \
    CATVOX_IOS_BUNDLE_ID=com.example.sbx CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME="CatVox Sandbox iOS" \
    CATVOX_FIREBASE_IOS_APP_DELETION_POLICY=DELETE CATVOX_FIREBASE_APPLE_TEAM_ID=TEAM123456 \
    CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM=true \
    RUN_TERRAFORM_APPLY=0 RUN_POSTHOG_TERRAFORM_APPLY=0 RUN_FUNCTIONS_DEPLOY=0 CREATE_PROJECT=1 \
    FOLDER_ID=1234 BILLING_ACCOUNT_ID=0X0X0X-0X0X0X-0X0X0X ALERT_EMAIL=alerts@example.com \
    "$@" bash "$SCRIPT" >"$OUT" 2>&1 || rc=$?
  # The project lookup's temporary file must not outlive the run, whatever its outcome.
  [[ -z "$(ls -A "$TMPROOT")" ]] || fail "temporary files left behind: $(ls -A "$TMPROOT")"
  return "$rc"
}

# A mocked CLI ran with this fragment in its argv / never did. Only grep's
# "no match" (exit 1) counts as never: a grep error fails the assertion.
called() { grep -qF -- "$1" "$CALLS"; }
not_called() {
  grep -qF -- "$1" "$CALLS"
  [[ $? -eq 1 ]]
}

# A refused run: it printed the expected message, no mocked CLI ran at all, and
# the tfvars file is as before (absent, or byte-identical to $TFVARS.before).
assert_refused_before_cloud() {  # case-id message-fragment
  grep -qF -- "$2" "$OUT" || fail "$1: expected '$2' in output: $(cat "$OUT")"
  [[ ! -s "$CALLS" ]] || fail "$1: refused only after cloud calls: $(cat "$CALLS")"
  if [[ -f "$TFVARS.before" ]]; then
    cmp -s "$TFVARS.before" "$TFVARS" || fail "$1: tfvars changed"
  else
    [[ ! -e "$TFVARS" ]] || fail "$1: tfvars was written"
  fi
}

# A refused run that needed a cloud read or link first: nothing was created,
# enabled, or written after it.
assert_no_mutation_after() {  # case-id
  local rc
  grep -qE '^gcloud (projects create|storage buckets (create|update))|^firebase projects:addfirebase|^make ' "$CALLS"
  rc=$?
  [[ $rc -eq 1 ]] || fail "$1: mutated before refusing (grep rc $rc): $(cat "$CALLS")"
  [[ ! -e "$TFVARS" ]] || fail "$1: tfvars was written"
}

# 1. Positive control: mutable environment, folder parent, new project, debug token.
reset false
run APP_CHECK_DEBUG_TOKEN="$TOKEN" || fail "C1 valid run should succeed: $(cat "$OUT")"
grep -qF "GCP project proj was not found (or this account cannot see it); creating it, as CREATE_PROJECT=1 asks." "$OUT" || fail "C1 gcloud's not-found answer with CREATE_PROJECT=1 should create the project: $(cat "$OUT")"
called "gcloud projects create proj --name=CatVox Sandbox --folder=1234" || fail "C1 project not created under the folder: $(cat "$CALLS")"
not_called "--organization" || fail "C1 must not pass --organization"
called "gcloud billing projects link proj --billing-account=0X0X0X-0X0X0X-0X0X0X" || fail "C1 billing not linked"
called "gcloud storage buckets create gs://catvox-tf-state-proj" || fail "C1 state bucket not created"
called "make terraform-plan" || fail "C1 did not reach terraform plan"
grep -qE '^alert_email[[:space:]]*=[[:space:]]*"alerts@example.com"$' "$TFVARS" || fail "C1 alert_email not written: $(cat "$TFVARS")"
grep -qE "^app_check_debug_token[[:space:]]*=[[:space:]]*\"${TOKEN}\"$" "$TFVARS" || fail "C1 debug token not written for a mutable env"
ok "valid run: project created under FOLDER_ID, billing linked, tfvars written with the mutable env's token"

# 2. Positive control: organization parent.
reset false
run FOLDER_ID= ORGANIZATION_ID=5678 || fail "C2 valid run should succeed: $(cat "$OUT")"
called "gcloud projects create proj --name=CatVox Sandbox --organization=5678" || fail "C2 project not created under the organization: $(cat "$CALLS")"
not_called "--folder" || fail "C2 must not pass --folder"
ok "valid run with ORGANIZATION_ID creates the project under the organization"

# 3. Both parents set -> refuse (ORGANIZATION_ID used to win silently).
reset false
if run ORGANIZATION_ID=5678; then fail "C3 expected refusal with both parents set"; fi
assert_refused_before_cloud C3 "Set exactly one of FOLDER_ID or ORGANIZATION_ID, not both."
ok "refuses FOLDER_ID and ORGANIZATION_ID together, before any cloud call"

# 4. Neither parent set -> refuse.
reset false
if run FOLDER_ID=; then fail "C4 expected refusal with no parent"; fi
assert_refused_before_cloud C4 "Set exactly one of FOLDER_ID or ORGANIZATION_ID: the parent"
ok "refuses a run with no parent, before any cloud call"

# 5. Non-numeric parent ID -> refuse.
reset false
if run FOLDER_ID=folders/1234; then fail "C5 expected refusal for a non-numeric FOLDER_ID"; fi
assert_refused_before_cloud C5 "FOLDER_ID must be a numeric folder ID (got: folders/1234)."
if run FOLDER_ID= ORGANIZATION_ID=" "; then fail "C5 expected refusal for a blank ORGANIZATION_ID"; fi
assert_refused_before_cloud C5 "ORGANIZATION_ID must be a numeric organization ID"
ok "refuses a non-numeric or blank parent ID, before any cloud call"

# 6. Existing project under another parent -> refuse before any mutation: same ID
# but another parent type, then same type but another ID.
reset false
if run MOCK_PROJECT_EXISTS=1 MOCK_PARENT_TYPE=organization MOCK_PARENT_ID=1234; then
  fail "C6 expected refusal when the existing project's parent type differs"
fi
grep -qF "already exists under organization 1234, not the requested folder 1234" "$OUT" || fail "C6 type message: $(cat "$OUT")"
assert_no_mutation_after C6
not_called "billing projects link" || fail "C6 must not link billing"
if run MOCK_PROJECT_EXISTS=1 MOCK_PARENT_ID=9999; then
  fail "C6 expected refusal when the existing project's parent ID differs"
fi
grep -qF "already exists under folder 9999, not the requested folder 1234" "$OUT" || fail "C6 id message: $(cat "$OUT")"
assert_no_mutation_after C6
not_called "billing projects link" || fail "C6 must not link billing"
ok "refuses an existing project under another parent (type or ID), before any mutation"

# 7. Positive control: existing project under the requested parent.
reset false
for create in 1 0; do
  run MOCK_PROJECT_EXISTS=1 CREATE_PROJECT="$create" || fail "C7 existing project under the requested folder should proceed (CREATE_PROJECT=$create): $(cat "$OUT")"
  not_called "gcloud projects create" || fail "C7 must not re-create an existing project (CREATE_PROJECT=$create)"
  called "gcloud billing projects link" || fail "C7 should go on to link billing (CREATE_PROJECT=$create)"
done
ok "existing project under the requested folder proceeds without being re-created, whatever CREATE_PROJECT says"

# 8. BILLING_ACCOUNT_ID missing -> refuse.
reset false
if run BILLING_ACCOUNT_ID=; then fail "C8 expected refusal without BILLING_ACCOUNT_ID"; fi
assert_refused_before_cloud C8 "BILLING_ACCOUNT_ID is required."
ok "refuses a run without BILLING_ACCOUNT_ID, before any cloud call"

# 9. Billing not enabled after linking (False, or an empty read) -> refuse
# before Firebase or any bucket. The project already exists, so the link is the
# only cloud write before the refusal.
reset false
for billing in False ""; do
  if run MOCK_PROJECT_EXISTS=1 MOCK_BILLING_ENABLED="$billing"; then fail "C9 expected refusal when billingEnabled is '$billing'"; fi
  grep -qF "Billing is not enabled on proj after linking" "$OUT" || fail "C9 message: $(cat "$OUT")"
  called "gcloud billing projects link proj" || fail "C9 should have linked billing first"
  assert_no_mutation_after C9
  not_called "firebase projects:addfirebase" || fail "C9 must stop before Firebase"
done
ok "refuses when billing is not enabled after linking, before Firebase or any bucket"

# 10. Protected environment + APP_CHECK_DEBUG_TOKEN -> refuse.
reset true
if run APP_CHECK_DEBUG_TOKEN="$TOKEN"; then fail "C10 expected refusal of a debug token for a protected env"; fi
assert_refused_before_cloud C10 "Refusing APP_CHECK_DEBUG_TOKEN: 'sbx' is a protected environment"
ok "refuses APP_CHECK_DEBUG_TOKEN for a protected environment, before any cloud call"

# 11. Positive control: protected environment without a token.
reset true
run || fail "C11 protected env without a token should proceed: $(cat "$OUT")"
grep -qE '^app_check_debug_token[[:space:]]*=[[:space:]]*null$' "$TFVARS" || fail "C11 token should be null: $(cat "$TFVARS")"
ok "protected environment without a debug token proceeds (tfvars token = null)"

# 12. Debug token, but the tier is not declared (key absent; then no xcconfig at
# all) -> refuse: the environment cannot be proven mutable.
reset absent
if run APP_CHECK_DEBUG_TOKEN="$TOKEN"; then fail "C12 expected refusal when the tier key is absent"; fi
assert_refused_before_cloud C12 "cannot confirm 'sbx' is a mutable environment"
rm -f "$CFG"
if run APP_CHECK_DEBUG_TOKEN="$TOKEN"; then fail "C12 expected refusal when the xcconfig is missing"; fi
assert_refused_before_cloud C12 "cannot confirm 'sbx' is a mutable environment"
ok "refuses a debug token when the xcconfig or its tier key is missing"

# 13. Debug token with a non-canonical tier value -> refuse (committed booleans
# are lowercase true/false only).
reset FALSE
if run APP_CHECK_DEBUG_TOKEN="$TOKEN"; then fail "C13 expected refusal for tier value FALSE"; fi
assert_refused_before_cloud C13 "(found: 'FALSE')"
ok "refuses a debug token when the tier value is not exactly false"

# 14. Protected environment whose existing tfvars already holds a token (none
# supplied) -> refuse: the Makefile would apply that file.
reset true
write_tfvars alerts@example.com "$TOKEN"
if run; then fail "C14 expected refusal of an existing tfvars token for a protected env"; fi
assert_refused_before_cloud C14 "Refusing the app_check_debug_token in ${TFVARS}: 'sbx' is a protected environment"
ok "refuses a debug token already in the tfvars file of a protected environment"

# 15. Existing tfvars + a different ALERT_EMAIL -> refuse (used to be silently ignored).
reset false
write_tfvars old-alerts@example.com null
if run; then fail "C15 expected refusal when ALERT_EMAIL differs from the tfvars file"; fi
assert_refused_before_cloud C15 "Refusing: ALERT_EMAIL does not match alert_email in the existing ${TFVARS}."
ok "refuses an ALERT_EMAIL that differs from the existing tfvars, leaving the file untouched"

# 16. Existing tfvars + a different APP_CHECK_DEBUG_TOKEN -> refuse.
reset false
write_tfvars alerts@example.com null
if run APP_CHECK_DEBUG_TOKEN="$TOKEN"; then fail "C16 expected refusal when the token differs from the tfvars file"; fi
assert_refused_before_cloud C16 "Refusing: APP_CHECK_DEBUG_TOKEN does not match app_check_debug_token"
ok "refuses an APP_CHECK_DEBUG_TOKEN that differs from the existing tfvars, leaving the file untouched"

# 17. Positive control: existing tfvars matching the supplied values is kept.
reset false
write_tfvars alerts@example.com "$TOKEN"
run APP_CHECK_DEBUG_TOKEN="$TOKEN" || fail "C17 matching values should proceed: $(cat "$OUT")"
cmp -s "$TFVARS.before" "$TFVARS" || fail "C17 tfvars changed"
grep -qF "Keeping existing ${TFVARS}" "$OUT" || fail "C17 should keep the existing tfvars"
ok "existing tfvars that matches the supplied values is kept as-is"

# 18. Positive control: existing tfvars with nothing supplied is kept.
reset false
write_tfvars old-alerts@example.com null
run ALERT_EMAIL= || fail "C18 nothing supplied should proceed: $(cat "$OUT")"
cmp -s "$TFVARS.before" "$TFVARS" || fail "C18 tfvars changed"
ok "existing tfvars is kept when no ALERT_EMAIL or token is supplied"

# 19. No tfvars + no ALERT_EMAIL -> refuse before any cloud call (this used to
# fail only after the project, billing, and buckets had been created).
reset false
if run ALERT_EMAIL=; then fail "C19 expected refusal without ALERT_EMAIL"; fi
assert_refused_before_cloud C19 "ALERT_EMAIL is required."
ok "refuses a missing ALERT_EMAIL before any cloud call"

# 20. Regression: a block-commented `null` above an active token must not hide
# that token. A protected environment used to pass preflight here, and the
# Makefile would then apply the live token. Refused before any cloud call.
reset true
write_tfvars_raw "/*
app_check_debug_token = null
*/
app_check_debug_token = \"${TOKEN}\"
alert_email = \"alerts@example.com\""
if run; then fail "C20 expected refusal of a block comment shadowing an active token"; fi
assert_refused_before_cloud C20 "is not in the plain form this script can read safely"
grep -qF "line 1: not a one-line key = value assignment" "$OUT" || fail "C20 should name the offending line: $(cat "$OUT")"
ok "a block comment hiding an active debug token is refused, not read as null"

# 21. Every other form outside the plain one is refused too: a one-line block
# comment, a repeated key, an unknown key, text after a value, an unquoted value,
# and a multi-line (heredoc) value.
reset false
for bad in \
  "/* app_check_debug_token = null */
app_check_debug_token = null
alert_email = \"alerts@example.com\"" \
  "alert_email = \"old@example.com\"
alert_email = \"alerts@example.com\"" \
  "alert_email = \"alerts@example.com\"
project_id = \"proj\"" \
  "alert_email = \"alerts@example.com\" extra" \
  "alert_email = alerts@example.com" \
  "alert_email = <<EOT
alerts@example.com
EOT"; do
  write_tfvars_raw "$bad"
  if run; then fail "C21 expected refusal for tfvars content: $bad"; fi
  assert_refused_before_cloud C21 "is not in the plain form this script can read safely"
done
ok "block comments, repeated or unknown keys, trailing text, and unquoted or multi-line values are refused"

# 22. Positive control: whole-line comments (one of them a commented-out token)
# and trailing comments are read as comments, on a protected environment.
reset true
write_tfvars_raw "# Private values for sbx.
// app_check_debug_token = \"${TOKEN}\"
app_check_debug_token = null  # none on a protected tier
alert_email = \"alerts@example.com\" // on-call"
run || fail "C22 comments should be accepted: $(cat "$OUT")"
cmp -s "$TFVARS.before" "$TFVARS" || fail "C22 tfvars changed"
ok "whole-line and trailing comments are read as comments, not as assignments"

# 23. A project lookup that fails for any reason other than gcloud's "not found
# or not visible" answer for this project stops the run before any mutation,
# even with CREATE_PROJECT=1 (the baseline), and quotes gcloud's error: expired
# credentials, invalid credentials, a permission error for this project with
# another cause, and the "not visible" answer for some other project. Each used
# to read as a missing project.
reset false
for err in expired unauthenticated disabled other-instance; do
  if run MOCK_DESCRIBE_ERROR="$err"; then fail "C23 expected refusal when the project lookup fails ($err)"; fi
  grep -qF "Could not look up GCP project proj (gcloud exited 1); stopping before any change:" "$OUT" || fail "C23 ($err) message: $(cat "$OUT")"
  grep -qF "ERROR: (gcloud.projects.describe)" "$OUT" || fail "C23 ($err) should quote gcloud's error: $(cat "$OUT")"
  assert_no_mutation_after C23
  not_called "billing projects link" || fail "C23 ($err) must not link billing"
done
ok "a project lookup that fails for another reason stops the run before any mutation, quoting gcloud's error"

# 24. An existing project that is not ACTIVE (pending deletion, or an empty state
# read) is refused before any mutation instead of being provisioned.
reset false
for state in DELETE_REQUESTED ""; do
  if run MOCK_PROJECT_EXISTS=1 MOCK_LIFECYCLE="$state"; then fail "C24 expected refusal when the project state is '$state'"; fi
  grep -qF "GCP project proj exists, but its state is ${state:-empty}, not ACTIVE." "$OUT" || fail "C24 message: $(cat "$OUT")"
  assert_no_mutation_after C24
  not_called "billing projects link" || fail "C24 must not link billing"
done
ok "an existing project that is not ACTIVE is refused before any mutation"

# 25. gcloud's "not found, or not visible" answer is inconclusive, so without
# CREATE_PROJECT=1 the run stops before any change, quoting gcloud's answer and
# naming the flag, instead of creating a project the operator did not ask for.
reset false
if run CREATE_PROJECT=0; then fail "C25 expected refusal to create a project without CREATE_PROJECT=1"; fi
grep -qF "GCP project proj was not found, or the active gcloud account cannot see it; stopping before any change." "$OUT" || fail "C25 message: $(cat "$OUT")"
grep -qF "does not have permission to access projects instance [proj] (or it may not exist)" "$OUT" || fail "C25 should quote gcloud's answer: $(cat "$OUT")"
grep -qF "re-run with CREATE_PROJECT=1 to create it under folder 1234." "$OUT" || fail "C25 should name the flag: $(cat "$OUT")"
assert_no_mutation_after C25
not_called "billing projects link" || fail "C25 must not link billing"
ok "a project gcloud cannot see is not created without CREATE_PROJECT=1, and the run stops before any mutation"

# 26. CREATE_PROJECT is required and must be 0 or 1, like the RUN_* flags:
# refused before any cloud call.
reset false
if run CREATE_PROJECT=; then fail "C26 expected refusal without CREATE_PROJECT"; fi
assert_refused_before_cloud C26 "CREATE_PROJECT is required."
if run CREATE_PROJECT=yes; then fail "C26 expected refusal for CREATE_PROJECT=yes"; fi
assert_refused_before_cloud C26 "CREATE_PROJECT must be 0 or 1."
ok "a missing or invalid CREATE_PROJECT is refused before any cloud call"

echo "PASS ($pass cases)"
