# App Store Privacy Notes

This file is the working checklist for CatVox App Store privacy submission. It
is not a replacement for legal review, but it records the current engineering
position so App Store Connect answers and the public privacy policy stay aligned
with the app and `CatVox/PrivacyInfo.xcprivacy`.

## Current Data Collection

CatVox collects the following data types for MVP:

| Data type | Purpose | Linked to user | Tracking |
|---|---|---:|---:|
| User ID | App functionality and analytics | Yes | No |
| Product interaction | Analytics | Yes | No |
| Photos or videos | App functionality | Yes | No |
| Audio data | App functionality | Yes | No |

Notes:

- **User ID** is the anonymous CatVox per-install UUID stored in
  `UserDefaults`. It is used for backend quota enforcement and PostHog
  analytics identity. It is not an advertising identifier.
- **Product interaction** is limited to named CatVox product events such as scan
  source choice, validation outcome, analysis outcome, quota pressure, and
  share actions.
- **Photos or videos** and **Audio data** cover user-provided clips recorded in
  app or selected from Photos and uploaded for AI analysis.
- CatVox does not use collected data for third-party advertising or tracking.
- CatVox analytics must not include raw video, AI-generated cat thoughts, local
  file paths, Photos asset identifiers, or owner-entered content.

The PostHog SDK also ships its own privacy manifest. App Store Connect answers
must account for both CatVox-owned collection and third-party SDK collection.

The current built app bundle contains privacy manifests from:

| Bundle | Manifest reports |
|---|---|
| `CatVox.app/PrivacyInfo.xcprivacy` | User ID, product interaction, photos or videos, audio data, UserDefaults, file timestamp API usage |
| `PostHog_PostHog.bundle/PrivacyInfo.xcprivacy` | Product interaction, other usage data, UserDefaults API usage |
| `PLCrashReporter_CrashReporter.bundle/PrivacyInfo.xcprivacy` | Crash data and other diagnostic data |

CatVox disables PostHog crash autocapture in `AnalyticsService`, but the
PostHog Swift package still includes `PLCrashReporter` as a packaged dependency
and Xcode includes that dependency's privacy manifest in the built bundle. Before
submission, generate Xcode's privacy report from the archive and make sure App
Store Connect answers match the final report.

## Required-Reason APIs

CatVox declares these app-owned required-reason API uses:

| API category | Reason | Why CatVox uses it |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Persist the anonymous install ID and local quota counters inside the app. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | Manage app-container media files, cache cleanup, validation, and scan-history assets. |

PostHog declares its own SDK-level required-reason API usage in its bundled
privacy manifest.

## Public Privacy Policy Points

The public privacy policy should state, in plain user-facing language:

- CatVox uploads selected or recorded cat video clips, including any audio in
  those clips, to provide AI analysis.
- Uploaded clips are used for app functionality, not advertising.
- Product analytics are collected through PostHog to understand scan funnel,
  validation, quota, and share/export behavior.
- Analytics use an anonymous per-install identifier and do not include raw
  videos, Photos asset identifiers, local file paths, or generated cat thoughts.
- CatVox does not sell user data and does not use third-party advertising
  tracking.
- PostHog crash autocapture is disabled in app configuration. If crash reporting
  is intentionally enabled later, the privacy policy and App Store Connect
  answers must be updated for crash diagnostics.
- Users can delete locally saved scan history in the app; deleting a CatVox scan
  does not delete the user's original Photos-library asset.
