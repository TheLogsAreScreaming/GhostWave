# Persistent field reports

Status: implementation proposal; not implemented or verified by this document.

## Requirements

- Persist named test sessions with notes, board and firmware information, timestamps, and bounded samples.
- Capture only measurements actually exposed by the radio; distinguish Bluetooth from LoRa signal history.
- Export a versioned JSON file through the platform save/share flow with an explicit preview of identifiers and location fields.
- Retain sessions across screen closure and app restart; offer deliberate deletion and clear storage errors.

## Acceptance checks

- [ ] Round-trip reports through persistence and export.
- [ ] Test restart, interrupted writes, corrupt files, limits, and counter resets.
- [ ] Verify export and cancellation on Android; no unsolicited transmissions.
