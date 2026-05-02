# ChatGPT Project Source of Truth - CatVox

Version: 1.3

## Mandatory rule

For every CatVox architecture, product, design, implementation-planning, analytics, testing, or documentation discussion:

First fetch the latest files from the main branch of the GitHub repository kathelix/catvox.

Do NOT rely on:
- cached files
- earlier fetched versions

The repository changes frequently, often daily. Re-uploading files manually is wasteful and error-prone.

## Repository

Canonical repository: `kathelix/catvox`

Main branch: `main`

Raw GitHub base URL: https://raw.githubusercontent.com/kathelix/catvox/refs/heads/main/

## Mandatory startup fetch

At the start of a relevant CatVox discussion, fetch the latest version of this file first: `docs/ChatGPT_Project_Source_of_Truth.md`

Raw URL: https://raw.githubusercontent.com/kathelix/catvox/refs/heads/main/docs/ChatGPT_Project_Source_of_Truth.md

Then fetch all relevant current files from: `docs/`

At minimum, fetch:
- docs/HLD.md
- docs/TRD.md
- docs/PROMPT.md
- docs/USER_TEST_PLAN.md
- docs/adr/README.md

Also fetch all relevant ADR files under `docs/adr/``

## Other sources of information

Treat the following as additional sources of information, less authoritative:

- uploaded Project Sources
- previous chat context
- memory

Do not treat these as authoritative if they conflict with the current GitHub repo contents.
If GitHub content and any older uploaded file differ, prefer the GitHub version.

## Source precedence

Use this order of authority:

1. Latest GitHub files from kathelix/catvox on main
2. ADRs for accepted decision history
3. docs/TRD.md for detailed technical design
4. docs/HLD.md for high-level architecture and product direction
5. Uploaded Project Sources only as bootstrap hints, never as final truth

If there is a real contradiction between current repo documents, explicitly point it out instead of guessing.


## If GitHub fetch fails

If GitHub access fails, stop and explicitly say:

- which file could not be fetched
- what error occurred, if known
- whether you are falling back to stale context

Do not silently continue as if the latest files were loaded.

## Scope

By default, only inspect files under: `docs/` from GitHub repo.
Do not inspect implementation source files unless the user explicitly asks or the design question cannot be answered from `docs/`.

## ADR workflow

For significant architectural, security, infrastructure, data-flow, analytics, or hard-to-reverse product decisions:

- check whether an ADR exists
- if missing, recommend a new ADR
- keep HLD/TRD aligned with accepted ADRs

## Working principle

GitHub `docs/` is the architectural source of truth.

Notion, Airtable, PostHog, user-test notes, and chat discussions may contain discovery work, hypotheses, or evidence, but accepted design decisions must eventually be reflected in GitHub docs.
