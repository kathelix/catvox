# Create a New CatVox Environment

This is the authoritative runbook for creating any named CatVox environment.
Environment names are data: scripts and code must not assume a fixed set of
environments exists. Behaviour differences between environments come from
`config/environments/<env>.xcconfig`, not from environment-specific code.

For one-time repository and GitHub Actions setup, see
`docs/CI_BOOTSTRAP.md`.

The canonical environment model — the security-tier rules, the xcconfig-driven
parameterization, and the mutable-vs-protected differences — lives in the
Environment Model section of `docs/TRD.md`. This runbook is the operational
how-to.

## Artifact Contract

Each environment owns these artifacts:

| Artifact | Location | Notes |
|---|---|---|
| App/runtime config | `config/environments/<env>.xcconfig` | Committed. Source of truth for non-secret app, backend, CI-auth identity, analytics, and Terraform environment values. Host fields store hostnames only, with no `https://`, path, or trailing slash. Do not put secrets or private operator values here. |
| Firebase iOS plist | `CatVox/Resources/Firebase/GoogleService-Info-<env>.plist` | Committed only after validation. The app loads the plist matching `CATVOX_ENVIRONMENT`. |

| Terraform variables | `terraform/core/env/<env>.tfvars` | Ignored. Contains only true secrets or deliberately private values: `app_check_debug_token` and `alert_email`. Commit only `.example` files. |
| GitHub Environment | `<env>` | Stores environment-scoped Actions secrets only. Mutable environments may be unprotected; protected environments must use a protected GitHub Environment. |
| Bundle ID | Terraform + xcconfig | Each environment sets its own bundle ID via `CATVOX_IOS_BUNDLE_ID`. |
| Apple Developer App ID | Apple Developer team | Conditional. Required only when the environment introduces a new iOS bundle ID that will be installed on physical devices or use App Attest. |
| App Check | Terraform | Mutable environments may have a Debug Provider token. Protected environments must not register debug tokens and use protected smoke checks only. |
| Backend URLs | `config/environments/<env>.xcconfig` | Set after Functions deploy from the deployed Gen 2 Function URLs. |
| PostHog config | `config/environments/<env>.xcconfig` | App-visible project token (`CATVOX_POSTHOG_PROJECT_TOKEN`), ingestion hostname (`CATVOX_POSTHOG_HOST_NAME`), Terraform API hostname (`CATVOX_POSTHOG_API_HOST_NAME`), PostHog project ID (`CATVOX_POSTHOG_PROJECT_ID`), and PostHog organization ID (`CATVOX_POSTHOG_ORGANIZATION_ID`). Create the environment's PostHog project before enabling real production analytics traffic. |
| PostHog Terraform state | `gs://catvox-tf-state-<gcp-project-id>/posthog/state` | Same GCS bucket as the GCP root, different prefix. No new bucket. See ADR-0020. |

PostHog environment isolation is project-based and maps 1:1 to CatVox
environments: each environment uses its own PostHog project, identified by the
PostHog values in `config/environments/<env>.xcconfig`
(`CATVOX_POSTHOG_PROJECT_TOKEN`, `CATVOX_POSTHOG_PROJECT_ID`). Never point one
environment at another environment's PostHog project as a stopgap. See ADR-0019
and ADR-0020.

Keep personal/API credentials and private operator values out of app config.
`POSTHOG_API_KEY`, `TF_VAR_APP_CHECK_DEBUG_TOKEN`, and `TF_VAR_ALERT_EMAIL` live
in the matching per-environment GitHub Environment as secrets. Non-secret
environment values live in `config/environments/<env>.xcconfig`, including the
GCP project ID, full CI service account email, full WIF provider resource name,
GCP/Firebase Terraform inputs, PostHog Terraform identifiers, and app runtime
values. The Makefile reads this file for local and CI automation. See ADR-0021.

## Organization Prerequisites

This setup happens once per Google Cloud organization, not once per
environment. See ADR-0029.

1. **Company-owned organization.** Environments live in an organization owned
   by Kathelix Ltd (a Cloud Identity or Google Workspace domain), never under a
   personal Google account. New organizations come with Google's
   secure-by-default organization policies.
2. **Operator roles.** At the organization level, the operator needs:
   - Organization Administrator;
   - Folder Admin;
   - Organization Policy Administrator;
   - Essential Contacts Admin;
   - permission to link projects to the billing account.

   Grant them in the Cloud console under IAM & Admin → IAM, with the
   organization (not a project) selected.
3. **Product folder.** Create one folder for CatVox, and create every
   environment project inside it with `FOLDER_ID`:

   ```bash
   gcloud resource-manager folders create --display-name=CatVox --organization=<org-id>
   ```

4. **Folder-scoped sharing exception.** Domain-restricted sharing
   (`iam.allowedPolicyMemberDomains`) blocks the `allUsers` invoker binding the
   public Functions need. Override it on the folder only; the organization
   keeps the restriction. Write this policy file:

   ```yaml
   name: folders/<folder-id>/policies/iam.allowedPolicyMemberDomains
   spec:
     rules:
     - allowAll: true
   ```

   Then apply it and confirm the folder's effective policy:

   ```bash
   gcloud org-policies set-policy <policy-file>.yaml
   gcloud org-policies describe iam.allowedPolicyMemberDomains --folder=<folder-id> --effective
   ```

5. **Essential Contacts.** Send organization-level Google notices (billing,
   suspension, security, product deprecations) to a monitored company mailbox:

   ```bash
   gcloud essential-contacts create --email=<monitored-address> \
     --notification-categories=all --language=en-GB --organization=<org-id>
   ```

6. **Billing.** Use a billing account owned by the company.
   - A Free Trial account is fine while building.
   - Upgrade it to paid before a protected environment takes public traffic,
     and before the trial's end date. When a trial ends, Google stops every
     resource billed to it.
7. **Firebase terms.** Accept the Firebase terms once with the operator
   account before the first run, at
   `https://console.firebase.google.com/?forceCheckTos=true`. Terms are per
   Google account and cannot be accepted from the CLI, the API or Terraform.
   Without them, `firebase projects:addfirebase` fails with a bare
   `403 The caller does not have permission`, even for the project owner.
8. **Operator workstation.** If the workstation also holds other Google
   identities, keep CatVox's separate:
   - **gcloud:** use a dedicated configuration, selected per command with
     `CLOUDSDK_ACTIVE_CONFIG_NAME=<config>`.
   - **Application Default Credentials:** keep them in a separate file.
     1. Run `CLOUDSDK_CONFIG=<dir> gcloud auth application-default login`.
     2. Point Terraform and the Node scripts at it with
        `GOOGLE_APPLICATION_CREDENTIALS=<dir>/application_default_credentials.json`,
        on every Terraform command in both roots. Even
        `terraform init -backend=false` reads the state of the backend the
        directory was last initialized with, using whatever credentials it
        finds.
     3. If a call fails because the credentials have no quota project, set one
        once the environment's project exists:
        `CLOUDSDK_CONFIG=<dir> gcloud auth application-default set-quota-project <project-id>`.
   - **Firebase CLI:** run `firebase login:add <account>`, then
     `firebase login:use <account>` in the repository folder.

## Inputs

Pick explicit values before running the script:

| Variable | Example | Required |
|---|---|---|
| `CATVOX_ENVIRONMENT` | `<env>` | Yes |
| `CATVOX_PROJECT_ID` | `kathelix-catvox-<env>` | Yes. Project IDs are permanent: never reuse a deleted project's ID. |
| `PROJECT_DISPLAY_NAME` | `Kathelix CatVox <Env>` | Yes |
| `FOLDER_ID` (or `ORGANIZATION_ID`) | `<catvox-folder-id>` | Yes, exactly one, numeric. Use the CatVox folder so its sharing exception applies (see Organization Prerequisites). An existing project must already sit under that parent. |
| `BILLING_ACCOUNT_ID` | `<billing-account-id>` | Yes. It is linked on every run and must read back as enabled before Firebase or any bucket is created. |
| `CREATE_PROJECT` | `0` or `1` | Yes. `1` lets the run create the GCP project when gcloud cannot find it: the first run for a new project. `0` never creates one: use it for re-runs. Any other project-lookup error, such as expired credentials, stops the run whatever the flag says. |
| `CATVOX_FUNCTION_REGION` | `us-central1` | Yes |
| `CATVOX_FIRESTORE_LOCATION` | `nam5` | Yes |
| `CATVOX_TF_STATE_BUCKET` | `catvox-tf-state-kathelix-catvox-<env>` | Yes |
| `CATVOX_TF_STATE_PREFIX` | `catvox/state` | Yes |
| `CATVOX_IOS_BUNDLE_ID` | `com.kathelix.catvox.<env>` | Yes |
| `CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME` | `CatVox <Env> iOS` | Yes |
| `CATVOX_FIREBASE_IOS_APP_DELETION_POLICY` | `ABANDON` | Yes. Use `ABANDON` for protected environments; use `DELETE` only for disposable mutable environments. |
| `CATVOX_FIREBASE_APPLE_TEAM_ID` | `QYT76L5836` | Yes |
| `CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM` | `true` at bootstrap | Yes. Use lowercase `true` or `false` only. |
| `APP_CHECK_DEBUG_TOKEN` | UUID4 token | Optional, mutable environments only. Presence registers the token. Refused unless `config/environments/<env>.xcconfig` exists and sets `CATVOX_ENVIRONMENT_PROTECTED = false`. |
| `ALERT_EMAIL` | alert recipient | Required when the ignored tfvars file does not exist. If it exists, a supplied `ALERT_EMAIL` or `APP_CHECK_DEBUG_TOKEN` must match it. Otherwise unset the variable, or edit or delete the file. The file must stay in the plain one-line form, with no block comments and no repeated keys. |
| `RUN_TERRAFORM_APPLY` | `0` or `1` | Yes. Set to `1` to apply Terraform; `0` runs only the safe preview phases. |
| `RUN_POSTHOG_TERRAFORM_APPLY` | `0` or `1` | Yes. Set to `1` to provision the environment's PostHog project/dashboard and write PostHog values into xcconfig. |
| `RUN_FUNCTIONS_DEPLOY` | `0` or `1` | Yes. Set to `1` to deploy Cloud Functions; `0` skips the deploy. |
| `POSTHOG_API_KEY` | PostHog personal API key | Optional. If omitted and `RUN_POSTHOG_TERRAFORM_APPLY=1`, the provisioning script prompts silently. |
| `GITHUB_ENVIRONMENT_REVIEWERS` | `IvanBoyko` | Required for protected environments when PostHog provisioning configures the GitHub Environment before storing `POSTHOG_API_KEY`. |

## Automated Creation

From the repository root:

```bash
CATVOX_ENVIRONMENT=<env> \
CATVOX_PROJECT_ID=<project-id> \
PROJECT_DISPLAY_NAME="Kathelix CatVox <Env>" \
FOLDER_ID=<catvox-folder-id> \
BILLING_ACCOUNT_ID=<billing-account-id> \
CATVOX_FUNCTION_REGION=us-central1 \
CATVOX_FIRESTORE_LOCATION=nam5 \
CATVOX_TF_STATE_BUCKET=catvox-tf-state-<project-id> \
CATVOX_TF_STATE_PREFIX=catvox/state \
CATVOX_IOS_BUNDLE_ID=<bundle-id> \
CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME="CatVox <Env> iOS" \
CATVOX_FIREBASE_IOS_APP_DELETION_POLICY=ABANDON \
CATVOX_FIREBASE_APPLE_TEAM_ID=QYT76L5836 \
CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM=true \
ALERT_EMAIL=<alerts@example.com> \
CREATE_PROJECT=1 \
RUN_TERRAFORM_APPLY=1 \
RUN_POSTHOG_TERRAFORM_APPLY=1 \
RUN_FUNCTIONS_DEPLOY=1 \
make environment-create
```

`CREATE_PROJECT=1` is for the first run of a new project. Pass
`CREATE_PROJECT=0` on every re-run.

If you are bootstrapping an environment that allows mutable integration tests,
pass `APP_CHECK_DEBUG_TOKEN=<your-uuid4>`.

On a **brand-new environment**, a single run cannot finish all three phases.
Right after the Terraform apply, the plist export validates against the
xcconfig, which still holds `replace-with-*` identity values, so the run stops
there.

1. Run it with `RUN_POSTHOG_TERRAFORM_APPLY=0` and `RUN_FUNCTIONS_DEPLOY=0`.
2. Then continue with steps 2–4 of the Operator Checklist below: identity
   config, PostHog, and the first Functions deploy.

The order is the same for both tiers.

Before any cloud call, the script checks the inputs above and runs
`terraform fmt -check -recursive` in `terraform/core`, the plan step's first
check. That check also reads every git-ignored `env/*.tfvars`, other
environments' included. Fix a file it lists with
`terraform -chdir=terraform/core fmt <file>`.

The script:

1. Looks up the GCP project. An existing project must sit under the requested
   parent. A project gcloud cannot find is created only with
   `CREATE_PROJECT=1`, and any other lookup error stops the run before any
   change.
2. Links billing to `BILLING_ACCOUNT_ID` and checks that it reads back as enabled.
3. Enables Firebase on the project. A failed `firebase projects:list` stops
   the run, for example when the Firebase CLI is not logged in.
4. Bootstraps the GCS Terraform state bucket with versioning.
5. Creates the Cloud Functions Gen 2 source bucket so Terraform can manage its IAM before the first deploy.
6. Creates secrets-only `terraform/core/env/<env>.tfvars` if it does not already exist. An existing file must agree with any supplied `ALERT_EMAIL` or `APP_CHECK_DEBUG_TOKEN`.
7. Runs Terraform init and plan.
8. Optionally applies Terraform.
9. Writes and validates `CatVox/Resources/Firebase/GoogleService-Info-<env>.plist`.
10. Optionally provisions PostHog for the environment. If a `POSTHOG_API_KEY`
    is not exported, the script prompts silently, configures/verifies the
    matching GitHub Environment, stores the key as that environment's
    `POSTHOG_API_KEY` secret, applies `terraform/posthog`, and writes the
    public PostHog project ID/token into the environment xcconfig.
11. Optionally sets the Functions artifact cleanup policy and deploys Cloud
    Functions. On a brand-new project the first deploy ends with a
    cleanup-policy error after deploying both functions; see checklist step 4.
12. Prints the remaining GitHub Environment secrets and committed xcconfig values still needing review.

`RUN_TERRAFORM_APPLY`, `RUN_POSTHOG_TERRAFORM_APPLY`, and
`RUN_FUNCTIONS_DEPLOY` must be set explicitly to either `0` or `1` — there are
no defaults. Set them to `0` to stop after the safe preview phases.

Two helpers support the steps that follow, both environment-agnostic
(`CATVOX_ENVIRONMENT=<env>`):

- `make environment-doctor` — a read-only preflight that asserts the provisioning
  prerequisites (billing, enabled APIs, the CI SA's roles including
  `roles/cloudfunctions.admin`, the full WIF trust chain — pool/provider scoping,
  the `attribute.environment` mapping, and the CI SA's `workloadIdentityUser`
  impersonation binding — the Cloud Functions Gen2 build SA's grants, and the
  state bucket) and fails fast with a fix hint instead of surfacing them as a
  mid-deploy error. It needs `node` on PATH. Its source-bucket line reads
  PASS, "lacks", or "could not read/parse … unverified". Its cleanup-policy
  line checks `gcf-artifacts`, the repository the Functions builds push to.
- `make environment-write-config` — writes the resolved non-secret values into
  `config/environments/<env>.xcconfig`. It takes them from:
  - the Terraform outputs and the plist (`PHASE=identity`, the default);
  - the deployed Cloud Run hosts (`PHASE=hosts`);
  - all of the above together (`PHASE=all`).

  Before writing anything, it checks that every Terraform root it reads belongs
  to this environment. The hosts phase fails on a function that is not deployed,
  unless `ALLOW_MISSING_HOSTS=1`. It edits the working tree only; you review and
  commit.

## GitHub Environment Secrets

Create or update the GitHub Environment named `<env>` and set:

| Secret | Value |
|---|---|
| `TF_VAR_ALERT_EMAIL` | same value as `alert_email` in ignored tfvars |
| `TF_VAR_APP_CHECK_DEBUG_TOKEN` | Mutable / integration-safe environments only |
| `POSTHOG_API_KEY` | PostHog scoped personal API key with project-write scope limited to this environment's PostHog project. Set automatically by `make posthog-environment-provision`. |

Example:

```bash
gh api --method PUT repos/kathelix/catvox/environments/<env>
gh secret set TF_VAR_ALERT_EMAIL --env <env>
gh secret set TF_VAR_APP_CHECK_DEBUG_TOKEN --env <env>
make posthog-environment-provision CATVOX_ENVIRONMENT=<env>
```

Protected environments must use a protected GitHub Environment and must not reuse
mutable-environment debug tokens or integration settings. Each environment's
`POSTHOG_API_KEY` must be a scoped PostHog personal API key limited to that
environment's PostHog project — never a shared org-admin key.

## Committed Environment Config

After Terraform apply and Functions deploy, update
`config/environments/<env>.xcconfig` with the environment's non-secret values.
`make environment-write-config` writes the Terraform/plist-derived values for you
(see the operator checklist); the mapping below documents what it writes and what
to fill by hand:

```xcconfig
CATVOX_PROJECT_ID = <project-id>
CATVOX_ENVIRONMENT = <env>
CATVOX_ENVIRONMENT_PROTECTED = <true for protected environments; false for mutable environments>
CATVOX_FUNCTION_REGION = <region>
CATVOX_FIRESTORE_LOCATION = <firestore-location>
CATVOX_TF_STATE_BUCKET = catvox-tf-state-<project-id>
CATVOX_GCP_CI_SERVICE_ACCOUNT = <terraform output -raw ci_service_account_email>
CATVOX_GCP_WIF_PROVIDER = <terraform output -raw github_actions_wif_provider>
CATVOX_GCP_WIF_GITHUB_REF = <empty for any ref; a ref such as refs/heads/main for protected environments>
CATVOX_IOS_BUNDLE_ID = <bundle-id>
CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME = <display-name>
CATVOX_FIREBASE_IOS_APP_DELETION_POLICY = ABANDON
CATVOX_FIREBASE_APPLE_TEAM_ID = QYT76L5836
CATVOX_FIREBASE_FIRESTORE_APP_CHECK_ENFORCEMENT = <UNENFORCED for mutable environments; ENFORCED for protected environments>

CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM = true
CATVOX_SIGNED_UPLOAD_URL_HOST = <getSignedUploadURL Cloud Run host only>
CATVOX_ANALYSE_VIDEO_HOST = <analyseVideo Cloud Run host only>
```

`CATVOX_GCP_CI_SERVICE_ACCOUNT` and `CATVOX_GCP_WIF_PROVIDER` come from Terraform
output. `terraform output -raw` prints **no trailing newline**, so zsh appends a
reverse-video `%` end-of-line marker that is easy to paste into the value by
mistake. Read each with a trailing newline — or send it straight to the clipboard
— so the value lands clean:

```bash
# Print on its own newline-terminated line (no trailing % to mis-copy):
terraform -chdir=terraform/core output -raw ci_service_account_email; echo
terraform -chdir=terraform/core output -raw github_actions_wif_provider; echo

# …or copy a single value directly to the macOS clipboard (nothing displayed):
terraform -chdir=terraform/core output -raw ci_service_account_email | pbcopy
```

Keep `CATVOX_GCP_CI_SERVICE_ACCOUNT` and `CATVOX_GCP_WIF_PROVIDER` as full
strings, not composed pieces. **Note for App Check:** `config/environments/<env>.xcconfig` no longer requires App Check debug token boolean flags. The token itself in `terraform/core/env/<env>.tfvars` or the GitHub Environment secret determines registration.
Committed boolean values must be lowercase `true` or `false`; do not use `1`,
`0`, `yes`, or `no`.

**WIF ref scoping (`CATVOX_GCP_WIF_GITHUB_REF`).** Leave empty for a mutable
environment (trusts any ref); set a pinned ref such as `refs/heads/main` for a
protected environment. The GitHub Environment name must equal `CATVOX_ENVIRONMENT`
and every CI job that authenticates must declare the matching `environment:`. The
trust model is specified in the Environment Model section of `docs/TRD.md`
(ADR-0024).

**Firestore App Check (`CATVOX_FIREBASE_FIRESTORE_APP_CHECK_ENFORCEMENT`).** One of
`OFF`, `UNENFORCED`, or `ENFORCED`: `UNENFORCED` for mutable environments,
`ENFORCED` for protected. Rationale and the service-account bypass note are in the
Environment Model section of `docs/TRD.md` (ADR-0025).

**Environment security tier (`CATVOX_ENVIRONMENT_PROTECTED`).** `true` for protected
environments, `false` for mutable. `make ios-validate-env-config-structure` (via
`scripts/validate-environment-config.mjs`) enforces the protected invariants; the
full mutable-vs-protected difference table is in the Environment Model section of
`docs/TRD.md` (ADR-0026). Validation and smoke are environment-agnostic — run them
with `CATVOX_ENVIRONMENT=<env>`; only the CI/CD promotion pipeline names
environments literally.

## Conditional Apple Developer Bundle Setup

Most environment creation is cloud/Firebase setup and does not require changing
local Xcode signing. Skip this section when the new environment reuses an
existing iOS bundle ID or when developers will continue to build only the active
mutable-environment bundle locally.

Run this section only when `CATVOX_IOS_BUNDLE_ID` is a new explicit bundle ID
that needs physical-device builds or App Attest configuration. This is manual
unless an Apple Developer API integration is added later.

1. In the Apple Developer account for team `QYT76L5836`, create or verify an
   explicit App ID for `CATVOX_IOS_BUNDLE_ID`.
2. Enable the App Attest capability for that App ID. CatVox's entitlements use
   `com.apple.developer.devicecheck.appattest-environment = production`.
3. Let automatic signing create the development provisioning profile, or create
   an iOS App Development profile manually for the exact bundle ID and selected
   test devices.
4. Keep signing settings in `project.yml`. Do not hand-edit
   `CatVox.xcodeproj`; regenerate it with `make ios-generate`.
5. Install and launch on the selected device:
   ```bash
   CATVOX_ENVIRONMENT=<env> \
   DEVICE_ID=<device-udid> \
   make ios-device-launch
   ```

If Xcode shows `Unknown Name (QYT76L5836)` or `No Accounts`, that is local
workstation setup, not an environment artifact. Add an Apple Developer account
in Xcode Settings → Accounts and verify it can access team `QYT76L5836`; see
`docs/DEBUG.md`.

## Update App Config After Deploy

After PostHog provisioning, fill the analytics values in
`config/environments/<env>.xcconfig`. `make posthog-environment-provision` does
this automatically after apply by calling `make environment-write-config
PHASE=posthog`; you can also re-run just the writeback step:

```bash
CATVOX_ENVIRONMENT=<env> make environment-write-config PHASE=posthog
```

This writes `CATVOX_POSTHOG_PROJECT_ID` and
`CATVOX_POSTHOG_PROJECT_TOKEN`. The token is the public ingestion key used by
the iOS client; it is safe to commit, unlike `POSTHOG_API_KEY`.

After Functions deploy, fill the host-only values in
`config/environments/<env>.xcconfig`. `CATVOX_ENVIRONMENT=<env> make
environment-write-config PHASE=hosts` reads the deployed hosts and writes them
(hostname only) for you. It fails if either function is not deployed, unless you
pass `ALLOW_MISSING_HOSTS=1` to skip one deliberately. The commands below show
the underlying values:

```bash
gcloud functions describe getSignedUploadURL \
  --v2 \
  --project <project-id> \
  --region us-central1 \
  --format='value(serviceConfig.uri)'

gcloud functions describe analyseVideo \
  --v2 \
  --project <project-id> \
  --region us-central1 \
  --format='value(serviceConfig.uri)'
```

Strip `https://` and store only the hostname.

Then validate:

```bash
CATVOX_ENVIRONMENT=<env> make ios-validate-env-config
```

## Required Validation

For mutable environments:

```bash
export CATVOX_ENVIRONMENT=<env>

make functions-test
make terraform-plan
make posthog-terraform-plan
make ios-generate
make ios-test
make functions-integration
```

The Terraform tfvars basename must match `CATVOX_ENVIRONMENT`; the
Makefile rejects mismatched tfvars paths.

Also run a real Debug device scan before retiring or cleaning any previous
backend for that environment.

For protected environments:

- Do not include the environment in `CATVOX_INTEGRATION_SAFE_ENVIRONMENTS`.
- Do not run Firestore-mutating integration tests against it.
- Use only the protected, non-invasive smoke path in `docs/SMOKE_CHECKLIST.md`.

## Provisioning Into a Project That Already Has Resources

When an environment's GCP project already contains resources Terraform would
manage — most commonly a Firebase iOS app and the Firestore `(default)` database
(for example a project that was preserved or previously used) — those resources
must be imported into Terraform state before the first apply. Otherwise apply
fails with `ALREADY_EXISTS` when it tries to create them. Importing also
preserves an App Store-registered Firebase app ID and avoids Firestore
soft-delete/recreate delays.

`make environment-create` handles this automatically. After `terraform init` and
before `terraform plan`, it runs `scripts/import-preexisting-resources.sh`, which
idempotently imports the two resources Terraform creates (and would therefore
fail to re-create):

- **Firestore `(default)` database** (`google_firestore_database.default`) —
  imported when `gcloud firestore databases describe` finds it in the project.
- **Firebase iOS app** (`google_firebase_apple_app.ios`) — discovered by matching
  `CATVOX_IOS_BUNDLE_ID` (exact match) against the project's iOS apps from
  `firebase apps:list IOS`, then imported by the discovered app ID. The bundle id
  is the stable identifier in committed config; the app ID is a deferred
  placeholder until provisioning completes, so it is discovered rather than read
  from config.

The phase is idempotent and safe to re-run: a resource already in Terraform state
is skipped, and a resource absent from the project is left for apply to create
(so a brand-new environment is a no-op). It imports nothing destructive — it only
records existing resources in state — but it does write to remote state, so it
runs as part of provisioning rather than a pure read-only preview. A failed
`terraform state list` stops the import step before any import.

App Check singleton configs (`google_firebase_app_check_app_attest_config`,
`google_firebase_app_check_service_config`) are intentionally not imported: they
are PATCH-based singletons, so apply reconciles them via update rather than
failing to create.

Run the preview first (`RUN_TERRAFORM_APPLY=0`) to import and review the plan,
then re-run with `RUN_TERRAFORM_APPLY=1` to apply. For a protected environment
the first apply is operator-local because it also creates the Workload Identity
Federation pool and `catvox-ci-sa` that CI later authenticates as (ADR-0024);
subsequent applies go through the protected CI path.

## Operator Checklist: Standing Up a Protected Environment

This sequences the manual operator actions to bring a **protected** environment
fully online, end to end. The sections above cover each piece in detail; this is
the order to run them in. Every step is operator-run — they need GCP-admin
credentials, repo-admin rights, and the environment's secret values, so they are
not part of any PR diff or CI job.

A brand-new **mutable** environment follows the same order. The differences:

- the mutable values in its xcconfig;
- an optional App Check debug token;
- no reviewers;
- `make functions-integration` after the deploy in step 4.

Set these once for the session (substitute your environment's name and project):

```bash
export ENV=<protected-env>
export PROJECT_ID=<protected-project-id>
```

**1 · First Terraform apply — operator-local (O1).** Run this locally with
GCP-admin credentials.

- **What the apply creates:** the WIF pool and `catvox-ci-sa` that CI
  authenticates as. For a preserved project, it first imports the existing
  Firebase app and Firestore.
- **Why not CI:** the CI service account has no `workloadIdentityPoolAdmin`
  (see `docs/CI_BOOTSTRAP.md`).
- **Leave PostHog and Functions off** here; steps 3 and 4 do them.
- **The run is expected to stop** right after the apply on a brand-new
  environment. The plist export validates the new plist against the xcconfig,
  which still holds `replace-with-*` identity values. By then the plist file is
  already written.
- **A fresh project's first apply can stop early** while newly enabled APIs
  and service agents come live, for example an `accessNotConfigured` 403 from
  the IAM API, or the Vertex AI service agent "does not exist" yet. Wait a
  minute and re-run the same command with `CREATE_PROJECT=0`; every step skips
  what already exists.

```bash
# Authenticate as the organization's GCP admin first (Organization
# Prerequisites → Operator workstation). CREATE_PROJECT=1 on the first run of
# a new project only; re-runs pass CREATE_PROJECT=0.
CATVOX_ENVIRONMENT="$ENV" \
CATVOX_PROJECT_ID="$PROJECT_ID" \
PROJECT_DISPLAY_NAME="Kathelix CatVox <Env>" \
FOLDER_ID=<catvox-folder-id> \
BILLING_ACCOUNT_ID=<billing-account-id> \
CATVOX_FUNCTION_REGION=us-central1 \
CATVOX_FIRESTORE_LOCATION=nam5 \
CATVOX_TF_STATE_BUCKET="catvox-tf-state-$PROJECT_ID" \
CATVOX_TF_STATE_PREFIX=catvox/state \
CATVOX_IOS_BUNDLE_ID=<protected-bundle-id> \
CATVOX_FIREBASE_IOS_APP_DISPLAY_NAME="CatVox <Env> iOS" \
CATVOX_FIREBASE_IOS_APP_DELETION_POLICY=ABANDON \
CATVOX_FIREBASE_APPLE_TEAM_ID=QYT76L5836 \
CATVOX_MANAGE_GCF_SOURCES_BUCKET_IAM=true \
ALERT_EMAIL=<alerts@example.com> \
CREATE_PROJECT=1 \
RUN_TERRAFORM_APPLY=1 \
RUN_POSTHOG_TERRAFORM_APPLY=0 \
RUN_FUNCTIONS_DEPLOY=0 \
make environment-create
```

**2 · Fill the identity config and validate the plist (O4).** These values only
exist after step 1's apply:

- the app's `GOOGLE_APP_ID` and `API_KEY`;
- the CI service account and WIF provider.

The API key *value* appears only inside the generated plist. Terraform outputs
the app ID and the key's *ID*, not its value.

1. `make environment-write-config` reads the Terraform outputs and the plist
   from step 1, and writes these values into `config/environments/$ENV.xcconfig`.
   Nothing is copied by hand, and each value is read through a clean capture,
   which avoids the trailing-`%` paste trap of `terraform output -raw`.
2. With the identity values in place, re-exporting the plist validates.

```bash
CATVOX_ENVIRONMENT="$ENV" make environment-write-config          # PHASE=identity (default)
CATVOX_ENVIRONMENT="$ENV" make terraform-output-firebase-plist   # validates now
```

**3 · Provision PostHog and the GitHub Environment (O1, O2).**
`make posthog-environment-provision`:

1. prompts silently for the environment's PostHog API key, unless it is
   exported;
2. configures or verifies the GitHub Environment from the xcconfig (required
   reviewers and a `main` branch policy for a protected environment);
3. stores `POSTHOG_API_KEY` there for CI;
4. applies `terraform/posthog`;
5. writes the public PostHog project ID and token into the xcconfig.

```bash
CATVOX_ENVIRONMENT="$ENV" GITHUB_ENVIRONMENT_REVIEWERS=IvanBoyko make posthog-environment-provision
```

**4 · First Functions deploy and backend hosts — operator-local (ADR-0030).**
This is the environment's one and only operator-local deploy.

- Its backend hosts go into the environment's config PR, because the
  release-safety check rejects placeholder hosts in a protected config.
- Every later deploy goes through the protected CI path (step 7).
- **On a brand-new project, the deploy ends with an error even though it
  worked.** `make functions-deploy` deploys both functions, then exits non-zero
  with "Functions successfully deployed but could not set up cleanup policy in
  location <region>". Its cleanup-policy step runs before the first deploy
  creates the `gcf-artifacts` repository. Run
  `firebase functions:artifacts:setpolicy --project <project-id> --location <region> --days 7 --non-interactive --force`
  once, then carry on; `make environment-doctor` prints the same command.
  Never pass `--force` to `firebase deploy`: there it also deletes deployed
  functions that are missing from the source.

```bash
CATVOX_ENVIRONMENT="$ENV" make functions-deploy
CATVOX_ENVIRONMENT="$ENV" make environment-write-config PHASE=hosts
CATVOX_ENVIRONMENT="$ENV" make ios-validate-release-safety   # no placeholder left
git add "CatVox/Resources/Firebase/GoogleService-Info-$ENV.plist" "config/environments/$ENV.xcconfig"
```

`make environment-write-config` edits the working tree only and never stages or
commits, so review the diff before committing. For a mutable environment, run
`make functions-integration` instead of the release-safety check, and confirm
no `replace-with-*` value is left in its xcconfig.

**5 · Verify the GitHub Environment from config (O2).** Step 3 already
configured it. Re-running is idempotent, and it confirms the live environment
still matches the config.

`make configure-github-environment` reads `CATVOX_ENVIRONMENT_PROTECTED` and
`CATVOX_GCP_WIF_GITHUB_REF` from `config/environments/$ENV.xcconfig` and
applies the matching protection:

- a **protected** environment gets required reviewers and a deployment-branch
  policy pinned to the WIF ref's branch;
- a **mutable** environment gets no reviewers and no branch restriction.

Pass the reviewers; they are required when the environment is protected:

```bash
make configure-github-environment CATVOX_ENVIRONMENT="$ENV" \
  GITHUB_ENVIRONMENT_REVIEWERS=IvanBoyko
```

You can also manage it from the UI: Settings → Environments → `$ENV`.

**6 · Set any remaining environment secrets (O3), then open the config PR.**
You supply the value when prompted.

- Protected environments get **no** App Check debug token.
- Step 3 already stored `POSTHOG_API_KEY`.

```bash
gh secret set TF_VAR_ALERT_EMAIL --env "$ENV" --repo kathelix/catvox
```

Open a PR with the plist and xcconfig from steps 2–4. Its Terraform and
PostHog plans should show no changes. Merging it starts step 7.

**7 · Promote to the protected environment.** First run the read-only preflight
to confirm the prerequisites a first deploy needs — CI-SA roles (incl.
`roles/cloudfunctions.admin`), WIF scoping, enabled APIs, billing, and the state
bucket — so they surface now instead of as a mid-deploy failure:

```bash
CATVOX_ENVIRONMENT="$ENV" make environment-doctor
```

Then promote. Promotion is split by tool until the delivery orchestrator (#106)
unifies it:

- **Terraform (apply infra first):** a manual dispatch from `main`, approved on the
  `$ENV` Environment — `gh workflow run terraform.yml --ref main`.
- **Functions:** automatic in the push pipeline. On merge to `main` it:
  1. deploys to the mutable environment;
  2. runs that environment's integration suite;
  3. **pauses the protected-environment deploy job for your approval** on the
     `$ENV` Environment.

  Approve it from the run page or Settings → Environments to promote. It only
  runs after the mutable deploy and integration tests pass. For a brand-new
  environment, the first approved run redeploys the code from step 4 through
  the protected path; from then on, CI owns every deploy (ADR-0030).

```bash
gh workflow run terraform.yml --ref main   # Terraform: manual dispatch, then approve
# Functions: no command — approve the paused protected-environment deploy job on the next push to main
```

**8 · Verify backend hosts + smoke.** Step 4 already wrote the hosts from the
first deploy, and the CI redeploy updates the same Cloud Run services.

1. Re-read the hosts. This must leave `config/environments/$ENV.xcconfig`
   unchanged; if it changes anything, investigate before committing.
2. Run the non-invasive smoke check and follow `docs/SMOKE_CHECKLIST.md`.

Never run Firestore-mutating integration tests against a protected environment.

```bash
# Reads the deployed getSignedUploadURL / analyseVideo hosts; expect no diff.
CATVOX_ENVIRONMENT="$ENV" make environment-write-config PHASE=hosts
git diff --exit-code -- "config/environments/$ENV.xcconfig"
CATVOX_ENVIRONMENT="$ENV" make smoke
```

Once verified, `docs/CUTOVER_AND_ROLLBACK.md` covers the pre-launch cutover
checklist for taking the environment live.

**Ongoing.** Later Terraform applies to the protected environment are a manual
dispatch (`gh workflow run terraform.yml --ref main`, approved on the `$ENV`
Environment); later Functions deploys promote automatically through the push
pipeline behind that same approval gate. The one exception is WIF
pool/provider/binding changes: apply those operator-local before merge, because
the CI SA cannot modify them (see `docs/CI_BOOTSTRAP.md`). To roll back app,
Functions, secret, or Terraform changes on a live protected environment, see
`docs/CUTOVER_AND_ROLLBACK.md`.

## Destroying an Environment

`make environment-destroy` tears a named environment down — the reverse of
`make environment-create`. It is operator-run (GCP-admin + repo-admin) and
**keeps the GCP project**: it removes the Terraform-managed resources, the
script-created Terraform-state and Cloud Functions source buckets, and the
GitHub Environment. Deleting the whole project and rotating to a fresh one for a
new create/destroy cycle is a separate capability (#111).

Environment-agnostic and config-gated:

| Tier | Command |
|---|---|
| Mutable (`CATVOX_ENVIRONMENT_PROTECTED=false`) | `make environment-destroy CATVOX_ENVIRONMENT=<env> CONFIRM=destroy` |
| Protected (`true`) | `make environment-destroy CATVOX_ENVIRONMENT=<env> CONFIRM=destroy ALLOW_PROTECTED_DESTROY=<env>` |

Without `CONFIRM=destroy` it refuses; a protected environment additionally
refuses unless `ALLOW_PROTECTED_DESTROY` exactly equals the environment name, so
a protected environment is safe by construction.

What it does, in order (the order is load-bearing):

1. Empties the `catvox-raw-videos-<project-id>` bucket — it is
   `force_destroy = false`, so Terraform can only delete it once empty.
2. `terraform destroy` (core). The Firebase iOS app honours
   `CATVOX_FIREBASE_IOS_APP_DELETION_POLICY`: `DELETE` removes it, `ABANDON`
   leaves it registered (use `DELETE` for a disposable environment). If this step
   fails the script stops before touching the buckets, so the state stays intact
   for a retry.
3. `terraform destroy` (PostHog) — tolerant of an environment with no PostHog
   state (deferred; see #37).
4. Deletes the script-created Cloud Functions Gen2 sources bucket
   (`gcf-v2-sources-<project-number>-<region>`).
5. Deletes the `<env>` GitHub Environment and its secrets — before the state
   bucket, so a `gh` failure leaves the state bucket intact for a re-run to retry.
6. Deletes the Terraform state bucket **last** — both destroys read and write it,
   and nothing recoverable-by-rerun runs once it is gone.

It is idempotent: absent resources are skipped, so re-running after a partial
teardown converges. Like the protected first apply, the destroy is
operator-local — it is never wired into CI.
