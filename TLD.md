# Top-level Design: CatVox AI


This file must contain only top level design decisions.
It is used to generate, and stay in sync with, Technical Requirements Document `TRD.md` for full technical specifications.
Later `TRD.md` is used with Claude Code to generate all the code, both for apps and infrastructure.

## 1. Project Context & Vision
CatVox AI is a premium iOS application and brand ambassador for Kathelix Ltd. It uses multimodal AI (Gemini 3.1 Flash) to interpret 10-second cat video clips, providing behavioral analysis and a humorous "inner monologue" translation based on specific feline personas.

## 2. Core Strategic Priorities
* **Resilient Infrastructure:** The system is built on Google Cloud Platform (GCP) using a "Phoenix" architecture—reproducible, secure, and tool-driven.
* **User Experience:** Focus on "Glassmorphism" design, minimalist interactions, and high-performance video processing.
* **Monetization:** A "Freemium" model with a 5-scan daily limit and a StoreKit 2-based Pro tier for unlimited use.

## 3. Key Design Decisions (The "Why")
* **Multimodal Engine:** Selected Gemini 3.1 Flash for its ability to process video and audio simultaneously via GCS URIs, reducing mobile device memory overhead.
* **Video Pipeline:** Chose to stick with native **HEVC (.mov)** at 1080p for the MVP to minimize bandwidth usage and avoid complex client-side transcoding.
* **Regional Strategy:** Standardized on `us-central1` (Iowa) for the lowest AI infrastructure costs and `nam5` for Firestore multi-region durability across the US market.
* **Security:** Implemented Firebase App Check (with Debug Provider for local dev) to prevent unauthorized API calls and manage GCP costs.

## 4. Current Implementation State
The iOS app is half implemented.
The foundational infrastructure has been successfully deployed via Terraform.

### Infrastructure & Secrets:
* **GCP Project ID:** `kathelix-catvox-prod`.
* **Region:** `us-central1`.
* **Firestore:** `nam5` (Multi-region US).
* **Secrets:** `APP_CHECK_DEBUG_TOKEN` and `GCP_PROJECT_ID` are stored in Secret Manager.
* **Storage:** Bucket `catvox-raw-videos-kathelix-catvox-prod` is live with a 24-hour auto-deletion lifecycle rule.

### iOS Development:
* **UI/UX:** Primary brand palette (Indigo to Cyan gradient) and initial result screen logic (Confidence Score color-coding) are established.
* **App Check:** The iOS app is configured to use the `AppCheckDebugProvider`, with the debug token synced from the cloud console to Xcode environment variables.

## 5. Immediate Next Steps (The Backlog)
1.  **Backend Proxy:** Develop the Firebase Cloud Function (TypeScript) to act as the interpretation engine.
2.  **Usage Guard:** Implement the Firestore-based daily limit logic (5 scans/day).
3.  **Video Pipeline:** Build the Swift logic to upload the native 10s HEVC clips to GCS.
4.  **AI Connection:** Link the Cloud Function to the Vertex AI Gemini 3.1 Flash endpoint.

---
