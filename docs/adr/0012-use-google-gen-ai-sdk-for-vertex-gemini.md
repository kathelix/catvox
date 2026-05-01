# ADR-0012: Use Google Gen AI SDK for Vertex Gemini Calls

- Status: Accepted
- Date: 2026-05-01
- Owners: Kathelix / CatVox
- Related docs: `docs/TRD.md`, `functions/src/gemini.ts`

## Context

CatVox calls Gemini 2.5 Flash from a Firebase Cloud Function using Vertex AI as
the managed inference surface. The backend previously used the deprecated
`@google-cloud/vertexai` generative AI module.

Google deprecated that generative AI module on June 24, 2025 and scheduled it
for removal on June 24, 2026. Production Cloud Run logs now emit a warning for
the existing dependency, so continuing to use it creates a near-term runtime and
maintenance risk.

## Decision

CatVox will use the Google Gen AI SDK (`@google/genai`) for backend Gemini
requests. The Cloud Function will instantiate `GoogleGenAI` with:

- `vertexai: true`
- the GCP project ID from the Cloud Functions runtime environment
- `location: "us-central1"`
- `apiVersion: "v1"`

The existing Vertex AI architecture remains unchanged: the iOS client still
never calls Gemini directly, the backend keeps using GCS `fileData` references
for uploaded clips, and the runtime service account continues to require
`roles/aiplatform.user`.

## Consequences

### Positive

- Removes the deprecated `@google-cloud/vertexai` dependency before its removal
  date
- Keeps the backend on Google's supported SDK path for Gemini features
- Preserves the current Vertex AI trust boundary, IAM model, prompt loading,
  structured output schema, safety settings, and retry behavior

### Negative / Trade-offs

- The backend response extraction code must follow the Google Gen AI SDK
  response shape rather than the old Vertex AI SDK wrapper shape
- Future Gemini SDK migrations should check both Google Cloud migration docs and
  the generated TypeScript typings because naming differs between SDK versions

## Implementation Notes

- Dependency: `@google/genai`
- Removed dependency: `@google-cloud/vertexai`
- Source file: `functions/src/gemini.ts`
- Runtime schema: `ANALYSIS_RESPONSE_SCHEMA` passed as
  `GenerateContentConfig.responseSchema`
- Runtime prompt: `docs/systemInstruction.md` copied to
  `functions/assets/systemInstruction.md` by the Functions build script
