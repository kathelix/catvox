#!/usr/bin/env bash
# Behaviour test for scripts/write-environment-config.sh.
#
# Runs the real script against PATH-mocked `terraform`, `plutil`, and `gcloud`
# in a hermetic environment: `env -i` (so a parent `make` cannot leak CATVOX_*
# values) plus a self-contained PATH that holds only the mocks and symlinks to
# the few system tools the script needs. There is no /usr/bin or /bin on that
# PATH, so a CLI preinstalled on a runner can never stand in for a mock. Writes
# into a sandbox xcconfig. Asserts: identity values land verbatim
# (slashes/colons preserved, no trailing-`%`/whitespace), idempotent re-runs,
# host-only stripping, append of an absent key, and that every refusal leaves
# the xcconfig byte-identical: a Terraform root initialised for another
# environment, an xcconfig without CATVOX_TF_STATE_BUCKET, an unreadable state
# output, a function that is not deployed (unless ALLOW_MISSING_HOSTS=1), and
# any other failed host lookup.
#
# Ends by running scripts/test/create-environment.test.sh (see the note there).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/write-environment-config.sh"

pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok - $*"; pass=$((pass + 1)); }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
BIN="$SANDBOX/bin"
SCRIPT_TMP="$SANDBOX/tmp"  # the script's TMPDIR; must be empty after every run
mkdir -p "$BIN" "$SCRIPT_TMP"

# System tools the script (and scripts/lib/read-xcconfig-value.sh) runs, linked
# one by one so PATH stays self-contained.
for tool in bash awk cat cmp dirname grep mktemp rm tr; do
  real="$(command -v "$tool")"
  [[ "$real" == /* ]] || fail "test host lacks $tool"
  ln -s "$real" "$BIN/$tool"
done

# ── Mocked CLIs ─────────────────────────────────────────────────────────────
# terraform: echo a canned value for the output name following `-raw`, keyed by
# root (the basename of -chdir: core or posthog). Trailing whitespace is
# intentional — clean_token must strip it (the `%`/newline trap). MOCK_STATE_BUCKET
# and MOCK_POSTHOG_ENV simulate a root initialised for another environment;
# MOCK_NO_STATE_OUTPUT an unreadable state output.
cat > "$BIN/terraform" <<'SH'
#!/usr/bin/env bash
root=""; name=""; prev=""
for a in "$@"; do
  case "$a" in -chdir=*) root="${a##*/}" ;; esac
  [[ "$prev" == "-raw" ]] && name="$a"
  prev="$a"
done
case "$root:$name" in
  core:terraform_state_bucket_name)
    [[ -n "${MOCK_NO_STATE_OUTPUT:-}" ]] && exit 1
    printf '%s\n' "${MOCK_STATE_BUCKET:-catvox-tf-state-proj}" ;;
  core:ci_service_account_email)    printf 'catvox-ci-sa@proj.iam.gserviceaccount.com  ' ;;
  core:github_actions_wif_provider) printf 'projects/123/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider\n' ;;
  core:firebase_ios_app_id)         printf '1:123:ios:abc964748' ;;
  posthog:environment_name)         printf '%s\n' "${MOCK_POSTHOG_ENV:-sbx}" ;;
  posthog:project_id)               printf '402530\n' ;;
  posthog:project_api_token)        printf 'phc_testtoken123\n' ;;
  *) exit 1 ;;
esac
SH

# plutil: echo the API key value for `-extract API_KEY raw <plist>`.
cat > "$BIN/plutil" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_API_KEY:-AIzaSyTESTKEY1234567890}"
SH

# gcloud: echo the Cloud Run URI for `functions describe <name>`. MOCK_NODEPLOY
# lists functions that report NOT_FOUND ("all" = every function); MOCK_DENIED
# fails every lookup with a permission error (worded "may not exist", as GCP
# does, which must NOT read as not-found); MOCK_NO_URI succeeds with no URI.
cat > "$BIN/gcloud" <<'SH'
#!/usr/bin/env bash
name=""; want=0
for a in "$@"; do [[ $want -eq 1 ]] && { name="$a"; want=0; }; [[ "$a" == "describe" ]] && want=1; done
if [[ -n "${MOCK_DENIED:-}" ]]; then
  echo "ERROR: (gcloud.functions.describe) PERMISSION_DENIED: Permission 'cloudfunctions.functions.get' denied on resource 'projects/proj/locations/us-central1/functions/${name}' (or it may not exist)." >&2
  exit 1
fi
case " ${MOCK_NODEPLOY:-} " in
  *" all "* | *" ${name} "*)
    echo "ERROR: (gcloud.functions.describe) NOT_FOUND: Resource 'projects/proj/locations/us-central1/functions/${name}' was not found" >&2
    exit 1 ;;
esac
[[ -n "${MOCK_NO_URI:-}" ]] && exit 0
case "$name" in
  getSignedUploadURL) printf 'https://getsigneduploadurl-abc-uc.a.run.app\n' ;;
  analyseVideo)       printf 'https://analysevideo-abc-uc.a.run.app/\n' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$BIN/terraform" "$BIN/plutil" "$BIN/gcloud"

# Build a fresh sandbox xcconfig (with placeholders) and plist for a case.
fixture() {
  CFG="$SANDBOX/$1.xcconfig"
  PLIST="$SANDBOX/$1.plist"
  cat > "$CFG" <<'EOF'
CATVOX_PROJECT_ID = proj
CATVOX_ENVIRONMENT = sbx
CATVOX_TF_STATE_BUCKET = catvox-tf-state-proj
CATVOX_GCP_CI_SERVICE_ACCOUNT = replace-with-ci-sa
CATVOX_GCP_WIF_PROVIDER = replace-with-wif-provider
CATVOX_FIREBASE_APP_ID = replace-with-app-id
CATVOX_FIREBASE_API_KEY = replace-with-api-key
CATVOX_SIGNED_UPLOAD_URL_HOST = replace-with-upload-host
CATVOX_ANALYSE_VIDEO_HOST = replace-with-analyse-host
CATVOX_POSTHOG_PROJECT_ID = replace-with-posthog-project-id
CATVOX_POSTHOG_PROJECT_TOKEN = replace-with-posthog-project-token
EOF
  : > "$PLIST"  # presence is enough; plutil is mocked
  cp "$CFG" "$CFG.before"
}

run() {  # phase extra_env...
  local phase="$1"; shift
  env -i PATH="$BIN" TMPDIR="$SCRIPT_TMP" \
    CATVOX_ENVIRONMENT=sbx CATVOX_ENV_CONFIG="$CFG" \
    CATVOX_PROJECT_ID=proj CATVOX_FUNCTION_REGION=us-central1 \
    CATVOX_FIREBASE_PLIST_OUTPUT="$PLIST" WRITE_CONFIG_PHASE="$phase" \
    "$@" bash "$SCRIPT"
}
val() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$CFG" | head -1 | sed -E 's/^[^=]*=[[:space:]]*//'; }

# A refused run printed the expected message (in $SANDBOX/err) and left the
# xcconfig byte-identical to the fixture, with no temp file left behind.
assert_refused_untouched() {  # case-id message-fragment
  grep -qF -- "$2" "$SANDBOX/err" || fail "$1: expected '$2' in: $(cat "$SANDBOX/err")"
  cmp -s "$CFG.before" "$CFG" || fail "$1: xcconfig changed on a refused run"
  [[ -z "$(ls -A "$SCRIPT_TMP")" ]] || fail "$1: temp files left behind: $(ls -A "$SCRIPT_TMP")"
}

# 1. Identity phase writes all four values, clean (no trailing %/space), slashes/colons intact.
fixture id
run identity >/dev/null 2>&1 || fail "S1 identity run errored"
[[ "$(val CATVOX_GCP_CI_SERVICE_ACCOUNT)" == "catvox-ci-sa@proj.iam.gserviceaccount.com" ]] || fail "S1 ci-sa: [$(val CATVOX_GCP_CI_SERVICE_ACCOUNT)]"
[[ "$(val CATVOX_GCP_WIF_PROVIDER)" == "projects/123/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider" ]] || fail "S1 wif: [$(val CATVOX_GCP_WIF_PROVIDER)]"
[[ "$(val CATVOX_FIREBASE_APP_ID)" == "1:123:ios:abc964748" ]] || fail "S1 app-id: [$(val CATVOX_FIREBASE_APP_ID)]"
[[ "$(val CATVOX_FIREBASE_API_KEY)" == "AIzaSyTESTKEY1234567890" ]] || fail "S1 api-key: [$(val CATVOX_FIREBASE_API_KEY)]"
ok "identity writes clean values (slashes/colons preserved, no %/whitespace)"

# 2. Idempotent: a second identity run produces an identical file.
cp "$CFG" "$SANDBOX/id.before"
run identity >/dev/null 2>&1 || fail "S2 second run errored"
diff -q "$SANDBOX/id.before" "$CFG" >/dev/null || fail "S2 re-run changed the file"
ok "identity re-run is a no-op (clean diff)"

# 3. Hosts phase strips scheme + path to hostname only.
fixture hosts
run hosts >/dev/null 2>&1 || fail "S3 hosts run errored"
[[ "$(val CATVOX_SIGNED_UPLOAD_URL_HOST)" == "getsigneduploadurl-abc-uc.a.run.app" ]] || fail "S3 upload host: [$(val CATVOX_SIGNED_UPLOAD_URL_HOST)]"
[[ "$(val CATVOX_ANALYSE_VIDEO_HOST)" == "analysevideo-abc-uc.a.run.app" ]] || fail "S3 analyse host: [$(val CATVOX_ANALYSE_VIDEO_HOST)]"
[[ -z "$(ls -A "$SCRIPT_TMP")" ]] || fail "S3 temp files left behind"
ok "hosts phase stores hostname only (scheme + path stripped)"

# 4. Hosts strict by default: one function not deployed -> fail, and the
# deployed one's host is not written either (both resolve before any write).
fixture nodeploy
if run hosts MOCK_NODEPLOY=analyseVideo >/dev/null 2>"$SANDBOX/err"; then
  fail "S4 expected failure when a function is not deployed"
fi
assert_refused_untouched S4 "analyseVideo is not deployed in proj (us-central1), so CATVOX_ANALYSE_VIDEO_HOST cannot be filled."
grep -qF "ALLOW_MISSING_HOSTS=1" "$SANDBOX/err" || fail "S4 should name the ALLOW_MISSING_HOSTS escape hatch"
ok "hosts phase fails when a function is not deployed, writing neither host"

# 5. ALLOW_MISSING_HOSTS=1: a not-deployed function is skipped with a warning,
# the deployed one is still written, exit 0.
fixture allowmissing
run hosts MOCK_NODEPLOY=analyseVideo ALLOW_MISSING_HOSTS=1 >/dev/null 2>"$SANDBOX/err5" || fail "S5 should succeed with ALLOW_MISSING_HOSTS=1"
[[ "$(val CATVOX_SIGNED_UPLOAD_URL_HOST)" == "getsigneduploadurl-abc-uc.a.run.app" ]] || fail "S5 deployed host should be written"
[[ "$(val CATVOX_ANALYSE_VIDEO_HOST)" == "replace-with-analyse-host" ]] || fail "S5 skipped host should be untouched"
grep -qF "skipped:   CATVOX_ANALYSE_VIDEO_HOST (analyseVideo not deployed yet" "$SANDBOX/err5" || fail "S5 expected a skip warning"
[[ -z "$(ls -A "$SCRIPT_TMP")" ]] || fail "S5 temp files left behind"
ok "ALLOW_MISSING_HOSTS=1 skips a not-deployed function and writes the rest"

# 6. A lookup that fails for any other reason (permission denied, worded "may
# not exist") is never treated as not-deployed, even with ALLOW_MISSING_HOSTS=1.
fixture denied
if run hosts MOCK_DENIED=1 ALLOW_MISSING_HOSTS=1 >/dev/null 2>"$SANDBOX/err"; then
  fail "S6 expected failure on a permission error"
fi
assert_refused_untouched S6 "PERMISSION_DENIED"
grep -qF "No backend host values were written" "$SANDBOX/err" || fail "S6 should report that nothing was written"
ok "a permission error fails the hosts phase even with ALLOW_MISSING_HOSTS=1"

# 7. A function that exists but reports no service URI is a failed deploy, not
# a missing one: fail even with ALLOW_MISSING_HOSTS=1.
fixture nouri
if run hosts MOCK_NO_URI=1 ALLOW_MISSING_HOSTS=1 >/dev/null 2>"$SANDBOX/err"; then
  fail "S7 expected failure when describe returns no URI"
fi
assert_refused_untouched S7 "getSignedUploadURL exists but reports no service URI"
ok "a function with no service URI fails the hosts phase even with ALLOW_MISSING_HOSTS=1"

# 8. ALLOW_MISSING_HOSTS accepts only 0 or 1.
fixture badflag
if run hosts ALLOW_MISSING_HOSTS=true >/dev/null 2>"$SANDBOX/err"; then
  fail "S8 expected failure for ALLOW_MISSING_HOSTS=true"
fi
assert_refused_untouched S8 "ALLOW_MISSING_HOSTS must be 0 or 1 (got: true)"
ok "ALLOW_MISSING_HOSTS rejects values other than 0 or 1"

# 9. Absent key is appended (then idempotent on re-run).
fixture append
grep -v '^CATVOX_FIREBASE_API_KEY' "$SANDBOX/append.xcconfig" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
run identity >/dev/null 2>&1 || fail "S9 run errored"
[[ "$(val CATVOX_FIREBASE_API_KEY)" == "AIzaSyTESTKEY1234567890" ]] || fail "S9 absent key not appended"
cp "$CFG" "$SANDBOX/append.before"
run identity >/dev/null 2>&1 || fail "S9 second run errored"
diff -q "$SANDBOX/append.before" "$CFG" >/dev/null || fail "S9 re-run after append changed the file"
ok "absent key is appended, then idempotent"

# 10. Missing xcconfig fails fast.
if env -i PATH="$BIN" CATVOX_ENVIRONMENT=sbx \
   CATVOX_ENV_CONFIG="$SANDBOX/does-not-exist.xcconfig" WRITE_CONFIG_PHASE=identity \
   bash "$SCRIPT" >/dev/null 2>&1; then
  fail "S10 expected failure on missing xcconfig"
fi
ok "missing xcconfig fails fast"

# 11. PostHog phase writes project id + public ingestion token from terraform/posthog outputs.
fixture posthog
run posthog >/dev/null 2>&1 || fail "S11 posthog run errored"
[[ "$(val CATVOX_POSTHOG_PROJECT_ID)" == "402530" ]] || fail "S11 project id: [$(val CATVOX_POSTHOG_PROJECT_ID)]"
[[ "$(val CATVOX_POSTHOG_PROJECT_TOKEN)" == "phc_testtoken123" ]] || fail "S11 project token: [$(val CATVOX_POSTHOG_PROJECT_TOKEN)]"
ok "posthog phase writes project id and public project token"

# 12. terraform/core initialised against another environment's state bucket -> refuse.
fixture foreigncore
if run identity MOCK_STATE_BUCKET=catvox-tf-state-other >/dev/null 2>"$SANDBOX/err"; then
  fail "S12 expected refusal when terraform/core belongs to another environment"
fi
assert_refused_untouched S12 "terraform/core is initialised against state bucket 'catvox-tf-state-other', but sbx uses 'catvox-tf-state-proj'"
ok "identity refuses a terraform/core backend that belongs to another environment"

# 13. The xcconfig names no state bucket -> refuse (nothing to check against).
fixture nobucketkey
grep -v '^CATVOX_TF_STATE_BUCKET' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
cp "$CFG" "$CFG.before"
if run identity >/dev/null 2>"$SANDBOX/err"; then
  fail "S13 expected refusal when the xcconfig has no CATVOX_TF_STATE_BUCKET"
fi
assert_refused_untouched S13 "does not set CATVOX_TF_STATE_BUCKET"
ok "identity refuses when the xcconfig names no state bucket"

# 14. terraform_state_bucket_name cannot be read (backend not initialised, or
# state without the output) -> refuse.
fixture nostateoutput
if run identity MOCK_NO_STATE_OUTPUT=1 >/dev/null 2>"$SANDBOX/err"; then
  fail "S14 expected refusal when terraform_state_bucket_name is unreadable"
fi
assert_refused_untouched S14 "Could not confirm terraform/core is initialised for sbx."
ok "identity refuses when the state-bucket output cannot be read"

# 15. terraform/posthog initialised against another environment's state -> refuse.
fixture foreignposthog
if run posthog MOCK_POSTHOG_ENV=other >/dev/null 2>"$SANDBOX/err"; then
  fail "S15 expected refusal when terraform/posthog belongs to another environment"
fi
assert_refused_untouched S15 "terraform/posthog is initialised against the 'other' environment's state, not sbx's."
ok "posthog refuses a terraform/posthog backend that belongs to another environment"

# 16. PHASE=all checks every backend before writing anything: a PostHog backend
# mismatch leaves even the identity keys untouched.
fixture allforeign
if run all MOCK_POSTHOG_ENV=other >/dev/null 2>"$SANDBOX/err"; then
  fail "S16 expected refusal for PHASE=all with a foreign PostHog backend"
fi
assert_refused_untouched S16 "terraform/posthog is initialised against the 'other' environment's state"
ok "PHASE=all checks every backend before writing any value"

echo "PASS ($pass cases)"

# create-environment.sh's suite runs from here until it is listed in the
# Makefile's scripts-test target, which the change that added it could not edit.
bash "${REPO_ROOT}/scripts/test/create-environment.test.sh" || fail "scripts/test/create-environment.test.sh failed"
