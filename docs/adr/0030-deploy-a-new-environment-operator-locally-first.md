# ADR-0030: Deploy a New Environment Operator-Locally Before Its Config Lands

- Status: Accepted
- Date: 2026-11-07
- Owners: Kathelix / CatVox
- Related docs: `docs/CREATE_NEW_ENVIRONMENT.md`, `docs/CI_BOOTSTRAP.md`,
  `docs/TRD.md` (Environment Model)
- Related ADRs: ADR-0024 (Scope CI WIF Trust to GitHub Environment and Branch
  Ref), ADR-0026 (Classify Environments by Security Tier in Config), ADR-0029
  (Host CatVox in a Kathelix Ltd Google Cloud Organization Folder)

## Context

A *switch PR* is the pull request that commits a new environment's identity —
its `config/environments/<env>.xcconfig` values and Firebase plist — to `main`.

The runbook for a protected environment deployed Functions only through the
protected CI path after that PR merged, and filled in the two backend host keys
(`CATVOX_SIGNED_UPLOAD_URL_HOST`, `CATVOX_ANALYSE_VIDEO_HOST`) after that first
deploy. The config therefore had to reach `main` with `replace-with-*`
placeholder hosts.

PR #135 (2026-06-01) made the Build workflow run the release-safety check
(`make ios-validate-release-safety`) on every iOS and config PR. It validates
the protected environment's config with `requireLive`, which rejects any
placeholder. The previous protected stand-up ran on 2026-05-30, before that
check existed. Followed today, the runbook would turn every PR and `main` red
until the hosts were written.

A mutable environment has the same dependency: its post-deploy integration
tests read the hosts from the committed config. The first Terraform apply of
any new project is already operator-local, because the CI service account
cannot create the WIF pool it authenticates through (ADR-0024).

## Decision

1. **The operator deploys Functions once from the workstation while creating
   any new environment.** It runs `make functions-deploy` after the first
   Terraform apply, the identity config and the PostHog provisioning, all in
   the same operator session. A single `make environment-create` run cannot do
   this for a brand-new environment: right after the apply, its plist export
   validates against the xcconfig, which still holds `replace-with-*` identity
   values, so the run stops there.
2. **The operator then writes the backend hosts before opening the switch
   PR**, using `make environment-write-config PHASE=hosts`. The switch PR is
   then fully live when opened: there are no placeholders, its Terraform and
   PostHog plans show no changes, and smoke checks pass.
3. **After the switch PR merges, CI owns every deploy.** For a protected
   environment, the approval-gated deploy job redeploys the same code through
   the protected path. That approval is the hand-over.
4. **For a protected environment, the operator-local Functions deploy is
   allowed exactly once.** It is the first deploy into a project that no
   released app or public traffic points at yet. Every later deploy goes
   through CI.

Considered alternative: pre-compute the hosts from Cloud Run's deterministic
URL (`<service>-<project-number>.<region>.run.app`). That would keep
protected deploys CI-only, but it changes the host scheme and needs live
verification first. It stays an option if the operator-local exception
becomes a problem.

## Consequences

- No `replace-with-*` value ever lands on `main`, so CI stays green throughout
  an environment's bring-up.
- A protected environment's very first code arrives without passing the
  approval gate. This is acceptable because nothing public uses the
  environment yet, and the next merge puts the same code through the gate.
- The protected checklist in `docs/CREATE_NEW_ENVIRONMENT.md`, the matching
  note in `docs/CI_BOOTSTRAP.md`, and the WIF section of `AGENTS.md` now
  describe this order.
