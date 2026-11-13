# Seeed Xiao ESP32-S3 + Wio-SX1262 kit

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `xiao_s3` (`cd firmware/mcu && pio run -e xiao_s3`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32s3/seeed_xiao_s3`.

Flash with `pio run -t upload`. The phone app connects over Bluetooth (pairing key `654321`), as on the nRF boards. Built, not yet tried on this board.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.
