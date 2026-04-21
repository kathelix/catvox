###############################################################################
# CatVox AI — Terraform Variables
# Populate values in terraform.tfvars (never commit that file).
###############################################################################

variable "project_id" {
  description = "GCP project ID (e.g. kathelix-catvox-prod)."
  type        = string
}

variable "region" {
  description = "Primary GCP region for compute and storage resources."
  type        = string
  default     = "us-central1"
}

variable "firestore_location" {
  description = <<-EOT
    Firestore location ID. Must be set at database creation time and cannot
    be changed afterwards. Use a multi-region ID for high availability:
      nam5  — North America (Iowa + South Carolina)  ← default
      eur3  — Europe (Belgium + Netherlands)
    Or a single-region ID (e.g. us-central1) for lower latency at the cost
    of redundancy.
  EOT
  type        = string
  default     = "nam5"
}

variable "app_check_debug_token" {
  description = <<-EOT
    Firebase App Check debug token for local development.
    Mark as sensitive — never commit the value to source control.
    Generate one in the Firebase Console under App Check → Apps → (overflow menu).
  EOT
  type        = string
  sensitive   = true
}

variable "wif_pool_id" {
  description = "Workload Identity Federation pool ID used by GitHub Actions. Created once by bootstrap_wif.sh."
  type        = string
  default     = "github-actions-pool"
}

variable "github_repo" {
  description = "GitHub repository in 'owner/repo' format, used to scope the WIF token binding on catvox-ci-sa."
  type        = string
  default     = "IvanBoyko/catvox"
}

variable "tf_state_bucket" {
  description = "GCS bucket name for Terraform remote state. Created by bootstrap_remote_state.sh before first terraform init — outside Terraform scope to avoid circular dependency."
  type        = string
  default     = "catvox-tf-state-kathelix-catvox-prod"
}

variable "alert_email" {
  description = "Email address to receive Cloud Monitoring alerts when a Cloud Function emits an ERROR-level log entry."
  type        = string
}
