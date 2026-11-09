# LilyGO T-Beam S3 Core (SX1262 version)

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_beam_s3` (`cd firmware/mcu && pio run -e t_beam_s3`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32s3/tbeam-s3-core and src/Power.cpp`.

Flash with `pio run -t upload`. It is serial only: ESP32 builds have no Bluetooth phone link yet.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

The GPS and power-chip battery reading are not used.
