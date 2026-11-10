# Complete ESP32 flash bundles

Status: planning draft. Implementation and verification are pending.

## Scope

Resolve board-specific upload offsets and all required images from the pinned PlatformIO framework. Produce complete bundles for the six selected ESP32 targets, with checksums and source manifests.

## Dependencies

Compatibility records and package tests

## Acceptance criteria

- [ ] Verify flash layouts against build output, including auxiliary images. Test overlap, missing images, invalid offsets and flash-size bounds; bench verification remains separate.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
