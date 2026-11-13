# Heltec Mesh Node T114

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `heltec_t114` (`cd firmware/mcu && pio run -e heltec_t114`). Pins come from meshtastic/firmware @ 771efca, `variants/nrf52840/heltec_mesh_node_t114`.

Flash the UF2 (`.pio/build/heltec_t114/firmware.uf2`) through the bootloader drive. Check `INFO_UF2.TXT` first: this build needs SoftDevice **S140 6.1.1**. It has the Bluetooth phone link.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. GPS, buttons and other extras are not used yet.

The 1.14" colour screen shows the same status, node, neighbour and message pages as the OLED boards, drawn at their original 128×64 size in the middle of the panel. The pairing key appears there while the phone pairs.
