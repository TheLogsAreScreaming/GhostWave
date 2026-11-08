# GhostWave app

The phone app (Android + iOS, Flutter) for the [GhostWave](https://github.com/TheLogsAreScreaming/GhostWave)
backcountry LoRa mesh. It drives one GhostWave node over the **client link** defined in GhostWave's
[`docs/CLIENT_PROTOCOL.md`](https://github.com/TheLogsAreScreaming/GhostWave/blob/694305f8840442d67749a0c9795d74d264d7ddcc/docs/CLIENT_PROTOCOL.md).
Today that link is TCP (`ghostwaved --client-tcp`). BLE to Heltec boards comes later and plugs in behind
the same transport interface.

This is a separate project from any other mesh app: its own repo, its own code, MIT license.

## Status

| Feature | State |
|---|---|
| Connect: host:port, remembered, Hello handshake, auto-reconnect with backoff | done |
| Me: node ID, name, keys, contact-card QR code | done |
| Status: every `Status` field, refreshed every 10 s | done |
| Contacts (QR scan / paste), Chat with queued → sent → delivered, Map, SOS | next PR |
| BLE transport | later (needs the Heltec BLE service) |
| iPhone install | blocked, see below |

## Try it without radios: the virtual mesh

You need a computer (Mac or Linux) on the **same Wi-Fi** as the phone, with the GhostWave repo.

```bash
git clone https://github.com/TheLogsAreScreaming/GhostWave.git
```

```bash
cd GhostWave && firmware/pi/tools/vmesh_lan.sh -n 4 --lan
```

The first run builds `ghostwaved` (needs `cmake` and a C++ compiler). The script starts 4 virtual nodes,
1.5 km apart on a simulated radio, and prints a table like this:

```
    node id       client link           ed25519 public key (contact / QR card)
    N1  1a2b3c4d  192.168.1.20:47800    9f…
    N2  …         192.168.1.20:47801    …
```

In the app, enter one of the **client link** addresses (for example `192.168.1.20:47800`) and tap
Connect. To chat between two phones (or a phone and `gwclient.py`), connect each one to a different
node. Ctrl-C stops the mesh.

If the phone cannot connect: check that both are on the same Wi-Fi (not a guest network that isolates
clients), and that the computer's firewall allows incoming connections on ports 47800–47805.

## Install the Android APK

Builds are published to
**[ghostwave-app-releases](https://github.com/TheLogsAreScreaming/ghostwave-app-releases/releases)**
(a public repo with builds only, no source).

1. Open the releases page on the phone and pick the newest release. Development builds are tagged
   `vX.Y.Z-dev.N` and marked pre-release.
2. Under **Assets**, download `ghostwave-app-<version>-arm64.apk`. It is built for 64-bit ARM, which
   covers every Android phone from roughly the last eight years.
3. Open it. Android asks you once to allow installs from that app (Chrome, Files, Drive or Gmail).

Or with `adb` and the GitHub CLI on a computer:

```bash
gh release download --repo TheLogsAreScreaming/ghostwave-app-releases --pattern '*.apk' --dir apk
```

```bash
adb install -r apk/*.apk
```

Development builds are signed with a throwaway debug key, and each build may have a different one, so
Android may refuse to install a newer build over an older one ("App not installed"). Uninstall the old
one first; this also clears the app's saved data. Proper signing comes with the first real release.

**CI builds.** Every CI run on a pull request or on `main` also builds the APK and tries to attach it to
the run as the `ghostwave-app-apk` artifact (Actions tab → the run → Artifacts, kept 14 days). That
upload is best effort: the account's artifact storage is shared by all its private repos and is
sometimes full, in which case the run stays green and the run summary shows the APK's size and SHA-256
but there is nothing to download.

**Follow-up: publish from CI.** Today releases are uploaded by hand. A CI job that publishes tagged
builds to `ghostwave-app-releases` needs a token with write access to that repo stored as a secret in
this one (a fine-grained PAT, or a GitHub App), which has not been set up yet.

## iPhone

**Blocked.** CI runs `flutter build ios --no-codesign` on every PR, which proves the iOS app compiles,
but installing it on an iPhone needs either Xcode on a Mac (free Apple ID, re-sign every 7 days) or a
paid Apple Developer account (TestFlight). That decision is still open. Android comes first.

## Known limits

- **No BLE yet.** The app only talks TCP, to `ghostwaved` on a computer or Pi.
- **No authentication on the TCP link.** Anyone who can reach the node's client port can read its DMs,
  send as it, add contacts and raise or ack SOS. `ghostwaved` only listens on 127.0.0.1 unless told
  otherwise; `--lan` / `--bind` are for a **trusted Wi-Fi only**. Stop the mesh when you are done.
- Map tiles need internet (OpenStreetMap). Offline tiles are a follow-up.

## Development

Toolchain: Flutter 3.47.7 (stable), Dart 3.13. CI (GitHub Actions) is the main build loop.

```bash
flutter pub get
```

```bash
flutter analyze --fatal-infos && flutter test
```

The integration test (`test/integration/vmesh_dm_test.dart`) starts two real `ghostwaved` nodes on the
UDP virtual radio and has two app link clients exchange a DM and get `Delivered`. It runs only when it
finds the daemon, and is skipped otherwise:

```bash
GHOSTWAVED=/path/to/GhostWave/firmware/build/ghostwaved flutter test test/integration
```

CI builds `ghostwaved` from the pinned GhostWave commit and runs it on every PR.

### Layout

```
proto/ghostwave.proto     copied from GhostWave @ 694305f8 (PR #106); do not edit here
lib/src/gen/              Dart generated from it (tool/gen_proto.sh); CI checks it is fresh
lib/src/link/             plain Dart, no Flutter: frame codec, transports, session, reconnecting link
lib/src/app/providers.dart  Riverpod providers (composition root)
lib/src/ui/               screens
test/link/                codec (GhostWave golden frames), session, link, card tests
test/integration/         real-daemon test, skipped without ghostwaved
```

### Protocol pin and code generation

`proto/ghostwave.proto` is a copy of GhostWave's `proto/ghostwave.proto` at commit
`694305f8840442d67749a0c9795d74d264d7ddcc`. To update it, copy the file again (keep the header comment,
with the new hash), then:

```bash
dart pub global activate protoc_plugin 25.1.0
```

```bash
./tool/gen_proto.sh
```

**Why generated code, not a hand-written codec:** the node hand-writes its codec to stay small on the
MCU, but on the phone size does not matter and correctness does. `protoc --dart_out` gives typed
classes straight from the schema, handles unknown fields and proto3 `optional` presence per the
protobuf spec, and keeps the app in step with the schema when it grows (regenerate, and the compiler
points at what changed). The protocol spec recommends it. Only the framing (magic, length, version) is
hand-written, in `lib/src/link/frame_codec.dart`, and the unit tests check it byte for byte against the
golden frames from GhostWave's `firmware/tests/test_client_proto.cpp`. The generated files are committed,
so building the app needs no `protoc`; CI regenerates them and fails if they differ.

### Contact card format

The QR code carries `ghostwave:<node id, 8 hex>:<ed25519 key, 64 hex>[:<name, percent-encoded>]`,
for example `ghostwave:1a2b3c4d:9f…e0:Bob`. Scanning it sends `AddContact`; the node checks that the key
hashes to the ID.

## License

MIT, see [LICENSE](LICENSE).
