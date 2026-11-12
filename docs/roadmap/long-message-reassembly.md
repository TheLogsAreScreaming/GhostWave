# Long-message reassembly

Status: implemented in the app (message_split.dart, message_groups.dart, chat_screen.dart). Host-tested;
not yet tried between two phones on real radios.

## How it works

- A message over one radio frame is split into at most 8 parts, each labelled `(i/n#tt) `. `tt` is a random
  byte in hex, the same on every part of one message, so parts of two long messages that interleave stay apart.
  The label costs 9 bytes of each part.
- Each part is still its own message underneath: its own delivery receipt, retry and delete. Only the chat
  view joins them into one bubble, placed where the first part arrived.
- The bubble shows the weakest state of its parts (failed, then pending, sent, delivered). Retry resends only
  the parts that failed. Delete removes every part.
- A missing part shows as `[part 2 of 3 not received yet]` and fills in when it arrives.
- Grouping is rebuilt from the saved messages, so it survives an app restart.
- Older apps send untagged `(1/3) ` parts. Those are shown as separate messages, never guessed into groups;
  older apps show the new labels as plain text.

## Rules

- Same direction (sent or received), tag and total, within one hour of the group's first part.
- The same part seen again with the same text is shown once. The same index with different text means the
  tag came round: it starts a new message.
- Labels with a total over 8, a total under 2, an index over the total or a bad tag are not parts.

## Acceptance checks

- [x] Round-trip Unicode within byte limits (message_split_test).
- [x] Shuffled, missing, duplicate, conflicting, expired and interleaved parts (message_groups_test).
- [x] Restart: grouping is computed from stored messages.
- [x] Mixed app versions: untagged parts stay separate.
- [x] Independent retries and receipts: per part, unchanged.
- [ ] Two phones on real radios.
