# ESP32 browser installer

Status: planning draft. Implementation and verification are pending.

## Scope

Add an ESP32-specific Web Serial installer alongside nRF DFU. Route only validated ESP32 manifests to it; show exact target, image layout, progress, failures and recovery steps.

## Dependencies

Complete ESP32 flash bundles

## Acceptance criteria

- [ ] Test transport selection, cancellation, interrupted writes and incompatible manifests. Verify actual flashing on a supported ESP32 board before enabling it as tested.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
