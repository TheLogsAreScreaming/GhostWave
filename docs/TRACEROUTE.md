# Traceroute and link ping

**Built:** the one-hop link ping (both directions) and the multi-hop
traceroute (probe collects, both ways), end to end. Neither has been run on
real radios yet; both are host-tested in the router simulation, the codecs,
the client handler and the app.

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

## Rules both follow

* Use an opt-in, low-priority probe with random correlation token, origin,
  destination and bounded hop limit (1–8 for a trace).
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

`firmware/core/include/ghostwave/diagnostics.h` defines the link ping's
fixed-width little-endian 14-byte probe and 20-byte hop report payloads, and
the traceroute's variable-length trace payload (below). The hop limit
belongs in the existing packet header; a decoder does not recover it from
the probe payload. RSSI uses signed dBm; SNR uses signed quarter-dB.

## Local codec test

`c++ -std=c++17 -Ifirmware/core/include firmware/core/tests/diagnostics_test.cpp -o /tmp/gw-diagnostics-test && /tmp/gw-diagnostics-test`

## Multi-hop traceroute (protocol 1.10)

GhostWave forwards by contention (geographic and flood modes), not fixed
routes, so "the path" can differ packet to packet. Of the two designs (each
relay reports back, or the probe collects as it goes) the probe-collects
design is built: one answer per trace, no amplification, and it fits a frame.

**How it works.**

1. The app (or `trace <hex-id> [hops]` on a board's console) asks the node to
   trace any node ID, 1–8 hops each way (default 5).
2. The node sends a `Diag` frame of kind `Trace` (4) as a hop-limited scoped
   flood (`hopsLeft` = hops − 1), addressed to the target.
3. Each relay that hears it for the first time appends its node ID and the
   RSSI it heard the frame at (5 bytes) and passes it on once, after a short
   random delay. If it hears two other relays pass it on first, it cancels
   its own copy (the same suppression channel messages use).
4. The target adds its own record and answers the first copy it hears with a
   `TraceBack` (5) frame carrying the way out. The answer floods back the same
   way, collecting the way back (up to the way out + 2 relays, at most 7).
5. The origin adds its own reading of the answer and reports both lists.

Every reading is taken by the radio that received the frame. The way back is
listed on its own, never assumed to mirror the way out. If no answer comes
within 45 s the result is *no answer* with no hops: a lost probe or answer says
nothing about where it was lost.

**Limits.** One trace out at a time per node, 30 s apart. A relay passes on at
most 6 trace frames a minute, and never one already carrying its ID. A target
answers at most once every 2 s. Records: up to 8 on the way out (7 relays +
the target) and 7 relays on the way back, so the largest answer is
14 + 2 + 5 × 15 = 91 bytes, inside the 105-byte payload of an unencrypted frame.

**Wire format** (`diagnostics.h`, little-endian):
`version 1 | kind | token 4 | origin 4 | target 4 | out count | out records… | (TraceBack only) back count | back records…`,
each record `node ID 4 | RSSI int8 dBm`.

**Older nodes.** A trace frame is addressed to the target, so an older relay
drops it (not addressed to it) and an older target cannot decode it. A path
through older firmware goes unanswered.

**Cost.** The probe is a flood within the hop limit: a busy mesh hears up to
one relay of it per node in range. Keep the hop count low when the target is
close.

**Client protocol 1.10.** `Traceroute` (29: `node_id`, `max_hops`) and
`TraceResult` (31: `node_id`, `answered`, `forward_nodes`/`forward_rssi_dbm`,
`back_nodes`/`back_rssi_dbm`, packed). The app opens *Trace route* from a
chat's menu or a heard node's sheet and lists each hop both ways in words.
The result type `PathTrace` (`app/lib/src/data/path_trace.dart`) is plain data
with JSON, for other screens to reuse.

**Not built:** SNR per hop (no SNR in the router's receive path yet), saved
trace history, and a check on two or more real radios.
