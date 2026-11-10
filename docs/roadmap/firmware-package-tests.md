# Automated firmware packaging tests

Status: planning draft. Implementation and verification are pending.

## Scope

Add isolated tests for both package formats, missing and empty files, checksum accuracy, source metadata, output collisions, and partial-write behavior. Integrate them into CI.

## Dependencies

#191

## Acceptance criteria

- [ ] Tests exercise real packaging functions with temporary fixtures and assert independently computed hashes; malformed or incomplete packages fail.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
