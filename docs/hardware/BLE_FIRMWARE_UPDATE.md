# Firmware updates over Bluetooth: findings

**Status: not built, on purpose.** This is what the RAK4631 and T1000-E bootloaders allow and why
GhostWave does not offer Bluetooth updates yet. Update these boards by USB (UF2).

## What this is based on

Upstream source only: `adafruit/Adafruit_nRF52_Bootloader` (master) and the `BLEDfu` service in the
Adafruit nRF52 Arduino core 1.7.0, which these builds use. **No real bootloader has been inspected.**
RAK's and Seeed's are vendor builds of that project, and their build options are unknown to us.

## What the upstream bootloader does

| Question | Answer | Where |
|---|---|---|
| Is there a Bluetooth update mode? | Yes, Nordic's legacy DFU, advertising as `AdaDFU`. The app enters it by setting GPREGRET to `0xB1`. | `src/main.c`, `BLEDfu.cpp` |
| Is the image authenticated? | Not by default. Only a CRC-16 is checked, unless the bootloader was built with `SIGNED_FW=1` and a public key. | `src/dfu_init.c`, `Makefile` |
| Who can connect in update mode? | When entered without a stored peer, anyone in range: the advertising filter is `BLE_GAP_ADV_FP_ANY`. A peer is whitelisted only when the app hands over its details first. | `dfu_transport_ble.c` |
| Is an interrupted update safe? | Default builds are single-bank: the application is erased before the new image arrives. Dual-bank needs `DUALBANK_FW=1`. | `Makefile`, `dfu_single_bank.c` |
| Does `BLEDfu` require bonding? | No. Its own source has "TODO may force bonded only for security reason". | `BLEDfu.cpp` |
| Is USB recovery still there after a failed update? | The bootloader is not rewritten by an application update, so UF2 should remain available. Not tested. | design of the update flow |

## Why it isn't shipped

1. **Anyone nearby could replace the firmware.** Unless the installed bootloader is a signed build,
   nothing stops a stranger within Bluetooth range installing their own image, and that image holds
   the node's identity key and channel keys. Pairing protects GhostWave's service, not the bootloader.
   For a safety device carrying SOS traffic, that is not acceptable.
2. **Adding the `BLEDfu` service to the app widens that.** As shipped it lets an unbonded central
   start update mode. It would need gating, and we could not test that gate.
3. **A failed update leaves a dead node in the field.** On a single-bank bootloader the node has no
   application until someone reaches it with a USB cable, and on the T1000-E recovery needs the
   magnetic cable and the button.
4. **None of it can be tested here.** No board has run GhostWave yet.

## What would make it safe

A signed bootloader: built with `SIGNED_FW=1` and our public key, ideally `DUALBANK_FW=1`, for each
board. `FORCE_UF2` must be weighed, since UF2 does not check signatures. Flashing a bootloader is the
one step here that **can** brick a board without a debug probe, so it needs real boards, a probe for
recovery and a per-board build. It also needs the board and SoftDevice versions read from a real
`INFO_UF2.TXT`.

An application-level A/B updater is not a shortcut: the nRF52840's flash could hold two images, but
something still has to verify and swap them, and that something is a bootloader.

## To check on real hardware before any of this

- `INFO_UF2.TXT` on each board: bootloader version and build.
- Whether the shipped bootloader accepts an unsigned image over Bluetooth, and whether it is dual-bank.
- Time to transfer a ~375 KB image at the MTU phones actually negotiate.
- That UF2 recovery works after an update is interrupted partway.
