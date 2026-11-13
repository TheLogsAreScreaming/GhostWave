# Coverage Explorer — implementation contract

Status: **built in the app** (Status → Field tests → Coverage walk). Host-tested
with a fake GPS and a fake node; **not yet walked with real radios**. No
firmware change: pings are encrypted DMs (`[Coverage] N`) and results come from
their delivery receipts.

What it does today: one destination per walk, a ping every 30 s, 1 min or 2 min
from the phone's own fix (a fix older than 30 s is not used, and that ping is
counted as skipped), pending until a receipt or 3 minutes (then failed; a late
receipt still turns it delivered), signal only from a real receipt, dots on the
Map with a legend, CSV export, delete. Walks are kept in a private file on the
phone; a walk left running when the app closed is ended on the next start. The
receiving app keeps pings in the chat but does not notify or count them unread.

## Proposed test flow

1. User selects a **specific destination node** and starts a session with
   explicit foreground location permission.
2. Collect GPS fix and accuracy. Reject stale or inaccurate fixes; do not infer
   a position from a neighbor beacon.
3. Send uniquely tagged, rate-limited test messages, honoring existing airtime
   budgets. Correlate the app's client message ID with SendQueued and Delivered.
4. Mark pending while a receipt may still arrive; classify failure only after
   a configurable timeout, and preserve late-receipt reconciliation.
5. Record measured last-hop RSSI separately from any future destination-side
   measurement. Current Delivered.rssi_dbm is **receipt last-hop RSSI**, not
   destination reception RSSI. A real destination RSSI needs a new authenticated
   telemetry exchange in the firmware and client protocol.
6. Plot dots on the existing Flutter map, with a legend distinguishing failed,
   pending, delivered without measurement, and strong/fair/weak RSSI.
7. Store sessions privately per local node, provide deletion and CSV/GPX export.
   Location logs are sensitive; do not auto-upload or broadcast them.

## Acceptance tests to add

- Virtual mesh: acked ping, timed-out ping, delayed receipt, duplicate receipt,
  disconnect and reconnect, multiple destinations, and no-fix behavior.
- Confirm RSSI semantics with both direct and multi-hop paths.
- Simulated half-mile walking trace, including bad GPS fixes and offline tiles.
- App unit/widget tests, generated protobuf consistency, Android/iOS CI.
- Real hardware validation on RAK4631 and T1000-E is **pending**.

## Compatibility

Existing GhostWave proto 1.7 has optional RSSI on Delivered and Neighbor.
Do not treat that as an end-to-end measurement. Prefer an additive protocol
extension with capability negotiation rather than changing existing fields.
