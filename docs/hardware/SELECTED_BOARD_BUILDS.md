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

UF2 packages contain an application image, requiring a matching existing bootloader.
ESP32 packages contain separate application, bootloader and partition images;
they are not complete factory-flash bundles. Until offsets and auxiliary images
are verified, use PlatformIO upload from the exact source commit.

## Flasher rollout

The existing browser installer speaks nRF52840 serial DFU only. Its enabled
board list remains `flasher/boards.json`. The separate catalog lists build
candidates without exposing an incompatible flash action. New nRF entries need
verified SoftDevice IDs and application offsets. ESP32 entries need an ESP32
installer and board-specific complete flash manifests before enabling a button.
No deployment, release publication, or hardware test is performed by this PR.
