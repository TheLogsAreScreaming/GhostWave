# Flasher release synchronization

Status: built: `scripts/release.py --site` rebuilds the flasher and opens the site pull request (docs/RELEASING.md). Deploying stays manual.

## Scope

Refresh downloadable versions after approved firmware publication. Validate the complete generated site before deployment and preserve a recoverable previous deployment.

## Dependencies

Release automation; board manifests and compatible installers

## Acceptance criteria

- [ ] Test missing assets, checksum mismatch, malformed releases and partial downloads. Failed synchronization must not replace the working site.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
