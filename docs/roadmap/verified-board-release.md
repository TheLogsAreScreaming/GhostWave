# Tested firmware release and supported-board documentation

Status: planning draft. Implementation and verification are pending.

## Scope

Publish only board builds that meet the recorded acceptance criteria. Update supported-board documentation and release notes with exact verification scope, unresolved limits and installation links.

## Dependencies

Hardware qualification results; release automation and flasher synchronization

## Acceptance criteria

- [ ] All required CI checks pass on the release source; assets and checksums match; hardware claims link to evidence. Untested boards retain an experimental label.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
