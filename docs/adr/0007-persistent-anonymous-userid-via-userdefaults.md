# ADR-007: Persistent Anonymous userId via UserDefaults for Quota Enforcement

- Status: Accepted
- Date: 2026-04-19
- Owners: Kathelix / CatVox
- Related docs: `docs/TRD.md`

## Context

CatVox enforces a daily scan limit of 5 free analyses per user to control Vertex AI costs (TRD §3.2, §6.4). The backend `analyseVideo` Cloud Function checks and increments a counter in Firestore at `usage/{userId}`.

This requires a stable, per-device user identifier to be generated on the client and sent with each request. At the time of MVP implementation:

- Firebase Authentication is not yet integrated
- The app has no sign-in or account creation flow
- The usage guard must still function before Auth is added

A decision is needed for how to produce and persist this identifier.

## Decision

CatVox will use a **locally-generated UUID stored in `UserDefaults`** under the key `"catvox.userId"` as the user identifier for quota enforcement.

The identifier is:

- generated once using `UUID().uuidString` on first launch
- persisted across app sessions in `UserDefaults`
- sent as `userId` in every `analyseVideo` request
- used as the Firestore document key at `usage/{userId}`

## Rationale

### 1. No authentication friction at MVP

Requiring sign-in before a user can analyse their cat would add meaningful friction at the top of the funnel. A locally-generated UUID gives each device a stable identity for quota purposes without any user-facing flow.

### 2. Sufficient for cost control

The goal of the usage guard is to prevent runaway Vertex AI spend, not to enforce watertight per-person limits. A UUID-per-install is adequate for this purpose at MVP scale.

### 3. Forward-compatible with Firebase Auth

The `userId` key is intentionally designed to be replaceable. When Firebase Auth is introduced, the value stored under `"catvox.userId"` can be swapped for the authenticated UID with a one-line change in `GCPService.swift`. The Firestore schema and backend logic require no modification.

### 4. No server round-trip required

The identifier is available immediately at app startup, before any network request, which simplifies the call flow for both `getSignedUploadURL` and `analyseVideo`.

## Consequences

### Positive

- Zero sign-in friction for new users
- Simple implementation with no backend dependency for ID generation
- Straightforward migration path to Firebase Auth UIDs
- No PII stored or transmitted — UUIDs are not linked to any personal identity

### Negative / Trade-offs

- The quota counter resets on app reinstall, since `UserDefaults` is cleared on uninstall
- A user with multiple devices gets a separate quota per device
- A determined user can reset their quota by reinstalling — acceptable at MVP scale
- When Firebase Auth is added, existing usage history under the anonymous UUID will not carry over to the authenticated UID unless an explicit migration is implemented

## Rejected Options

### Option A: Require Firebase Authentication before allowing scans

Rejected because:

- adds sign-in friction before the user has experienced the core product value
- full Auth integration is a post-MVP item
- quota enforcement does not require verified identity at this stage

### Option B: Use device fingerprint or `identifierForVendor`

Rejected because:

- `identifierForVendor` resets on reinstall and is not stable across app reinstalls from a different vendor bundle
- device fingerprinting raises privacy and App Store review concerns
- UUID-in-UserDefaults is simpler and raises no platform policy issues

### Option C: Server-assigned identifier (backend generates and returns a UUID on first call)

Rejected because:

- adds a bootstrapping round-trip before the first scan
- increases backend complexity for no MVP benefit
- client-side generation is equally random and collision-resistant

## Implementation Notes

- Key: `UserDefaults.standard` under `"catvox.userId"`
- Generated in `GCPService.swift` as a computed property; value is written on first read
- Sent in the JSON body of `analyseVideo` as `{ gcsUri, userId }`
- Firestore path: `usage/{userId}` — schema: `{ count: Int, lastResetDate: String (YYYY-MM-DD) }`
- When Firebase Auth is integrated, replace the `userId` computed property value with `Auth.auth().currentUser?.uid`

## Required Document Updates

### TRD

- `§6.4` — document the `userId` strategy and note that it is forward-compatible with Firebase Auth

### HLD

- Note that user identity for quota enforcement is currently an anonymous per-install UUID; Firebase Auth is the planned migration path

## Review Trigger

Revisit this ADR if any of the following becomes true:

- Firebase Auth is integrated and a migration of existing usage records is needed
- per-person (cross-device) quota enforcement becomes a product requirement
- App Store review raises concerns about the identifier approach
