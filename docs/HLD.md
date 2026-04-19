# High-level Design: CatVox AI


This file must contain only high-level design decisions.
It is used to generate, and stay in sync with, Technical Requirements Document `docs/TRD.md` for full technical specifications.
Later `docs/TRD.md` is used with Claude Code to generate all the code, both for apps and infrastructure.

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
* **Security:** Firebase App Check uses App Attest for production iOS app verification and Debug Provider for local development, preventing unauthorized API calls and managing GCP costs.

---
