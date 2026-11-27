# ADR-0031: Host CatVox's Public Pages on GitHub Pages

- Status: Accepted
- Date: 2026-11-07
- Owners: Kathelix / CatVox
- Related: `docs/APP_STORE_COMPLIANCE_GAP_AUDIT.md` (items B1 and B2), `docs/public-site/`

## Context

App Store Connect needs a Privacy Policy URL and a Support URL before CatVox can be submitted, and Apple requires the policy to be linked from inside the app (audit items B1 and B2).

Three constraints shape where those pages live:

- They must stay up even if CatVox's Google Cloud billing lapses, as it did in June 2026, so they can't be served from Google Cloud.
- The in-app link ships inside the binary, so the URL must not need to change.
- The policy describes what the code and infrastructure do, so it has to change whenever they change.

Two hosts were considered:

- **GitHub Pages from this public repository.**
- **The Kathelix website.** kathelix.com is a Hugo 0.79.1 site from 2020, served by Netlify from source outside the `kathelix` GitHub organisation, with no app pages yet.

## Decision

Host the pages on GitHub Pages from this repository, served at `https://catvox.kathelix.com`.

- `docs/public-site/` holds the source. `.github/workflows/pages.yml` builds it with Jekyll and deploys it.
- The workflow publishes an allowlist: `index.md`, `privacy.md` and `support.md`, with `_config.yml`. The folder's internal `README.md` is never published.
- A check job skips publishing while any published page still contains a `PLACEHOLDER` marker or its "Draft for review" notice. Merging drafts therefore can't put them live. The merge that removes the last placeholder is the sign-off that publishes them.

## Consequences

- The policy lives next to the code it describes. A change to data handling and the matching policy change can be reviewed in one PR, markdownlint checks the text, and the git history is the public record of earlier versions.
- The pages don't depend on Google Cloud billing or on the Kathelix website.
- On the GitHub Free plan, Pages works only for public repositories, so making this repository private would take the pages down.
- GitHub logs visitors' IP addresses for security purposes, and the policy says so.
- Ivan does a one-time setup: verify the domain for the organisation, add the DNS record, and set the Pages source, custom domain and HTTPS. The steps are in `docs/public-site/README.md`.
