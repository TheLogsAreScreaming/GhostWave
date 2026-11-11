# Publish selected-board firmware and refresh the flasher

The flasher supports Nordic serial DFU and a separate ESP32 installer using
ESP Web Tools 10.1.0. New entries remain unavailable until compatible releases
exist. The nine additional boards remain experimental; build success is not
physical-hardware qualification.

## Build and publish

1. Merge the installer changes after the Web flasher and Selected board firmware
   packages checks pass. Use a successful **main-branch** board-packages run.
2. With `gh` authenticated for GhostWave and GhostWave-Releases, stage all 11:

   ```sh
   python3 scripts/publish-board-release.py --run RUN_ID --out /tmp/ghostwave-candidates
   ```

   This downloads the exact run artifacts, checks GitHub archive digests, board
   identity, source commit, UF2 offsets and ESP32 merged-image manifests. Legacy
   ESP32 bundles without resolved flash settings are rejected; rebuild them.
3. Publish the same run using a fresh output directory and explicit `--publish`:

   ```sh
   python3 scripts/publish-board-release.py --run RUN_ID --out /tmp/ghostwave-release --publish
   ```

   Tags use the embedded firmware version plus `+build.SOURCE_SHA` to distinguish
   artifacts without misrepresenting the firmware's reported version. Existing
   tags are never overwritten. All uploads are drafts before publication starts.
   A failed upload leaves drafts for inspection; nothing deletes existing releases.
4. Generate and validate:

   ```sh
   python3 flasher/build_site.py --out dist/webflasher
   python3 flasher/verify_site.py dist/webflasher
   ```

5. Copy the complete generated directory into `meshmayhem-site/public/webflasher`,
   preserving older firmware paths if they are still linked externally. Commit
   that update, then deploy the site's existing Wrangler configuration to the
   account that owns meshmayhem.org. Check the live manifest and every new file.

## Installation and recovery

For Nordic boards, compare `INFO_UF2.TXT` with the exact SoftDevice requirement
shown by the flasher. The UF2 download is available without Web Serial. Do not
replace a bootloader to work around a mismatch without a board-specific procedure.

For ESP32, use desktop Chrome or Edge over HTTPS. Select the exact board model;
chip detection cannot distinguish two boards with ESP32-S3 chips. The separate
installer shows its own port selection, installation progress, erase choice,
errors and retry controls. If interrupted, enter BOOT mode and reinstall.
The installer module is loaded from unpkg at a pinned version; firmware remains
same-origin. A failed module load leaves installation disabled and shows an error.

## Verification limits

Automated coverage checks package integrity, transport routing, invalid selections,
and existing Nordic DFU framing/timeouts. Browser USB cancellation, interrupted
writes, radio operation and recovery must still be checked with physical hardware.
Record those results before describing any additional board as hardware-tested.
