# T1000-E: flashing and bench test

GhostWave node firmware for the **Seeed SenseCAP T1000-E** (nRF52840 + LR1110 radio + AG3335 GNSS,
with a button, buzzer, LED and battery). It is built from `firmware/mcu`, env `t1000e`. It has the
same router, serial CLI and BLE client link as the RAK4631 build (`RAK4631_FLASHING.md`,
docs/CLIENT_PROTOCOL.md §9), plus the GPS, an SOS button, sounds and a battery reading.

> **Early hardware results.** One T1000-E has run dev.6 to dev.8: LoRa (LR1110), GPS, Bluetooth to
> the phone app, SOS with acknowledgement and signed cancel, and a link of about half a mile to a
> RAK3401 1 W board at 20 dBm (2026-11-09 to 11-11). `fw-t1000e-v0.1.0-dev.10` adds signal reports, link ping
> and transmit from the app, and has not been flashed yet. Keep the Meshtastic UF2 at hand to go back.

## Before you start

- **Antennas** are inside the case. Nothing to attach.
- **Power:** the default is **10 dBm**, and `power <dBm>` changes it (capped at 22 dBm). From 15 dBm
  up the LR1110 switches to its high-power amplifier. **Frequency:** 914.875 MHz, US 902–928 MHz only.
- **Power off:** press the button three times quickly while on battery. It gives one long low tone and
  shuts down, and a button press wakes it. It refuses during an SOS, within 5 s of stopping one, and
  while USB power is connected. Long press is SOS, not off as on Meshtastic.
- **Transmit is off at first.** A freshly set-up board only receives until you type `tx on` on the
  serial console. Holding the button for an SOS transmits anyway, until the SOS stops.
- **Bootloader:** Seeed's UF2 bootloader with the **S140 7.3.0** SoftDevice, as the T1000-E ships.
  This build is linked for that (application at 0x27000). It is **not** the RAK4631 file. Each board
  needs its own UF2.

## 1. Flash (UF2 drag and drop)

1. Download `ghostwave-t1000e-0.1.0-dev.10.uf2` from the prerelease
   [`fw-t1000e-v0.1.0-dev.10`](https://github.com/TheLogsAreScreaming/GhostWave-Releases/releases/tag/fw-t1000e-v0.1.0-dev.10).
   A CI build of any commit is also in that run's `ghostwave-t1000e-uf2` artifact.
2. **Enter the bootloader:** unplug the magnetic USB cable. Press and **hold** the button, plug the
   cable back in (into a computer, not a charger), then let go. The green LED stays lit, and a USB
   drive appears, usually named **`T1000-E`**.
   - If the device is already running Meshtastic or GhostWave, double-pressing reset is not possible
     (there is no reset button), so use this hold-while-plugging method.
3. Open `INFO_UF2.TXT` on that drive. It must say `SoftDevice: S140 7.3.0`. If it shows `S140 6.1.1`,
   stop: this build will not start on that bootloader.
4. Drag the `.uf2` onto the drive. The drive disappears by itself when the copy is done, and the
   T1000-E restarts into GhostWave. You hear nothing at boot. A single press of the button now
   chirps.

From the command line (macOS), with the drive name as it appears:

```bash
cp ghostwave-t1000e-0.1.0-dev.10.uf2 /Volumes/T1000-E/
```

To build it yourself: `cd firmware/mcu && pio run -e t1000e`. The UF2 is
`.pio/build/t1000e/firmware.uf2`.

## 2. Serial console

This is the same as on the RAK4631. The port is native USB (`/dev/cu.usbmodem…` on macOS, set
115200 baud), and the board does not echo what you type:

```bash
picocom -b 115200 --echo /dev/cu.usbmodem*
```

Or use `pio device monitor -e t1000e` from `firmware/mcu`. Type `status` to see the boot details and
`help` for the commands. They are the same as the RAK4631's, including `ble`, `ble on|off` and
`ble clear`. Settings, keys and phone pairings live in the nRF52's internal flash and survive
reflashing.

`status` adds a battery line on the T1000-E: `battery 3987 mV (87%, rough while charging)`. The
percentage follows Meshtastic's T1000-E voltage table. It reads high while the cable is in.

### GPS

The AG3335 is powered at boot. Its NMEA output goes through the same parser as the Heltec Tracker.
`pos` shows `fix ... (gps, Ns old)` once it has a fix. Before that it shows `(gps: N good sentences)`,
or the stored position if you set one with `setpos`. A first fix outdoors can take a minute or more.
Indoors it may never come. For bench tests, use `setpos`: the GPS takes over as soon as it has a fix.

## 3. Button, buzzer and LED

| You do | The node does | You hear / see |
|---|---|---|
| **Hold ~3 s** | Starts an SOS (text `SOS (button)`, with battery %, at the current position). It repeats until stopped, like `sos` on the CLI. | A tick at 1 s and 2 s while holding, then three long beeps. The LED flashes every 2 s while the SOS is on. |
| **Double press** | Stops our SOS. | One low beep. Two very low beeps if no SOS was on. |
| **Three quick presses** | Powers off, on battery with no SOS running. A press wakes it. | One long low tone. Two very low beeps if refused. |
| **Single press** | Prints `stats` on the console. | One short chirp, so you know it is alive. |
| — (a DM arrives) | Prints `MSG from ...` | Two short beeps. |
| — (a responder acks our SOS) | Prints `SOSACK from ...` | Three rising tones. |
| — (SOS started or stopped from the CLI or the app) | — | Same sounds as the button. |
| Hold ~3 s within a minute of the last SOS | Refused (rate limit) | Two very low beeps. |

## 4. Pair a phone

This is the same as on the RAK4631 (`RAK4631_FLASHING.md` section 3). Connect to `GhostWave-xxxx` in
nRF Connect and subscribe to FromRadio. Then type the pairing key, `654321` unless changed with
`ble pin`. No screen or computer is needed.

## 5. Two-board bench test

The bench test works with two T1000-Es, or one T1000-E and one RAK4631 (both run GhostWave at
914.875 MHz with the same Trail preset). Follow `RAK4631_FLASHING.md` section 4 step by step, using
`setpos` on both. Then also check the T1000-E's own parts:

1. **Radio:** `status` says `radio ok`. If it says `radio FAILED`, the boot log has a line
   `radio init failed: <number>`. The TCXO voltage is the first suspect (`BOARD_PIN_EVIDENCE.md`).
   Send the log.
2. **DM receipt sound:** when B sends a DM to the T1000-E, it beeps twice.
3. **SOS by button:** hold the T1000-E's button for 3 s. It beeps three times. The other board prints
   `SOS from <id> seq 1 at ...: SOS (button)` with `batt NN%`.
4. **SOS ack:** on the other board, type `sosack <T1000-E id>`. The T1000-E plays the rising tones
   and prints `SOSACK from ...`.
5. **Stop:** double-press. One low beep, and `stats` no longer ends with `SOS-ACTIVE`.
6. **GPS:** take the T1000-E outside for a few minutes, then type `pos`. It should say
   `fix ... (gps, ...)`.
7. **Battery:** `status` shows a voltage between about 3.6 and 4.2 V on battery.

## 6. Go back to Meshtastic

1. Download the T1000-E build of Meshtastic, `firmware-tracker-t1000-e-<version>.uf2`, from
   [flasher.meshtastic.org](https://flasher.meshtastic.org) (pick *Seeed SenseCAP T1000-E*) or from
   the Meshtastic firmware releases on GitHub.
2. Enter the bootloader as in section 1: hold the button while plugging in. The drive appears.
3. Drag the Meshtastic `.uf2` onto it.

Meshtastic ignores GhostWave's settings file, and GhostWave ignores Meshtastic's. For a clean start,
use Meshtastic's *factory reset*. On the phone, forget `GhostWave-xxxx`.

## What is not verified until it runs on a board

- The LR1110 radio:
  - It starts up with the 1.6 V TCXO setting.
  - The RF switch table is right.
  - It interoperates with a RAK4631 or Heltec SX1262 node (same sync word 0x24, SF9/BW125, CRC on).
  - The real transmit power on the low- and high-power amplifiers.
- The AG3335:
  - It powers up with these pin levels.
  - It outputs NMEA at 115200 without being configured first.
  - The time to a first fix.
- The button gesture timing in the hand, the buzzer loudness, and the LED.
- The battery voltage scale (1:2 divider, 3.0 V reference) and the percentage curve.
- Everything the RAK4631 list says about flash, pairing, MTU and RAM.

When something fails, send the whole serial log from boot (`reboot`, then reattach), the output of
`status` and `ble`, and the label on the back of the T1000-E.
