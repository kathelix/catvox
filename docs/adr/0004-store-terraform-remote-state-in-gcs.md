# ADR-004: Store Terraform Remote State in GCS and Bootstrap the State Bucket Outside Terraform

- Status: Accepted
- Date: 2026-04-19
- Owners: Kathelix / CatVox
- Related docs: `docs/TRD.md`

## Context

CatVox infrastructure is managed with Terraform on Google Cloud Platform. The project requires:

- shared, durable Terraform state
- safe use of Terraform from both local development and CI/CD
- versioned state history for recovery and auditability
- avoidance of circular dependency during initial infrastructure bootstrap

Terraform state must not live only on a local machine and must not be committed to Git.

## Decision

CatVox will use a **Google Cloud Storage bucket as the Terraform remote backend**.

The Terraform state bucket will:

- be named using the project-specific pattern `catvox-tf-state-<project-id>`
- live in `us-central1`
- have object versioning enabled

The state bucket is **bootstrapped manually outside Terraform** before normal Terraform workflows begin.

Terraform will not attempt to create or manage the state bucket that it itself depends on as a backend.

## Rationale

### 1. Shared and durable state

A remote GCS backend allows consistent Terraform execution from multiple environments without relying on local state files.

### 2. Better recovery characteristics

Object versioning gives a practical recovery path if state is accidentally damaged or overwritten.

### 3. Clean bootstrap model

Trying to create the backend bucket from the same Terraform configuration that depends on that bucket creates an unnecessary bootstrapping cycle. Separating initial backend creation keeps the flow simple and explicit.

### 4. Good fit for GCP-native infrastructure

Because CatVox is already standardized on GCP, GCS is the most natural remote backend choice.

## Consequences

### Positive

- Terraform state is centralized and durable
- Local and CI workflows can use the same backend
- State history is preserved through bucket object versioning
- Bootstrapping is explicit and avoids circular dependency

### Negative / Trade-offs

- One manual bootstrap step is required before Terraform can fully manage the rest of the infrastructure
- The state bucket remains partially outside normal IaC lifecycle management
- Operators must protect access to the backend bucket carefully

## Rejected Options

### Option A: Keep Terraform state local

Rejected because:

- it is unsafe for shared or CI-driven workflows
- it increases risk of drift and accidental loss
- it does not fit the project’s reproducibility goals

### Option B: Attempt to fully create backend state storage from the same Terraform stack

Rejected because:

- it introduces a bootstrap circular dependency
- it complicates first-time setup unnecessarily
- a clear manual bootstrap step is simpler and more robust

## Implementation Notes

- Bootstrap script creates the backend bucket before Terraform init against remote state
- Enable object versioning on the bucket
- Never commit local state to source control
- Scope CI state-bucket access narrowly to what the Terraform pipeline needs

## Required Document Updates

### HLD

Optionally add one short sentence at high level that the infrastructure follows a reproducible Terraform model with **remote state in GCS**.

### TRD

Keep the Terraform backend section, naming convention, and manual bootstrap rule aligned with this ADR. Add an ADR reference near the backend-state subsection if useful.

## Review Trigger

Revisit this ADR if any of the following becomes true:

- the team adopts a different Terraform backend standard
- state access patterns become more complex than the current project needs
- a future platform decision replaces Terraform or materially changes backend requirements
