# ADR-001: Use Firebase App Check with App Attest for Production iOS Attestation

- Status: Accepted
- Date: 2026-04-19
- Owners: Kathelix / CatVox
- Related docs: `HLD.md`, `TRD.md`

## Context

CatVox uses Firebase Cloud Functions as a backend proxy for Vertex AI and signed Google Cloud Storage upload URLs. The system also enforces daily usage limits and is explicitly designed to prevent unauthorized backend access and uncontrolled cloud spend.

The current backlog item in `TRD.md` is:

- `App Check Setup: Configure App Check in Apple and Firebase consoles.`

A decision is required for the Apple production attestation provider used by Firebase App Check:

- DeviceCheck
- App Attest

The project does not need to support older iOS devices.

## Decision

CatVox will use:

- **Firebase App Check with App Attest** for production Apple builds
- **Firebase App Check Debug Provider** for local development and simulator-based workflows
- **No DeviceCheck implementation** in the MVP

DeviceCheck is intentionally excluded from the primary architecture. It may only be reconsidered later if a concrete operational issue appears in production that cannot be solved within the App Attest approach.

## Rationale

### 1. Better fit for CatVox security goals

CatVox protects cost-sensitive backend resources:

- Firebase Cloud Functions endpoints
- signed upload URL issuance
- Vertex AI inference calls
- usage-limit enforcement paths

For this project, App Check is not a cosmetic safeguard. It is part of the abuse-prevention boundary. App Attest is the stronger and more modern Apple attestation path for this purpose.

### 2. Compatibility is not a project constraint

A common reason to prefer DeviceCheck is broader compatibility. That does not apply here because the project explicitly does not need to support older iOS devices.

Therefore, choosing DeviceCheck would mostly add architectural noise and a weaker parallel path without a clear business benefit.

### 3. Clean development split

Using App Attest in production and Debug Provider in development gives a simple and understandable operating model:

- real attestation for production traffic
- friction-free local development and simulator testing

This also matches the project’s existing high-level design direction that App Check is mandatory and the Debug Provider is acceptable for local development.

## Consequences

### Positive

- Stronger protection against unauthorized use of CatVox backend resources
- Better alignment with the project’s security and cost-control goals
- Simpler architecture than supporting both App Attest and DeviceCheck from the start
- Clear separation between production and development behavior

### Negative / Trade-offs

- App Attest rollout must be handled carefully for larger user bases because Apple/Firebase guidance recommends gradual onboarding to avoid quota-related issues
- App Attest adds attestation complexity compared with Debug Provider workflows
- Operational debugging in production may require more care than a weaker compatibility-first setup

## Implementation Notes

### Apple Developer side

- Enable the **App Attest** capability for the CatVox app
- Ensure the correct entitlements configuration is present for production use

### Firebase side

- Register the iOS app in **Firebase App Check** using the **App Attest** provider
- Configure **Debug Provider** for local development
- Enable App Check enforcement for the relevant protected products only after validation

### Recommended rollout approach

1. Integrate App Check with App Attest in the app
2. Verify token flow in development using Debug Provider where appropriate
3. Register the production app in Firebase App Check
4. Observe metrics before full enforcement
5. Enable enforcement for protected backend entry points

## Rejected Options

### Option A: Use DeviceCheck for production

Rejected because:

- weaker fit for the project’s abuse-prevention posture
- mainly useful when compatibility is a stronger requirement
- adds a legacy-style path that does not solve a current CatVox problem

### Option B: Support both App Attest and DeviceCheck from day one

Rejected because:

- extra implementation and operational complexity
- no current product requirement justifies dual-provider support
- increases documentation and testing scope for minimal MVP value

## Required Document Updates

### HLD

Replace the generic security wording with:

- `Firebase App Check uses App Attest for production iOS app verification and Debug Provider for local development.`

### TRD

Update the security section to:

- `App Verification: Firebase App Check mandatory for all backend entry points. App Attest is the production provider for Apple platforms; Debug Provider is used for local development.`

Update the backlog item to:

- `App Check Setup: Configure App Attest in Apple Developer and Firebase App Check, plus Debug Provider for local development.`

## Review Trigger

Revisit this ADR if any of the following becomes true:

- CatVox later needs to support older Apple devices that cannot use the chosen approach
- production metrics show unacceptable App Attest operational issues
- Firebase or Apple materially changes provider guidance
- the app introduces new distribution or CI/testing patterns that require a different attestation strategy
