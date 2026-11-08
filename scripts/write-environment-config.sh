#!/usr/bin/env bash
# Write the resolved non-secret values for a CatVox environment into its
# committed config/environments/<env>.xcconfig, reading them from Terraform
# outputs, the generated Firebase plist, and (post-deploy) the deployed Cloud Run
# hosts — so the operator never hand-pastes them. Replaces the manual copy steps
# in docs/CREATE_NEW_ENVIRONMENT.md. Issue #108.
#
# Environment-agnostic: the same command works for mutable (dev-like) and
# protected (prod-like) environments. Literal environment names never appear
# here — everything is keyed off CATVOX_ENVIRONMENT.
#
#   WRITE_CONFIG_PHASE   identity | hosts | posthog | all   (default: identity)
#     identity  values that exist after `terraform apply` + plist export:
#               CATVOX_GCP_CI_SERVICE_ACCOUNT, CATVOX_GCP_WIF_PROVIDER,
#               CATVOX_FIREBASE_APP_ID (Terraform outputs) and
#               CATVOX_FIREBASE_API_KEY (read from the plist — Terraform exposes
#               only the key *id*, not its value).
#     hosts     the two Cloud Run host keys, which exist only after the Functions
#               deploy: CATVOX_SIGNED_UPLOAD_URL_HOST, CATVOX_ANALYSE_VIDEO_HOST.
#     posthog   values that exist after PostHog Terraform apply:
#               CATVOX_POSTHOG_PROJECT_ID and CATVOX_POSTHOG_PROJECT_TOKEN.
#     all       identity, then hosts, then posthog.
#
#   ALLOW_MISSING_HOSTS  0 | 1   (default: 0)
#     1 lets the hosts phase skip a function that is not deployed yet (gcloud
#     answers with a 404 naming it), leaving its key unchanged. Any other lookup
#     failure still fails the run.
#
# Writes the working tree only. It never stages or commits — the operator
# reviews the diff and commits (this keeps committed config, especially a
# protected environment's xcconfig, under operator control). Idempotent:
# re-running converges the managed keys and leaves every other line untouched, so
# an unchanged re-run produces no diff.
#
# Backend check: a Terraform working directory keeps whatever backend the last
# `make terraform-init` selected, which may be another environment's. Before any
# value is written, every root this run reads must prove it belongs to this
# environment: terraform/core's terraform_state_bucket_name output must equal
# CATVOX_TF_STATE_BUCKET in the environment's xcconfig, and terraform/posthog's
# environment_name output must equal CATVOX_ENVIRONMENT.
#
# Identity reads are strict (a missing Terraform output or plist fails the run —
# the precondition is that apply + plist export already happened). Host reads are
# strict too: both hosts are resolved before either is written, and a function
# that is not deployed fails the run unless ALLOW_MISSING_HOSTS=1 (then it is
# reported and skipped — re-run PHASE=hosts after the deploy). A lookup that fails
# for any other reason (auth, permission, an unknown region, no service URI)
# always fails the run.
#
# Expects the same environment the Makefile terraform targets read, and that
# `make terraform-init` (and apply) has already run for this environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ENVIRONMENT="${CATVOX_ENVIRONMENT:?CATVOX_ENVIRONMENT is required}"
ENV_CONFIG="${CATVOX_ENV_CONFIG:-config/environments/${ENVIRONMENT}.xcconfig}"
PHASE="${WRITE_CONFIG_PHASE:-identity}"
PROJECT_ID="${CATVOX_PROJECT_ID:-}"
REGION="${CATVOX_FUNCTION_REGION:-}"
PLIST="${CATVOX_FIREBASE_PLIST_OUTPUT:-CatVox/Resources/Firebase/GoogleService-Info-${ENVIRONMENT}.plist}"
ALLOW_MISSING_HOSTS="${ALLOW_MISSING_HOSTS:-0}"

# Cloud Run function names are part of the backend contract and identical in
# every environment (TRD §6.2). Each maps to the host-only xcconfig key it fills.
FUNCTION_GETSIGNEDUPLOADURL="getSignedUploadURL"
FUNCTION_ANALYSEVIDEO="analyseVideo"

case "$PHASE" in
  identity | hosts | posthog | all) ;;
  *) echo "WRITE_CONFIG_PHASE must be 'identity', 'hosts', 'posthog', or 'all' (got: $PHASE)" >&2; exit 1 ;;
esac

case "$ALLOW_MISSING_HOSTS" in
  0 | 1) ;;
  *) echo "ALLOW_MISSING_HOSTS must be 0 or 1 (got: $ALLOW_MISSING_HOSTS)" >&2; exit 1 ;;
esac

if [[ ! -f "$ENV_CONFIG" ]]; then
  echo "ERROR: environment config not found: ${ENV_CONFIG}" >&2
  echo "Create the xcconfig skeleton first (see docs/CREATE_NEW_ENVIRONMENT.md)." >&2
  exit 1
fi

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}

# Collapse a single-token value to itself with all surrounding whitespace and any
# stray CR/newline removed. The xcconfig values handled here (emails, app ids,
# resource names, hostnames) contain no internal whitespace, so stripping all of
# it is safe and immune to the `terraform output -raw` trailing-`%`/newline trap.
clean_token() { printf '%s' "$1" | tr -d '[:space:]'; }

# Replace KEY's value in the xcconfig (canonical `KEY = VALUE` form), or append
# the key if it is absent. Whole-file rewrite into a temp file, then an in-place
# content overwrite that preserves the file's permissions and inode. A no-op when
# the value already matches, so re-runs leave a clean git diff. KEY and VALUE are
# passed through the environment (not awk -v) so backslashes are never reinterpreted.
set_xcconfig_value() {
  local key="$1" val="$2" tmp existed
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$ENV_CONFIG"; then existed=1; else existed=0; fi
  tmp="$(mktemp "${ENV_CONFIG}.XXXXXX")"
  WC_KEY="$key" WC_VAL="$val" awk '
    BEGIN { k = ENVIRON["WC_KEY"]; v = ENVIRON["WC_VAL"]; seen = 0 }
    {
      if (!seen && $0 ~ ("^[ \t]*" k "[ \t]*=")) { print k " = " v; seen = 1 }
      else { print }
    }
    END { if (!seen) print k " = " v }
  ' "$ENV_CONFIG" > "$tmp"
  if cmp -s "$tmp" "$ENV_CONFIG"; then
    rm -f "$tmp"
    echo "  unchanged: ${key}"
    return 0
  fi
  cat "$tmp" > "$ENV_CONFIG"
  rm -f "$tmp"
  if [[ "$existed" == "1" ]]; then echo "  updated:   ${key}"; else echo "  added:     ${key} (was absent)"; fi
}

# Strict read of a Terraform output. `$(...)` already strips the trailing newline,
# so the value lands clean with no `%` end-of-line marker.
tf_output() {
  local name="$1" val
  if ! val="$(terraform -chdir="${REPO_ROOT}/terraform/core" output -raw "$name" 2>/dev/null)"; then
    echo "ERROR: could not read Terraform output '${name}'." >&2
    echo "Run 'make terraform-init' (and apply) for ${ENVIRONMENT} first." >&2
    return 1
  fi
  clean_token "$val"
}

posthog_tf_output() {
  local name="$1" val
  if ! val="$(terraform -chdir="${REPO_ROOT}/terraform/posthog" output -raw "$name" 2>/dev/null)"; then
    echo "ERROR: could not read PostHog Terraform output '${name}'." >&2
    echo "Run 'make posthog-terraform-init' and apply PostHog Terraform for ${ENVIRONMENT} first." >&2
    return 1
  fi
  clean_token "$val"
}

# Fail unless terraform/core is initialised against this environment's state
# bucket (the one its committed xcconfig names), so no other environment's
# outputs are ever read as this one's.
assert_core_backend() {
  local expected actual
  expected="$("${REPO_ROOT}/scripts/lib/read-xcconfig-value.sh" "$ENV_CONFIG" CATVOX_TF_STATE_BUCKET)"
  if [[ -z "$expected" ]]; then
    echo "ERROR: ${ENV_CONFIG} does not set CATVOX_TF_STATE_BUCKET, so the Terraform backend cannot be checked." >&2
    exit 1
  fi
  if ! actual="$(tf_output terraform_state_bucket_name)"; then
    echo "Could not confirm terraform/core is initialised for ${ENVIRONMENT}." >&2
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: terraform/core is initialised against state bucket '${actual}', but ${ENVIRONMENT} uses '${expected}' (${ENV_CONFIG})." >&2
    echo "Its outputs belong to another environment. Run 'make terraform-init CATVOX_ENVIRONMENT=${ENVIRONMENT}', then re-run." >&2
    if [[ -n "${CATVOX_TF_STATE_BUCKET:-}" && "${CATVOX_TF_STATE_BUCKET}" != "$expected" ]]; then
      echo "CATVOX_TF_STATE_BUCKET=${CATVOX_TF_STATE_BUCKET} is set in your environment and overrides the xcconfig in make." >&2
      echo "If that is ${ENVIRONMENT}'s bucket, update CATVOX_TF_STATE_BUCKET in ${ENV_CONFIG} first; otherwise unset it." >&2
    fi
    exit 1
  fi
}

# Fail unless terraform/posthog is initialised against this environment's
# PostHog state (its environment_name output names the environment).
assert_posthog_backend() {
  local actual
  if ! actual="$(posthog_tf_output environment_name)"; then
    echo "Could not confirm terraform/posthog is initialised for ${ENVIRONMENT}." >&2
    exit 1
  fi
  if [[ "$actual" != "$ENVIRONMENT" ]]; then
    echo "ERROR: terraform/posthog is initialised against the '${actual}' environment's state, not ${ENVIRONMENT}'s." >&2
    echo "Run 'make posthog-terraform-init CATVOX_ENVIRONMENT=${ENVIRONMENT}', then re-run." >&2
    exit 1
  fi
}

write_identity() {
  require_tool terraform
  require_tool plutil
  if [[ ! -f "$PLIST" ]]; then
    echo "ERROR: Firebase plist not found: ${PLIST}" >&2
    echo "Run 'make terraform-output-firebase-plist' for ${ENVIRONMENT} first." >&2
    exit 1
  fi

  local ci_sa wif_provider app_id api_key
  ci_sa="$(tf_output ci_service_account_email)"
  wif_provider="$(tf_output github_actions_wif_provider)"
  app_id="$(tf_output firebase_ios_app_id)"
  if ! api_key="$(plutil -extract API_KEY raw "$PLIST" 2>/dev/null)"; then
    echo "ERROR: could not read API_KEY from ${PLIST}." >&2
    exit 1
  fi
  api_key="$(clean_token "$api_key")"

  echo "Writing identity values into ${ENV_CONFIG}:"
  set_xcconfig_value CATVOX_GCP_CI_SERVICE_ACCOUNT "$ci_sa"
  set_xcconfig_value CATVOX_GCP_WIF_PROVIDER "$wif_provider"
  set_xcconfig_value CATVOX_FIREBASE_APP_ID "$app_id"
  set_xcconfig_value CATVOX_FIREBASE_API_KEY "$api_key"
}

write_posthog() {
  require_tool terraform

  local project_id project_token
  project_id="$(posthog_tf_output project_id)"
  project_token="$(posthog_tf_output project_api_token)"

  echo "Writing PostHog values into ${ENV_CONFIG}:"
  set_xcconfig_value CATVOX_POSTHOG_PROJECT_ID "$project_id"
  set_xcconfig_value CATVOX_POSTHOG_PROJECT_TOKEN "$project_token"
}

# Read a deployed Cloud Run function's host. Prints the hostname only (no
# scheme/path) and returns 0 when deployed. Returns 3 only on gcloud's answer
# for a function that is not deployed: a 404 naming this exact function,
# "Resource 'projects/<project>/locations/<region>/functions/<name>' was not
# found" (gcloud 592). Any other failure returns 1 and is never mistaken for
# "not deployed": auth, permission, transient, a function with no service URI,
# or an unknown region, whose 403 also says "not found" ("Location <region> is
# not found or access is unauthorized.").
function_host() {
  local name="$1" uri host err_file rc=0
  err_file="$(mktemp "${TMPDIR:-/tmp}/catvox-function-describe.XXXXXX")" || {
    echo "ERROR: could not create a temp file to read ${name}." >&2
    return 1
  }
  uri="$(gcloud functions describe "$name" --v2 \
        --project "$PROJECT_ID" --region "$REGION" \
        --format='value(serviceConfig.uri)' 2>"$err_file")" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    if grep -qF -- "Resource 'projects/${PROJECT_ID}/locations/${REGION}/functions/${name}' was not found" "$err_file"; then
      rm -f "$err_file"
      return 3
    fi
    echo "ERROR: could not read ${name} (gcloud functions describe exited ${rc}):" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi
  rm -f "$err_file"
  uri="$(clean_token "$uri")"
  if [[ -z "$uri" ]]; then
    echo "ERROR: ${name} exists but reports no service URI (deploy incomplete or failed?)." >&2
    return 1
  fi
  host="${uri#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  printf '%s' "$host"
}

# Resolve the host for KEY from function NAME. Prints the host, or nothing when
# a not-deployed function is skipped under ALLOW_MISSING_HOSTS=1; returns
# non-zero when the run must fail.
lookup_host() {
  local name="$1" key="$2" host rc=0
  host="$(function_host "$name")" || rc=$?
  case "$rc" in
    0)
      printf '%s' "$host"
      ;;
    3)
      if [[ "$ALLOW_MISSING_HOSTS" == "1" ]]; then
        echo "  skipped:   ${key} (${name} not deployed yet; re-run PHASE=hosts after deploy)" >&2
      else
        echo "ERROR: ${name} is not deployed in ${PROJECT_ID} (${REGION}), so ${key} cannot be filled." >&2
        echo "Deploy the functions first, or pass ALLOW_MISSING_HOSTS=1 to fill only the deployed ones." >&2
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

write_hosts() {
  require_tool gcloud
  [[ -n "$PROJECT_ID" ]] || { echo "ERROR: CATVOX_PROJECT_ID is required for the hosts phase." >&2; exit 1; }
  [[ -n "$REGION" ]] || { echo "ERROR: CATVOX_FUNCTION_REGION is required for the hosts phase." >&2; exit 1; }

  # Resolve both hosts before writing either, so a failed lookup leaves the
  # file untouched.
  local upload_host analyse_host failed=0
  upload_host="$(lookup_host "$FUNCTION_GETSIGNEDUPLOADURL" CATVOX_SIGNED_UPLOAD_URL_HOST)" || failed=1
  analyse_host="$(lookup_host "$FUNCTION_ANALYSEVIDEO" CATVOX_ANALYSE_VIDEO_HOST)" || failed=1
  if [[ "$failed" == "1" ]]; then
    echo "No backend host values were written to ${ENV_CONFIG}." >&2
    exit 1
  fi

  echo "Writing backend host values into ${ENV_CONFIG}:"
  if [[ -n "$upload_host" ]]; then
    set_xcconfig_value CATVOX_SIGNED_UPLOAD_URL_HOST "$upload_host"
  fi
  if [[ -n "$analyse_host" ]]; then
    set_xcconfig_value CATVOX_ANALYSE_VIDEO_HOST "$analyse_host"
  fi
}

# Every Terraform root this run reads must belong to this environment, checked
# before any phase writes a value.
if [[ "$PHASE" == "identity" || "$PHASE" == "all" ]]; then
  require_tool terraform
  assert_core_backend
fi
if [[ "$PHASE" == "posthog" || "$PHASE" == "all" ]]; then
  require_tool terraform
  assert_posthog_backend
fi

if [[ "$PHASE" == "identity" || "$PHASE" == "all" ]]; then
  write_identity
fi
if [[ "$PHASE" == "hosts" || "$PHASE" == "all" ]]; then
  write_hosts
fi
if [[ "$PHASE" == "posthog" || "$PHASE" == "all" ]]; then
  write_posthog
fi

echo "Done. Review the diff and commit ${ENV_CONFIG} when it looks right."
