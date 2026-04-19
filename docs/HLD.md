# High-level Design: CatVox AI

This file captures the high-level architecture and stable design intent for CatVox.
It should stay concise and remain aligned with `docs/TRD.md`, which holds the detailed technical design and implementation constraints.
For formal architecture decisions, see `docs/adr/README.md` and the ADR files under `docs/adr/`.

## 1. Project Context & Vision
CatVox AI is a premium iOS application and brand ambassador for Kathelix Ltd. It uses multimodal AI (Gemini 3.1 Flash) to interpret 10-second cat video clips, providing behavioral analysis and a humorous "inner monologue" translation based on specific feline personas.

## 2. System Flow
1. The iOS app records a fixed 10-second cat video clip.
2. The app requests a signed upload URL from the backend.
3. The app uploads the video to Google Cloud Storage.
4. The app calls the backend analysis endpoint.
5. The backend validates App Check, enforces usage limits, invokes Vertex AI, and returns a normalized result payload.

## 3. Core Strategic Priorities
* **Resilient Infrastructure:** The system is built on Google Cloud Platform (GCP) using a "Phoenix" architecture - reproducible, secure, and tool-driven.
* **User Experience:** Focus on "Glassmorphism" design, minimalist interactions, and high-performance video processing.
* **Monetization:** A "Freemium" model with a 5-scan daily limit and a StoreKit 2-based Pro tier for unlimited use.

## 4. Key Design Decisions
* **Multimodal Engine:** Selected Gemini 3.1 Flash for its ability to process video and audio simultaneously via GCS URIs, reducing mobile device memory overhead.
* **Video Pipeline:** Chose to stick with native **HEVC (.mov)** at 1080p for the MVP to minimize bandwidth usage and avoid complex client-side transcoding.
* **Regional Strategy:** Standardized on `us-central1` (Iowa) for the lowest AI infrastructure costs and `nam5` for Firestore multi-region durability across the US market.
* **Security:** Firebase App Check uses App Attest for production iOS app verification and Debug Provider for local development, preventing unauthorized API calls and managing GCP costs.
* **Backend Pattern:** Firebase Cloud Functions (2nd Gen) act as the backend proxy between the iOS client and privileged GCP services.

## 5. Trust Boundary
* The iOS client never calls Vertex AI directly.
* Signed upload URL issuance is server-side only.
* Firebase App Check is mandatory on backend entry points.
* Secrets and privileged cloud access stay server-side.

## 6. Infrastructure Model
* CatVox runs on GCP and is provisioned with Terraform.
* The infrastructure model is intended to be reproducible and rebuildable.
* CI/CD for infrastructure uses keyless GitHub Actions authentication via Workload Identity Federation.

## 7. MVP Boundaries / Non-goals
* No direct client-side access to privileged GCP services.
* No client-side video transcoding in MVP.
* 4K video capture is outside MVP scope.
* Older Apple device compatibility is not a design driver for the attestation approach.

---
