#!/usr/bin/env bash
# Read-only preflight for a CatVox environment: assert the provisioning
# prerequisites that, when missing, otherwise surface only as a mid-deploy
# failure. Fails fast with an actionable hint instead. Issue #109.
#
# Environment-agnostic: keyed entirely off CATVOX_ENVIRONMENT and the matching
# config/environments/<env>.xcconfig values; no literal environment names.
# Mutates nothing — safe to run anytime.
#
# Checks (each PASS / WARN / FAIL):
#   - billing linked on the project
#   - required GCP APIs enabled
#   - catvox-ci-sa holds the expected roles (incl. roles/cloudfunctions.admin,
#     the one a first new-function deploy needs and roles/editor lacks)
#   - the WIF pool is ACTIVE, its provider is scoped to this environment, its
#     attribute_mapping maps attribute.environment, and catvox-ci-sa carries the
#     roles/iam.workloadIdentityUser impersonation binding for this env
#   - the Cloud Functions Gen2 build SA (compute default SA) holds its build
#     grants: artifactregistry.writer, logging.logWriter, actAs on the backend SA
#     (plus WARN-only storage.objectAdmin on the gcf-v2-sources bucket, read
#     from the bucket's IAM policy as JSON; a failed read gets its own WARN)
#   - (WARN-only) the cleanup policy on gcf-artifacts, the Artifact Registry
#     repository the Functions builds push to
#   - the Terraform state bucket is reachable
#
# Exit non-zero if any check FAILs; WARNs do not fail the run.

set -uo pipefail

ENVIRONMENT="${CATVOX_ENVIRONMENT:?CATVOX_ENVIRONMENT is required}"
PROJECT_ID="${CATVOX_PROJECT_ID:?CATVOX_PROJECT_ID is required}"
REGION="${CATVOX_FUNCTION_REGION:-}"
GITHUB_REPO="${CATVOX_GITHUB_REPO:-kathelix/catvox}"
CI_SA="${CATVOX_GCP_CI_SERVICE_ACCOUNT:-catvox-ci-sa@${PROJECT_ID}.iam.gserviceaccount.com}"
STATE_BUCKET="${CATVOX_TF_STATE_BUCKET:-catvox-tf-state-${PROJECT_ID}}"
WIF_PROVIDER_RESOURCE="${CATVOX_GCP_WIF_PROVIDER:-}"

command -v gcloud >/dev/null 2>&1 || { echo "Missing required tool: gcloud" >&2; exit 1; }
# node parses the bucket IAM policy JSON (check 4d); `make doctor` already
# lists it as a core prerequisite.
command -v node >/dev/null 2>&1 || { echo "Missing required tool: node" >&2; exit 1; }

# Roles catvox-ci-sa must hold (keep in sync with terraform/core/iam.tf).
# cloudfunctions.admin is the one roles/editor excludes (it grants
# cloudfunctions.functions.setIamPolicy, required to deploy a *new* function).
REQUIRED_ROLES=(
  roles/editor
  roles/resourcemanager.projectIamAdmin
  roles/iam.serviceAccountAdmin
  roles/secretmanager.secretAccessor
  roles/cloudfunctions.admin
)

# Required GCP APIs (keep in sync with terraform/core/main.tf google_project_service).
REQUIRED_APIS=(
  aiplatform.googleapis.com
  cloudfunctions.googleapis.com
  cloudbuild.googleapis.com
  run.googleapis.com
  eventarc.googleapis.com
  pubsub.googleapis.com
  firestore.googleapis.com
  storage.googleapis.com
  secretmanager.googleapis.com
  firebase.googleapis.com
  firebaseextensions.googleapis.com
  firebaseappcheck.googleapis.com
  iam.googleapis.com
  artifactregistry.googleapis.com
  cloudbilling.googleapis.com
  compute.googleapis.com
  monitoring.googleapis.com
  clouderrorreporting.googleapis.com
)

# Derive the WIF pool/provider ids from the committed resource name when present,
# else fall back to the Terraform defaults (terraform/core/variables.tf).
WIF_POOL=""
WIF_PROVIDER=""
if [[ -n "$WIF_PROVIDER_RESOURCE" ]]; then
  WIF_POOL="$(printf '%s' "$WIF_PROVIDER_RESOURCE" | sed -nE 's#.*/workloadIdentityPools/([^/]+)/providers/.*#\1#p')"
  WIF_PROVIDER="$(printf '%s' "$WIF_PROVIDER_RESOURCE" | sed -nE 's#.*/providers/([^/]+).*#\1#p')"
fi
WIF_POOL="${WIF_POOL:-github-actions-pool}"
WIF_PROVIDER="${WIF_PROVIDER:-github-actions-provider}"

# Backend runtime SA, and the Cloud Functions Gen2 build identity (the Compute
# Engine default SA, whose email needs the project number). Resolve the number
# once; the compute-SA checks degrade to WARN if it cannot be read.
BACKEND_SA="catvox-backend-sa@${PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || true)"

problems=0
warns=0
pass() { printf '  PASS: %s\n' "$*"; }
warn() { printf '  WARN: %s\n' "$*" >&2; warns=$((warns + 1)); }
fail() { printf '  FAIL: %s\n' "$*" >&2; problems=$((problems + 1)); }

# Run a read-only gcloud command with its stdout in CAPTURED_OUT and the first
# line of its stderr in CAPTURED_ERR; return gcloud's exit status. Capturing
# first means no pipe for gcloud to die on, and keeps its error to report.
CAPTURED_OUT=""
CAPTURED_ERR=""
capture_gcloud() {
  local err_file rc=0
  CAPTURED_OUT=""
  CAPTURED_ERR=""
  if ! err_file="$(mktemp "${TMPDIR:-/tmp}/catvox-doctor.XXXXXX")"; then
    CAPTURED_ERR="could not create a temporary file for gcloud's error output"
    return 1
  fi
  CAPTURED_OUT="$(gcloud "$@" 2>"$err_file")" || rc=$?
  CAPTURED_ERR="$(sed -n '/[^[:space:]]/{p;q;}' "$err_file")"
  rm -f "$err_file"
  return "$rc"
}

# Read an IAM policy as JSON on stdin and answer whether it binds role $1 to
# member $2: exit 0 if it does, 20 if it does not. Any other exit status (input
# that is not a policy, or node itself failing) means the answer is unknown, so
# it can never read as a missing grant.
policy_binds() {
  node -e '
    const [role, member] = process.argv.slice(1);
    let policy;
    try {
      policy = JSON.parse(require("fs").readFileSync(0, "utf8"));
    } catch {
      process.exit(2);
    }
    if (policy === null || typeof policy !== "object" || Array.isArray(policy)) process.exit(2);
    const bindings = policy.bindings === undefined ? [] : policy.bindings;
    if (!Array.isArray(bindings)) process.exit(2);
    const bound = bindings.some((b) =>
      b !== null && typeof b === "object" && b.role === role &&
      Array.isArray(b.members) && b.members.includes(member));
    process.exit(bound ? 0 : 20);
  ' "$1" "$2"
}

echo "environment-doctor: ${ENVIRONMENT} (${PROJECT_ID})"
echo

# 1 — Billing linked.
echo "Billing:"
billing="$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null || true)"
if [[ "$billing" == "True" ]]; then
  pass "billing is linked"
else
  fail "billing is not linked to ${PROJECT_ID} — link a billing account before deploy"
fi

# 2 — Required APIs enabled.
echo "APIs:"
enabled_apis="$(gcloud services list --enabled --project "$PROJECT_ID" --format='value(config.name)' 2>/dev/null || true)"
missing_apis=()
for api in "${REQUIRED_APIS[@]}"; do
  printf '%s\n' "$enabled_apis" | grep -qxF "$api" || missing_apis+=("$api")
done
if [[ "${#missing_apis[@]}" -eq 0 ]]; then
  pass "all ${#REQUIRED_APIS[@]} required APIs enabled"
else
  fail "disabled APIs: ${missing_apis[*]} — enable via terraform apply (google_project_service.apis)"
fi

# 3 — CI service account roles (the cloudfunctions.admin gap lives here).
echo "CI service account roles (${CI_SA}):"
ci_roles="$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${CI_SA}" \
  --format='value(bindings.role)' 2>/dev/null || true)"
missing_roles=()
for role in "${REQUIRED_ROLES[@]}"; do
  printf '%s\n' "$ci_roles" | grep -qxF "$role" || missing_roles+=("$role")
done
if [[ "${#missing_roles[@]}" -eq 0 ]]; then
  pass "all ${#REQUIRED_ROLES[@]} required roles present"
else
  fail "missing roles: ${missing_roles[*]} — grant via terraform apply (terraform/core/iam.tf)"
fi

# 4 — WIF pool ACTIVE + provider scoped to this environment.
echo "Workload Identity Federation (pool=${WIF_POOL}, provider=${WIF_PROVIDER}):"
wif_state="$(gcloud iam workload-identity-pools describe "$WIF_POOL" \
  --location=global --project "$PROJECT_ID" --format='value(state)' 2>/dev/null || true)"
case "$wif_state" in
  ACTIVE) pass "WIF pool is ACTIVE" ;;
  DELETED) fail "WIF pool is soft-deleted — undelete it, or use a fresh project (see docs/CREATE_NEW_ENVIRONMENT.md)" ;;
  *) fail "WIF pool '${WIF_POOL}' not found in ${PROJECT_ID}" ;;
esac

wif_cond="$(gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
  --workload-identity-pool="$WIF_POOL" --location=global --project "$PROJECT_ID" \
  --format='value(attributeCondition)' 2>/dev/null || true)"
if [[ -z "$wif_cond" ]]; then
  fail "WIF provider '${WIF_PROVIDER}' not found or has no attribute condition"
else
  if printf '%s' "$wif_cond" | grep -qF "assertion.environment == '${ENVIRONMENT}'" \
     && printf '%s' "$wif_cond" | grep -qF "assertion.repository == '${GITHUB_REPO}'"; then
    pass "WIF provider is scoped to environment '${ENVIRONMENT}' and repo '${GITHUB_REPO}'"
  else
    fail "WIF provider attribute condition is not scoped to environment '${ENVIRONMENT}' + repo '${GITHUB_REPO}'"
  fi
fi
echo "  note: WIF pool/provider/binding changes must be applied operator-local (catvox-ci-sa lacks workloadIdentityPoolAdmin)."

# 4b — CI SA impersonation binding. This is the half the pool/provider checks
# above do NOT cover: roles/iam.workloadIdentityUser for the env's principalSet
# is what lets the federated identity actually impersonate catvox-ci-sa. The #101
# Dev outage was exactly this binding missing while the pool + provider stayed
# correct, so the existing WIF checks would have stayed green.
wif_binding_members="$(gcloud iam service-accounts get-iam-policy "$CI_SA" --project "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --filter="bindings.role:roles/iam.workloadIdentityUser" \
  --format='value(bindings.members)' 2>/dev/null || true)"
if printf '%s\n' "$wif_binding_members" | grep -qF "workloadIdentityPools/${WIF_POOL}/attribute.environment/${ENVIRONMENT}"; then
  pass "CI SA has the WIF impersonation binding (roles/iam.workloadIdentityUser, attribute.environment/${ENVIRONMENT})"
else
  fail "CI SA is missing roles/iam.workloadIdentityUser for principalSet .../attribute.environment/${ENVIRONMENT} — GitHub Actions cannot impersonate ${CI_SA}; every WIF auth fails. Restore operator-local: terraform apply (google_service_account_iam_member.ci_sa_wif_binding)"
fi

# 4c — The provider attribute_mapping must map attribute.environment. The
# impersonation principalSet above keys on the MAPPED attribute, while the
# condition check reads the raw assertion — different namespaces, no coupling. If
# the mapping drops attribute.environment, the binding resolves to nobody even
# with a correct condition.
wif_map_env="$(gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
  --workload-identity-pool="$WIF_POOL" --location=global --project "$PROJECT_ID" \
  --format='value(attributeMapping["attribute.environment"])' 2>/dev/null || true)"
if [[ "$wif_map_env" == "assertion.environment" ]]; then
  pass "WIF provider maps attribute.environment = assertion.environment"
else
  fail "WIF provider attribute_mapping is missing attribute.environment=assertion.environment — the impersonation principalSet resolves to nobody. Fix operator-local: terraform apply (provider attribute_mapping)"
fi

# 4d — Cloud Functions Gen2 builds run as the Compute Engine default SA, not
# catvox-ci-sa, so its grants are invisible to the CI-SA check above. Missing
# ones fail the deploy mid-build while the doctor otherwise stays green
# (terraform/core/iam.tf compute_sa_*).
echo "Cloud Functions Gen2 build identity (compute default SA):"
if [[ -z "$PROJECT_NUMBER" ]]; then
  warn "could not resolve project number — skipped compute-SA build-identity checks"
else
  COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
  compute_roles="$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten='bindings[].members' \
    --filter="bindings.members:serviceAccount:${COMPUTE_SA}" \
    --format='value(bindings.role)' 2>/dev/null || true)"
  for role in roles/artifactregistry.writer roles/logging.logWriter; do
    if printf '%s\n' "$compute_roles" | grep -qxF "$role"; then
      pass "compute SA has ${role}"
    else
      fail "compute SA (${COMPUTE_SA}) missing ${role} — Gen2 build fails (image push / build logs); grant via terraform apply (terraform/core/iam.tf compute_sa_*)"
    fi
  done
  backend_actas="$(gcloud iam service-accounts get-iam-policy "$BACKEND_SA" --project "$PROJECT_ID" \
    --flatten='bindings[].members' \
    --filter="bindings.role:roles/iam.serviceAccountUser" \
    --format='value(bindings.members)' 2>/dev/null || true)"
  if printf '%s\n' "$backend_actas" | grep -qF "serviceAccount:${COMPUTE_SA}"; then
    pass "compute SA can actAs ${BACKEND_SA} (roles/iam.serviceAccountUser)"
  else
    fail "compute SA (${COMPUTE_SA}) lacks roles/iam.serviceAccountUser on ${BACKEND_SA} — Gen2 deploy fails setting the Cloud Run runtime identity (iam.serviceAccounts.actAs denied); grant via terraform apply"
  fi
  # The gcf-v2-sources bucket grant is count-gated (CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM)
  # and the bucket may not exist before the first deploy — WARN, never FAIL.
  # `gcloud storage buckets get-iam-policy` takes no list flags (gcloud 592
  # rejects --filter), so read the whole policy as JSON and look for the
  # binding in it. A failed or unreadable read gets its own WARN: it says
  # nothing about the grant.
  if [[ -n "$REGION" ]]; then
    src_bucket="gcf-v2-sources-${PROJECT_NUMBER}-${REGION}"
    if ! gcloud storage buckets describe "gs://${src_bucket}" --project "$PROJECT_ID" >/dev/null 2>&1; then
      warn "gcf-v2-sources bucket not present yet — created on first deploy"
    else
      src_iam_rc=0
      capture_gcloud storage buckets get-iam-policy "gs://${src_bucket}" --project "$PROJECT_ID" --format=json || src_iam_rc=$?
      if [[ "$src_iam_rc" -ne 0 ]]; then
        warn "could not read the IAM policy of ${src_bucket} (gcloud exited ${src_iam_rc}: ${CAPTURED_ERR:-no error output}) — storage.objectAdmin for the compute SA is unverified"
      else
        grant_rc=0
        policy_binds roles/storage.objectAdmin "serviceAccount:${COMPUTE_SA}" <<< "$CAPTURED_OUT" || grant_rc=$?
        case "$grant_rc" in
          0) pass "compute SA has storage.objectAdmin on ${src_bucket}" ;;
          20) warn "compute SA lacks storage.objectAdmin on ${src_bucket} — Gen2 source fetch may 403 if CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM=true" ;;
          *) warn "could not parse the IAM policy gcloud returned for ${src_bucket} (exit ${grant_rc}) — storage.objectAdmin for the compute SA is unverified" ;;
        esac
      fi
    fi
  fi
fi

# 5 — Functions build-image cleanup policy (informational). Gen2 builds push to
# gcf-artifacts, the repository Cloud Functions creates on the first deploy, and
# that is where `make functions-deploy` sets the cleanup policy (firebase
# functions:artifacts:setpolicy). The Terraform-managed catvox-functions
# repository receives no images, so checking it could never pass.
FUNCTIONS_IMAGE_REPO="gcf-artifacts"
echo "Artifact Registry (${FUNCTIONS_IMAGE_REPO}, the Functions build images):"
if [[ -z "$REGION" ]]; then
  warn "CATVOX_FUNCTION_REGION unset — skipped Artifact Registry check"
elif gcloud artifacts repositories describe "$FUNCTIONS_IMAGE_REPO" \
       --location="$REGION" --project "$PROJECT_ID" --format='value(name)' >/dev/null 2>&1; then
  policy="$(gcloud artifacts repositories describe "$FUNCTIONS_IMAGE_REPO" \
    --location="$REGION" --project "$PROJECT_ID" --format='value(cleanupPolicies)' 2>/dev/null || true)"
  if [[ -n "$policy" ]]; then
    pass "${FUNCTIONS_IMAGE_REPO} has a cleanup policy"
  else
    # The command `make functions-deploy` runs before deploying (keep the two in
    # step). On a brand-new project that run comes before the repository exists,
    # so the first deploy leaves the policy unset.
    warn "${FUNCTIONS_IMAGE_REPO} has no cleanup policy — set it with: firebase functions:artifacts:setpolicy --project ${PROJECT_ID} --location ${REGION} --days 7 --non-interactive --force"
  fi
else
  warn "${FUNCTIONS_IMAGE_REPO} not present yet — the first Functions deploy creates it"
fi

# 6 — Terraform state bucket reachable.
echo "Terraform state bucket (${STATE_BUCKET}):"
if gcloud storage buckets describe "gs://${STATE_BUCKET}" --project "$PROJECT_ID" >/dev/null 2>&1; then
  pass "state bucket is reachable"
else
  fail "state bucket gs://${STATE_BUCKET} is not reachable — create it before init (see scripts/create-environment.sh)"
fi

echo
echo "Summary for ${ENVIRONMENT}: ${problems} problem(s), ${warns} warning(s)."
if [[ "$problems" -ne 0 ]]; then
  echo "environment-doctor FAILED — resolve the FAIL items above before deploying." >&2
  exit 1
fi
echo "environment-doctor passed."
