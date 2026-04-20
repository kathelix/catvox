# ADR-008: Load AI System Prompt from Markdown at Build Time

- Status: Accepted
- Date: 2026-04-20
- Owners: Kathelix / CatVox
- Related docs: `docs/Instructions.md`

## Context

The CatVox backend passes a system instruction to Vertex AI Gemini with every `analyseVideo` call. This instruction defines the model's role, analysis protocol, persona definitions, constraints, and output schema (TRD §4).

The system prompt is expected to change frequently, particularly during the early product phase when the AI researcher and product owner are actively tuning persona behavior, tone, and output quality. The prompt is maintained in `docs/Instructions.md`, which is also used as a reference document when designing prompt changes with external AI tools (e.g. Gemini, ChatGPT).

Two questions arise:

1. Where should the prompt live as a source of truth?
2. How should the Cloud Function consume it?

## Decision

The system prompt will be maintained in **`docs/Instructions.md`** as the single source of truth and loaded into the Cloud Function **at build time** via a build script that copies it into the deployment artifact.

The mechanism:

- `functions/package.json` `build` script runs `cp ../docs/Instructions.md assets/instructions.md` before `tsc`
- `functions/src/gemini.ts` reads the file at module load using `fs.readFileSync`
- `functions/assets/` is gitignored — it is a build artifact, not source
- Changing the prompt requires only editing `docs/Instructions.md`; no TypeScript changes are needed

## Rationale

### 1. Single source of truth for prompt iteration

`docs/Instructions.md` is already the authoritative home for the system prompt. Duplicating it inside TypeScript would create two places to keep in sync and make it easy for the prompt to drift from the documented version.

### 2. Accessible to non-engineers

The primary audience for prompt changes is an AI researcher or product owner, not a TypeScript developer. Editing a Markdown file is a much lower barrier than opening TypeScript source, finding the right string constant, and being careful not to break surrounding code. Decoupling the prompt from the code removes an unnecessary engineering dependency from the prompt iteration workflow.

### 3. Visible and reviewable in version control

Because `docs/Instructions.md` is a tracked Markdown file, every prompt change appears as a clean diff in a pull request, separate from infrastructure or backend logic changes. This makes prompt history easy to read and audit.

### 4. CI pipeline handles deployment automatically

`docs/Instructions.md` is listed in the path triggers of `.github/workflows/functions.yml`. When the file changes and the PR is merged, the Functions pipeline runs `npm run build` (which copies the file) and deploys the updated function. No additional steps are required.

## Consequences

### Positive

- Prompt changes require no TypeScript edits
- Non-engineers can iterate on the prompt independently
- Full version history of every prompt change is in Git
- CI deploys prompt changes automatically on merge

### Negative / Trade-offs

- Prompt changes still require a Cloud Function redeploy (a CI deploy takes ~2–3 minutes)
- There is no mechanism to update the prompt on a running instance without redeployment
- The `assets/` directory must be excluded from version control to avoid committing a build artifact

## Rejected Options

### Option A: Hardcode the system prompt as a TypeScript string constant in `gemini.ts`

Rejected because:

- every prompt change requires a TypeScript edit, creating an unnecessary engineering dependency
- the prompt and code history are entangled in the same commits, making each harder to read independently
- it is a higher barrier for an AI researcher who is not a TypeScript developer

### Option B: Store the system prompt in Secret Manager

Rejected because:

- updating the prompt requires a `gcloud secrets versions add` command, which is more friction than a Git commit
- Secret Manager adds per-access cost and latency, which is disproportionate for a non-sensitive configuration value
- the function still requires a restart or redeploy to pick up a new version on a warm instance, so the "no redeploy" advantage is smaller than it appears
- Secret Manager is the right tool for credentials, not for AI prompt content

### Option C: Fetch the prompt from Cloud Storage or Firestore at runtime

Rejected because:

- adds a network call on every cold start (or requires in-memory caching, adding complexity)
- introduces a runtime dependency that can fail independently of the function code
- no meaningful advantage over the build-time copy for the current prompt iteration workflow

## Implementation Notes

- Source file: `docs/Instructions.md`
- Build script: `mkdir -p assets && cp ../docs/Instructions.md assets/instructions.md && tsc`
- Runtime read: `readFileSync(join(__dirname, '../assets/instructions.md'), 'utf-8')` in `gemini.ts`
- `functions/.gitignore` excludes `assets/`
- `docs/Instructions.md` is added to the path triggers in `.github/workflows/functions.yml` so a prompt-only commit triggers the pipeline

## Required Document Updates

### TRD

- `§4.1` — note that the full system prompt lives in `docs/Instructions.md` and is loaded into the Cloud Function at build time

### HLD

- No changes required; the prompt management approach is an implementation detail below HLD level

## Review Trigger

Revisit this ADR if any of the following becomes true:

- prompt iteration speed becomes a bottleneck and zero-redeploy updates are needed (at which point Secret Manager or a Firestore-backed config becomes more attractive)
- the system prompt grows large enough that build-time bundling becomes impractical
- a prompt A/B testing or versioning requirement emerges that needs runtime switching
