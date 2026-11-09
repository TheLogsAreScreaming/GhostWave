# LilyGO T-LoRa V2.1-1.6

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `tlora_v2_1_6` (`cd firmware/mcu && pio run -e tlora_v2_1_6`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32/tlora_v2_1_16`.

Flash with `pio run -t upload`. It is serial only: ESP32 builds have no Bluetooth phone link yet.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

The SX1276 is limited to 17 dBm here. Whether it talks to SX1262 boards has not been tested.
