# ADR-0011: Use PostHog for Product Analytics

- Status: Accepted
- Date: 2026-04-29
- Owners: Kathelix / CatVox
- Related docs: `docs/TRD.md`

## Context

CatVox needs lightweight product analytics before wider MVP testing so the team
can understand where users drop out of the scan funnel, which input source they
choose, how often quota pressure appears, and whether share/export and upgrade
intent paths are being used.

The app does not have authenticated accounts in the MVP. It already has a
stable anonymous per-install UUID used for quota enforcement, documented in
ADR-0007.

## Decision

CatVox will use the PostHog iOS SDK for MVP product analytics.

The iOS app will:

1. add PostHog through `project.yml`, because XcodeGen owns the Xcode project
2. configure PostHog from app-owned build settings copied into `Info.plist`,
   with environment-variable overrides available for local development
3. disable analytics without crashing if the required project token is missing
4. identify the PostHog user with the same anonymous per-install UUID used for
   quota enforcement
5. capture product events for scan source selection, Photos import validation,
   recording, analysis, quota pressure, history deletion, share/export actions,
   and upgrade intent

CatVox will not send raw video, AI-generated cat thoughts, owner-entered
content, file paths, or Photos asset identifiers as analytics properties.

## Consequences

### Positive

- Scan-funnel drop-off can be measured across recorded and Photos-import paths
- Backend quota identity and product analytics identity are aligned
- Analytics dependency/configuration survives XcodeGen regeneration and CI
- Missing analytics configuration does not prevent the app from launching
- Share events distinguish sheet opened, completed share, and cancellation

### Negative / Trade-offs

- The app now includes a third-party analytics SDK
- The PostHog project token is embedded in the app bundle, which is normal for
  client analytics tokens but not suitable for secret values
- Event taxonomy needs to be maintained as product flows evolve

## Implementation Notes

- SDK package: `https://github.com/PostHog/posthog-ios` from version `3.57.2`
- Central wrapper: `CatVox/Services/AnalyticsService.swift`
- Anonymous identity owner: `CatVox/Services/UserIdentityStore.swift`
- XcodeGen source of truth: `project.yml`
- Event setup follows the PostHog iOS SDK guidance for `PostHogConfig`,
  lifecycle capture, event capture, and user identification.
