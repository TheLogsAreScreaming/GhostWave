# Live connection diagnostics

Status: implementation proposal; not implemented or verified by this document.

## Requirements

- Refresh last-response age while visible using a cancellable timer and a monotonic elapsed-time basis.
- Expose connected Bluetooth RSSI through an injectable capability where supported; show unavailable explicitly elsewhere.
- Keep Bluetooth RSSI distinct from LoRa link signal and include measurement time.
- Provide actionable permission, pairing, stale-bond, and reconnect guidance without revealing PINs.

## Acceptance checks

- [ ] Fake time verifies age refresh and stale detection.
- [ ] Fake Bluetooth verifies unsupported readings, errors, disconnects, and reconnection.
- [ ] Dispose timers and subscriptions; verify narrow screens and large text.
