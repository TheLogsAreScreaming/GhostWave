# GhostWave roadmap after host-side and app work

Last rewritten 2026-11-09, at main `d22f91b`.

Host tests, CI builds, simulator runs and documents are not evidence of a working radio mesh.
**Nothing here has run on a real radio yet.**

## Built, not yet run on hardware

The code exists and CI builds or host-tests it. Each item still needs a test on real boards.

- RAK4631 (SX1262) and T1000-E (LR1110) firmware targets, with a BLE client link.
  Prereleases: `fw-rak4631-v0.1.0-dev.2` and `fw-t1000e-v0.1.0-dev.2`, built from `6bdf73b`.
- Channels and pinned contact keys kept in flash (#119).
- Ed25519 identity on fresh MCU boards, with the node ID derived from the key (#129).
  Boards already holding an X25519 identity keep it until their settings are erased.
- Transmit off on a fresh board until `tx on` on the serial console (#132). The board's own SOS
  overrides this while the SOS runs.
- Beacon recovery (#118), measured velocity in beacons (#120), beacon MAC (#125, counted by default,
  enforced only with `--require-beacon-mac`), Bloom-filter spray hand-offs (#128).
- Per-region band limits and the regulatory duty-cycle cap (#121).
- Client link: PIN (#115), TCP encryption after the PIN handshake (#131), battery level (#122),
  keys for heard nodes (#134).
- Android app through `app-v0.1.0-dev.15`: Bluetooth, background connection and location, encrypted
  chat history, encrypted backup, long messages split into parts. Part of this has only been tried
  against the virtual mesh or in CI, and from dev.4 on most of it is untried on a phone.

## Required next, on hardware

1. Flash a RAK4631. Confirm `INFO_UF2.TXT` says `S140 6.1.1` first.
2. Pair it over BLE with the app, then run `tx on`.
3. Flash a T1000-E. Confirm `INFO_UF2.TXT` says `S140 7.3.0`, and check the radio starts. The TCXO
   voltage is the main risk, because the sources disagree (`docs/hardware/BOARD_PIN_EVIDENCE.md`).
4. Run a two-board on-air test: encrypted DATA, SOS, acknowledgement, retries, duplicate suppression.
5. Check flash persistence and reboot-safe message IDs across real power cycles.
6. Measure real TX power and RAM headroom with the SoftDevice.
7. Record physical test logs and safety/regulatory evidence for each board.

## Open work and decisions

8. Confirm board revisions and pin mappings against manufacturer documents.
9. Bump `GW_FW_VERSION` in `firmware/mcu/src/main.cpp` (firmware dev.2 still reports `0.1.0-dev.1`)
   and update the flashing guides, which still name the dev.1 files.
10. Report "transmit is off" to the app. Today its messages stay queued with no error.
11. Decide US transmit power policy (DESIGN §12).
12. Add a power-off or sleep mode for the T1000-E.
13. Bluetooth firmware updates: assessed in #123, not built.
14. Board identity backup: not built. Private keys must not cross the client link, so the app's
    backup covers phone data only.
15. App ID: `org.ghostwave.ghostwave_app`. `org.ghostwave.app` is possible only until the first
    store upload. Release signing key and privacy policy are parked.
16. iPhone: on hold. CI only proves it compiles.
17. Later: Meshtastic/MeshCore bridge, Pi HATs, field tuning.

## Before any release candidate

18. Fix what hardware testing finds.
19. Perform a security review.
20. Only then consider a release candidate and 1.0.

## Explicit exclusions

No claim of flash-proven firmware, working RF transmission, successful SOS delivery or release
readiness is made by this roadmap. The release gate must remain fail-closed until qualification.
