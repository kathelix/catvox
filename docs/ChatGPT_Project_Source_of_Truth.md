# Project Source of Truth - CatVox

**Version:** 1.2

For architecture, design, and technical planning discussions in this ChatGPT Project:

## Source of truth

Use the GitHub repository below as the canonical source of truth:

- Repository: `kathelix/catvox`

Do not treat uploaded Project Sources as authoritative if they conflict with the current GitHub repo contents.

If GitHub content and any older uploaded file differ, prefer the GitHub version.

## Default document scope

For architecture and design work, prioritize the `docs/` subtree in the repository.

Primary files:

- `docs/HLD.md`
- `docs/TRD.md`
- `docs/adr/README.md`
- `docs/adr/*.md`

These files should be treated as the main design corpus for:

- product architecture
- technical design
- infrastructure decisions
- security decisions
- ADR-driven decision history

## How to use the repo

At the start of any new architecture/design discussion, first consult the relevant files in `docs/` from the GitHub repo if needed.

Prefer:

- `docs/HLD.md` for high-level direction and architectural intent
- `docs/TRD.md` for detailed technical requirements and implementation constraints
- `docs/adr/*.md` for specific architectural decisions and rationale

## Scope outside `docs/`

Do not inspect files outside `docs/` by default.

Only look outside `docs/` when:

- the user explicitly asks about a non-`docs` file
- a design question cannot be answered reliably from `docs/`
- implementation context is needed to validate whether design docs match repo reality

## ADR workflow expectations

This project uses ADRs as the formal decision log.

When a significant architectural, security, infrastructure, or costly-to-reverse decision is discussed:

- check whether an ADR should exist
- if missing, recommend creating a new ADR
- keep HLD/TRD aligned with accepted ADRs

## Conflict resolution

When documents disagree, use this order of precedence:

1. Latest GitHub repo contents
2. ADRs for historical decision intent
3. `docs/TRD.md` for detailed current technical design
4. `docs/HLD.md` for high-level design direction
5. Any uploaded Project Source copies, if still present

If there is a real contradiction between current repo documents, explicitly point it out instead of guessing.

## Output expectations

For architectural/design discussions:

- do not generate code unless explicitly asked
- prefer reasoning, trade-offs, structure, and exact wording suggestions for docs
- when relevant, propose updates to:
  - `docs/HLD.md`
  - `docs/TRD.md`
  - `docs/adr/*.md`

## Practical intent

This ChatGPT Project should use the live GitHub repo as the working design source, so that future chats do not depend on stale uploaded markdown files.
