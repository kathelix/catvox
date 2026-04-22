# ADR-0009: Render Share Videos On Device

**Status:** Accepted  
**Date:** 2026-04-22

## Context

CatVox now preserves successful scans locally as reusable memory artifacts: the original clip plus the structured AI interpretation.

The product needs a shareable video feature that turns that saved scan into a funny export with CatVox overlays. The team must decide:

- whether share rendering happens on iOS or on backend infrastructure
- whether the original saved clip is mutated or a separate derived file is created
- when rendered outputs are generated and how long they are retained

This decision affects privacy, cloud cost, storage lifecycle, product responsiveness, and whether previously saved scans can be re-used without another upload.

Key decision drivers:

- cost efficiency and avoiding extra cloud-rendering infrastructure
- privacy and keeping the rendered artifact on-device unless the user shares it
- responsiveness of the export flow from an already-saved scan
- engineering tradeoffs between native iOS media composition and server-side rendering infrastructure

Options considered:

- server-side rendering using backend-managed video processing infrastructure
- client-side rendering using native iOS frameworks such as AVFoundation and Core Animation

## Decision

CatVox will render shareable result videos on device using native iOS media frameworks.

The rendered share output is a separate derived video artifact. The original preserved clip remains canonical and untouched.

For MVP:

- rendering is triggered only when the user explicitly chooses Save to Photos or Share
- rendering uses AVFoundation-based composition/export with overlay graphics generated locally
- the first export style preserves the original aspect ratio rather than reframing into a fixed social format
- exports include the cat thought as the primary overlay, plus persona, primary emotion, and subtle CatVox / Kathelix branding
- rendered outputs are stored only as temporary CatVox-owned cache files and are eligible for cleanup
- there is no separate preview step before save/share

## Consequences

### Positive

- no additional backend or cloud-rendering infrastructure is required
- no extra upload of the user’s clip is required for sharing
- saved scans can be re-rendered locally later using the preserved original clip and stored result
- privacy exposure is reduced because the share pipeline stays on the device
- export behavior remains available even when reopening history items

### Negative

- export time and success depend on device-side media capabilities and local storage availability
- the MVP share style remains intentionally simple because social-format reframing and template variants are deferred
- temporary output cleanup must be handled locally by the app
- implementation complexity shifts into the iOS client because video composition and overlay rendering must be managed in Swift

### Follow-up implications

- when Pro is implemented, watermark-removal logic can be attached to the derived export path without changing the original scan model
- if a future product need requires backend rendering, a later ADR should supersede this one rather than rewriting it
