# Range test

Numbered pings between two GhostWave boards, so you can see how far a link reaches. Untested in the field.

## Set up

1. Both boards: `tx on`, antenna attached. Raise power for real range, for example `power 20`.
2. Let them hear each other: `status` should show `nb 1` on each.
3. On the board that stays put, type `rangetest <other-node-id>`. It pings every 30 s. Add seconds to change that
   (`rangetest 9f219dbb 20`, 15 s at least). It stops itself after 240 pings. `rangetest stop` ends it sooner.

The sender keeps pinging with no computer attached, as long as it has power.

## Reading it

- **Sender:** each ping that arrives comes back as a receipt, and the console prints `RANGE ping 5 delivered, 4 of 5
  so far, last signal heard -98 dBm`. A screen shows delivered/sent and the signal.
- **Receiver:** the console prints `RANGE ping 5 received, signal -98 dBm`. A screen shows the count and signal. A
  T1000-E beeps on every ping, so you can walk until the beeps stop.
- Signal is from the last frame the node heard. On the sender that is normally the receipt.

A phone paired with the receiver will show the pings as messages (`RT 5`).
