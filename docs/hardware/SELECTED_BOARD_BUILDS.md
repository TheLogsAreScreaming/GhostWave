# Selected board firmware packages

The Selected board firmware packages workflow builds the 11 targets in
`flasher/board-catalog.json` independently. Successful jobs upload images,
a source-commit manifest, checksums, and format-specific instructions.
Artifacts are development candidates, not published or hardware-qualified releases.

## Download and qualification

1. Open the workflow run on GitHub Actions and check the exact board job.
2. Download its matching artifact. Check SHA256SUMS after extraction.
3. Confirm the physical board revision, radio band, pin evidence and bootloader.
4. Run the existing board bench checks and record results before publishing.

UF2 packages contain an application image requiring a matching existing bootloader.
ESP32 installer artifacts contain a merged image with the pinned PlatformIO uploader's
resolved flash mode, frequency, size and offsets. The ordinary ESP32 build artifact
still contains separate diagnostic images; use the artifact ending in `-installer-SHA`
for browser installation.

## Flasher rollout

See [the release procedure](WEB_FLASHER_RELEASE.md). The flasher routes Nordic DFU
and ESP32 installation separately. Board entries have no installable versions until
compatible releases are published and the generated website is deployed. Additional
boards remain experimental until physical-board checks are recorded.
