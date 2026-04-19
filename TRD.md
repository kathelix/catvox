# Technical Requirements Document: CatVox AI (MVP)

**Version:** 1.5
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
* **Video Pipeline:** App records in native **HEVC (.mov)** at 1080p to maximize quality while minimizing bandwidth. No mandatory re-encoding is required for MVP.
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
You are CatVox AI, a multimodal expert in feline ethology and a sophisticated creative writer. Your task is to analyze 10-second video clips (including audio) to provide professional insights into a cat's emotional state, paired with a witty "inner monologue" translation.

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
* **Resource Scope:**
    * **Project Services:** Enablement of `aiplatform`, `cloudfunctions`, `run`, `firestore`, `storage`, `secretmanager`, and `artifactregistry`.
    * **Databases:** Explicit provisioning of a **Firestore instance** in `(default)` mode.
    * **Container Registry:**
    * **Artifact Registry repository** for Cloud Functions (2nd Gen) build images.
    * **Service Accounts:** `catvox-backend-sa` with least-privilege IAM roles.
    * **Secrets:** Secret Manager for `GCP_PROJECT_ID` and `APP_CHECK_DEBUG_TOKEN`.

### 6.2 Compute & API Orchestration
* **Environment:** Firebase Cloud Functions (2nd Generation).
* **Runtime:** Node.js (TypeScript).
* **Vertex AI Integration:** Call Gemini 3.1 Flash using `fileData` (GCS URI) for multimodal analysis.

### 6.3 Security & Identity
* **App Verification:** Firebase App Check mandatory for all backend entry points (Debug Provider for local dev).
* **IAM Policy:** SA requires roles/aiplatform.user, roles/storage.objectViewer, and roles/datastore.user.
* **Secrets:** Zero hardcoded identifiers; all retrieved via Secret Manager at runtime.

### 6.4 Data Lifecycle & Persistence
* **Google Cloud Storage (GCS):**
    * Bucket: `catvox-raw-videos`.
    * **CORS Policy:** Configuration to allow direct uploads from the iOS app.
    * **Lifecycle Rule:** `action: Delete`, `condition: Age > 1 day`.
* **Firestore (Usage Guard):**
    * Collection: usage/{userId}.
    * Schema: { count: integer, lastResetDate: string (YYYY-MM-DD) }.
    * **Logic:** Backend increments count; rejects request (429) if limit reached.

---

## 7. Implementation Backlog (MVP)

* [x] **Asset Integration:** App Icon & Accent Colors implemented.
* [x] **UI Logic:** Confidence Score color-coding implemented.
* [x] **GCP Foundation:** Deploy Terraform plan to provision GCS (with CORS), IAM, Artifact Registry, and Firestore.
* [ ] **App Check Setup:** Configure App Check in Apple and Firebase consoles.
* [ ] **Backend Proxy:** Develop Firebase Cloud Function (TypeScript) with usage-limit logic.
* [ ] **Video Pipeline:** Implement Swift-based background upload of native HEVC to GCS.
* [ ] **AI Connection:** Connect Cloud Function to Vertex AI Gemini 3.1 Flash.
* [ ] **Persistence:** Set up SwiftData for local scan history storage.
* [ ] **Monetization:** Implement StoreKit 2 for "Pro" tier (Unlimited scans).
* [ ] **Social:** Build branded video overlay and sharing features.

---

## 8. Future Enhancements (Post-MVP)
* **Haptic Completion:** Tactile feedback on successful AI interpretation.
* **Multi-Cat Profiles:** Specific tracking for different pets.
* **Health Monitoring:** Advanced analysis for subtle pain or distress markers.
* **Social Feed:** A community "Wall of Meows" to see global cat interpretations.
* **Advanced Mood Analytics:** Week-over-week trends for cat behavior.