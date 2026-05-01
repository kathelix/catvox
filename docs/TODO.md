# TODO

## Infrastructure / Runtime Maintenance

### Dev / Production Environment Split Before Launch
Before public launch, split the current live GCP/Firebase environment from the real production environment. Until that split, treat `kathelix-catvox-prod` operationally as the Dev environment despite the current project name. See ADR-0013.

Subtasks:
* Decide final environment naming and whether `kathelix-catvox-prod` is kept, renamed by convention only, or replaced during launch cutover.
* Create separate GCP/Firebase projects for Dev and Prod, with separate Firebase apps, App Check configuration, Firestore databases, GCS buckets, Secret Manager secrets, Artifact Registry repos, and Cloud Functions deployments.
* Split Terraform state and variables per environment so Dev and Prod can be planned/applied independently.
* Split GitHub Actions environments and secrets; keep PR and merge-to-main deploys pointed at Dev, and require an explicit protected release path for Prod.
* Split iOS configuration per environment, including Firebase plist handling, bundle IDs or schemes if needed, App Check providers/debug tokens, and backend endpoint selection.
* Split analytics configuration so Dev/test traffic cannot pollute production PostHog dashboards.
* Restrict live integration tests that mutate Firestore to Dev by default; require explicit approval and a separate runbook for any production smoke checks.
* Define launch cutover and rollback steps, including how to handle any pre-launch Firestore usage data, GCS objects, and deployed function revisions.

### Firebase Functions Node.js Runtime Review
Review this around **2026-06-01** before changing the Cloud Functions runtime.

Current position as of 2026-05-01:
* Keep CatVox Functions on Node.js 22 for now. The main Firebase Functions "Manage functions" page was last updated on 2026-04-30 and still lists Node.js 22, Node.js 20, and Node.js 18 (deprecated) as the supported Firebase SDK for Cloud Functions runtime choices.
* Google Cloud runtime support already lists Cloud Run functions support for `nodejs24`, with Node.js 24 deprecating on 2028-04-30 and decommissioning on 2028-10-31.
* Node.js 22 remains safe for now. Google Cloud runtime support lists Node.js 22 deprecation on 2027-04-30 and decommissioning on 2027-10-31.
* Local developer Node versions, such as Node.js 25.8.1, should not drive the deployed Functions runtime. Firebase-supported runtime guidance should remain the source of truth.

When revisiting:
* Re-check the Firebase Functions "Manage functions" page, Firebase CLI release notes, and Google Cloud Functions runtime support.
* If Node.js 24 is clearly supported and recommended for Cloud Functions for Firebase, update `functions/package.json`, `functions/package-lock.json`, `.github/workflows/functions.yml`, `docs/TRD.md`, and `AGENTS.md`.
* Consider adding `.nvmrc` or `.node-version` with the selected runtime so local validation does not drift to unsupported versions.
* Validate with `npm --prefix functions test` under the selected runtime and `firebase deploy --only functions --dry-run`.

## Deferred Product Work

### Native iPad Support
Treat native iPad support as a dedicated post-MVP feature. The iPhone MVP is effectively portrait-first; matching that on iPad is not just a matter of adding the iPad target family.

Why the spike proved difficult:
* iPad support crosses product, layout, and AVFoundation boundaries at the same time.
* App/interface orientation, physical device orientation, SwiftUI layout geometry, AVFoundation preview orientation, and recorded movie-output orientation are related but separate pieces of state.
* The iPhone path hides many of these problems because the app behaves as a portrait-first phone app. iPad can expose them through landscape launch, physical rotation, portrait-upside-down handling, and larger/resizable scene geometry.
* The system Camera app does not simply rotate the whole preview. It keeps the camera surface visually stable and adapts controls. Reaching that level of polish requires a purpose-built camera layout, not a quick view modifier.
* Supporting iPad also affects modal positioning, Photos picker presentation, save/share flows, result layouts, and imported-video aspect-ratio handling.

Post-MVP design choices to make before implementation:
* Decide whether native iPad support should be portrait-only for parity with iPhone, or a full all-orientation iPad experience.
* If portrait-only, confirm the App Store and iPadOS tradeoffs around full-screen/rotation behavior, then explicitly verify camera preview and recorded output orientation on real iPad hardware.
* If all-orientation, design a dedicated iPad camera container with a stable preview surface, smoothly adapting controls, and explicit AVFoundation orientation handling.
* Define whether Stage Manager, Split View, and Slide Over are supported initially or intentionally out of scope.

Regression matrix for the eventual feature:
* iPad portrait, portrait upside down, landscape left, and landscape right.
* Device rotation before opening Recording, while Recording is open, during recording, and after the review step.
* Recorded output orientation compared with on-screen preview orientation.
* Imported portrait and landscape videos from Photos.
* Home-source modal positioning after rotation.
* Upload/progress, Result, history reopen, save-to-Photos, and share-sheet flows.

### Is Priority PayGo justified?
Test switching Gemini 2.5 Flash from Standard PayGo tier to Priority PayGo (twice more expensive, but still in Preview not GA) - measure and compare time spent on analysis. Assess importance of faster response for user.

### Shareable Rendered Video Follow-up
* Add additional share-video style variants so previously saved scans can be re-rendered with upgraded templates.
* Explore fixed social-format exports only after validating whether preserving the original aspect ratio is limiting real usage.
* Consider whether a preview/edit step is worth adding once the base share flow is stable.

### Temporal Highlight Metadata
* Extend the AI/backend response to optionally return temporal highlight metadata for emotionally meaningful moments inside the clip.
* Define a `temporal_highlights` schema with at least `timestamp`, short overlay text, and emotion beat fields.
* Ensure backend parsing and iOS decoding tolerate missing or empty `temporal_highlights` arrays.
* Use temporal highlight metadata later for timed on-device overlays in share exports.

### Future Storage / Lifecycle Questions
* Decide whether the app should later offer a Settings option for imported-video retention behavior.
