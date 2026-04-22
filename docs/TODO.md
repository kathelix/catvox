# TODO

## Deferred Product Work

### Shareable Rendered Video
* Build a rendered funny result video as a derived artifact from the preserved original clip and AI result.
* Keep the rendering pipeline on iOS rather than on the backend, to reduce cloud usage, bandwidth, and privacy exposure.
* Design the first Instagram-first visual style for the rendered output.
* Allow additional style variants later so previously saved scans can be re-rendered with improved templates.
* Render the shareable video only when the user explicitly taps Share or Save.
* Avoid long-term permanent storage of rendered share videos by default; prefer temporary caching with cleanup.

### Overlay Layer Contents
* The cat thought as the primary overlay.
* Persona label.
* Primary emotion label.
* Subtle CatVox / Kathelix branding or watermark.

### Future Storage / Lifecycle Questions
* Decide whether the app should later offer a Settings option for imported-video retention behavior.
* Define the retention and cleanup policy for temporary rendered share videos.
