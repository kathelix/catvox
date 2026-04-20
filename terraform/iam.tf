###############################################################################
# CatVox AI — Service Accounts & IAM
# TRD §6.3 — two SAs with distinct purposes and least-privilege roles.
###############################################################################

# ── Runtime SA — Cloud Functions ─────────────────────────────────────────────
# catvox-backend-sa: identity for running Cloud Functions.
# Holds only the minimal roles needed at runtime — never has CI-level access.

resource "google_service_account" "backend_sa" {
  account_id   = "catvox-backend-sa"
  display_name = "CatVox Backend"
  description  = "Least-privilege runtime identity for CatVox Cloud Functions (TRD §6.3)."
}

# Vertex AI — call Gemini 2.5 Flash for multimodal video analysis.
resource "google_project_iam_member" "aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# Cloud Storage — read video objects by GCS URI when invoking Vertex AI.
resource "google_project_iam_member" "storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# Cloud Storage — create objects in GCS. Required so that signed URLs generated
# by this SA (via signBlob) are accepted by GCS when the iOS client PUTs the
# video file. objectViewer alone is read-only and does not grant write access.
resource "google_project_iam_member" "storage_object_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# Firestore — read and write usage/{userId} documents for credit enforcement.
resource "google_project_iam_member" "datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# Secret Manager — resolve GCP_PROJECT_ID and APP_CHECK_DEBUG_TOKEN at runtime.
resource "google_project_iam_member" "secretmanager_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# Signed URL generation — the SA self-signs tokens to produce short-lived GCS
# upload URLs for the iOS client (TRD §6.2). Scoped to self only.
resource "google_service_account_iam_member" "sa_token_creator" {
  service_account_id = google_service_account.backend_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.backend_sa.email}"
}

# ── Compute Engine Default SA — Functions 2nd Gen Build ──────────────────────
# Cloud Functions 2nd gen (Gen 2) runs builds via Cloud Build, but the build
# job executes as the Compute Engine default service account
# (PROJECT_NUMBER-compute@developer.gserviceaccount.com), NOT the Cloud Build
# default SA. Four grants are required:
#   1. storage.objectAdmin on gcf-v2-sources bucket — gcs-fetcher reads the
#      uploaded function source zip from this bucket during the build step.
#   2. artifactregistry.writer — push the built container image.
#   3. iam.serviceAccountUser on catvox-backend-sa — deploy the Cloud Run
#      service with the correct runtime identity.
#   4. logging.logWriter — write Cloud Build step logs.
#
# The gcf-v2-sources bucket is auto-created by Cloud Functions on first deploy
# and is outside Terraform scope, but its IAM is tracked here.
# Bucket name pattern: gcf-v2-sources-{PROJECT_NUMBER}-{REGION}
#
# All four grants were first applied manually via gcloud (bootstrap) so that
# the initial firebase deploy could succeed; tracked here for state consistency.

data "google_project" "project" {
  project_id = var.project_id
}

locals {
  compute_default_sa = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "compute_sa_sources_object_admin" {
  bucket = "gcf-v2-sources-${data.google_project.project.number}-${var.region}"
  role   = "roles/storage.objectAdmin"
  member = local.compute_default_sa
}

resource "google_project_iam_member" "compute_sa_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = local.compute_default_sa
}

resource "google_service_account_iam_member" "compute_sa_backend_sa_user" {
  service_account_id = google_service_account.backend_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = local.compute_default_sa
}

resource "google_project_iam_member" "compute_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.compute_default_sa
}

# ── CI SA — Terraform / GitHub Actions ───────────────────────────────────────
# catvox-ci-sa: identity for GitHub Actions Terraform plan/apply runs.
# Holds broader project-level rights needed for IaC, isolated from runtime.
#
# The WIF pool and OIDC provider are created by bootstrap_wif.sh (one-time,
# outside Terraform scope). On a fresh project, run bootstrap_wif.sh once
# before the first GitHub Actions run. The bindings below ensure that after a
# destroy/recreate of this SA its IAM policy is fully restored by Terraform
# without any manual steps.
#
# After the first terraform apply that creates this SA, one manual step
# is still required before GitHub Actions will succeed:
#   1. Update GitHub secret GCP_SERVICE_ACCOUNT to:
#      catvox-ci-sa@<project-id>.iam.gserviceaccount.com

resource "google_service_account" "ci_sa" {
  account_id   = "catvox-ci-sa"
  display_name = "CatVox Terraform CI"
  description  = "GitHub Actions identity for Terraform plan/apply via WIF (TRD §6.3)."
}

# roles/editor — manage GCP resources (APIs, GCS, Artifact Registry, Secret
# Manager, Firestore, service accounts).
resource "google_project_iam_member" "tf_ci_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

# roles/resourcemanager.projectIamAdmin — read and write project-level IAM
# bindings (required for all google_project_iam_member resources).
resource "google_project_iam_member" "tf_ci_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

# roles/secretmanager.secretAccessor — required to read secret versions during
# terraform plan/apply. secretmanager.versions.access is intentionally excluded
# from roles/editor for security; must be granted explicitly.
resource "google_project_iam_member" "tf_ci_secretmanager_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

# roles/iam.serviceAccountAdmin — set IAM policies on individual service
# accounts (google_service_account_iam_member resources). This permission is
# intentionally excluded from roles/editor; must be granted explicitly.
resource "google_project_iam_member" "tf_ci_sa_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

# Workload Identity Federation — allow GitHub Actions tokens from
# IvanBoyko/catvox to impersonate catvox-ci-sa. Previously applied only by
# bootstrap_wif.sh; tracked here so destroy/recreate of ci_sa restores this
# binding automatically without needing to re-run the bootstrap script.
resource "google_service_account_iam_member" "ci_sa_wif_binding" {
  service_account_id = google_service_account.ci_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${var.wif_pool_id}/attribute.repository/${var.github_repo}"
}

# Terraform state bucket access — catvox-ci-sa must be able to read, write, and
# lock the GCS state file. The bucket is outside Terraform scope (bootstrapped
# before first tf init), but the IAM binding is tracked here so it is restored
# after a destroy/recreate of ci_sa without any manual gcloud commands.
resource "google_storage_bucket_iam_member" "ci_sa_state_bucket_admin" {
  bucket = var.tf_state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ci_sa.email}"
}
