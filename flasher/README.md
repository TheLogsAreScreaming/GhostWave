# GhostWave web flasher

A static page that installs GhostWave on nRF52840 boards from desktop Chrome or Edge, over Web Serial.
It speaks the Adafruit bootloader's serial update protocol (`dfu.js`).

**Not yet run against a real board.** Frames match `adafruit-nrfutil` byte for byte, and the tests use a
simulated bootloader.

## Build

```bash
python3 flasher/build_site.py --out dist/webflasher
```

This needs `gh`. It downloads each board's latest five releases from GhostWave-Releases, and the output
folder is the whole site. Firmware has to be on the same origin as the page, because GitHub's download
links send no CORS headers. Rebuild and redeploy after publishing firmware.

## Add a board

Add it to `boards.json` with its SoftDevice ID and application start address, then publish releases
tagged `fw-<id>-v<version>`.

## Test

```bash
node --test flasher/tests/dfu.test.mjs
```

```bash
python3 flasher/tests/test_build_site.py
```

The bootloader refuses firmware built for a different SoftDevice. It can't tell two boards with the same
bootloader apart, such as a RAK4631 and a RAK3401, which is why the page asks.
