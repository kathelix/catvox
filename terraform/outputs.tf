###############################################################################
# CatVox AI — Terraform Outputs
# Values referenced when configuring Cloud Functions and the iOS build.
###############################################################################

output "backend_sa_email" {
  description = "Service account email — set as the Cloud Functions runtime SA."
  value       = google_service_account.backend_sa.email
}

output "raw_videos_bucket_name" {
  description = "GCS bucket name for transient video uploads."
  value       = google_storage_bucket.raw_videos.name
}

output "raw_videos_bucket_url" {
  description = "GCS URI prefix used in Vertex AI fileData references."
  value       = "gs://${google_storage_bucket.raw_videos.name}"
}

output "artifact_registry_url" {
  description = "Docker registry URL — used in Cloud Functions deploy commands."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/catvox-functions"
}

output "firestore_database_name" {
  description = "Firestore database name — always '(default)' for the primary database."
  value       = google_firestore_database.default.name
}

output "gcp_project_id_secret_id" {
  description = "Secret Manager secret ID for GCP_PROJECT_ID."
  value       = google_secret_manager_secret.gcp_project_id.secret_id
}

output "app_check_debug_token_secret_id" {
  description = "Secret Manager secret ID for APP_CHECK_DEBUG_TOKEN."
  value       = google_secret_manager_secret.app_check_debug_token.secret_id
}
