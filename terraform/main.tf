###############################################################################
# CatVox AI — GCP Foundation
# Kathelix Ltd | TRD §6
###############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "catvox-tf-state-kathelix-491213"
    prefix = "catvox/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ── Project APIs ──────────────────────────────────────────────────────────────
# TRD §6.1 — enable all required GCP services.

resource "google_project_service" "apis" {
  for_each = toset([
    "aiplatform.googleapis.com",         # Vertex AI / Gemini
    "cloudfunctions.googleapis.com",     # Cloud Functions
    "run.googleapis.com",                # Functions 2nd gen runs on Cloud Run
    "firestore.googleapis.com",          # Usage guard storage
    "storage.googleapis.com",            # Video uploads
    "secretmanager.googleapis.com",      # Credential management
    "firebase.googleapis.com",           # Firebase platform
    "firebaseappcheck.googleapis.com",   # App Check enforcement
    "iam.googleapis.com",                # SA + role management
    "artifactregistry.googleapis.com",   # Container images for Functions 2nd gen
  ])

  service            = each.value
  disable_on_destroy = false  # Keep APIs enabled on terraform destroy
}

# ── Cloud Storage — Raw Video Bucket ─────────────────────────────────────────
# TRD §6.4 — transient clip hosting; delete after 24 h (privacy + cost).
#
# Bucket name appends project ID for global uniqueness — GCS names are
# world-unique. Base name matches TRD §6.4: "catvox-raw-videos".

resource "google_storage_bucket" "raw_videos" {
  name                        = "catvox-raw-videos-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false  # Prevent accidental data loss

  # TRD §6.4 — delete uploaded clips after 24 h (privacy + cost).
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 1  # days
    }
  }

  # TRD §6.4 — allow direct PUT uploads from the iOS client via signed URLs.
  # origin "*" is safe here because access is controlled by the signed URL
  # itself (time-limited, single-object), not by the CORS origin header.
  cors {
    origin          = ["*"]
    method          = ["PUT", "HEAD"]
    response_header = ["Content-Type", "Content-Length", "ETag"]
    max_age_seconds = 3600
  }

  depends_on = [google_project_service.apis]
}

# ── Artifact Registry — Cloud Functions Container Images ─────────────────────
# TRD §6.1 — Cloud Functions 2nd gen builds container images and stores them
# in Artifact Registry before deploying to Cloud Run.

resource "google_artifact_registry_repository" "functions" {
  location      = var.region
  repository_id = "catvox-functions"
  format        = "DOCKER"
  description   = "Container images for CatVox Cloud Functions (2nd gen) builds."

  depends_on = [google_project_service.apis]
}

# ── Firestore — Usage Guard ───────────────────────────────────────────────────
# TRD §6.4 — collection: usage/{userId}
#             schema:     { count: integer, lastResetDate: string (YYYY-MM-DD) }
#             logic:      backend rejects with 429 when daily limit reached.

resource "google_firestore_database" "default" {
  name        = "(default)"
  location_id = var.firestore_location  # See variables.tf
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.apis]
}

# ── Secret Manager ────────────────────────────────────────────────────────────
# TRD §6.1 — zero hardcoded identifiers; all resolved at Cloud Function
# startup via Secret Manager. Values are never stored in source control.

resource "google_secret_manager_secret" "gcp_project_id" {
  secret_id = "GCP_PROJECT_ID"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "gcp_project_id" {
  secret      = google_secret_manager_secret.gcp_project_id.id
  secret_data = var.project_id
}

resource "google_secret_manager_secret" "app_check_debug_token" {
  secret_id = "APP_CHECK_DEBUG_TOKEN"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "app_check_debug_token" {
  secret      = google_secret_manager_secret.app_check_debug_token.id
  secret_data = var.app_check_debug_token  # sensitive — supplied via tfvars
}
