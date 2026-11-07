# ADR-0029: Host CatVox in a Kathelix Ltd Google Cloud Organization Folder

- Status: Proposed (accepted on merge)
- Date: 2026-11-07
- Owners: Kathelix / CatVox
- Related docs: `docs/CREATE_NEW_ENVIRONMENT.md` (Organization Prerequisites),
  `docs/CI_BOOTSTRAP.md`, `docs/CUTOVER_AND_ROLLBACK.md`
- Related ADRs: ADR-0002 (App Attest for App Check), ADR-0018 (Create Dedicated
  Dev Environment), ADR-0026 (Classify Environments by Security Tier in Config)
- Related issues: #102 (Kathelix-owned backend), #127 (go-live)

## Context

The original CatVox projects lived in an organization created for a personal
Google account and were billed by a Free Trial billing account. The trial ended
on 2026-06-23 while nobody was working on the project. The billing account
closed, every environment's endpoints started returning HTTP 500, and nothing
noticed: the only notices went to a personal mailbox. Issue #102 had already
required the backend to be owned and billed by Kathelix Ltd before launch, so
the environments are being rebuilt rather than revived. GCP project IDs are
permanent, so the rebuilt environments get new IDs.

The Kathelix Ltd organization (`kathelix.com`) was created after 2024-05-03, so
Google's secure-by-default organization policies apply to it. Most of them were
already in force in the old organization and the Terraform copes with them
(no service-account keys, no automatic Editor grant to default service accounts,
uniform bucket-level access). One was not: **domain-restricted sharing**
(`iam.allowedPolicyMemberDomains`) only admits IAM members from the Kathelix
customer. It blocks the `allUsers` invoker binding that the two public HTTPS
Functions need. Those endpoints are public by design: anonymous app installs
call them, and App Check is enforced in code rather than at the IAM layer
(ADR-0002).

## Decision

1. **Every CatVox environment project lives in the `CatVox` folder** of the
   Kathelix Ltd organization. Environments are created into the folder
   (`FOLDER_ID`), never directly under the organization.

2. **The folder overrides domain-restricted sharing to allow all members.** The
   organization keeps the restriction for everything else. This is the narrowest
   scope the legacy list constraint supports, and it is what lets the public
   Functions bind `allUsers`. If the organization ever forbids the override, the
   fallback is Cloud Run's `--no-invoker-iam-check`, Google's recommended way to
   run a public service under domain-restricted sharing.

3. **Organization-level Essential Contacts point at a monitored Kathelix
   mailbox for all notification categories**, so billing, suspension, security,
   and model-deprecation notices reach someone who reads them.

4. **Billing comes from a Kathelix Ltd billing account.** A Free Trial account
   is acceptable while building. A protected environment must not take public
   traffic on a trial: upgrade the account to paid before launch and before the
   trial's end date (tracked by a v1.0 issue and listed as a go-live
   precondition in #127). When a trial ends, Google stops every resource on it.
   Budget alerts are added once the environment projects exist.

5. **New project IDs are data.** They live in `config/environments/<env>.xcconfig`
   and the TRD §7.3 roster, like every other per-environment value. The old
   personal-organization projects are deleted after the new protected
   environment has run in production for a while.

## Consequences

- The operator needs these organization-level roles: Organization
  Administrator, Folder Admin, Organization Policy Administrator, and Essential
  Contacts Admin. They also need permission to link projects to the billing
  account. `docs/CREATE_NEW_ENVIRONMENT.md` lists the one-time setup.
- Inside the folder, anyone who can edit a project's IAM can grant access to
  principals outside Kathelix. That is the cost of public endpoints. A narrower
  managed constraint (`iam.managed.allowedPolicyMembers`, allowing `allUsers`
  plus organization principals) can replace the override later.
- Running out of trial credit, or reaching the trial's end date, stops the
  backend. The upgrade issue and the launch precondition exist so the 2026
  outage cannot repeat silently.
- The organization has a single administrator for now. A second, break-glass
  organization and billing administrator is tracked for v2.0.
