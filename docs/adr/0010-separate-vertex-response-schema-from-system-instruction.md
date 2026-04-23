# ADR-0010: Separate Vertex Response Schema from System Instruction

- Status: Accepted
- Date: 2026-04-23
- Owners: Kathelix / CatVox
- Related docs: `docs/systemInstruction.md`, `docs/TRD.md`
- Supersedes: ADR-0008 in the areas of prompt file naming and output-schema ownership

## Context

CatVox originally kept the full JSON output schema inside the system prompt
document and asked Gemini to return that shape as plain JSON.

Vertex AI now provides `responseSchema`, which allows the backend to define the
machine-enforced output structure directly in the request. Google recommends
putting the schema in `responseSchema` rather than duplicating it in the prompt,
because duplicating the schema can reduce output quality and create drift
between prompt text and runtime enforcement.

CatVox also wants the prompt filename to match Vertex terminology more closely:
the document is a system instruction, not a generic instruction file.

## Decision

CatVox will:

1. keep the behavioral prompt in Markdown at `docs/systemInstruction.md`
2. continue loading that Markdown file into the Cloud Function at build time
3. define the machine-enforced analysis output contract in `functions/src/gemini.ts`
   using Vertex `generationConfig.responseSchema`
4. keep `docs/TRD.md` as the human-readable API contract for the returned JSON
   fields

The system instruction should describe model role, analysis behavior, tone,
persona selection, and safety constraints. It should not duplicate the literal
JSON schema.

## Consequences

### Positive

- Vertex receives a first-class structured-output schema with required fields
- Prompt/schema drift risk is reduced
- `docs/systemInstruction.md` stays focused on behavioral prompt tuning
- The backend can add precise field descriptions for the model without forcing
  prompt authors to duplicate low-level schema syntax

### Negative / Trade-offs

- Changes to output fields now require coordinated edits to code and TRD, not
  only a prompt edit
- Prompt authors no longer see the exact runtime schema inline in the prompt
  document
- Schema ownership shifts partly from prompt iteration to backend review

## Implementation Notes

- Source file: `docs/systemInstruction.md`
- Build script: `mkdir -p assets && cp ../docs/systemInstruction.md assets/systemInstruction.md && tsc`
- Runtime read: `readFileSync(join(__dirname, '../assets/systemInstruction.md'), 'utf-8')` in `gemini.ts`
- Runtime schema: `ANALYSIS_RESPONSE_SCHEMA` in `functions/src/gemini.ts`
- Workflow trigger: `.github/workflows/functions.yml` watches `docs/systemInstruction.md`
