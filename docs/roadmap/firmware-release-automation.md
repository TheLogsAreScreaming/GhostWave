# Firmware release automation

Status: built: `scripts/release.py` (see docs/RELEASING.md). Dry run by default; `--publish` releases firmware and app.

## Scope

Publish explicitly selected and approved versioned board packages to GhostWave-Releases with source SHA, checksums, signing/provenance information where applicable, and accurate prerelease notes. Preserve existing credentials without exposing them.

## Dependencies

Passing build and packaging checks; compatible bundles

## Acceptance criteria

- [ ] Verify exact artifacts before publication; fail on missing or conflicting tags, incomplete assets or mismatched source. Do not publish automatically from unreviewed PR code.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
