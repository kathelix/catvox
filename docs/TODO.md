# TODO

## Deferred Product Work

### USER_TEST_PLAN.md
Free version of consumer Gemini allows to analyse max 5 minutes video of user testing session.
We should allow longer sessions.
We can upgrade to Plus/Pro tiers, or upload videos to YouTube - both options will accept much longer videos.
Alterntively we can build a testing backend, in a similar way that the app way behaves - upload testing video to GCS and analyse via Gemini/Vertex.

### Collect feedback from users using app
Consdier:
- automatic sending of errors
- special dialog "Feeddback", with variants 3-5 variants what to priotise in development
- ...

### Is Priority PayGo justified?
Test switching Gemini 2.5 Flash from Standard PayGo tier to Priority PayGo (twice more expensive, but still in Preview not GA) - measure and compare time spent on analysis. Assess importance of faster response for user.

### Support iPad
* While we are still early in dev cycle, it's easier to add support for iPadOS than later when the app will become more complicated.

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
