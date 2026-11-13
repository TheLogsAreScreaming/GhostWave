# Traceroute / repeater ping — implementation work in progress

**Built: one-hop link ping** (both directions), end to end, from the codec
below. **Not built: multi-hop traceroute** (see the end).

Link ping: the app (or the `ping <hex-id>` console command) asks a node heard
directly. Its radio answers with the signal it heard the ping at, and ours
measures the answer, so both directions of that link are real readings.
Packet type `Diag` (0x09), never forwarded (hopsLeft 0), unicast to the
neighbor; older nodes drop the unknown type. Limits: one ping out at a time,
5 s apart, an answer within 10 s or it reports *no answer*; a node answers at
most once a second. Client protocol 1.9: `LinkPing` (28) and
`LinkPingResult` (30). The app offers *Ping* in a chat's menu (when the node
is heard directly) and on a heard node's sheet. Host-tested in the router
simulation, the codec, the handler and the app; not yet run on two radios.

## Proposed behavior

* Use an opt-in, low-priority probe with random correlation token, origin,
  destination and bounded hop limit (1–15).
* Each participating receiver reports the RSSI and SNR of the **packet it
  received**. Never infer the other end's signal from a local reading.
* Send separate return-path probes and label reverse observations explicitly;
  routes can be asymmetric and cannot be assumed identical.
* Report timeouts and missing hops as **unknown**, never fabricate measurements.
* Suppress duplicate probes, cap response sizes, and rate-limit probes to avoid
  interfering with SOS or normal mesh traffic.
* Match reports to the initiating probe token and enforce an expiry window.
* Older nodes must ignore unknown packet types safely.

## Codec

`firmware/core/include/ghostwave/diagnostics.h` defines fixed-width
little-endian 14-byte probe and 20-byte hop report payloads. The hop limit
belongs in the existing packet header; a decoder does not recover it from
the probe payload. RSSI uses signed dBm; SNR uses signed quarter-dB.

## Remaining integration

1. Reserve wire packet types and update packet validation/dispatch.
2. Add probe origin, forwarding, destination reply and per-hop reporting.
3. Add anti-amplification, deduplication, expiry and airtime limits.
4. Expose requests/events in protobuf and hand-written node codec.
5. Add Flutter UI, path visualization and history.
6. Add simulated multi-node tests and physical-radio verification.

## Local codec test

`c++ -std=c++17 -Ifirmware/core/include firmware/core/tests/diagnostics_test.cpp -o /tmp/gw-diagnostics-test && /tmp/gw-diagnostics-test`

## Multi-hop traceroute: a design decision first

GhostWave forwards by contention (geographic and flood modes), not fixed
routes, so "the path" can differ packet to packet. Two ways to trace one:

1. **Each relay reports back** (a Hop report per forwarder). Simple per node,
   but one probe makes many reports: needs strict rate limits to avoid flooding.
2. **The probe collects as it goes** (each forwarder appends id + RSSI, 5 bytes
   per hop). One reply, no amplification, but limited by the 128-byte frame
   (about 15 hops) and it shows only the path that one probe happened to take.

Option 2 fits the frame budget and the no-amplification rule better. It is
not built until that choice is made.
