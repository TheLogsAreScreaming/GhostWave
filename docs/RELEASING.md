# Releasing GhostWave

One command stages a release from a commit on main and, with `--publish`, publishes it to
[GhostWave-Releases](https://github.com/TheLogsAreScreaming/GhostWave-Releases).

## Before you start

- `gh` is signed in with access to GhostWave, GhostWave-Releases and meshmayhem-site.
- The commit is merged to main, and its **CI** and **App** runs passed.
- A **firmware** release also needs the commit's **Selected board firmware packages** run. That
  workflow runs only when `firmware/` changes, so release new firmware from the commit that bumped
  `GW_FW_VERSION` (or a later one that also touched `firmware/`).
- Bump `GW_FW_VERSION` in `firmware/mcu/src/main.cpp` when the firmware changed. The app's dev number
  is picked for you.

## Dry run (the default)

```bash
python3 scripts/release.py --out /tmp/gw-release --site ../meshmayhem-site
```

This downloads and checks everything, and publishes nothing:

- **Firmware**, if this commit's version has no release yet. Each nRF UF2 (RAK4631, RAK3401 1 W,
  T1000-E, WisMesh Tag) must embed that version. The 11 board packages are checked by
  `publish-board-release.py`. A version that is already released is skipped.
- **App**: the next `app-v0.1.0-dev.N`, with the APK, Windows and macOS builds and `SHA256SUMS`. The
  notes list the PRs merged since the last app release. If main has nothing new since then, it
  stops.
- **Web flasher**: rebuilt and verified (`flasher/build_site.py`, `verify_site.py`).
- **Site**: the GhostWave page with downloads moved to the new app, written to
  `<out>/site-preview/`. The site clone is not touched.

Read `<out>/app/notes.md` and `<out>/uf2/*-notes.md`, and edit them if you like before publishing.

## Publish

```bash
python3 scripts/release.py --out /tmp/gw-release-2 --site ../meshmayhem-site --publish
```

- Each release is created as a draft, then published as a prerelease. Existing tags are never
  overwritten: a clash stops the run.
- The site changes go to a `release/ghostwave-<version>` branch and a pull request on meshmayhem-site.
  The script **never merges or deploys** the site.

## Then

1. Merge the site pull request.
2. Check https://www.meshmayhem.org/GhostWave and https://www.meshmayhem.org/webflasher/manifest.json.
3. If they did not update within a few minutes, Workers Builds did not run. Deploy from a clean
   checkout of the site's main: `npx wrangler deploy`.

A commit that only changed firmware has no App build (that workflow skips it). Release such
firmware with `--skip-app`, and the app from the last commit that changed it
(`--commit SHA --skip-firmware`).

Options: `--commit SHA` (default main's head), `--app-version 0.1.0-dev.N`, `--skip-firmware`,
`--skip-app`. Tests: `python3 scripts/test-release.py` (offline).
