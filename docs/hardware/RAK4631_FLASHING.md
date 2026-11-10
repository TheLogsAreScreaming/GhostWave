# RAK4631: flashing and bench test

GhostWave node firmware for the **RAK4631** WisBlock core (nRF52840 + SX1262) on a **RAK19007** or
**RAK19003** base board. It is built from `firmware/mcu`, env `rak4631`, and has the same router and
serial CLI as the Heltec builds, plus the BLE client link (docs/CLIENT_PROTOCOL.md §9).

> **Untested on hardware.** As of `fw-rak4631-v0.1.0-dev.8`, this build compiles, links and passes the
> host tests. Nobody has run it on a board yet. The pins come from RAK's datasheet and agree with
> RAK's and Meshtastic's variant files (`firmware/mcu/variants/rak4631/variant.h`), but they have not
> been checked on a board. Expect to find problems, and keep the Meshtastic UF2 at hand to go back.

## Before you start

- **Antenna on first.** Screw the LoRa antenna onto the RAK4631's LoRa IPEX connector before you
  plug in USB. A freshly set-up board stays silent until you type `tx on`, but after that it
  transmits beacons by itself at every boot, and transmitting into no antenna can damage the SX1262. The second, smaller IPEX connector is for BLE.
- **Power:** the default is **10 dBm** at the antenna port, which is plenty for a bench. `power <dBm>`
  changes it (capped at 22 dBm). **Frequency:** 914.875 MHz, US 902–928 MHz only (DESIGN §12).
- **Bootloader:** the drop-in UF2 needs the Adafruit nRF52 bootloader with the **S140 6.1.1**
  SoftDevice, which is what RAK ships and what Meshtastic uses on this board. The steps below check it.

## 1. Flash (UF2 drag and drop)

1. Download `ghostwave-rak4631-0.1.0-dev.8.uf2` from the prerelease
   [`fw-rak4631-v0.1.0-dev.8`](https://github.com/TheLogsAreScreaming/GhostWave-Releases/releases/tag/fw-rak4631-v0.1.0-dev.8).
   A CI build of any commit is also in that run's `ghostwave-rak4631-uf2` artifact.
2. Plug the base board into the computer with a USB **data** cable.
3. **Double-tap the reset button** on the base board (two presses within about half a second). A
   USB drive named **`RAK4631`** appears, and the green LED pulses slowly.
4. Open `INFO_UF2.TXT` on that drive. It must say `SoftDevice: S140 6.1.1`. If it shows another
   SoftDevice (for example `S140 7.3.0`), stop: this build will not start on that bootloader.
5. Drag the `.uf2` file onto the `RAK4631` drive. Copying takes a few seconds. The drive then
   disappears by itself and the board restarts into GhostWave. macOS may warn that the disk was not
   ejected properly. That is normal for UF2 drives.

From the command line instead of dragging (macOS):

```bash
cp ghostwave-rak4631-0.1.0-dev.8.uf2 /Volumes/RAK4631/
```

To build it yourself: `cd firmware/mcu && pio run -e rak4631`. The UF2 is
`.pio/build/rak4631/firmware.uf2`.

## 2. Serial console

The CLI runs on the board's native USB serial port. The port shows up as `/dev/cu.usbmodem…` on macOS
and `/dev/ttyACM0` on Linux. The baud rate is **115200**. USB serial ignores it, but set it anyway.
The board does not echo what you type, so turn on local echo:

```bash
picocom -b 115200 --echo /dev/cu.usbmodem*
```

Quit picocom with Ctrl-A, then Ctrl-X. With PlatformIO instead:

```bash
cd firmware/mcu && pio device monitor -e rak4631
```

With `screen` (no local echo, so you type blind; quit with Ctrl-A then K):

```bash
screen /dev/cu.usbmodem* 115200
```

The boot banner prints in the first two seconds, before most terminals attach. Type `status` to
see it again. Type `help` for the command list.

On first boot the node makes an Ed25519 identity from the hardware RNG and derives its node ID from
it. It stores them in the nRF52's internal flash (`/gw/settings`, LittleFS), so they survive
reflashing. The node then sends IDENT, so peers learn its key and its name. A board first set up by
an older build keeps its X25519 key and node ID. It sends no IDENT and cannot be named.

### Commands

These are the same as on the Heltec boards (README, "Run on a Heltec board"): `send`, `known`, `pos`,
`keys`, `peer`, `sos`, `sosstop`, `sosack`, `stats`, `status`, `setpos`, `psk`, `power`, `freq`,
`requireenc`, `responder`, `name`, `tx` and `reboot`. The RAK4631 adds three:

| Command | Effect |
|---|---|
| `ble` | BLE state: on or off, the advertised name, and whether a phone is connected, paired and has sent `Hello`. |
| `ble on` / `ble off` | Starts or stops advertising, and drops a connected phone on `off`. Saved. The default is on. |
| `ble clear` | Forgets every paired phone. Remove the node from the phone's Bluetooth list too. |

There is no GPS on a bare RAK19007. The node's position comes from the app (`SetOwnPosition`, not
saved) or from `setpos <lat> <lon>` (saved). `pos` says which one it is using.

## 3. Pair a phone

The GhostWave app does not speak BLE yet (a later app release adds it). Until then, you can check
pairing and the link with Nordic's free **nRF Connect** app (iOS or Android):

1. The pairing key is `654321` unless changed with `ble pin`.
2. In nRF Connect, scan and connect to **`GhostWave-xxxx`**, where `xxxx` is the last four hex digits
   of the node ID from `keys`.
3. Open the service `47570001-…` and tap the subscribe (notify) button on FromRadio `47570003-…`. The
   phone asks for a pairing code. Type `654321`.
4. The console prints `BLE pairing done, phone bonded`, then `BLE link encrypted`.
5. Optional: check the link end to end. Write this hex value (a `Hello`, docs/CLIENT_PROTOCOL.md §6)
   to ToRadio `47570002-…`: `94C30C00010801520708011203617070`. A notification arrives on FromRadio
   starting with `94C3`: that is `NodeInfo`. `ble` on the console now says `app session open`.

The next time, the phone reconnects without a passkey. To pair a different phone, or after
forgetting the node on the phone, type `ble clear` on the console.

## 4. Two-board bench test (CLI only)

You need two flashed RAK4631s, A and B, a couple of metres apart, each with its LoRa antenna and its
own serial console. 10 dBm is fine at this distance.

1. **Turn on transmit, then give each a position.** With the antennas on, type `tx on` on each board
   (a board first set up by an older build is already on). On A, type `setpos 46.8700 -113.9900`. On B, type
   `setpos 46.8710 -113.9900` (made up, 110 m north). Type `pos` on each. It should print
   `fix 46.870000 -113.990000 (stored)`.
2. **Check the radio.** Type `status` on each. The second line must say `radio ok`, `10 dBm out` and
   `914.875 MHz`. If it says `radio FAILED`, stop and send the console output (see the end).
3. **Swap public keys.** Type `keys` on each board. It prints `<id> <pubkey>`. On B, type `peer `
   followed by A's line. On A, type `peer ` followed by B's line. Each prints `ok`.
4. **Refuse plaintext.** On both boards, type `requireenc on`, then `reboot`. Reattach the console.
   `status` should end its channel-key line with `plaintext DATA refused`.
5. **Encrypted DM and delivery receipt.** On A, type `known <B-id> 46.8710 -113.9900`, then
   `send <B-id> hello over aead`.
   - A prints `queued id <msg-id> -> <B-id>`.
   - B prints `MSG from <A-id> id <msg-id>: hello over aead`.
   - A prints `DELIVERED to <B-id> id <msg-id>` within a few seconds. That is the delivery receipt.
   - `stats` on B shows `authfail 0`, and `tx` and `rx` have gone up on both.
6. **SOS.** On A, type `sos bench test, ankle`.
   - A prints `SOS on, repeating until sosstop`.
   - B prints `SOS from <A-id> seq 1 at 46.870000 -113.990000: bench test, ankle` and
     `(ack with: sosack <A-id>)`.
7. **SOS ack.** On B, type `sosack <A-id>`. B prints `acked SOS from <A-id>`, and A prints
   `SOSACK from <B-id> for seq 1`.
8. **Stop the SOS.** On A, type `sosstop`. `stats` no longer ends with `SOS-ACTIVE`.
9. **Persistence.** Unplug B for a few seconds and plug it back in. `keys` prints the same ID and key,
   `status` still shows `peer keys 1 stored` and `plaintext DATA refused`, and `pos` still has the
   stored position.
10. **Memory.** Type `status` on both. The `heap:` line shows the free heap and the worst-case table
    estimate. Every table should be under its cap.

Optional, with nRF Connect paired to A (section 3): leave the app connected but without `Hello`, send
a DM from B to A, then send the `Hello` frame. The DM comes back as a replayed `TextMessage`
notification. That is the offline event queue.

## 5. Go back to Meshtastic

1. Download the RAK4631 build of Meshtastic, `firmware-rak4631-<version>.uf2`, from
   [flasher.meshtastic.org](https://flasher.meshtastic.org) (pick *RAK WisBlock 4631*) or from the
   Meshtastic firmware releases on GitHub.
2. Double-tap reset. The `RAK4631` drive appears.
3. Drag the Meshtastic `.uf2` onto it. The board restarts into Meshtastic.

Meshtastic and GhostWave use the same internal-flash filesystem. Meshtastic ignores GhostWave's
`/gw/settings` file, and GhostWave ignores Meshtastic's files, so either can be reflashed over the
other and keeps its own settings. For a clean start in Meshtastic, use its *factory reset* (app:
Settings → Device → Factory reset). On the phone, forget `GhostWave-xxxx` in the Bluetooth settings.

## RAK WisMesh Tag

Build env `rak_wismesh_tag`. The Tag is a RAK4630 in a sealed case, so the radio pins, bootloader and
steps above are the same, with the UF2 from that env. **Untested on hardware.** Its built-in GPS,
button and buzzer are not used yet: position comes from the app or `setpos`, and there is no SOS
button. Its USB drive may have a different name.

## What is not verified until it runs on a board

- The SX1262 pins, the TCXO voltage (1.8 V on DIO3), DIO2 driving the antenna switch, and P1.05
  powering it. If `status` says `radio FAILED`, the error number tells which.
- Real transmit power and frequency accuracy. No spectrum check has been made.
- Settings, bonds, joined group channels and pinned contact keys in internal flash across reboots,
  power cuts and reflashes.
- Pairing with LE Secure Connections on iOS and Android, the MTU each negotiates, and notification
  throughput.
- RAM headroom with the SoftDevice running: the free heap at boot against the ~180 KB worst-case table
  estimate (the duplicate table is capped at 256 entries on nRF52 to leave room).
- The BLE task stacks with this workload. GhostWave runs in its own 16 KB task, but Bluefruit's own
  tasks are at their defaults.

When something fails, send the whole serial log from boot (`reboot`, then reattach), the output of
`status` and `ble`, and the board and base-board revision printed on the PCBs.
