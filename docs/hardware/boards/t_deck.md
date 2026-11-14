# LilyGO T-Deck

> **Untested on hardware.** This build compiles, and nobody has run it on this board.

Build env: `t_deck` (`cd firmware/mcu && pio run -e t_deck`). Pins come from meshtastic/firmware @ 771efca, `variants/esp32s3/t-deck`.

From `firmware/mcu`, flash with `pio run -e t_deck -t upload`. If several serial devices are attached, select this board explicitly with `--upload-port PORT`. Close any serial monitor before uploading. The phone app connects over Bluetooth (pairing key `654321`), as on the nRF boards. Built, not yet tried on this board.

Fit the antenna first, then type `tx on`: a fresh board only receives until you do. Pressing the trackball works as the button: press to turn the screen page, hold 3 seconds to start an SOS, double-press to stop it. GPS is not used yet.

The screen shows the status, node, neighbour and message pages at twice their OLED size, and the pairing key while the phone pairs. The keyboard and trackball are not used yet.

## After an interrupted upload

Reconnect this board over USB, select its serial port again, then rerun the same `t_deck` upload command. If the port does not appear, use the manufacturer's download-mode procedure for the exact PCB revision. After upload, open `pio device monitor --port PORT --baud 115200` and run `status` to check the running firmware before a radio test.
