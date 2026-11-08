# CatVox public pages

This folder is the source for CatVox's public web pages:

- [privacy.md](privacy.md): the privacy policy (App Store audit item B1);
- [support.md](support.md): the support page (audit item B2);
- [index.md](index.md): a short landing page linking to both, plus `_config.yml` for the Jekyll build.

App Store Connect needs both URLs before CatVox can be submitted. The policy must also be linked from inside the app, from the About screen (plan item P25). See [APP_STORE_COMPLIANCE_GAP_AUDIT.md](../APP_STORE_COMPLIANCE_GAP_AUDIT.md).

**Status: draft, not published.** Ivan reviews the wording, with legal input if needed, before anything goes live. This README is internal and is not published with the pages.

Each open item in the drafts is marked `[PLACEHOLDER Qn: …]` or `[PLACEHOLDER Nn: …]`. `Qn` points to a decision, and `Nn` to a follow-up fix, both listed in the pull request that added this folder.

## Before publishing

- [ ] Every placeholder is resolved (`git grep -n PLACEHOLDER -- docs/public-site` returns nothing) and the draft notices are removed.
- [ ] The one-time hosting setup below is done, and the final URLs are entered in App Store Connect and in the app's About screen (P25).
- [ ] `catvox@kathelix.com`, the contact address on both pages, exists in Kathelix's Google Workspace (as a mailbox, alias or group) and is read regularly.
- [ ] Everything the policy promises exists in the build that ships:
  - the analytics opt-out and the pre-upload consent screen (P26);
  - the install ID, shown and copyable in the About screen (P25);
  - automatic deletion of inactive usage records (audit H6).
- [ ] The vendor settings the policy relies on are live in the protected environment: soft delete off for clip storage and Gemini caching off (Q4).
- [ ] PostHog's IP-based location (GeoIP) stays on, as decided for Q5, so the App Privacy answers and `CatVox/PrivacyInfo.xcprivacy` declare Coarse Location for analytics (see `docs/app-store-privacy.md`). If "Discard client IP data" is also switched on, the policy can add that PostHog then discards the IP address itself.
- [ ] Gemini still runs in a US location after the model upgrade (Q13, plan item P11).
- [ ] The App Store age rating matches the policy's minimum age (Q9).
- [ ] Service-provider terms are in place and recorded (audit H5). Google's Cloud Data Processing Addendum applies automatically; PostHog's DPA does not, so it has to be generated and countersigned in the PostHog app.
- [ ] The facts are re-checked against the code, Terraform and vendor settings that ship, using the table below.
- [ ] The App Store Connect App Privacy answers match this policy and the archive's privacy report.

## Keeping the pages true

Each fact in the policy comes from a file or setting below. Changing one means checking the policy too. A significant change, such as new data or a new provider, may also need a new consent prompt (audit M4).

| Policy statement | Source of truth |
|---|---|
| What is uploaded, the 10-second and 100 MB limits | `CatVox/Services/GCPService.swift`, `CatVox/Services/ImportedVideoService.swift`, `CatVox/Services/CameraService.swift` |
| Clips deleted once a day old, and how long deleted clips stay recoverable | `terraform/core/main.tf` (`raw_videos` lifecycle rule; soft-delete policy) |
| Gemini caching | The Vertex AI cache setting of the protected project (an API setting, not in Terraform today) |
| Processing in the United States | `config/environments/*.xcconfig` (`CATVOX_FUNCTION_REGION`, `CATVOX_FIRESTORE_LOCATION`) and `functions/src/config.ts` (`vertexLocation`, overridable with `CATVOX_VERTEX_LOCATION`) |
| Usage record contents, five scans a day, failed scans not counted | `functions/src/usageGuard.ts`, `functions/src/analyse.ts` |
| Server log contents | `functions/src/analyse.ts`, `functions/src/appCheck.ts`, `functions/src/usageGuard.ts` (logger calls) |
| Install ID | `CatVox/Services/UserIdentityStore.swift` |
| Analytics events, their properties and the SDK switches | `CatVox/Services/AnalyticsService.swift` and its call sites, `docs/app-store-privacy.md` |
| PostHog IP and GeoIP handling, event retention | PostHog project and plan settings; `terraform/posthog/main.tf` |
| Scan history and deletion | `CatVox/Services/ScanHistoryStore.swift` |
| App permissions | `project.yml` (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`) |
| "This website" section | `.github/workflows/pages.yml` and ADR-0031 (GitHub Pages hosting) |

## Hosting

**Decided on 2026-11-07:** the pages are hosted on GitHub Pages from this repository, served at `https://catvox.kathelix.com` ([ADR-0031](../adr/0031-host-public-pages-on-github-pages.md)). They stay outside Google Cloud, so they keep working if CatVox's cloud billing lapses. The custom domain keeps the URL stable whatever the host, which matters because the in-app link ships inside the binary.

Once live, the URLs are:

- Privacy policy: `https://catvox.kathelix.com/privacy`
- Support: `https://catvox.kathelix.com/support`

### How publishing works

`.github/workflows/pages.yml` runs on every push to `main` that touches this folder, and on demand from the Actions tab.

1. It first checks `index.md`, `privacy.md` and `support.md` for `PLACEHOLDER` markers and "Draft for review" notices. While any remain, it stops there, so merging drafts never publishes them.
2. Once they're gone, it copies those three pages and `_config.yml`, and only those, builds them with Jekyll and deploys them.

The merge that removes the last placeholder is therefore the sign-off that puts the pages live.

### One-time setup (Ivan: repository and DNS settings)

1. **Verify the domain.** Verify `kathelix.com` for GitHub Pages in the `kathelix` organisation's settings, by adding the TXT record GitHub asks for at name.com. Do this first: it stops anyone else claiming the subdomain.
2. **Add the DNS record.** At name.com, add a CNAME record for `catvox` pointing to `kathelix.github.io`.
3. **Set up Pages in this repository.** In Settings → Pages:
   - set the source to **GitHub Actions**;
   - set the custom domain to `catvox.kathelix.com`;
   - tick **Enforce HTTPS** once GitHub has issued the certificate.
4. **Publish.** Merge the change that resolves the last placeholder. The workflow then publishes, and you can re-run it by hand from the Actions tab.
