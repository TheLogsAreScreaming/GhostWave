# Long-message reassembly

Status: implementation proposal; not implemented or verified by this document.

## Requirements

- Define a versioned multipart envelope with a shared message identifier scoped to sender and conversation; keep legacy labelled parts readable without guessing groups.
- Budget envelope overhead within the radio UTF-8 byte limit; reject invalid totals and indices and bound retained groups.
- Combine matching parts into one bubble; display missing parts and preserve per-part delivery, retry, and deletion behavior.
- Persist enough metadata to survive restart without merging unrelated messages.

## Acceptance checks

- [ ] Round-trip Unicode within byte limits.
- [ ] Handle shuffled, missing, duplicate, conflicting, expired, and interleaved parts.
- [ ] Verify restart, mixed app versions, independent retries, and receipts.
