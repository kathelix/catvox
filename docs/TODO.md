# TODO

## Deferred Product Work

### Support iPad
* While we are still early in dev cycle, it's easier to add support for iPadOS than later when the app will become more complicated.

### Retrospectively cover source code with unit tests

### Collect in-app feedback from users
Consdier:
* automatic sending of errors
* special dialog "Feeddback", with variants 3-5 variants what to priotise in development
* anything else?

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
