# Chat and connection screen redesign

Status: chat side built (delivery badges, connection strip, large text with keyboard). The Connect screen side is in the connection health PR. Host-tested; not yet tried on a phone.

## Requirements

- Carry the approved visual language through chat and connection screens while retaining GhostWave branding.
- Use clear delivery badges and compact connection summaries with troubleshooting details progressively disclosed.
- Keep composition, retry, contact-key warnings, and Bluetooth discovery reachable.
- Respect keyboard and system-navigation insets; preserve scroll position and content at large text sizes.

## Acceptance checks

- [ ] Widget tests cover narrow widths, keyboard visibility, and large text.
- [ ] Verify pending, accepted, delivered, failed, and missing-key states.
- [ ] Capture real rendered screens for review and verify the Samsung clipping regression.
