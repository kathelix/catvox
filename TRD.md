# Technical Requirements Document: CatVox AI (MVP)

**Version:** 1.8
**Company:** Kathelix Ltd  
**Project Lead:** Ivan Boyko
**Date:** April 2026  
**Status:** Infrastructure & Backend Definition

---

## 1. Executive Summary
CatVox AI is a premium, minimalist iOS application designed to interpret cat behavior from 10-second video clips using multimodal Generative AI (Gemini 3.1 Flash). The app serves as a high-tech brand ambassador for Kathelix Ltd, showcasing expertise in AI integration, Cloud architecture, and superior UX design.

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
* **Video Capture:** Fixed 10-second recording window with a visual countdown UI and an audio ping at the moment recording ends.
* **Video Pipeline:** App records in native **HEVC (.mov)** with resolution hard-capped at **1920 × 1080 (1080p)**. The cap keeps free-tier clip sizes to approximately 15–25 MB per 10-second recording. No re-encoding is required for MVP. Devices that do not support HEVC fall back silently to H.264. 4K capture is reserved as a potential future Pro-tier feature.
* **Multimodal Analysis:** Simultaneous processing of video (body language) and audio (vocalization) via Vertex AI.
* **Persona Engine:** Logic to assign one of 6 "Cat Personas" to the interpretation to drive engagement and humor.
* **Mood Diary:** A local history of scans saved using on-device persistent storage.
* **Social Sharing:** Integrated "Share to Story" feature with a branded overlay.

### 3.2 Monetization & Sustainability
* **Credit System:** 5 free scans/day to manage GCP costs.
* **Pro Tier (IAP):** One-time in-app purchase for unlimited scans and watermark removal.
* **Brand Promotion:** Subtle "Powered by Kathelix" watermark on all free-tier exports.

---

## 4. AI System Instructions (The "Prompt Gate")

### 4.1 Role & Context
Short version:
You are CatVox AI, a multimodal expert in feline ethology and a sophisticated creative writer. Your task is to analyze 10-second video clips (including audio) to provide professional insights into a cat's emotional state, paired with a witty "inner monologue" translation.

Full version see in the file `Instructions.md`

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
1. **Home Screen:** Minimalist dashboard showing the latest "Mood" and a "Start Scan" button.
2. **Recording Screen:** Viewfinder with a 10-second progress ring.
3. **Result Screen:**
    * Full-screen looping video background.
    * Animated Glassmorphism "Thought Bubble".
    * **Confidence Score UI:** The percentage ring must be dynamically color-coded:
        * **Green:** > 80% (High Confidence)
        * **Amber:** 50% - 80% (Moderate Confidence)
        * **Red:** < 50% (Low Confidence/Ambiguous)
    * Expandable "Expert Insights" drawer.
    * "Share to Story" CTA.

---

## 6. Cloud Infrastructure & Security (IaC)

### 6.1 Infrastructure as Code (Terraform)
* **Provider:** Google Cloud Platform (GCP).
* **Deployed Project:** GCP Project ID `kathelix-catvox-prod`, region `us-central1`, Firestore location `nam5` (US multi-region).
* **Terraform State:** Remote state stored in GCS bucket `catvox-tf-state-<project-id>` (`us-central1`, object versioning enabled). State is never stored locally or committed to source control. The GCS backend enables consistent state access from both local development and CI/CD pipelines. The state bucket is bootstrapped manually (outside of Terraform) to avoid a circular dependency.
* **Resource Scope:**
    * **Project Services:** Enablement of `aiplatform`, `cloudfunctions`, `run`, `firestore`, `storage`, `secretmanager`, `artifactregistry`, `firebase`, `firebaseappcheck`, and `iam`.
    * **Databases:** Explicit provisioning of a **Firestore instance** in `(default)` mode.
    * **Artifact Registry repository** for Cloud Functions (2nd Gen) build images.
    * **Service Accounts:** `catvox-backend-sa` (Cloud Functions runtime) and `catvox-ci-sa` (Terraform CI / GitHub Actions) — see §6.3 for roles.
    * **Secrets:** Secret Manager for `GCP_PROJECT_ID` and `APP_CHECK_DEBUG_TOKEN`.

### 6.2 Compute & API Orchestration
* **Environment:** Firebase Cloud Functions (2nd Generation).
* **Runtime:** Node.js (TypeScript).
* **Vertex AI Integration:** Call Gemini 3.1 Flash using `fileData` (GCS URI) for multimodal analysis.

### 6.3 Security & Identity
* **App Verification:** Firebase App Check mandatory for all backend entry points. App Attest is the production provider for Apple platforms; Debug Provider is used for local development. (See ADR-0002.)
* **Secrets:** Zero hardcoded identifiers; all retrieved via Secret Manager at runtime.
* **Service Account: `catvox-backend-sa`** — Runtime identity for Cloud Functions. Holds only the minimal roles required at runtime; never has CI-level access.
    * `roles/aiplatform.user` — invoke Gemini 3.1 Flash via Vertex AI.
    * `roles/storage.objectViewer` — read video objects from GCS for Vertex AI.
    * `roles/datastore.user` — read/write Firestore usage documents.
    * `roles/secretmanager.secretAccessor` — resolve secrets at function startup.
    * `roles/iam.serviceAccountTokenCreator` (self) — generate signed GCS upload URLs for the iOS client.
* **Service Account: `catvox-ci-sa`** — Terraform CI identity for GitHub Actions. Holds broader project-level rights needed for IaC; isolated from the runtime SA to limit blast radius if either is compromised.
    * `roles/editor` — manage GCP resources (APIs, GCS, Artifact Registry, Secret Manager, Firestore, service accounts).
    * `roles/resourcemanager.projectIamAdmin` — read and write project-level IAM bindings.
    * `roles/storage.objectAdmin` (state bucket only) — read/write Terraform state; granted via `bootstrap_wif.sh`, not Terraform (state bucket is outside IaC scope).

### 6.4 Data Lifecycle & Persistence
* **Google Cloud Storage (GCS):**
    * Bucket: `catvox-raw-videos-<project-id>` (project ID suffix ensures global uniqueness).
    * **CORS Policy:** Configuration to allow direct uploads from the iOS app.
    * **Lifecycle Rule:** `action: Delete`, `condition: Age > 1 day`.
* **Firestore (Usage Guard):**
    * Collection: usage/{userId}.
    * Schema: { count: integer, lastResetDate: string (YYYY-MM-DD) }.
    * **Logic:** Backend increments count; rejects request (429) if limit reached.

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

### 7.3 WIF Bootstrap & GitHub Secrets
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

---

## 8. Implementation Backlog (MVP)

* [x] **Asset Integration:** App Icon & Accent Colors implemented.
* [x] **UI Logic:** Confidence Score color-coding implemented.
* [x] **GCP Foundation:** Deploy Terraform plan to provision GCS (with CORS), IAM, Artifact Registry, and Firestore.
* [x] **Remote Terraform State:** GCS backend configured and local state migrated; state bucket bootstrapped with versioning enabled.
* [x] **CI/CD Terraform Pipeline:** GitHub Actions workflow live — plan on PR (with PR comment), apply on merge; authenticated via Workload Identity Federation.
* [ ] **App Check Setup:** Configure App Attest in Apple Developer and Firebase App Check consoles, plus Debug Provider for local development. (See ADR-0002.)
* [ ] **Backend Proxy:** Develop Firebase Cloud Function (TypeScript) with usage-limit logic.
* [x] **Video Recording:** Local capture implemented — HEVC codec enforced, resolution hard-capped at 1080p.
* [ ] **Video Upload:** Implement Swift-based background upload of the recorded HEVC file to GCS via signed URL.
* [ ] **AI Connection:** Connect Cloud Function to Vertex AI Gemini 3.1 Flash.
* [ ] **Persistence:** Set up SwiftData for local scan history storage.
* [ ] **Monetization:** Implement StoreKit 2 for "Pro" tier (Unlimited scans).
* [ ] **Social:** Build branded video overlay and sharing features.

---

## 9. Future Enhancements (Post-MVP)
* **Haptic Completion:** Tactile feedback on successful AI interpretation.
* **Multi-Cat Profiles:** Specific tracking for different pets.
* **Health Monitoring:** Advanced analysis for subtle pain or distress markers.
* **Social Feed:** A community "Wall of Meows" to see global cat interpretations.
* **Advanced Mood Analytics:** Week-over-week trends for cat behavior.
* **4K Video (Pro Tier):** Unlock 4K capture for Pro subscribers; free tier remains capped at 1080p.
