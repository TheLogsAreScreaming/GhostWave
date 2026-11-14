# LilyGO T-Beam S3 Core (SX1262 version)

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_beam_s3` (`cd firmware/mcu && pio run -e t_beam_s3`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32s3/tbeam-s3-core and src/Power.cpp`.

Flash with `pio run -t upload`. The phone app connects over Bluetooth (pairing key `654321`), as on the nRF boards. Built, not yet tried on this board.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. The middle button: press it to turn the screen page, hold it 3 seconds to start an SOS, double-press to stop it. GPS is not used yet: it needs the power chip switched on for it.

GPS is not used yet.

The battery level shows on the screen and in the app, read by the power chip.
