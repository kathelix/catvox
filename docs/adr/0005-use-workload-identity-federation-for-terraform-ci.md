# ADR-005: Use GitHub Actions Workload Identity Federation for Terraform CI Authentication

- Status: Accepted
- Date: 2026-04-19
- Owners: Kathelix / CatVox
- Related docs: `docs/TRD.md`

## Context

CatVox uses GitHub Actions for infrastructure CI/CD. The Terraform pipeline must authenticate to Google Cloud Platform in order to:

- run `terraform init`, `validate`, `plan`, and `apply`
- manage GCP resources
- access the Terraform state bucket
- operate without embedding long-lived credentials in GitHub

The project emphasizes secure, reproducible infrastructure and wants to minimize credential risk.

## Decision

CatVox will use **Workload Identity Federation (WIF)** from GitHub Actions to Google Cloud Platform for Terraform CI authentication.

The pipeline will:

- use GitHub Actions OIDC tokens
- exchange those tokens for short-lived GCP credentials
- authenticate as the dedicated CI service account `catvox-ci-sa`
- avoid storing long-lived GCP service account keys in GitHub secrets or the repository

## Rationale

### 1. Stronger credential posture

WIF avoids static JSON keys, which are harder to rotate, easier to leak, and generally worse than short-lived federated credentials.

### 2. Good fit for GitHub-hosted CI

GitHub Actions already supports OIDC-based federation, making this a practical and modern approach rather than a custom workaround.

### 3. Clear separation of duties

Using a dedicated CI identity keeps IaC privileges distinct from runtime privileges such as the backend service account.

### 4. Better long-term operability

Federated authentication is easier to reason about and safer to scale than distributing long-lived service account keys.

## Consequences

### Positive

- No long-lived GCP service account keys stored in GitHub
- Better alignment with modern cloud IAM practices
- Cleaner separation between CI and runtime identities
- Lower blast radius than reusing broader or static credentials

### Negative / Trade-offs

- Initial WIF setup is more involved than dropping in a JSON key
- Debugging auth and IAM bindings can be more subtle during bootstrap
- CI depends on correct OIDC and IAM trust configuration

## Rejected Options

### Option A: Store a long-lived GCP service account key in GitHub Secrets

Rejected because:

- it increases credential leakage risk
- it adds rotation burden
- it is weaker than short-lived federated auth

### Option B: Reuse the runtime backend service account for CI

Rejected because:

- it mixes CI and runtime trust boundaries
- it expands blast radius
- CI and runtime have materially different privilege needs

## Implementation Notes

- Create a dedicated CI service account: `catvox-ci-sa`
- Configure WIF pool and OIDC provider for the GitHub repository
- Grant state-bucket access separately where required
- Keep runtime and CI roles isolated
- Use GitHub secrets only for non-key identifiers such as project ID, provider resource name, and service account email

## Required Document Updates

### HLD

Add one concise statement that infrastructure CI/CD uses **keyless GitHub Actions authentication via Workload Identity Federation**.

### TRD

Keep the CI/CD authentication section aligned with this ADR and cross-reference it from the Terraform pipeline section if useful.

## Review Trigger

Revisit this ADR if any of the following becomes true:

- CI moves away from GitHub Actions
- GCP authentication standards change materially
- the project needs a different trust model for deployment automation
