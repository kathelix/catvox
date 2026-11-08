#!/usr/bin/env bash
# Bootstrap a named CatVox GCP/Firebase environment.
#
# This script is intentionally environment-name based. It creates or verifies
# the GCP/Firebase project, bootstraps remote Terraform state and Functions
# source storage, prepares ignored local Terraform config files, and can
# optionally apply Terraform, export the Firebase plist, and deploy Functions.
#
# Fail-fast preflight: every input is checked before the first cloud mutation,
# so a bad or ambiguous input aborts with nothing created, linked, or written.
#   - exactly one numeric parent, FOLDER_ID or ORGANIZATION_ID (never both); an
#     existing project must already sit under that parent;
#   - the project lookup tells a missing project from a failed lookup: expired
#     credentials or any other error stop the run instead of reading as absent,
#     and an existing project must be ACTIVE;
#   - BILLING_ACCOUNT_ID is required, and billing must read back as enabled
#     after linking, before any bucket is created;
#   - an App Check debug token (APP_CHECK_DEBUG_TOKEN, or one already in the
#     tfvars file) is refused unless config/environments/<env>.xcconfig sets
#     CATVOX_ENVIRONMENT_PROTECTED = false;
#   - an existing terraform/core/env/<env>.tfvars is kept as-is, so a supplied
#     ALERT_EMAIL or APP_CHECK_DEBUG_TOKEN that differs from it is refused
#     rather than silently ignored; the file must be in the plain one-line form
#     this script writes, so what is checked is what Terraform reads.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENVIRONMENT="${CATVOX_ENVIRONMENT:-}"
PROJECT_ID="${CATVOX_PROJECT_ID:-}"
PROJECT_DISPLAY_NAME="${PROJECT_DISPLAY_NAME:-}"
REGION="${CATVOX_FUNCTION_REGION:-}"
FIRESTORE_LOCATION="${CATVOX_FIRESTORE_LOCATION:-}"
STATE_BUCKET="${CATVOX_TF_STATE_BUCKET:-}"
STATE_PREFIX="${CATVOX_TF_STATE_PREFIX:-}"
TFVARS_FILE="${CATVOX_TF_VARS_FILE:-}"
IOS_BUNDLE_ID="${CATVOX_IOS_BUNDLE_ID:-}"
IOS_APP_DISPLAY_NAME="${CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME:-}"
IOS_APP_DELETION_POLICY="${CATVOX_FIREBASE_IOS_APP_DELETION_POLICY:-}"
APPLE_TEAM_ID="${CATVOX_FIREBASE_APPLE_TEAM_ID:-}"
RUN_TERRAFORM_APPLY="${RUN_TERRAFORM_APPLY:-}"
RUN_FUNCTIONS_DEPLOY="${RUN_FUNCTIONS_DEPLOY:-}"
RUN_POSTHOG_TERRAFORM_APPLY="${RUN_POSTHOG_TERRAFORM_APPLY:-}"
MANAGE_GCF_SOURCES_BUCKET_IAM="${CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM:-}"
FOLDER_ID="${FOLDER_ID:-}"
ORGANIZATION_ID="${ORGANIZATION_ID:-}"
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
APP_CHECK_DEBUG_TOKEN="${APP_CHECK_DEBUG_TOKEN:-}"

cd "${REPO_ROOT}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

require_value() {
  local name="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "${name} is required." >&2
    exit 1
  fi
}

normalize_bool() {
  local name="$1"
  local value="$2"
  local normalized

  normalized="$(printf '%s' "$value" | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print tolower($0); }')"
  case "$normalized" in
    true|false)
      printf '%s' "$normalized"
      ;;
    *)
      echo "${name} must be true or false." >&2
      exit 1
      ;;
  esac
}

quote_tf_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Read the existing tfvars file into TFVARS_ALERT_EMAIL and TFVARS_DEBUG_TOKEN:
# the text between the quotes (still escaped, so compare it with
# quote_tf_string output), `null` for a null value, or empty when the key is
# absent. The whole file is parsed, and it must be in the plain form this
# script writes: blank lines, whole-line # or // comments, and one-line
# `key = null` or `key = "string"` assignments of app_check_debug_token and
# alert_email, each at most once and optionally followed by a # or // comment.
# Anything else — a block comment, a multi-line value, a repeated or unknown
# key, text after a value — is refused, so a commented-out or shadowed line can
# never stand in for the assignment Terraform actually reads.
TFVARS_ALERT_EMAIL=""
TFVARS_DEBUG_TOKEN=""
load_tfvars() {
  local parsed key value
  if ! parsed="$(awk '
    function refuse(why) {
      printf "%s line %d: %s\n", FILENAME, FNR, why > "/dev/stderr"
      exit 1
    }
    /^[[:space:]]*$/ || /^[[:space:]]*(#|\/\/)/ { next }
    {
      if ($0 !~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=/) {
        refuse("not a one-line key = value assignment or a whole-line comment")
      }
      key = $0
      sub(/^[[:space:]]+/, "", key)
      sub(/[[:space:]]*=.*$/, "", key)
      if (key != "app_check_debug_token" && key != "alert_email") refuse("unexpected key " key)
      if (key in seen) refuse(key " is assigned more than once")
      seen[key] = 1
      rest = $0
      sub(/^[^=]*=[[:space:]]*/, "", rest)
      if (rest ~ /^null[[:space:]]*((#|\/\/).*)?$/) {
        print key "\tnull"
        next
      }
      if (match(rest, /^"[^"]*"/)) {
        if (substr(rest, RLENGTH + 1) !~ /^[[:space:]]*((#|\/\/).*)?$/) {
          refuse("unexpected text after the value of " key)
        }
        print key "\t" substr(rest, 2, RLENGTH - 2)
        next
      }
      refuse("the value of " key " is not null or a one-line quoted string")
    }
  ' "${TFVARS_FILE}")"; then
    echo "Refusing: ${TFVARS_FILE} is not in the plain form this script can read safely (see above)." >&2
    echo "Keep only whole-line comments and one-line app_check_debug_token and alert_email assignments, or delete the file to regenerate it." >&2
    exit 1
  fi
  while IFS=$'\t' read -r key value; do
    case "${key}" in
      alert_email) TFVARS_ALERT_EMAIL="${value}" ;;
      app_check_debug_token) TFVARS_DEBUG_TOKEN="${value}" ;;
    esac
  done <<< "${parsed}"
}

# An App Check debug token lets any client that holds it pass App Check, so only
# an environment whose committed xcconfig positively declares it mutable
# (CATVOX_ENVIRONMENT_PROTECTED = false) may register one. A missing file, a
# missing key, or any other value fails closed. $1 names where the token came
# from, for the error message.
refuse_debug_token_unless_mutable() {
  local origin="$1" tier
  tier="$("${SCRIPT_DIR}/lib/read-xcconfig-value.sh" "${ENV_CONFIG}" CATVOX_ENVIRONMENT_PROTECTED)"
  case "${tier}" in
    false)
      return 0
      ;;
    true)
      echo "Refusing ${origin}: '${ENVIRONMENT}' is a protected environment (CATVOX_ENVIRONMENT_PROTECTED = true in ${ENV_CONFIG})." >&2
      echo "Protected environments must not register an App Check debug token." >&2
      ;;
    *)
      echo "Refusing ${origin}: cannot confirm '${ENVIRONMENT}' is a mutable environment." >&2
      echo "${ENV_CONFIG} must exist and set CATVOX_ENVIRONMENT_PROTECTED = false (found: '${tier}')." >&2
      ;;
  esac
  exit 1
}

refuse_tfvars_mismatch() {  # $1 = supplied variable, $2 = tfvars key
  echo "Refusing: ${1} does not match ${2} in the existing ${TFVARS_FILE}." >&2
  echo "An existing tfvars file is kept as-is, so the supplied value would be silently ignored." >&2
  echo "Unset ${1} to keep the file's value, or update ${2} in that file (or delete the file to regenerate it), then re-run." >&2
  exit 1
}

# Look up the GCP project three ways: it exists (PROJECT_LIFECYCLE then holds its
# lifecycleState), it is absent, or the lookup failed. Resource Manager answers a
# project that does not exist and one this account cannot see the same way, with
# a permission error ending "(or it may not exist): The caller does not have
# permission". Only that answer, for this project, counts as absent; the create
# that follows then fails loudly if the ID is already taken. Any other failure,
# such as expired credentials, a network error or a disabled API, stops the run
# here instead of reading as a missing project.
PROJECT_STATE=""
PROJECT_LIFECYCLE=""
lookup_project() {
  local err_file rc=0
  if ! err_file="$(mktemp "${TMPDIR:-/tmp}/catvox-project-describe.XXXXXX")"; then
    echo "Could not create a temporary file to look up GCP project ${PROJECT_ID}." >&2
    exit 1
  fi
  PROJECT_LIFECYCLE="$(gcloud projects describe "${PROJECT_ID}" --format='value(lifecycleState)' 2>"${err_file}")" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    PROJECT_STATE="exists"
  elif grep -qF -- "access projects instance [${PROJECT_ID}] (or it may not exist): The caller does not have permission" "${err_file}"; then
    PROJECT_STATE="absent"
  else
    echo "Could not look up GCP project ${PROJECT_ID} (gcloud exited ${rc}); stopping before any change:" >&2
    cat "${err_file}" >&2
    rm -f "${err_file}"
    echo "Fix the error above (for expired credentials, run gcloud auth login), then re-run." >&2
    exit 1
  fi
  rm -f "${err_file}"
}

require_value CATVOX_ENVIRONMENT "${ENVIRONMENT}"
require_value CATVOX_PROJECT_ID "${PROJECT_ID}"
require_value PROJECT_DISPLAY_NAME "${PROJECT_DISPLAY_NAME}"
require_value CATVOX_FUNCTION_REGION "${REGION}"
require_value CATVOX_FIRESTORE_LOCATION "${FIRESTORE_LOCATION}"
require_value CATVOX_TF_STATE_BUCKET "${STATE_BUCKET}"
require_value CATVOX_TF_STATE_PREFIX "${STATE_PREFIX}"
require_value CATVOX_TF_VARS_FILE "${TFVARS_FILE}"
require_value CATVOX_IOS_BUNDLE_ID "${IOS_BUNDLE_ID}"
require_value CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME "${IOS_APP_DISPLAY_NAME}"
require_value CATVOX_FIREBASE_IOS_APP_DELETION_POLICY "${IOS_APP_DELETION_POLICY}"
require_value CATVOX_FIREBASE_APPLE_TEAM_ID "${APPLE_TEAM_ID}"
require_value RUN_TERRAFORM_APPLY "${RUN_TERRAFORM_APPLY}"
require_value RUN_FUNCTIONS_DEPLOY "${RUN_FUNCTIONS_DEPLOY}"
require_value RUN_POSTHOG_TERRAFORM_APPLY "${RUN_POSTHOG_TERRAFORM_APPLY}"
require_value CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM "${MANAGE_GCF_SOURCES_BUCKET_IAM}"

# The committed config that declares this environment's security tier.
ENV_CONFIG="${CATVOX_ENV_CONFIG:-config/environments/${ENVIRONMENT}.xcconfig}"

MANAGE_GCF_SOURCES_BUCKET_IAM="$(normalize_bool CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM "${MANAGE_GCF_SOURCES_BUCKET_IAM}")"

case "${RUN_TERRAFORM_APPLY}" in
  0|1)
    ;;
  *)
    echo "RUN_TERRAFORM_APPLY must be 0 or 1." >&2
    exit 1
    ;;
esac

case "${RUN_POSTHOG_TERRAFORM_APPLY}" in
  0|1)
    ;;
  *)
    echo "RUN_POSTHOG_TERRAFORM_APPLY must be 0 or 1." >&2
    exit 1
    ;;
esac

case "${RUN_FUNCTIONS_DEPLOY}" in
  0|1)
    ;;
  *)
    echo "RUN_FUNCTIONS_DEPLOY must be 0 or 1." >&2
    exit 1
    ;;
esac

require_tool gcloud
require_tool firebase
require_tool terraform
require_tool node

echo "Environment : ${ENVIRONMENT}"
echo "Project     : ${PROJECT_ID}"
echo "Region      : ${REGION}"
echo "State bucket: gs://${STATE_BUCKET}/${STATE_PREFIX}"
echo ""

case "${IOS_APP_DELETION_POLICY}" in
  ABANDON|DELETE)
    ;;
  *)
    echo "FIREBASE_IOS_APP_DELETION_POLICY must be ABANDON or DELETE." >&2
    exit 1
    ;;
esac

# ── Preflight: no cloud calls until every input below checks out ────────────

# Parent: exactly one of FOLDER_ID / ORGANIZATION_ID. Silently preferring one
# when both are set could create the project outside the intended folder, and
# so outside any org-policy exception that folder carries.
if [[ -n "${FOLDER_ID}" && -n "${ORGANIZATION_ID}" ]]; then
  echo "Set exactly one of FOLDER_ID or ORGANIZATION_ID, not both." >&2
  exit 1
elif [[ -n "${FOLDER_ID}" ]]; then
  PARENT_VAR="FOLDER_ID"
  PARENT_TYPE="folder"
  PARENT_ID="${FOLDER_ID}"
elif [[ -n "${ORGANIZATION_ID}" ]]; then
  PARENT_VAR="ORGANIZATION_ID"
  PARENT_TYPE="organization"
  PARENT_ID="${ORGANIZATION_ID}"
else
  echo "Set exactly one of FOLDER_ID or ORGANIZATION_ID: the parent to create the project under (an existing project must already have it)." >&2
  exit 1
fi
if [[ ! "${PARENT_ID}" =~ ^[0-9]+$ ]]; then
  echo "${PARENT_VAR} must be a numeric ${PARENT_TYPE} ID (got: ${PARENT_ID})." >&2
  exit 1
fi

# Billing: required up front. The state bucket below cannot be created on a
# project without billing, and failing there leaves a half-built environment.
require_value BILLING_ACCOUNT_ID "${BILLING_ACCOUNT_ID}"

# App Check debug token and the private tfvars values.
if [[ -n "${APP_CHECK_DEBUG_TOKEN}" ]]; then
  refuse_debug_token_unless_mutable "APP_CHECK_DEBUG_TOKEN"
fi
if [[ -f "${TFVARS_FILE}" ]]; then
  load_tfvars
  if [[ -n "${ALERT_EMAIL}" && "$(quote_tf_string "${ALERT_EMAIL}")" != "${TFVARS_ALERT_EMAIL}" ]]; then
    refuse_tfvars_mismatch ALERT_EMAIL alert_email
  fi
  if [[ -n "${APP_CHECK_DEBUG_TOKEN}" && "$(quote_tf_string "${APP_CHECK_DEBUG_TOKEN}")" != "${TFVARS_DEBUG_TOKEN}" ]]; then
    refuse_tfvars_mismatch APP_CHECK_DEBUG_TOKEN app_check_debug_token
  fi
  # The Makefile passes this file to every terraform plan/apply, so a token
  # already in it is registered exactly like a supplied one.
  if [[ "${TFVARS_DEBUG_TOKEN}" != "null" && -n "${TFVARS_DEBUG_TOKEN//[[:space:]]/}" ]]; then
    refuse_debug_token_unless_mutable "the app_check_debug_token in ${TFVARS_FILE}"
  fi
else
  require_value ALERT_EMAIL "${ALERT_EMAIL}"
fi

# ── Cloud bootstrap ─────────────────────────────────────────────────────────

lookup_project
if [[ "${PROJECT_STATE}" == "exists" ]]; then
  if [[ "${PROJECT_LIFECYCLE}" != "ACTIVE" ]]; then
    echo "GCP project ${PROJECT_ID} exists, but its state is ${PROJECT_LIFECYCLE:-empty}, not ACTIVE." >&2
    echo "Restore it first (gcloud projects undelete ${PROJECT_ID}), or use a new project ID." >&2
    exit 1
  fi
  echo "GCP project ${PROJECT_ID} already exists."
  # The requested parent must hold for an existing project too; otherwise a
  # project made elsewhere would be provisioned outside the intended parent.
  existing_parent_type="$(gcloud projects describe "${PROJECT_ID}" --format='value(parent.type)')"
  existing_parent_id="$(gcloud projects describe "${PROJECT_ID}" --format='value(parent.id)')"
  if [[ "${existing_parent_type}" != "${PARENT_TYPE}" || "${existing_parent_id}" != "${PARENT_ID}" ]]; then
    echo "GCP project ${PROJECT_ID} already exists under ${existing_parent_type:-no parent} ${existing_parent_id}, not the requested ${PARENT_TYPE} ${PARENT_ID}." >&2
    echo "Pass the project's actual parent instead, or move the project under ${PARENT_TYPE} ${PARENT_ID} first." >&2
    exit 1
  fi
else
  echo "GCP project ${PROJECT_ID} was not found (or this account cannot see it); creating it."
  gcloud projects create "${PROJECT_ID}" "--name=${PROJECT_DISPLAY_NAME}" "--${PARENT_TYPE}=${PARENT_ID}"
fi

gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}"
# Confirm billing reads back as enabled before creating the buckets, which need it.
billing_enabled="$(gcloud billing projects describe "${PROJECT_ID}" --format='value(billingEnabled)')"
if [[ "$(printf '%s' "${billing_enabled}" | tr '[:upper:]' '[:lower:]')" != "true" ]]; then
  echo "Billing is not enabled on ${PROJECT_ID} after linking ${BILLING_ACCOUNT_ID} (billingEnabled: ${billing_enabled:-empty})." >&2
  echo "Check that the billing account is open, then re-run." >&2
  exit 1
fi

if firebase projects:list --json --non-interactive | grep -q "\"projectId\": \"${PROJECT_ID}\""; then
  echo "Firebase is already enabled for ${PROJECT_ID}."
else
  firebase projects:addfirebase "${PROJECT_ID}" --non-interactive
fi

if gcloud storage buckets describe "gs://${STATE_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Terraform state bucket ${STATE_BUCKET} already exists."
else
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
fi

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
GCF_SOURCES_BUCKET="gcf-v2-sources-${PROJECT_NUMBER}-${REGION}"

if gcloud storage buckets describe "gs://${GCF_SOURCES_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Cloud Functions source bucket ${GCF_SOURCES_BUCKET} already exists."
else
  gcloud storage buckets create "gs://${GCF_SOURCES_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access
fi

mkdir -p "$(dirname "${TFVARS_FILE}")"

if [[ ! -f "${TFVARS_FILE}" ]]; then
  # The preflight already required ALERT_EMAIL and vetted any debug token.
  app_check_line='app_check_debug_token             = null'
  if [[ -n "${APP_CHECK_DEBUG_TOKEN}" ]]; then
    app_check_line="app_check_debug_token             = \"$(quote_tf_string "${APP_CHECK_DEBUG_TOKEN}")\""
  fi
  cat > "${TFVARS_FILE}" <<EOF
${app_check_line}
alert_email           = "$(quote_tf_string "${ALERT_EMAIL}")"
EOF
  echo "Created ${TFVARS_FILE}"
else
  echo "Keeping existing ${TFVARS_FILE}"
fi

export CATVOX_ENVIRONMENT="${ENVIRONMENT}"
export CATVOX_PROJECT_ID="${PROJECT_ID}"
export CATVOX_FUNCTION_REGION="${REGION}"
export CATVOX_FIRESTORE_LOCATION="${FIRESTORE_LOCATION}"
export CATVOX_TF_STATE_BUCKET="${STATE_BUCKET}"
export CATVOX_TF_STATE_PREFIX="${STATE_PREFIX}"
export CATVOX_TF_VARS_FILE="${TFVARS_FILE}"
export CATVOX_IOS_BUNDLE_ID="${IOS_BUNDLE_ID}"
export CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME="${IOS_APP_DISPLAY_NAME}"
export CATVOX_FIREBASE_IOS_APP_DELETION_POLICY="${IOS_APP_DELETION_POLICY}"
export CATVOX_FIREBASE_APPLE_TEAM_ID="${APPLE_TEAM_ID}"
export CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM="${MANAGE_GCF_SOURCES_BUCKET_IAM}"

make terraform-init \
  CATVOX_ENVIRONMENT="${ENVIRONMENT}" \
  CATVOX_PROJECT_ID="${PROJECT_ID}" \
  CATVOX_TF_VARS_FILE="${TFVARS_FILE}"

# Import pre-existing resources (idempotent) so applying into a project that
# already contains them succeeds instead of failing ALREADY_EXISTS. No-op for a
# brand-new project. See docs/CREATE_NEW_ENVIRONMENT.md and issue #38 Step 3 (S5).
./scripts/import-preexisting-resources.sh

make terraform-plan \
  CATVOX_ENVIRONMENT="${ENVIRONMENT}" \
  CATVOX_PROJECT_ID="${PROJECT_ID}" \
  CATVOX_TF_VARS_FILE="${TFVARS_FILE}"

if [[ "${RUN_TERRAFORM_APPLY}" == "1" ]]; then
  make terraform-ci-apply \
    CATVOX_ENVIRONMENT="${ENVIRONMENT}" \
    CATVOX_PROJECT_ID="${PROJECT_ID}" \
    CATVOX_TF_VARS_FILE="${TFVARS_FILE}"

  make terraform-output-firebase-plist \
    CATVOX_ENVIRONMENT="${ENVIRONMENT}" \
    CATVOX_PROJECT_ID="${PROJECT_ID}" \
    CATVOX_TF_VARS_FILE="${TFVARS_FILE}"
else
  echo "RUN_TERRAFORM_APPLY is not 1; skipped terraform apply and plist export."
fi

if [[ "${RUN_POSTHOG_TERRAFORM_APPLY}" == "1" ]]; then
  make posthog-environment-provision \
    CATVOX_ENVIRONMENT="${ENVIRONMENT}"
else
  echo "RUN_POSTHOG_TERRAFORM_APPLY is not 1; skipped PostHog Terraform apply."
fi

if [[ "${RUN_FUNCTIONS_DEPLOY}" == "1" ]]; then
  # make functions-deploy sets the Artifact Registry cleanup policy itself.
  make functions-deploy \
    CATVOX_ENVIRONMENT="${ENVIRONMENT}" \
    CATVOX_PROJECT_ID="${PROJECT_ID}"
else
  echo "RUN_FUNCTIONS_DEPLOY is not 1; skipped Functions deploy."
fi

cat <<EOF

Remaining secrets to add to the GitHub Environment named '${ENVIRONMENT}':
  TF_VAR_ALERT_EMAIL=<same alert email used in ${TFVARS_FILE}>
  TF_VAR_APP_CHECK_DEBUG_TOKEN=<mutable environments only; same UUID used in ${TFVARS_FILE}>
  POSTHOG_API_KEY=<already set by RUN_POSTHOG_TERRAFORM_APPLY=1, otherwise set manually>

After Terraform apply and Functions deploy, update config/environments/${ENVIRONMENT}.xcconfig with:
  CATVOX_PROJECT_ID=${PROJECT_ID}
  CATVOX_ENVIRONMENT=${ENVIRONMENT}
  CATVOX_FUNCTION_REGION=${REGION}
  CATVOX_FIRESTORE_LOCATION=${FIRESTORE_LOCATION}
  CATVOX_TF_STATE_BUCKET=${STATE_BUCKET}
  CATVOX_GCP_CI_SERVICE_ACCOUNT=catvox-ci-sa@${PROJECT_ID}.iam.gserviceaccount.com
  CATVOX_GCP_WIF_PROVIDER=projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider
  CATVOX_IOS_BUNDLE_ID=${IOS_BUNDLE_ID}
  CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME=${IOS_APP_DISPLAY_NAME}
  CATVOX_FIREBASE_IOS_APP_DELETION_POLICY=${IOS_APP_DELETION_POLICY}
  CATVOX_FIREBASE_APPLE_TEAM_ID=${APPLE_TEAM_ID}
  CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM=${MANAGE_GCF_SOURCES_BUCKET_IAM}
  CATVOX_SIGNED_UPLOAD_URL_HOST=<getSignedUploadURL Cloud Run host only>
  CATVOX_ANALYSE_VIDEO_HOST=<analyseVideo Cloud Run host only>
EOF
