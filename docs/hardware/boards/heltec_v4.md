# Heltec V4

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `heltec_v4` (`cd firmware/mcu && pio run -e heltec_v4`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32s3/heltec_v4 and src/mesh/LoRaFEMInterface.cpp`.

Flash with `pio run -t upload`. It is serial only: ESP32 builds have no Bluetooth phone link yet.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

This board has an amplifier after the radio chip. `power` sets the level at the antenna port using Meshtastic's gain tables, which nobody has measured for GhostWave. Output stays capped at 22 dBm.
