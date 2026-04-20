# ADR-006: Split Runtime and CI Service Accounts

- Status: Accepted
- Date: 2026-04-19
- Owners: Kathelix / CatVox
- Related docs: `docs/TRD.md`

## Context

CatVox needs two distinct types of GCP identity:

- a **runtime identity** for Cloud Functions — needs access to Vertex AI, Cloud Storage, Firestore, and Secret Manager at request time
- a **CI/CD identity** for GitHub Actions Terraform runs — needs broad IaC rights to create and configure GCP resources

An earlier iteration of the project used a single service account (`catvox-backend-sa`) for both purposes. This meant the runtime identity held CI-level permissions, and the CI pipeline was bound to the same SA that handles live production traffic.

## Decision

CatVox will use **two strictly separated service accounts**:

- **`catvox-backend-sa`** — runtime identity for Cloud Functions; holds only the minimal roles required at request time
- **`catvox-ci-sa`** — CI/CD identity for GitHub Actions Terraform plan/apply; holds the broader IaC rights required to manage GCP resources

Neither SA holds the roles of the other. The split is enforced in Terraform and documented in `TRD.md §6.3`.

## Rationale

### 1. Reduced blast radius

If `catvox-backend-sa` is compromised (e.g. via a vulnerability in the Cloud Function), an attacker gains access only to the minimal runtime roles. Without this split, a compromised runtime SA with CI-level roles would give near-full project control.

### 2. Principle of least privilege

Each identity holds exactly the roles it needs to do its job. `catvox-backend-sa` has no ability to modify infrastructure or manage IAM. `catvox-ci-sa` has no runtime access to Vertex AI or end-user data.

### 3. Clear audit and change trail

IAM changes to the runtime identity are reviewed through Terraform PRs, not conflated with runtime credential management. Any unexpected change to the runtime SA's roles is immediately visible.

### 4. Alignment with WIF security model

Workload Identity Federation (ADR-0005) binds `catvox-ci-sa` to the `IvanBoyko/catvox` GitHub repository. Keeping the CI SA separate means the WIF trust boundary is isolated to infrastructure operations, not production data access.

## Consequences

### Positive

- Weaker runtime credential blast radius
- Clear separation of concerns between infrastructure management and production operation
- Easier to audit and reason about each identity's access independently

### Negative / Trade-offs

- Two service accounts to manage instead of one
- Bootstrap sequence is more involved: `catvox-ci-sa` must exist before it can manage its own downstream IAM, requiring a manual bootstrap step
- Post-split, three manual steps are required: re-run `bootstrap_wif.sh`, update the `GCP_SERVICE_ACCOUNT` GitHub secret, and optionally clean up the old WIF binding on `catvox-backend-sa`

## Rejected Options

### Option A: Single shared service account for runtime and CI

Rejected because:

- it combines runtime and IaC privileges in one identity, creating an unnecessarily wide blast radius
- a compromised Cloud Function would have near-full project access

### Option B: Use owner/personal credentials for Terraform CI

Rejected because:

- personal credentials are not suitable for automated pipelines
- no auditability or rotation capability
- superseded by the WIF approach in ADR-0005

### Option C: Dedicated SA per Cloud Function

Rejected because:

- over-engineering for the current MVP scope
- all CatVox Cloud Functions share the same minimal runtime roles; a single runtime SA is sufficient
- can be revisited if the function surface area grows substantially

## Implementation Notes

- `catvox-backend-sa` roles: `aiplatform.user`, `storage.objectViewer`, `datastore.user`, `secretmanager.secretAccessor`, `iam.serviceAccountTokenCreator` (self only)
- `catvox-ci-sa` roles: `roles/editor`, `roles/resourcemanager.projectIamAdmin`, `roles/iam.serviceAccountAdmin`, `roles/secretmanager.secretAccessor`
- All bindings are managed in `terraform/iam.tf`
- The elevated CI roles (`projectIamAdmin`, `serviceAccountAdmin`) are a known trade-off flagged in `TRD.md §9` for post-MVP review

## Required Document Updates

### TRD

- `§6.3` — document both SAs with their full role lists and the rationale for separation; cross-reference this ADR

### HLD

- Add a statement that CatVox uses two separated GCP service accounts: one for runtime, one for CI/CD, to limit blast radius

## Review Trigger

Revisit this ADR if any of the following becomes true:

- the Cloud Function surface area grows to the point where per-function identities are warranted
- the CI SA's elevated roles (`projectIamAdmin`, `serviceAccountAdmin`) become a compliance concern
- a Terraform layer split (admin vs infra) is adopted, which would allow dropping `projectIamAdmin` from routine CI
