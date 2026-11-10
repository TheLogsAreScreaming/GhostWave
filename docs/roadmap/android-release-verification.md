# Android release verification

Status: implementation proposal; not implemented or verified by this document.

## Requirements

- Record exact source commit, app version, firmware versions, board revisions, and phone model/Android version.
- Run two-radio messaging and SOS send/receive/acknowledgment/cancellation checks, including disconnect and reboot recovery.
- Verify screen-off notifications and a 30-minute background connection on Samsung; record failures and battery settings.
- Update status documentation using measured results, then prepare a signed Android prerelease with checksum and known limits.

## Acceptance checks

- [ ] All required CI checks pass on the exact release source.
- [ ] Verify APK signer, installation over the previous development build, and retained data.
- [ ] Require actual operator hardware results before calling the release tested; do not fabricate evidence or publish an unverified artifact.
