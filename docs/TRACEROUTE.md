# Traceroute / repeater ping — implementation work in progress

This branch introduces a **portable diagnostic payload codec** and unit tests.
It is **not yet a working traceroute**. No radio packet dispatch, firmware
forwarding, client-protocol request/event, Flutter UI or on-device testing is
implemented in this commit. Do not merge until those pieces are complete.

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
