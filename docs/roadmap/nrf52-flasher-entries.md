# Additional nRF52840 flasher entries

Status: planning draft. Implementation and verification are pending.

## Scope

Prepare T114, Wio Tracker L1 and T-Echo entries using verified bootloader SoftDevice IDs, application addresses and board-revision records. Keep incompatible or unverified combinations unavailable.

## Dependencies

Compatibility records and successful board builds

## Acceptance criteria

- [ ] Validate each UF2 against the exact board layout; test manifest generation and incompatible images. Record device flashing results before marking hardware verified.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
