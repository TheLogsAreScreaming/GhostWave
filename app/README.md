# GhostWave app

The phone app (Android + iOS, Flutter) for the GhostWave backcountry LoRa mesh. It drives one GhostWave
node over the **client link** defined in [`docs/CLIENT_PROTOCOL.md`](../docs/CLIENT_PROTOCOL.md) and
[`proto/ghostwave.proto`](../proto/ghostwave.proto).
Today that link is TCP (`ghostwaved --client-tcp`). BLE to Heltec boards comes later and plugs in behind
the same transport interface.

It lives in `app/` of the GhostWave repo, next to the firmware it talks to, and shares no code with
any other mesh app.

## Status

| Feature | State |
|---|---|
| **Connect:** host:port, remembered, Hello handshake, auto-reconnect with backoff | done |
| **Me:** node ID, name, keys, contact-card QR code (copy as text too) | done |
| **Contacts:** scan a QR code or paste the card text → `AddContact`; last seen and position from `Neighbor` beacons; "heard nearby" list; key-change warning | done |
| **Group channels** (node protocol 1.1): create a channel (new random key) and share it by QR code or text (`ghostwave-ch:…`), join by scanning or pasting, channel chat with sender names, leave; best effort (a few hops, no receipts), saved on the phone, offline outbox | done |
| **Messaging:** unread badges for DMs and channels, tap or long-press to retry a failed message, long-press to copy or delete a message, delete a conversation or clear a channel | done |
| **Key change:** a contact whose node announced a different key is marked unverified with a prominent warning until you accept the new key (pinned on the node) or keep the old one | done |
| **Settings** (Me tab, gear): rename the node (`SetName`), reset the app's data, version, licenses (including the bundled fonts) | done |
| **Chat:** per-contact DM threads, queued → sent → delivered (`SendQueued` / `Delivered`), live UTF-8 byte counter against the node's 73-byte limit, saved on the phone, offline outbox sent on reconnect, failed messages retry on tap | done |
| **Map:** own node, contacts, nearby nodes and SOS alerts on OpenStreetMap tiles (online) | done |
| **SOS:** hold 3 s to raise, "SOS active" with acks received, stop; incoming SOS banner on every tab with Ack | done |
| **Status:** every `Status` field, refreshed every 10 s | done |
| **Recent nodes:** one-tap reconnect on the Connect screen; "Connected to N1 (9d66916b)" bar above the tabs | done |
| **Share phone location:** opt-in switch on the Me tab sends the phone's GPS to the node (`SetOwnPosition`) on 50 m of movement, at most every 30 s, while the app is open, and optionally in the background (a second switch, off by default) | done |
| **Notifications:** new DMs and SOS alerts while the app is in the background and still connected | done |
| **Background connection (Android, optional):** foreground service keeps the link up with the screen off | built, not tried on a phone |
| **PIN:** a node on a network asks for its PIN once; the app keeps it in the phone's secure storage, proves it without sending it, and encrypts the link with it | done |
| **Bluetooth** (RAK4631, T1000-E): scan, signal strength, system passkey pairing, remembered under recent nodes, drops recover by themselves | done, untested on real radios |
| **Offline maps:** save the area on screen from a tile source you configure (Map tab or Settings), with a size estimate and limits (zoom 16, 15,000 tiles per region, 1 GB in total) | done |
| **First run:** a four-page introduction (what GhostWave is, connecting, your QR card, how SOS works) | done |
| **SOS:** elapsed time and next repeat while active; an incoming SOS opens the map at the sender, with distance and bearing from you | done |
| **Units:** km or mi (Settings) | done |
| iPhone install | blocked, see below |

History (contacts, chats, SOS) is stored per node ID in the app's private storage, so connecting to a
different node does not mix conversations. Each file is encrypted, see [History on the phone](#history-on-the-phone).

## Try it without radios: the virtual mesh

You need a computer (Mac or Linux) on the **same Wi-Fi** as the phone, with this repo.

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

Builds are published as releases of
**[GhostWave-Releases](https://github.com/TheLogsAreScreaming/GhostWave-Releases/releases)**, with tags
that start with `app-` (for example `app-v0.1.0-dev.1`). Development builds are marked pre-release.

1. Open the releases page on the phone and pick the newest `app-` release.
2. Under **Assets**, download `ghostwave-app-<version>-arm64.apk`. It is built for 64-bit ARM, which
   covers every Android phone from roughly the last eight years.
3. Open it. Android asks you once to allow installs from that app (Chrome, Files, Drive or Gmail).

Or with `adb` and the GitHub CLI on a computer:

```bash
gh release download app-v0.1.0-dev.2 --repo TheLogsAreScreaming/GhostWave-Releases --pattern '*.apk' --dir apk
```

```bash
adb install -r apk/*.apk
```

**Signing.** From `app-v0.1.0-dev.4` on, CI signs the APK with a fixed GhostWave **dev key**, so a
newer build installs over an older one and keeps the app's data. Its certificate SHA-256 is
`A2:B5:61:8F:53:64:B9:FB:01:8C:A8:52:20:F4:AF:E5:EC:82:42:64:A4:8C:E8:D1:D7:FA:63:BA:2E:7D:A9:AE`
(CI checks every APK against it). This is a development key only, never for store releases.
Builds dev.1 to dev.3 used a different throwaway key each, so moving from one of those to dev.4 needs
**one more uninstall** (this clears the app's saved data). After that, updates install over the top.

How it works: the keystore (PKCS12) and its password are repository secrets
(`ANDROID_DEV_KEYSTORE_B64`, `ANDROID_DEV_KEYSTORE_PASSWORD`, `ANDROID_DEV_KEY_ALIAS`). CI decodes it to
a temporary file and passes it to Gradle through `GW_DEV_KEYSTORE*` environment variables. Without the
secrets (local builds, pull requests from forks) release builds fall back to the throwaway debug key.

**CI builds.** Every App workflow run on a pull request or on `main` also attaches the APK to the run
as the `ghostwave-app-apk` artifact (Actions tab → the run → Artifacts, kept 14 days); the run summary
shows its size and SHA-256.

**Follow-up: publish from CI.** Today releases are uploaded by hand from a CI artifact. A job that
publishes tagged builds to GhostWave-Releases needs a token with write access to that repo stored as a
secret here (a fine-grained PAT, or a GitHub App), which has not been set up yet.

## iPhone

**Blocked.** CI runs `flutter build ios --no-codesign` on every PR, which proves the iOS app compiles,
but installing it on an iPhone needs either Xcode on a Mac (free Apple ID, re-sign every 7 days) or a
paid Apple Developer account (TestFlight). That decision is still open. Android comes first.

## First Bluetooth connection (checklist)

Bluetooth nodes are the RAK4631 and T1000-E builds. The Heltec builds have no client link over Bluetooth.

1. Flash the node and open its USB serial console at 115200 baud. Check it prints `BLE "GhostWave-xxxx" advertising`.
2. In the app: Connect → **Find Bluetooth nodes**, and allow Nearby devices. Your node should be listed with its signal.
3. Tap it. Android asks for a passkey: type the 6 digits from `BLE pairing: enter passkey …` on the console.
4. The bar above the tabs should say `Connected to GhostWave-xxxx`.
5. Reconnect test: restart the node, or walk out of range and back. It should reconnect with no passkey and no taps.

If pairing fails, retype the passkey and tap **Retry now**. If you ran `ble clear` on the node, or reflashed it, forget
the node in Android's Bluetooth settings first, because the phone's old bond no longer matches. A node serves one
phone at a time and doesn't advertise while connected, so disconnect other phones if it isn't listed.

## Backup and restore (Android)

Settings → Backup and restore writes one encrypted file, to wherever you choose, with contacts and pinned keys, channels
and their keys, chat history, saved PINs and settings. It uses Argon2id (64 MiB) and XChaCha20-Poly1305. If you forget the
passphrase, the file can't be recovered. Restoring replaces the data on the phone.

It doesn't include the node's identity. The private key stays on the node (`docs/CLIENT_PROTOCOL.md` §7), so a lost board
means a new identity and node ID, and people have to add you again. On a Pi, keep a copy of the `--key` file yourself.
Offline maps, the background connection and location-sharing choices aren't included. Not tried on a phone yet.

## Background connection checks (needs a real phone)

CI can't run a foreground service, so these are still to do, on Android 14 or newer if possible:

1. Connect, accept the explanation screen, allow notifications and the battery exemption. The "GhostWave connected"
   notification appears.
2. Screen off for 30 minutes, on TCP and on Bluetooth. Send a DM and then an SOS from another node: both notify, the SOS
   on the "SOS alerts" channel.
3. Swipe the app away from recents, repeat the DM, then tap the notification. The chat shows it, with no duplicate.
4. Send a DM with the screen off, have the peer ack it, and check the tick when you reopen.
5. Take the node out of range for a few minutes and back: the notification says "reconnecting", then "connected".
6. Tap **Disconnect** on the notification, and separately disconnect in the app: the notification goes away both times.
7. Check battery use over a few hours, and test a vendor with aggressive app killing (Samsung, Xiaomi) if you can.

## History on the phone

Contacts, chats, channels and their keys, and SOS records are encrypted on the phone with XChaCha20-Poly1305. The key is
random, made on first use, and kept in Android's Keystore-backed secure storage. Files from older versions are encrypted
the next time the app starts, and the plaintext copies are removed. Flash storage can keep deleted blocks for a while, so
removing a file is not a guarantee that its old contents are gone.

This protects the files if they are copied off the phone. It doesn't protect against someone using the unlocked phone or
malware running as the app on a rooted phone, and there is no separate app passcode. Saved settings and the list of
recent node addresses aren't encrypted by this.

The key can't leave the phone, so Android's cloud backup and phone-to-phone transfer are turned off for this app. To move
to a new phone, use Backup and restore. If the key is lost, the old files can't be opened. The Chats screen says so if that
happens. Not tried on a phone yet.

## Known limits

- **Bluetooth has not been tried on real radios.** CI has none: the tests use a fake radio layer. Radio
  builds keep channels in memory only (the app joins them again after a reboot), and can't be renamed.
- **The TCP link's security depends on the PIN.** On a network the node requires a PIN (printed at start, and in
  the `vmesh_lan.sh` table), and the link is encrypted with keys agreed from it, so a captured handshake gives
  nothing to guess against. Anyone who has the PIN can connect or pose as the node, so keep it private. The
  handshake hasn't had an independent review, and it hasn't been tried from a real phone. A node from before this
  build can't connect, and the app refuses an unencrypted node on a network.
  See `docs/CLIENT_PROTOCOL.md` §7.
- **Offline maps need your own tile source.** The default map uses OpenStreetMap's tile servers, whose
  [usage policy](https://operations.osmfoundation.org/policies/tiles/) does not permit offline use or
  downloading areas in advance, so the app refuses to do that with them. Places you have viewed stay
  cached for a while. To save regions, set a tile URL from a provider whose terms allow offline use, or
  from your own tile server (Settings → Offline maps), and give its attribution, which the map always shows.
- **Background connection is Android only, and optional.** Turn it on when asked after the first connection, or
  in Settings. A persistent notification and a foreground service keep the TCP or Bluetooth link up with the screen
  off or the app swiped away, and it costs battery because the phone can't fully sleep. Without it, or on iPhone,
  or if the phone's vendor kills the app anyway, the link closes once the app is stopped. Nothing more arrives until
  it's opened again. There is no push service. The node holds DMs and SOS alerts and replays them on reconnect.
  **It hasn't been tried on a real phone.** See "Background connection checks" below.
- **Location sharing in the background is a separate choice.** It needs the location switch, the background connection,
  and "Keep sharing in the background" on the Me tab, which is off by default. It uses a foreground service, so it needs
  only the "while using the app" permission, and the notification says "sharing your location". Android only allows this
  when it's turned on with the app open. **It hasn't been tried on a real phone.**
- **Contacts come from the node.** A node in radio range becomes a contact on its own once your node
  hears its identity (IDENT; trust on first use, marked with a radio icon). Until then it shows under
  "Heard nearby, waiting for their key" and cannot be messaged: the client protocol carries no key
  for heard nodes, so the app cannot add them itself. Scanning or pasting the contact card pins the key
  (check-mark icon).

## Development

Toolchain: Flutter 3.47.7 (stable), Dart 3.13. CI (GitHub Actions) is the main build loop.

```bash
flutter pub get
```

```bash
flutter analyze --fatal-infos && flutter test
```

The integration test (`test/integration/vmesh_dm_test.dart`) starts two real `ghostwaved` nodes on the
UDP virtual radio. One test has two app link clients exchange a DM and get `Delivered`; a second runs
the full app state layer (two `MeshController`s): they add each other from encoded contact cards, and
the DM goes queued → sent → delivered on one side and shows up unread on the other. It runs only when
it finds the daemon, and is skipped otherwise:

```bash
cd ../firmware && cmake -S . -B build -DGHOSTWAVE_BUILD_VIRT=ON && cmake --build build --target ghostwaved
```

```bash
flutter test test/integration
```

It finds `../firmware/build/ghostwaved` on its own; set `GHOSTWAVED=/path/to/ghostwaved` to use another
build. CI (`.github/workflows/app.yml`) builds the daemon from the same commit and runs it on every PR
that touches `app/` or `proto/`.

### Layout

```
lib/src/gen/              Dart generated from ../proto/ghostwave.proto (tool/gen_proto.sh); CI checks it is fresh
lib/src/link/             plain Dart, no Flutter: frame codec, transports, session, reconnecting link
lib/src/app/providers.dart  Riverpod providers (composition root)
lib/src/app/mesh_controller.dart  mesh state: events in, actions out, saved per node
lib/src/data/             models and the encrypted history store
lib/src/map/              offline regions: tile maths, limits, download, storage
lib/src/ui/               screens
test/link/                codec (GhostWave golden frames), session, link, card tests
test/app/                 mesh controller against a fake node (DM states, outbox, dedup, SOS, history)
test/integration/         real-daemon test, skipped without ghostwaved
```

### Protocol and code generation

The app uses the repo's own [`proto/ghostwave.proto`](../proto/ghostwave.proto), the same file the
firmware implements; there is no copy in `app/`. After changing it, regenerate the Dart code:

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
golden frames from `firmware/tests/test_client_proto.cpp`. The generated files are committed,
so building the app needs no `protoc`; CI regenerates them and fails if they differ.

### Contact card format

The QR code carries `ghostwave:<node id, 8 hex>:<ed25519 key, 64 hex>[:<name, percent-encoded>]`,
for example `ghostwave:1a2b3c4d:9f…e0:Bob`. Scanning it sends `AddContact`; the node checks that the key
hashes to the ID.

## Brand

The icon, logo and colours come from the GhostWave brand kit; the logo is used unchanged. Colour
tokens, the dark theme and the type scale live in `lib/src/ui/theme.dart`. SOS and alerts use a plain
high-contrast red, never a brand colour.

- Fonts: Space Grotesk (headlines), Inter (body), JetBrains Mono (IDs and keys), bundled under
  `assets/fonts/` (SIL OFL 1.1; sources and versions in `assets/fonts/NOTICE.md`).
- Icons: generated by `dart run flutter_launcher_icons` from `assets/icon/` (config in `pubspec.yaml`);
  the generated files are committed. The Android adaptive foreground is the circular icon scaled so
  the whole circle sits inside the 66 dp safe zone. There is no themed (monochrome) Android icon yet:
  the brand kit's monochrome file is a placeholder circle, not a ghost glyph.

## License

MIT, see [LICENSE](../LICENSE).
