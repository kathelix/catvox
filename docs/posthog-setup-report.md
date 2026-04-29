<wizard-report>
# PostHog post-wizard report

The wizard has completed a deep integration of PostHog analytics into CatVox (iOS SwiftUI). The PostHog iOS SDK was added as a Swift Package Manager dependency in `CatVox.xcodeproj/project.pbxproj`, a `PostHogEnv` enum was created for safe environment-variable-based configuration, and PostHog is initialised with lifecycle event capture at app startup in `CatVoxApp.swift`. Ten business events covering the full scan lifecycle — from source selection through recording, analysis, sharing, and monetisation intent — were instrumented across five Swift source files. A `PBXFrameworksBuildPhase` was added to the CatVox target so the framework links correctly.

| Event | Description | File |
|-------|-------------|------|
| `scan_source_chosen` | User taps "Read My Cat" and selects a video source (record or photos). Top of conversion funnel. Properties: `source` | `Views/Home/HomeView.swift` |
| `recording_started` | User taps the record button in the camera viewfinder. | `Views/Recording/RecordingView.swift` |
| `recording_completed` | User accepts a recorded clip with "Use This Clip". | `Views/Recording/RecordingView.swift` |
| `analysis_completed` | GCP pipeline returns a successful result. Properties: `persona_type`, `primary_emotion`, `confidence_score`, `source_type` | `Views/Result/ResultView.swift` |
| `analysis_failed` | Upload or analysis pipeline failed. Properties: `error_message` | `Views/Result/ResultView.swift` |
| `quota_exceeded` | Server returned HTTP 429 — daily free scan limit reached. | `Views/Result/ResultView.swift` |
| `scan_shared` | User opens the iOS share sheet for a scan video. | `Views/Result/ResultView.swift` |
| `scan_saved_to_photos` | User saves a scan video to Photos successfully. | `Views/Result/ResultView.swift` |
| `scan_deleted` | User confirms deletion of a scan from history. Properties: `persona_type` | `Views/Home/HomeView.swift` |
| `upgrade_to_pro_tapped` | User taps "Upgrade to Pro" on the quota-exceeded card. Key monetisation intent signal. | `Views/Result/QuotaExceededView.swift` |

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behaviour, based on the events we just instrumented:

- **Dashboard — Analytics basics**: https://us.posthog.com/project/402530/dashboard/1524032
- **Scan conversion funnel** (scan_source_chosen → recording_completed → analysis_completed): https://us.posthog.com/project/402530/insights/HpsroXVQ
- **Daily scan volume** (analyses completed per day): https://us.posthog.com/project/402530/insights/3ZD4bnzS
- **Top cat personas** (analysis_completed broken down by persona_type): https://us.posthog.com/project/402530/insights/kB5Hjls2
- **Quota pressure & upgrade intent** (quota_exceeded vs. upgrade_to_pro_tapped): https://us.posthog.com/project/402530/insights/brptiNF5
- **Scan share actions** (scan_shared vs. scan_saved_to_photos): https://us.posthog.com/project/402530/insights/5dK5T6k9

### Before your first build

In Xcode, open **Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables** and confirm `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST` are present (the wizard already set these in the shared scheme file). Xcode will need to resolve the `posthog-ios` package from SPM on first open — this happens automatically.

### Agent skill

We've left an agent skill folder in your project at `.claude/skills/integration-swift/`. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
