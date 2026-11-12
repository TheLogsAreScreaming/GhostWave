# Persistent field reports

Status: built in the app (Status → Field tests). Not yet tried on a phone in the field.

## How it works

- **Field tests list.** Each test has a name, notes and up to 200 samples. Tests stay on the phone after the screen or
  the app closes, until you delete them. Up to 50 are kept.
- **Recording a sample.** This asks the connected radio for its counters (sent, received, delivered, bad frames,
  airtime, uptime). It adds the phone's position and each neighbor's last-heard time and distance. You can attach a
  short note to it, such as "top of the ridge". Recording never transmits on the mesh.
- **Storage.** Tests are kept in one JSON file in the app's private folder. It is written to a temporary file and
  renamed, so a crash mid-save keeps the last good copy. A damaged file is set aside as `field_reports.json.bad`, and
  the screen says so. A failed save is shown on screen and does not stop later saves.
- **Export.** On Android, export saves a file through the system file chooser. On other platforms it copies to the
  clipboard. The file is versioned:
  `{"format":"ghostwave-field-report","formatVersion":1,"appVersion":…,"exportedAtUtc":…,"report":{…}}`.
- **Import.** On Android you can import an exported file. It is added as a new copy and never overwrites a test
  already on the phone. A file made by a newer app version is refused.
- **CSV.** Copies counters as CSV, one row per sample. Text is quoted, and cells starting with `=`, `+`, `-` or `@`
  are escaped so a spreadsheet does not run them.

## Limits

- Signal (RSSI, whole dBm) is recorded from firmware dev.9 on (client protocol 1.7): the last frame the node heard,
  and each neighbor's last beacon. It is the last hop only. SNR is not reported.
- Counters are cumulative and reset when the radio restarts.

## Acceptance checks

- [x] Round-trip reports through persistence and export (`test/data/field_reports_test.dart`).
- [x] Restart, interrupted writes, corrupt files, failed saves, limits, newer-version refusal.
- [x] Notes kept after leaving the screen; delete asks first (`test/ui_field_reports_test.dart`).
- [ ] Export, import and cancel on a real Android phone.
