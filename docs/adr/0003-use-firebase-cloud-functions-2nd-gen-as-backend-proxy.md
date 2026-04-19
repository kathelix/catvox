# ADR-003: Use Firebase Cloud Functions 2nd Gen as the CatVox Backend Proxy

- Status: Accepted
- Date: 2026-04-19
- Owners: Kathelix / CatVox
- Related docs: `docs/HLD.md`, `docs/TRD.md`

## Context

CatVox is an iOS application that records short cat videos, uploads them to Google Cloud Storage, and invokes multimodal analysis in Vertex AI Gemini 3.1 Flash. The backend must:

- protect Vertex AI and storage-related operations from direct client abuse
- enforce usage limits for the free tier
- verify app authenticity via Firebase App Check
- issue signed upload URLs for client video uploads
- keep backend implementation operationally simple for an MVP

The project is already committed to Google Cloud Platform and Firebase-oriented mobile integration.

## Decision

CatVox will use **Firebase Cloud Functions 2nd Generation** as the backend proxy layer for the MVP.

This backend layer is responsible for:

- receiving authenticated requests from the iOS app
- validating Firebase App Check on backend entry points
- enforcing daily usage limits
- issuing signed Google Cloud Storage upload URLs
- invoking Vertex AI Gemini 3.1 Flash for multimodal analysis
- returning the normalized CatVox response schema to the client

## Rationale

### 1. Best fit for Firebase-centered mobile architecture

CatVox already uses Firebase-aligned capabilities, especially App Check, and benefits from the tighter operational fit of Firebase Cloud Functions for mobile backends.

### 2. Security boundary for cost-sensitive services

The client must not directly hold privileged access to Vertex AI or signing capabilities for storage uploads. A backend proxy is required to keep these controls server-side.

### 3. Lower operational burden for MVP

Compared with building and operating a separate custom service stack, Cloud Functions 2nd Gen provides a simpler deployment model while still running on Cloud Run infrastructure underneath.

### 4. Adequate flexibility for current workload

The CatVox MVP workload is request-driven and well suited to eventless HTTP-style backend endpoints rather than a more complex service topology.

## Consequences

### Positive

- Stronger separation between client app and privileged cloud operations
- Natural place to enforce App Check and free-tier usage limits
- Simpler MVP deployment and maintenance model
- Good alignment with Firebase and GCP tooling already chosen by the project

### Negative / Trade-offs

- Less explicit service-level control than a fully custom Cloud Run service stack
- Runtime cold-start and request-shaping concerns must still be managed
- Backend logic is coupled to Firebase/GCP platform choices

## Rejected Options

### Option A: Direct client access to Vertex AI and storage operations

Rejected because:

- it would expose privileged or cost-sensitive operations too directly to the client
- it weakens the abuse-prevention boundary
- it makes usage enforcement and signing control harder to secure

### Option B: Custom backend on Cloud Run from day one

Rejected because:

- it adds operational and packaging complexity for limited MVP benefit
- the current CatVox use case does not yet justify a more custom service model
- Firebase Cloud Functions 2nd Gen already meets the project’s current backend needs

## Implementation Notes

- Use Firebase Cloud Functions **2nd Gen**
- Use the dedicated runtime identity `catvox-backend-sa`
- Require Firebase App Check on all public backend entry points
- Keep backend responsibilities narrow: validation, limits, URL issuance, AI orchestration, response normalization

## Required Document Updates

### HLD

Add or tighten wording so the high-level architecture explicitly states that CatVox uses a **Firebase Cloud Functions 2nd Gen backend proxy** between the iOS app and privileged GCP services.

### TRD

Keep `Compute & API Orchestration` aligned with this ADR and cross-reference this ADR in the backend/security sections where useful.

## Review Trigger

Revisit this ADR if any of the following becomes true:

- CatVox requires more complex service decomposition
- long-running workloads or higher operational tuning needs emerge
- non-Firebase backend capabilities become a first-class requirement
- Cloud Functions operational constraints become a bottleneck
