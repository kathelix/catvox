# High-level Design: CatVox AI

**Version:** 1.1
**Company:** Kathelix Ltd
**Project Lead:** Ivan Boyko
**Date:** April 2026

This file captures the high-level architecture and stable design intent for CatVox.
It should stay concise and remain aligned with `docs/TRD.md`, which holds the detailed technical design and implementation constraints.
For formal architecture decisions, see `docs/adr/README.md` and the ADR files under `docs/adr/`.

## 1. Project Context & Vision
CatVox AI is a premium iOS application and brand ambassador for Kathelix Ltd. It uses multimodal AI (Gemini 2.5 Flash) to interpret short cat video clips, providing behavioral analysis and a humorous "inner monologue" translation based on specific feline personas.

The MVP supports two local input sources:
1. recording a new clip in-app, with the ability to stop early once a brief minimum capture threshold is reached
2. selecting an existing clip from the user's Photos library

The product also includes a local on-device scan history as part of the MVP user experience, allowing users to revisit previous cat mood interpretations without relying on cloud-side user accounts.

## 2. System Flow
1. The user taps the primary CTA `Read My Cat` in the iOS app.
2. The app presents a lightweight source choice sheet with:
   * `Record New Video`
   * `Choose from Photos`
3. The user provides a local video by either recording a new clip or selecting an existing clip from Photos.
4. For in-app recording, the app records up to 10 seconds and allows the user to stop early after a short minimum capture threshold.
5. After recording ends, the app presents a lightweight review decision:
   * `Retake`
   * `Use This Clip`
6. The app validates the selected local video against MVP client-side rules before upload.
7. The app requests a signed upload URL from the backend.
8. The app uploads the validated video to Google Cloud Storage.
9. The app submits the uploaded clip for backend analysis using the server-issued storage reference.
10. The backend validates App Check, enforces usage limits, validates server-side guardrails such as upload file size, invokes Vertex AI, and returns a normalized result payload.

## 3. Core Strategic Priorities
* **Resilient Infrastructure:** The system is built on Google Cloud Platform (GCP) using a "Phoenix" architecture - reproducible, secure, and tool-driven.
* **User Experience:** Focus on "Glassmorphism" design, minimalist interactions, and high-performance video processing.
* **Monetization:** A freemium model with server-enforced daily usage limits and a StoreKit 2-based Pro tier for unlimited use.

## 4. Key Design Decisions
* **Multimodal Engine:** Selected Gemini 2.5 Flash for its ability to process video and audio simultaneously via GCS-hosted media, reducing mobile device memory overhead.
* **Video Pipeline:** The MVP accepts validated local videos from either in-app recording or Photos selection. In-app recording captures up to 10 seconds, with support for early user stop after a short minimum threshold, followed by a lightweight `Retake` / `Use This Clip` review step before upload. Native HEVC (.mov) at 1080p remains the preferred capture path for in-app recording, with silent fallback to H.264 on devices that do not support HEVC. Client-side transcoding is intentionally out of scope for MVP.
* **MVP Input Rules:** Submitted videos must already satisfy MVP limits before upload: maximum 10 seconds duration, maximum 100 MB file size, supported codec/container, and no ProRes input. 4K input is temporarily accepted for simplicity.
* **UX Validation Strategy:** The app validates candidate videos locally before upload and clearly explains rejection reasons when a selected video is ineligible. In-app trimming is out of scope for MVP.
* **Regional Strategy:** Standardized on `us-central1` (Iowa) for the lowest AI infrastructure costs and `nam5` for Firestore multi-region durability across the US market.
* **Security:** Firebase App Check uses App Attest for production iOS app verification and Debug Provider for local development, preventing unauthorized API calls and managing GCP costs.
* **Backend Pattern:** Firebase Cloud Functions (2nd Gen) act as the backend proxy between the iOS client and privileged GCP services.
* **Prompt Management:** The AI system prompt is maintained as a versioned markdown document in the repository and treated as part of the deployable backend behavior.
* **Identity Separation:** Runtime cloud execution and automated infrastructure delivery use separate service accounts to reduce blast radius and keep privileged automation isolated from application runtime.

## 5. Trust Boundary
* The iOS client never calls Vertex AI directly.
* Signed upload URL issuance is server-side only.
* Firebase App Check is mandatory on backend entry points.
* Usage policy enforcement is server-side.
* Secrets and privileged cloud access stay server-side.
* Client-side validation improves UX and is the primary MVP enforcement point for duration/format eligibility, while the backend remains authoritative for server-side guardrails such as quota and upload file size.

## 6. Infrastructure Model
* CatVox runs on GCP and is provisioned with Terraform.
* The infrastructure model is intended to be reproducible and rebuildable.
* The project uses three distinct CI/CD pipelines: iOS build validation, infrastructure delivery, and backend function delivery.
* CI/CD authentication uses keyless GitHub Actions federation.

## 7. MVP Boundaries / Non-goals
* No direct client-side access to privileged GCP services.
* No client-side video transcoding in MVP.
* No in-app video trimming in MVP.
* No post-capture trimming or clip editing in MVP beyond `Retake` or `Use This Clip`.
* No backend video-duration validation in MVP; duration is enforced client-side, with server-side upload file-size guardrails only.
* No custom filtered gallery browser in MVP beyond the system video picker flow.
* User identity for MVP is an anonymous per-install identifier used for quota enforcement; full authenticated user accounts are outside current MVP scope.
* Older Apple device compatibility is not a design driver for the attestation approach.

---
