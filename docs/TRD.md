# Technical Requirements Document: CatVox AI (MVP)

**Version:** 2.3
**Company:** Kathelix Ltd  
**Project Lead:** Ivan Boyko
**Date:** April 2026  
**Status:** Infrastructure & Backend Definition

---

## 1. Executive Summary
CatVox AI is a premium, minimalist iOS application designed to interpret cat behavior from short video clips using multimodal Generative AI (Gemini 2.5 Flash). The app serves as a high-tech brand ambassador for Kathelix Ltd, showcasing expertise in AI integration, Cloud architecture, and superior UX design.

For MVP, the user can either record a new video in-app or select an existing video from Photos, provided the submitted clip satisfies the product limits and validation rules defined in this document.

---

## 2. Brand Identity & Design Language
* **Brand Pillars:** Resilience (Phoenix narrative), Engineering Excellence, Playful Intelligence.
* **Visual Style:** Glassmorphism (Frosted glass), dark mode aesthetics, fluid spring-based animations.
* **Brand Palette:** Primary gradient Indigo `#4F46E5` → Cyan `#06B6D4`. Used for progress rings, primary CTAs, and interactive controls.
* **App Icon:** 1024 × 1024 px master asset. All platform-required scaled variants must be derived from this master.
* **Target Market:** UK & International English-speaking tech-savvy pet owners.

---

## 3. Functional Requirements

### 3.1 Core Features (MVP)
* **Unified Scan Entry:** The home screen exposes one primary CTA labeled **Read My Cat**. After tapping it, the app presents a source choice sheet with:
    * **Record New Video**
    * **Choose from Photos**
* **Video Capture:** In-app recording supports clips up to **10 seconds**. The user may stop recording early once a minimum capture threshold of **2.0 seconds** has elapsed. If the user does not stop manually, recording ends automatically at 10 seconds, with an audio ping at the moment recording ends.
* **Post-Capture Review:** After an in-app recording ends, the app presents a lightweight review decision with:
    * **Retake**
    * **Use This Clip**
  Upload and analysis begin only after the user chooses **Use This Clip**.
* **Photos Import:** The app supports selecting an existing video from the user's Photos library using the system video picker flow. The picker is restricted to videos, but detailed eligibility checks are performed by the app after selection rather than by a custom filtered gallery browser.
* **Video Validation Rules:** Before upload, the app must validate the candidate video locally. MVP acceptance rules are:
    * maximum duration: **10 seconds**
    * maximum file size: **100 MB**
    * supported inputs: native **HEVC (.mov)**, H.264, and common iPhone-exported video variants
    * unsupported input: **ProRes**
    * no in-app trimming in MVP
    * no client-side transcoding or re-encoding in MVP
* **Video Pipeline:** In-app recording uses native **HEVC (.mov)** with resolution hard-capped at **1920 × 1080 (1080p)**. The cap keeps free-tier clip sizes to approximately 15–25 MB per 10-second recording. Devices that do not support HEVC fall back silently to H.264. For Photos-imported videos, MVP accepts videos that pass the validation rules above, including temporary acceptance of 4K source video for simplicity. Re-evaluation of 4K cost and normalization strategy is deferred.
* **Multimodal Analysis:** Simultaneous processing of video (body language) and audio (vocalization) via Vertex AI.
* **Persona Engine:** Logic to assign one of 6 "Cat Personas" to the interpretation to drive engagement and humor.
* **Scan History:** The app saves a local history of successful scans using on-device persistent storage. Each saved scan is a self-contained record consisting of:
    * the original clip preserved in CatVox app-local storage
    * the structured AI result returned by the backend
    * a locally generated thumbnail for list presentation
    * source metadata and timestamps
* **History Save Rule:** A scan is persisted only after analysis completes successfully and a valid result payload is returned. Failed validation attempts, rejected selections, upload failures, quota rejections, retakes, and abandoned flows must not create history entries.
* **History Reliability:** For MVP, CatVox must preserve its own app-local copy of the original clip for each successful scan, including clips imported from Photos. This keeps history self-contained and reliable even if the user later deletes the original Photos asset.
* **History Replay:** Opening a saved scan from history must use the locally persisted clip and AI result. It must not trigger a new upload, a new backend analysis request, or quota consumption.
* **Result Completion Flow:** Successful scans are already persisted before the user leaves the Result screen. The Result screen action is therefore a completion/exit action rather than the persistence trigger.
* **Social Sharing:** Deferred as a separate MVP backlog item. It is not part of the persistence / scan history feature defined in this section.

### 3.2 Monetization & Sustainability
* **Credit System:** 5 free scans/day to manage GCP costs.
* **Quota Burn Rule:** A quota unit is consumed only when analysis completes successfully and a result payload is returned. Failed local validation attempts, rejected selections, and abandoned uploads do not consume quota.
* **Pro Tier (IAP):** One-time in-app purchase for unlimited scans and watermark removal.
* **Brand Promotion:** Subtle "Powered by Kathelix" watermark on all free-tier exports.

---

## 4. AI System Instructions (The "Prompt Gate")

### 4.1 Role & Context
Short version:
You are CatVox AI, a multimodal expert in feline ethology and a sophisticated creative writer. Your task is to analyze short video clips (including audio) to provide professional insights into a cat's emotional state, paired with a witty "inner monologue" translation.

Full prompt: `docs/Instructions.md` — this is the single source of truth for the system instruction. The Cloud Function build script copies it into the deployment artifact at build time; editing the file and merging the PR is all that is required to update the live prompt. (See ADR-0008.)

### 4.2 The 6 Cat Personas
Select the archetype that best fits the observed behavior:
1. **The Grumpy Boss:** Authoritative, judgmental, and demanding.
2. **The Existential Philosopher:** Poetic, melancholic, and confused by the "red dot."
3. **The Dramatic Diva:** High-octane energy; grand theatrical flair.
4. **The Secret Agent:** Stealthy, tactical; treating the room as a mission zone.
5. **The Chaotic Hunter:** Pure prey-drive energy; "zero thoughts" behind the eyes.
6. **The Affectionate Sweetheart:** Detached, calm, and observing with silent peace.

### 4.3 API Data Schema
The backend must return ONLY a valid JSON object following this structure:
{
  "primary_emotion": "string",
  "confidence_score": float (0.0 - 1.0),
  "analysis": "2-3 sentences of expert feline behavior analysis",
  "persona_type": "string",
  "cat_thought": "First-person monologue matching the assigned persona",
  "owner_tip": "A practical, actionable suggestion for the owner"
}

---

## 5. UI/UX Specifications

### 5.1 Key Screens
1. **Home Screen:** Minimalist dashboard with this top-to-bottom order:
    * Cat logo and `Powered by Kathelix` text
    * a browsable list of previous scans
    * one primary CTA labeled **Read My Cat** and supporting quota text such as `5 free scans remaining today`
2. **Source Choice Sheet:** A lightweight chooser offering:
    * **Record New Video**
    * **Choose from Photos**
3. **Recording Screen:** Viewfinder with a progress ring for a clip up to 10 seconds, a tappable stop control after the minimum threshold is reached, and a lightweight post-capture review step.
4. **Post-Capture Review State:**
    * shown immediately after recording ends, whether by early stop or automatic 10-second completion
    * offers:
        * **Retake**
        * **Use This Clip**
5. **Result Screen:**
    * Full-screen looping background using the original scanned clip.
    * Background playback is muted and continuous.
    * The same looping local clip background is used when reopening a saved scan from history.
    * Animated Glassmorphism "Thought Bubble".
    * **Confidence Score UI:** The percentage ring must be dynamically color-coded:
        * **Green:** > 80% (High Confidence)
        * **Amber:** 50% - 80% (Moderate Confidence)
        * **Red:** < 50% (Low Confidence/Ambiguous)
    * Expandable "Expert Insights" drawer.
    * "Done" CTA.
6. **Scan History List:**
    * Presents saved scans in chronological order, with the newest saved scan closest to the bottom of the list.
    * Each row corresponds to one saved scan.
    * Each row shows:
        * a thumbnail image for the saved clip
        * a mood and/or persona label
        * the beginning of the saved `cat_thought` text
    * Tapping a row opens the saved result for that scan.

### 5.2 Validation UX
* If a Photos-selected video fails validation, the app must reject it before upload and clearly explain the reason.
* Rejection messaging must be specific and user-readable, using these canonical messages:
    * "This video is longer than 10 seconds. Please choose a shorter clip."
    * "This video is larger than 100 MB. Please choose a smaller clip."
    * "ProRes videos aren't supported."
    * "This video format isn't supported."
* The MVP UX favors clear post-selection validation messaging over a custom gallery browser with disabled or hidden ineligible assets.

### 5.3 Recording UX
* The record control starts capture when tapped from idle state.
* During recording, the central capture control must become the stop affordance once the minimum capture threshold is reached.
* Minimum early-stop threshold: **2.0 seconds**.
* Before 2.0 seconds, tapping the control must not end recording.
* If the user taps the control before 2.0 seconds, the app should show a brief hint such as `KEEP RECORDING A BIT LONGER`.
* The UI must make the early-stop affordance clear while recording, using explicit helper text such as:
    * before early-stop is allowed: `KEEP RECORDING`
    * after early-stop is allowed: `TAP TO FINISH`
* When recording ends, the app must not begin upload or analysis immediately.
* Upload and analysis begin only after the user taps **Use This Clip**.
* Tapping **Retake** discards the recorded clip and returns the user to the live camera view in ready-to-record state.
* The same post-capture review flow applies whether recording ended by manual early stop or by automatic completion at 10 seconds.

### 5.4 Scan History UX
* Scan history is part of the Home experience and should be easy to browse without entering a separate management flow.
* The history list must use chronological ordering so earlier scans appear higher in the list and the newest saved scan sits nearest to the primary CTA at the bottom of Home.
* If there is no saved scan history yet, the Home screen should show a lightweight empty state indicating that completed scans will appear there.
* Each history row must remain lightweight and scannable, prioritizing thumbnail, interpretation cue, and short text preview over dense metadata.
* The `Done` action on the Result screen must return the user to the Home screen.
* After the user returns from a successful result, the newly persisted scan must be visible in the scan history list in its chronological position.
* Deleting a saved scan must always require user confirmation.
* Confirmed deletion must remove:
    * the persisted history record
    * the CatVox-owned local original clip
    * any other CatVox-owned local assets associated with that scan
* Deleting a saved scan must never delete the user's original Photos asset.

---

## 6. Cloud Infrastructure & Security (IaC)

### 6.1 Infrastructure as Code (Terraform)
* **Provider:** Google Cloud Platform (GCP).
* **Deployed Project:** GCP Project ID `kathelix-catvox-prod`, region `us-central1`, Firestore location `nam5` (US multi-region).
* **Terraform State:** Remote state stored in GCS bucket `catvox-tf-state-<project-id>` (`us-central1`, object versioning enabled). State is never stored locally or committed to source control. The GCS backend enables consistent state access from both local development and CI/CD pipelines. The state bucket is bootstrapped manually (outside of Terraform) to avoid a circular dependency.
* **Resource Scope:**
    * **Project Services:** Enablement of `aiplatform`, `cloudfunctions`, `cloudbuild`, `run`, `eventarc`, `pubsub`, `firestore`, `storage`, `secretmanager`, `artifactregistry`, `firebase`, `firebaseappcheck`, and `iam`.
    * **Databases:** Explicit provisioning of a **Firestore instance** in `(default)` mode.
    * **Artifact Registry repository** for Cloud Functions (2nd Gen) build images.
    * **Service Accounts:** `catvox-backend-sa` (Cloud Functions runtime) and `catvox-ci-sa` (Terraform CI / GitHub Actions) — see §6.3 for roles.
    * **Secrets:** Secret Manager for `GCP_PROJECT_ID` and `APP_CHECK_DEBUG_TOKEN`.

### 6.2 Compute & API Orchestration
* **Environment:** Firebase Cloud Functions (2nd Generation).
* **Runtime:** Node.js 22 (TypeScript).
* **Vertex AI Integration:** Call Gemini 2.5 Flash using `fileData` (GCS URI) for multimodal analysis.

### 6.3 Security & Identity
* **App Verification:** Firebase App Check mandatory for all backend entry points. App Attest is the production provider for Apple platforms; Debug Provider is used for local development. (See ADR-0002.)
* **Secrets:** Zero hardcoded identifiers; all retrieved via Secret Manager at runtime.
* **Service Account: `catvox-backend-sa`** — Runtime identity for Cloud Functions. Holds only the minimal roles required at runtime; never has CI-level access.
    * `roles/aiplatform.user` — invoke Gemini 2.5 Flash via Vertex AI.
    * `roles/storage.objectViewer` — read video objects from GCS for Vertex AI.
    * `roles/storage.objectCreator` — create objects in GCS; required so that signed URLs generated by this SA (via `signBlob`) are honoured by GCS when the iOS client PUTs the video file.
    * `roles/datastore.user` — read/write Firestore usage documents.
    * `roles/secretmanager.secretAccessor` — resolve secrets at function startup.
    * `roles/iam.serviceAccountTokenCreator` (self) — generate signed GCS upload URLs for the iOS client.
* **Service Account: `catvox-ci-sa`** — Terraform CI identity for GitHub Actions. Holds broader project-level rights needed for IaC; isolated from the runtime SA to limit blast radius if either is compromised. (See ADR-0006.)
    * `roles/editor` — manage GCP resources (APIs, GCS, Artifact Registry, Secret Manager, Firestore, service accounts).
    * `roles/resourcemanager.projectIamAdmin` — read and write project-level IAM bindings.
    * `roles/iam.serviceAccountAdmin` — set IAM policies on individual service accounts (`google_service_account_iam_member` resources); intentionally excluded from `roles/editor`.
    * `roles/secretmanager.secretAccessor` — read secret versions during `terraform plan/apply`; intentionally excluded from `roles/editor`.
    * `roles/storage.objectAdmin` (state bucket only) — read/write Terraform state. Managed by Terraform (`google_storage_bucket_iam_member.ci_sa_state_bucket_admin`); the bucket itself is outside IaC scope.

### 6.4 Data Lifecycle & Persistence
* **Google Cloud Storage (GCS):**
    * Bucket: `catvox-raw-videos-<project-id>` (project ID suffix ensures global uniqueness).
    * **CORS Policy:** Configuration to allow direct uploads from the iOS app.
    * **Lifecycle Rule:** `action: Delete`, `condition: Age > 1 day`.
    * **Vertex AI service agent** (`service-{PROJECT_NUMBER}@gcp-sa-aiplatform.iam.gserviceaccount.com`) requires `roles/storage.objectViewer` on this bucket so that Vertex AI can fetch the video via the `fileData` GCS URI. This binding is managed by Terraform (`google_storage_bucket_iam_member.vertexai_sa_raw_videos_viewer`).
* **Firestore (Usage Guard):**
    * Collection: `usage/{userId}`.
    * Schema: `{ count: integer, lastResetDate: string (YYYY-MM-DD) }`.
    * **Logic:** Backend increments count; rejects request (429) if limit reached.
    * **userId:** A UUID generated once on first launch and persisted in `UserDefaults` under the key `"catvox.userId"`. Sent by the iOS client with every `analyseVideo` request. Forward-compatible with Firebase Auth — when Auth is introduced, the computed property value is replaced with the authenticated UID and the Firestore schema requires no changes. (See ADR-0007.)
* **App-Local Scan Persistence:**
    * Local scan history is stored on-device using SwiftData for metadata persistence.
    * Each persisted scan record must include at least:
        * a stable local identifier
        * the local file location of the CatVox-owned original clip
        * the saved AI result fields
        * source type metadata (`recorded` or `photos`)
        * thumbnail reference
        * created-at timestamp
    * Original clip files are stored in CatVox-controlled app-local storage and referenced by the persisted scan record.
    * Thumbnail images are generated locally and stored for fast history rendering.
    * Persisted scan history must remain available offline.
    * Removing a saved scan must delete the SwiftData record together with CatVox-owned local files for that scan.
    * CatVox must never attempt to delete the user's original Photos-library asset.

### 6.5 Validation & Upload Guardrails
* **Client Validation:** The iOS client must validate duration, size, and basic format eligibility before requesting a signed upload URL whenever that metadata is available locally.
* **Backend Validation Point:** The backend must validate uploaded object constraints in the analysis path before invoking Vertex AI.
* **Backend Validation Rules:** For MVP, backend validation should enforce at least these two protected limits:
    * duration <= 10 seconds
    * file size <= 100 MB
* **Upload Economics:** Signed upload URLs should not be issued for videos that the client already knows are invalid. This is primarily a cost-control and UX measure, not a trust substitute.
* **Optional Abuse Mitigation:** A lightweight rate-limit on signed URL issuance is desirable if it can be implemented cheaply without materially complicating MVP delivery; otherwise it should be deferred to post-MVP work.

---

## 7. CI/CD Pipelines

### 7.1 iOS Build Pipeline
* **Trigger:** Every push and pull request targeting `main`.
* **Runner:** macOS 15 (Xcode 16, iOS 17+ SDK).
* **Steps:** Checkout → XcodeGen (regenerate `.xcodeproj` from `project.yml`) → build for generic iOS Simulator slice (`CODE_SIGNING_ALLOWED=NO`).
* **Purpose:** Catches build breaks and XcodeGen drift on every change. No device signing or provisioning profiles required.

### 7.2 Terraform Infrastructure Pipeline
* **Trigger:** Push or pull request targeting `main` when files under `terraform/` or the workflow file itself change.
* **Authentication:** Keyless via **Workload Identity Federation (WIF)**. GitHub Actions presents its OIDC token; GCP exchanges it for a short-lived credential scoped to `catvox-ci-sa` (the dedicated Terraform CI identity). No long-lived service account keys are stored anywhere.
* **Plan job (on PR):**
    1. Authenticate to GCP via WIF.
    2. `terraform init` → `terraform fmt -check` → `terraform validate` → `terraform plan`.
    3. Post a structured comment to the PR with fmt/init outcomes and the full plan output (collapsible, truncated at 60k characters if needed).
    4. Fail the job if the plan step fails, surfacing the error in the PR comment.
* **Apply job (on merge to `main`):** `terraform init` → `terraform apply -auto-approve`.
* **Variables:** `TF_VAR_project_id` and `TF_VAR_app_check_debug_token` supplied from GitHub Actions secrets; `region` and `firestore_location` use the defaults defined in `variables.tf`.

### 7.3 Firebase Cloud Functions Pipeline
* **Trigger:** Push or pull request targeting `main` when files under `functions/`, `firebase.json`, `docs/Instructions.md`, or the workflow file itself change. `docs/Instructions.md` is included because it is copied into the deployment artifact at build time — a prompt-only change must trigger a redeploy. (See ADR-0008.)
* **Authentication:** Same WIF setup as the Terraform pipeline — `catvox-ci-sa` via `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` secrets.
* **Build job (on PR and push):** `npm ci` → `npm run build` (TypeScript compile check).
* **Deploy job (on merge to `main`):** Runs after build passes → `firebase deploy --only functions`.

### 7.4 WIF Bootstrap & GitHub Secrets
The following one-time manual setup is required before the Terraform pipeline can run. Bootstrap scripts are in `terraform/`:

| Script | Purpose |
|---|---|
| `bootstrap_remote_state.sh` | Creates the GCS state bucket with versioning |
| `bootstrap_wif.sh` | Creates the WIF pool + OIDC provider, binds the GitHub repo to `catvox-ci-sa`, grants state bucket access |

**Required GitHub Actions secrets:**

| Secret | Value |
|---|---|
| `GCP_PROJECT_ID` | GCP project ID (`var.project_id`) |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full WIF provider resource name (output of `bootstrap_wif.sh`) |
| `GCP_SERVICE_ACCOUNT` | `catvox-ci-sa@<project-id>.iam.gserviceaccount.com` |
| `TF_VAR_app_check_debug_token` | Firebase App Check debug token |

### 7.5 From-Scratch Environment Runbook

Use this when deploying to a new GCP project, or after a full `terraform destroy`.

#### Prerequisites (one-time per GCP project)
1. Create the GCP project and enable billing — manual, unavoidable.
2. Initialise Firebase on the project:
   ```bash
   firebase projects:addfirebase <PROJECT_ID>
   ```
3. Run the bootstrap scripts from `terraform/`:
   ```bash
   PROJECT_ID=<your-project-id> ./bootstrap_remote_state.sh  # creates TF state bucket
   PROJECT_ID=<your-project-id> ./bootstrap_wif.sh            # creates WIF pool + OIDC provider
   ```
4. Add the four GitHub Actions secrets printed by `bootstrap_wif.sh` (see §7.4).

#### Deploy infrastructure and backend
```bash
# 1. Provision all GCP infrastructure
cd terraform
terraform apply

# 2. Deploy Cloud Functions
cd ../functions
firebase deploy --only functions
```

After step 1 the GitHub Actions CI pipeline is fully functional — all subsequent infrastructure changes go through CI.

#### Known gotchas

| Issue | Cause | Fix |
|---|---|---|
| `terraform apply` fails with 409 on Firestore | `(default)` database is soft-deleted after destroy; GCP retains it for a grace period | `terraform import 'google_firestore_database.default' 'projects/<PROJECT_ID>/databases/(default)'` then re-run apply |
| `terraform destroy` fails on raw videos bucket | Bucket contains objects and `force_destroy = false` | `gcloud storage rm -r "gs://catvox-raw-videos-<PROJECT_ID>/**"` then re-run destroy |
| WIF pool ID conflict after destroy | WIF pools are soft-deleted for 30 days — same ID cannot be reused | WIF pool/provider are intentionally outside Terraform; `bootstrap_wif.sh` only needs to be re-run on a genuinely new GCP project |

---

## 8. Implementation Backlog (MVP)

* [x] **Asset Integration:** App Icon & Accent Colors implemented.
* [x] **UI Logic:** Confidence Score color-coding implemented.
* [x] **GCP Foundation:** Deploy Terraform plan to provision GCS (with CORS), IAM, Artifact Registry, and Firestore.
* [x] **Remote Terraform State:** GCS backend configured and local state migrated; state bucket bootstrapped with versioning enabled.
* [x] **CI/CD Terraform Pipeline:** GitHub Actions workflow live — plan on PR (with PR comment), apply on merge; authenticated via Workload Identity Federation.
* [ ] **App Check Setup:** Configure App Attest in Apple Developer and Firebase App Check consoles, plus Debug Provider for local development. (See ADR-0002.) When App Check is wired in, one temporary workaround must be reverted:
    1. **`invoker: 'public'` on both Cloud Functions** (`functions/src/signedUrl.ts`, `functions/src/analyse.ts`) — currently allows unauthenticated callers. Replace with App Check token validation in-code: verify the `X-Firebase-AppCheck` header using the Firebase Admin SDK at the top of each handler, before any business logic.
* [x] **Backend Proxy:** Firebase Cloud Functions (TypeScript) deployed — `getSignedUploadURL` and `analyseVideo` live in `us-central1`; Firestore usage guard, Vertex AI call, CI deploy pipeline via GitHub Actions.
* [x] **Video Recording:** Local capture implemented — HEVC codec enforced, resolution hard-capped at 1080p.
* [x] **Video Upload:** Swift upload of the recorded HEVC file to GCS via signed URL; real pipeline live (`mockMode = false`).
* [x] **AI Connection:** Cloud Function calls Vertex AI Gemini 2.5 Flash via `fileData` GCS URI.
* [x] **Quota Exceeded UI:** Dedicated glassmorphic card shown when the daily scan limit is reached (HTTP 429); includes stub "Upgrade to Pro" CTA (shows "Coming soon" alert) and "Maybe Later" dismiss. StoreKit 2 wiring deferred to the Monetization backlog item.
* [x] **Photos Import:** Add support for selecting an existing video from Photos through the unified scan flow, with local validation for duration, size, and unsupported formats before upload.
* [x] **Early Stop Recording:** Allow users to stop in-app recording after a 2.0-second minimum threshold using the main capture control.
* [x] **Post-Capture Review:** Add `Retake` and `Use This Clip` actions after recording ends; only `Use This Clip` continues to upload and analysis.
* [x] **Backend File Size Validation:** Add backend validation for file size <= 100 MB in the analysis path before Vertex AI is invoked.
* [x] **Scan History Persistence:** Set up SwiftData-backed local storage for successful scans, including saved AI result metadata, thumbnail reference, and CatVox-owned original clip reference.
* [x] **Scan History UI:** Add the frontend history list to the Home experience, showing prior scans with thumbnail, mood/persona cue, and short `cat_thought` preview.
* [x] **Saved Result Reopen:** Allow users to reopen a saved scan from local history without re-upload or re-analysis.
* [x] **Scan Deletion:** Add confirmed deletion of saved scans, removing the history record and CatVox-owned local assets without touching the original Photos asset.
* [ ] **Monetization:** Implement StoreKit 2 for "Pro" tier (Unlimited scans).
* [ ] **Social:** Build branded video overlay and sharing features.

---

## 9. Future Enhancements (Post-MVP)
* **Gemini Model Upgrade:** The backend currently uses `gemini-2.5-flash` (the latest GA Gemini Flash model on Vertex AI as of TRD v2.0). Upgrade to Gemini 3.x Flash once it reaches GA on Vertex AI.
* **IAM Security Review:** `catvox-ci-sa` currently holds `roles/editor`, `roles/resourcemanager.projectIamAdmin`, `roles/iam.serviceAccountAdmin`, and `roles/secretmanager.secretAccessor` — broad rights required for Terraform to manage IAM bindings via CI. Consider splitting Terraform into an admin layer (IAM, SAs — applied manually or via a privileged gated workflow) and an infra layer (GCS, Firestore, Artifact Registry — applied by CI with `roles/editor` only), removing the need for `projectIamAdmin` and `serviceAccountAdmin` on the routine CI identity.
* **Picker Eligibility UX:** Consider richer pre-selection eligibility hints or a more advanced gallery experience only if later product testing shows clear value over the simpler MVP rejection flow.
* **Signed URL Issuance Rate-Limit:** Add a dedicated anti-abuse rate-limit for signed upload URL requests if App Check plus upload-gate quota enforcement prove insufficient.
* **Quota Race Hardening:** The MVP may intentionally accept a small race between non-mutating quota pre-checks and post-success usage increments when concurrent requests start near the daily limit. Add reservation or idempotency-based quota accounting later if this becomes visible in production.
* **Backend Duration Validation:** Add backend validation for uploaded video duration <= 10 seconds before Vertex AI is invoked, rather than relying only on client-side duration checks.
* **4K Import Strategy Review:** Re-evaluate cost and UX trade-offs of accepting 4K gallery videos, and decide later whether to keep raw upload, cap imported resolution, or introduce client-side normalization.
* **Failure Reporting UX Review:** Review likely user-visible failure points across the app and design one simple, consistent way for users to report failures without adding bespoke report flows to individual screens. Example failure points should include failure to open a saved video on the Result screen, including the case where the Result screen uses the original local clip as its looping background. The future design should also decide what diagnostic context to capture internally for such failures.
* **Automated Test Coverage:** Add automated tests for critical user flows that are currently manually verified in MVP, especially scan persistence, reopen from history, deletion, and local video playback behavior.
* **Haptic Completion:** Tactile feedback on successful AI interpretation.
* **Multi-Cat Profiles:** Specific tracking for different pets.
* **Health Monitoring:** Advanced analysis for subtle pain or distress markers.
* **Social Feed:** A community "Wall of Meows" to see global cat interpretations.
* **Advanced Mood Analytics:** Week-over-week trends for cat behavior.
* **4K Video (Pro Tier):** Unlock 4K capture for Pro subscribers; free tier remains capped at 1080p.
