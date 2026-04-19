###############################################################################
# CatVox AI — Service Account & IAM
# TRD §6.3 — least-privilege policy; exact roles specified in spec.
###############################################################################

# ── Service Account ───────────────────────────────────────────────────────────

resource "google_service_account" "backend_sa" {
  account_id   = "catvox-backend-sa"
  display_name = "CatVox Backend"
  description  = "Least-privilege runtime SA for CatVox Cloud Functions (TRD §6.3)."
}

# ── IAM Bindings — exact roles from TRD §6.3 ─────────────────────────────────

# Vertex AI — call Gemini 3.1 Flash for multimodal video analysis.
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

# Firestore — read and write usage/{userId} documents for credit enforcement.
resource "google_project_iam_member" "datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# ── IAM Bindings — implied by TRD §6.3 (zero hardcoded secrets) ──────────────

# Secret Manager — resolve GCP_PROJECT_ID and APP_CHECK_DEBUG_TOKEN at runtime.
resource "google_project_iam_member" "secretmanager_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# Signed URL generation — the SA must be able to self-sign tokens in order to
# produce short-lived GCS upload URLs for the iOS client (TRD §6.2 pipeline).
# This grants the SA the Token Creator role on itself only — not project-wide.
resource "google_service_account_iam_member" "sa_token_creator" {
  service_account_id = google_service_account.backend_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.backend_sa.email}"
}
