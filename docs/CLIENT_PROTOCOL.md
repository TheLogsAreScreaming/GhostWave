# GhostWave client protocol, v1.2

The link an app (the Flutter phone app, a desktop tool, a script) uses to drive one GhostWave
node. This is DESIGN §10 made concrete.

- **Schema:** [`proto/ghostwave.proto`](../proto/ghostwave.proto).
- **Node codec:** `firmware/core` (`ghostwave/client_proto.h`). It is portable and reused by the MCU
  firmware for BLE.
- **Request handling:** `firmware/core` (`ghostwave/client_handler.h`): requests, replies, the event
  queue and its replay. Shared by every transport, so TCP and BLE behave the same.
- **Daemon transport:** `ghostwaved --client-tcp [HOST:]PORT` (`firmware/pi/client_link.cpp`).
- **MCU transport:** BLE on the nRF52 boards (`firmware/mcu/src/ble_link.cpp`, §9).
- **Reference client:** `firmware/pi/tools/gwclient.py`, Python stdlib only.

**Versions.** The frame version and `Hello.protocol_version` stay 1. Minor versions only add
messages and fields, and `NodeInfo.protocol_minor` says which ones a node has. Absent, or 0, means
the original 1.0. A newer app checks it before using 1.1 features. An older node answers 1.1
requests with `UNKNOWN_REQUEST`. An older app ignores the new fields and events.

| Minor | Adds |
|---|---|
| 0 | the original set |
| 2 | the PIN handshake on `Hello` (`PinChallenge`, `Hello.client_nonce`, `Hello.pin_proof`, error `BAD_PIN`) (§7) |
| 1 | group channels (`SendChannelText`, `AddChannel`, `RemoveChannel`, `ListChannels`, `ChannelMessage`, `Channel`, `ChannelsEnd`, `NodeInfo.max_channel_text_bytes`, error `CHANNEL_LIMIT`) and `SetName` |

## 1. Transports

| Transport | Status | Notes |
|---|---|---|
| TCP | done (`ghostwaved`) | Off by default. `--client-tcp 4403` listens on 127.0.0.1:4403. A host must be named explicitly to listen anywhere else (see §7). Up to 4 clients at once. |
| BLE | done (RAK4631, T1000-E) | A GhostWave GATT service: the app writes frames to ToRadio, the node notifies on FromRadio. The same frames, unchanged. Pairing required. See §9. Not on the ESP32 builds yet. |
| USB serial | planned | The same frames. Garbage before a magic is skipped, so boot logs on the same port are harmless. |

All transports carry one byte stream in each direction, made of frames.

## 2. Framing

```
+------+------+--------+--------+---------+------------------------------+
| 0x94 | 0xC3 | len_lo | len_hi | version | protobuf ToRadio / FromRadio |
+------+------+--------+--------+---------+------------------------------+
               len = 1 + protobuf bytes, 1..176
```

- **Magic:** `0x94 0xC3` is the magic from DESIGN §10, the same idea as Meshtastic's stream framing.
- **len:** little-endian. It counts the version byte plus the protobuf bytes.
- **version:** `1` for this document. A node that gets a different version answers
  `Error{BAD_VERSION}` and closes the link. The app should then show "update the app or the node".
- **Size limit:** a whole frame is at most **180 bytes** (`kMaxFrame`), so `len` ≤ 176. 180 bytes fits
  one BLE write or notification at ATT MTU 185, the smallest a current iPhone negotiates. On BLE every
  frame is then a single write, with no reassembly. The length prefix still makes the stream
  self-delimiting if a transport splits it.
- **Bad length:** if `len` is 0 or over 176, the receiver reports `Error{BAD_FRAME}`. It then drops the
  magic and searches for the next one.
- **Bad protobuf:** an undecodable body gets `Error{BAD_FRAME}`, and the link stays up.

Every v1 message fits easily. The largest is `NodeInfo` at about 110 bytes. A DM's text is capped at
73 bytes anyway (§4).

## 3. Encoding: protobuf (proto3), hand-coded on the node

DESIGN §10 already chose protobuf, and it suits both ends:

- **Dart:** gets generated classes from `protoc --dart_out` and the official `protobuf` package. No
  hand-written parser on the phone.
- **Node:** v1 has about 30 small messages, each made only of varints, fixed32s and byte strings. A
  generic runtime would be overkill. `client_proto.cpp` is a hand-written codec of about 500 lines,
  with no protoc, nanopb or code generation in the firmware build. It is no larger than a TLV
  codec would be. The wire format is still standard protobuf, so any protobuf tool can decode a
  capture.
- **Why not TLV:** it is simpler on paper, but every client would have to hand-write the codec, and
  it gives no schema evolution rules.
- **Why not nanopb:** it remains an option for the MCU if the schema grows a lot. It produces the
  same bytes.

Schema evolution rules are in the header of `ghostwave.proto`. In short: never renumber or retype a
field. Add new requests and events as new oneof fields. A receiver skips unknown fields. An unknown
request gets `Error{UNKNOWN_REQUEST}`.

Encoding conventions:
- **Node IDs and message IDs** are `fixed32`: they are random 32-bit values.
- **Positions** are `sint32` in units of 1e-7°. An absent `Position` means "no fix", so a real fix at
  0,0 is still sent as a present but empty sub-message.
- **Text from the air** (`TextMessage.text`, SOS text, names) is `bytes`. It is usually UTF-8, but
  the radio does not guarantee that. Decode it leniently, e.g. Dart `utf8.decode(b, allowMalformed: true)`.
- **`optional uint32`** is used where 0 is meaningful (battery %, accuracy). Absent means "unknown".

## 4. Messages

Every `ToRadio` may carry a `req_id`. Each reply to it echoes that `req_id`. Unsolicited events
have `req_id` 0. A request gets exactly one reply: its result, `Ok` or `Error`. The exceptions are
`ListContacts`, which gets zero or more `Contact` and then `ContactsEnd`, and `ListChannels`, which
gets zero or more `Channel` and then `ChannelsEnd`.

### App → node (`ToRadio`)

| # | Request | Fields | Reply |
|---|---|---|---|
| 10 | `Hello` | `protocol_version` (=1), `client_name` | `NodeInfo`, then replayed events (§5) |
| 11 | `SendText` | `dest`, `text` (≤ 73 bytes), `client_msg_id` | `SendQueued{dest, msg_id, client_msg_id}`; later the event `Delivered` |
| 12 | `AddContact` | `node_id` (0 = derive from the key), `ed25519_pub`, or `x25519_pub` for a legacy node; `name` (≤ 32 bytes) | `Ok` / `KEY_REJECTED` |
| 13 | `ListContacts` | none | `Contact`…, `ContactsEnd{count}` |
| 14 | `SetKnownPosition` | `node_id`, `pos` | `Ok` |
| 15 | `SosStart` | `text` (cut to 60 bytes), optional `battery_pct`, optional `accuracy_m` | `Ok` / `RATE_LIMITED` |
| 16 | `SosStop` | none | `Ok` |
| 17 | `SosAck` | `node_id` (the SOS originator) | `Ok` / `NOT_FOUND` |
| 18 | `GetStatus` | none | `Status` |
| 19 | `GetPosition` | none | `OwnPosition{pos}` |
| 20 | `SetOwnPosition` | `pos` (absent = clear) | `Ok`. The phone's GPS becomes the node's position, for nodes without GPS. A node GPS fix overrides it. |
| 21 | `SendChannelText` (1.1) | `channel` (name), `text` (≤ `max_channel_text_bytes`, 86), `client_msg_id` | `SendQueued{dest = 0xFFFFFFFF, msg_id, client_msg_id}` / `NOT_FOUND` / `TOO_LONG`. No `Delivered` follows. |
| 22 | `AddChannel` (1.1) | `name` (1–16 bytes UTF-8), `psk` (32 bytes) | `Ok` (also for the same name and key again) / `BAD_ARGUMENT` / `CHANNEL_LIMIT` |
| 23 | `RemoveChannel` (1.1) | `name` | `Ok` / `NOT_FOUND` |
| 24 | `ListChannels` (1.1) | none | `Channel`…, `ChannelsEnd{count}` |
| 25 | `SetName` (1.1) | `name` (≤ 9 bytes UTF-8) | `Ok` / `BAD_ARGUMENT` / `NO_IDENTITY`. The node re-signs and announces its IDENT. |

Notes on the requests:

- **Hello comes first.** Any other request before it gets `NEED_HELLO`.
- **Text limit:** 73 bytes is `NodeInfo.max_text_bytes`. It is the most that always fits a 128-byte
  radio frame: header 19 + forward, destination and source positions 20 + Poly1305 tag 16. Longer
  text gets `TOO_LONG`, never a silent cut. The app should count UTF-8 bytes, not characters.
- **AddContact is the QR scan.** A contact card is `node_id` + `ed25519_pub` + a display name.
  The key must hash to the ID (DESIGN §3), or the request gets `KEY_REJECTED`. A pinned key overrides
  one learned over the air (TOFU).
- **SetKnownPosition** seeds where a node is believed to be. With it, DMs route geographically
  instead of waiting for SPRAY encounters. The app should send it for contacts with a known
  location.
- **SOS:** accuracy is carried in 4 m steps on the air, so it comes back rounded up. A second
  `SosStart` within a minute of the last one gets `RATE_LIMITED` (DESIGN §8). Calling `SosStart`
  again while an SOS is active updates its text.

- **Group channels (1.1, DESIGN §9.3)** are flooded a few hops to every node holding the key:
  best effort, with no receipt. A channel is a name and a 32-byte key. A node holds up to 8.
  `ghostwaved` keeps them across restarts. The MCU firmware (BLE) holds them in RAM for now, so
  the app joins them again after a reboot. Share one as text or a QR code:
  `ghostwave-ch:<name, percent-encoded>:<psk, 64 hex>`. Anyone with it can read and write the
  channel. An `AddChannel` with a name already in use under another key, or a key already joined
  under another name, gets `BAD_ARGUMENT`.
- **SetName** changes the IDENT name (`ghostwaved` keeps it across restarts). Nodes without an
  Ed25519 identity, such as the MCU firmware today, answer `NO_IDENTITY`. Peers see it as
  `PeerIdent{is_new = false}`. A new `Hello` returns it in `NodeInfo.name`.

### Node → app (`FromRadio`)

| # | Event | Fields | When |
|---|---|---|---|
| 10 | `NodeInfo` | `protocol_version`, `node_id`, `name`, `ed25519_pub`, `x25519_pub`, `legacy`, `firmware`, `max_text_bytes` | reply to `Hello` |
| 11 | `TextMessage` | `src`, `msg_id`, `text` | a DM for us arrived |
| 12 | `Delivered` | `dest`, `msg_id`, `client_msg_id` | end-to-end receipt for our DM |
| 13 | `SosAlert` | `src`, `seq`, `pos`, `accuracy_m`, `battery_pct`, `text` | a new SOS, or a newer seq of one already held |
| 14 | `SosAckReceived` | `responder`, `seq` | someone acknowledged our SOS |
| 15 | `Neighbor` | `node_id`, `pos`, `is_new` | a neighbor's beacon (live only, not queued) |
| 16 | `Status` | counters, `store_size`, `neighbors`, `sos_held`, `sos_active`, `uptime_s`, `clients`, `queued`, `battery_pct` | reply to `GetStatus` |
| 17 | `OwnPosition` | `pos` | reply to `GetPosition` |
| 18 | `Error` | `code`, `detail` | a request failed, or the stream is bad |
| 19 | `Contact` | `node_id`, `name`, `x25519_pub`, `ed25519_pub`, `pinned` | reply to `ListContacts` |
| 20 | `ContactsEnd` | `count` | ends `ListContacts` |
| 21 | `SendQueued` | `dest`, `msg_id`, `client_msg_id` | reply to `SendText` |
| 22 | `Ok` | none | success with no data |
| 23 | `PeerIdent` | `node_id`, `name`, `is_new` | a verified IDENT taught a new key, or a new name |
| 24 | `KeyChange` | `node_id`, `ed25519_pub`, `name` | a signed IDENT carries a different key (DESIGN §9.2). Warn the user. The node keeps the old key. |
| 25 | `ChannelMessage` (1.1) | `channel` (name), `src`, `msg_id`, `text` | a group channel message arrived (queued like `TextMessage`) |
| 26 | `Channel` (1.1) | `name`, `psk` | reply to `ListChannels` (the key lets the app share the channel) |
| 27 | `ChannelsEnd` (1.1) | `count` | ends `ListChannels` |
| 28 | `PinChallenge` (1.2) | `nonce` (16 bytes) | reply to `Hello` on a link that needs a PIN (§7) |

`NodeInfo` (1.1) also carries `protocol_minor` and `max_channel_text_bytes`.

Notes on the events:

- **Matching receipts:** match `Delivered` to the UI message by `client_msg_id`, which the app chose.
  `msg_id` also works. A receipt can arrive more than once, so treat it as idempotent.
- **No receipt is not a failure.** A missing `Delivered` does not mean the message failed. DTN
  delivery can take hours, and the receipt may wait on the far side of a partition (DESIGN §5.4).
  Show the message as "sent" (queued) until `Delivered` arrives.
- **Only opened messages reach the app.** A DM sealed with a key the node cannot match (no
  key for the sender yet, and no shared channel key) is dropped on the node. So the app only
  ever sees plaintext the node could decrypt.
- **Contact.ed25519_pub** is only filled for keys pinned from an Ed25519 key since the daemon
  started. Keys learned over IDENT give only `x25519_pub`.

### Error codes

| Code | Name | Meaning |
|---|---|---|
| 1 | `BAD_FRAME` | bad length, or an undecodable protobuf |
| 2 | `BAD_VERSION` | frame version or `Hello.protocol_version` not 1. The link is closed. |
| 3 | `UNKNOWN_REQUEST` | no request this node knows (newer app) |
| 4 | `NEED_HELLO` | a request before `Hello` |
| 5 | `BAD_ARGUMENT` | e.g. dest 0, broadcast or self; empty text; missing position |
| 6 | `TOO_LONG` | text over `max_text_bytes` |
| 7 | `RATE_LIMITED` | SOS restarted within a minute |
| 8 | `NOT_FOUND` | `SosAck` for a node we hold no SOS from |
| 9 | `KEY_REJECTED` | the key does not hash to the ID, is low-order, or the peer table is full of pinned keys |
| 10 | `SEND_FAILED` | the router refused the message |
| 11 | `TOO_MANY_CLIENTS` | a 5th connection. Sent, then the link is closed. |
| 12 | `NO_IDENTITY` | the operation needs an Ed25519 identity (`SetName` on a legacy node) |
| 13 | `CHANNEL_LIMIT` | `AddChannel`: the node already holds the most channels it can (8) |
| 14 | `BAD_PIN` | `Hello`: the `pin_proof` is wrong, malformed or reused. Ask for a new challenge. |

## 5. No client connected: the event queue

While no client has completed `Hello`, the node holds these events in memory: `TextMessage`,
`Delivered`, `SosAlert`, `SosAckReceived`, `PeerIdent` and `KeyChange`. `Neighbor` is not held,
because it is only useful live.

- **Capacity:** at most 64 events. When the queue is full, the oldest non-SOS event is dropped.
  SOS alerts are dropped last.
- **Replay:** the first client to send `Hello` gets `NodeInfo`, then every held event in order, each
  with `replayed = true`. The queue then empties.
- **Several clients:** live events go to every connected client that has sent `Hello`. Only the
  first client to connect after a quiet period gets the replay.
- **Lifetime:** the queue lives in RAM, so a daemon restart loses it. The radio side still holds
  undelivered DMs in its own store-carry-forward queue.

**For the app:** de-duplicate by (`src`, `msg_id`), since a replayed message may already be on
screen after a reconnect. Show replayed SOS alerts prominently. They may be hours old, and their
`seq` and position say how stale they are.

## 6. A session

```
app                                   node
 |-- Hello{v=1, "GhostWave iOS"} ----->|
 |<----------------- NodeInfo ---------|  (req_id echoed)
 |<----- TextMessage{replayed} --------|  held while no app was connected
 |-- AddContact{id, ed25519, "Bob"} -->|
 |<-------------------- Ok ------------|
 |-- SetKnownPosition{bob, pos} ------>|
 |<-------------------- Ok ------------|
 |-- SendText{bob, "hi", cmid 7} ----->|
 |<------- SendQueued{msg_id M} -------|
 |                 ...                 |  radio
 |<-- Delivered{bob, M, cmid 7} -------|
 |<---- SosAlert{src, pos, text} ------|
 |-- SosAck{src} --------------------->|
 |<-------------------- Ok ------------|
```

Test vectors are byte-exact frames checked by `firmware/tests/test_client_proto.cpp`:

| Message | Frame (hex) |
|---|---|
| `ToRadio{req_id 1, Hello{1, "app"}}` | `94c30c0001 0801 5207 0801 1203 617070` |
| `ToRadio{req_id 2, SendText{a1b2c3d4, "hi", 42}}` | `94c3100001 0802 5a0b 0dd4c3b2a1 12026869 182a` |
| `FromRadio{Delivered{a1b2c3d4, 01020304, 42}}` | `94c30f0001 620c 0dd4c3b2a1 1504030201 182a` |
| `ToRadio{req_id 3, SendChannelText{"ops", "hi", 7}}` (1.1) | `94c3110001 0803 aa010b 0a036f7073 12026869 1807` |

PIN proof vector: PIN `424242`, `nonce` = bytes 00..0f, `client_nonce` = bytes 10..1f gives
`5e5862bce3b4059e23916b5f749966ec2429362592017600dab003d8da215319`.

## 7. Security

- **PIN on TCP (1.2):** a link bound to anything but loopback requires a PIN. `ghostwaved` makes a
  6-digit one on first use, prints it at start and keeps it in `<key file>.pin` (mode 600).
  `--client-pin PIN` (4–16 digits) sets one, and also turns the check on for loopback, which otherwise
  has none: `--client-tcp` binds to 127.0.0.1 unless a host is named.
- **Handshake:**
  1. The app sends `Hello`. The node answers `PinChallenge{nonce}`, not `NodeInfo`.
  2. The app sends `Hello` again with a random 16-byte `client_nonce` and `pin_proof`, the first 32 bytes
     of `HMAC-SHA-512(PIN, "ghostwave-pin-v1" || nonce || client_nonce)`. The PIN never crosses the link.
  3. The node answers `NodeInfo`, or `BAD_PIN`. Until then every other request gets `NEED_HELLO` and
     held events stay held. Each nonce works once.
- **Guessing:** wrong proofs are counted across all connections. From the third in a row the node
  answers `RATE_LIMITED` for 1 s, doubling up to 5 minutes; a right PIN resets the count. Someone
  guessing can therefore also keep the owner out for a few minutes at a time.
- **What the PIN does not do (threat model).** There is no TLS: it needs certificates that a phone can
  check for a device on a LAN address, which is not simple to do well. So on the network path:
  - All traffic after the handshake is in clear, and an eavesdropper can read DMs (as plaintext between
    app and node), channel keys and positions.
  - An eavesdropper who captures one handshake can test all 10^6 six-digit PINs offline in moments, then
    log in. A longer `--client-pin` raises that cost.
  - Someone who can alter traffic can take over a session after it is authenticated.
  - A fake node can collect a handshake to attack the PIN the same way; the app does not authenticate
    the node.

  The PIN stops other people on the network from simply connecting and driving the node. It does not make
  an untrusted network safe, so use a Wi-Fi you trust. The radio mesh's end-to-end encryption is separate.
- **Why not on BLE:** the PIN applies to TCP only. BLE already requires an encrypted, passkey-paired link
  (below), and a second PIN would add a step with no added protection.
- **BLE:** every attribute needs an encrypted, MITM-protected LE Secure Connections link, so a phone
  must pair (with the passkey the node prints on its serial console) before it can read, write or
  subscribe. See §9.
- **Keys:** private keys never cross the link. `NodeInfo` and `Contact` carry public keys only.

## 8. Notes for the Flutter app (Part 2)

- **Code generation:** `protoc --dart_out=lib/gen -I proto proto/ghostwave.proto`. Copy or submodule
  `proto/` from this repo, and pin it to the protocol version.
- **Framing:** implement the framer as a `StreamTransformer<List<int>, FromRadio>`. Skip to the magic,
  read `len`, check the version, then call `FromRadio.fromBuffer`. The Python `FrameReader` in
  `gwclient.py` is a 25-line model.
- **Request IDs:** use a counter per connection, and keep a map from `req_id` to `Completer`. Route
  `req_id == 0` to an event stream.
- **Reconnect:** on every reconnect, send `Hello` again. Then de-duplicate replayed messages (§5).
- **Text limit:** enforce `max_text_bytes` in the composer by UTF-8 byte count.
- **Contact card / QR:** carry `ghostwave:` + node ID (8 hex) + Ed25519 key (64 hex) + name. The node
  only needs ID + key (`AddContact`). The format of the QR string itself belongs to the app spec.
- **Testing:** `firmware/pi/tools/vmesh_lan.sh --lan` runs 4–6 virtual nodes whose client ports a
  phone on the same Wi-Fi can reach (README, "Client link").

## 9. BLE transport

Used by the nRF52 node firmware (`firmware/mcu`, envs `rak4631` and `t1000e`), with Bluefruit on the Adafruit nRF52
core. The bytes are the §2 frames, unchanged; BLE only carries them.

### Service

| Item | UUID | Properties |
|---|---|---|
| GhostWave service | `47570001-eea4-45e8-ac37-ff6530d92471` | primary |
| ToRadio (app → node) | `47570002-eea4-45e8-ac37-ff6530d92471` | write (with response), max 244 bytes per write |
| FromRadio (node → app) | `47570003-eea4-45e8-ac37-ff6530d92471` | notify, max 244 bytes per notification |

- **Advertising:** the advertisement carries the flags and the 128-bit service UUID, and the scan
  response carries the name, `GhostWave-<last 4 hex digits of the node ID>` (for example node
  `6e57a11b` is `GhostWave-a11b`). Scan for the service UUID, not the name. Advertising runs every 100 ms
  for 30 s after boot or a disconnect, then every 1 s.
- **One phone at a time.** While one is connected the node does not advertise.
- **Security:** both characteristics and FromRadio's CCCD need an LE Secure Connections link with MITM
  protection (`SECMODE_ENC_WITH_LESC_MITM`). A request before pairing gets ATT "insufficient
  authentication", which makes iOS and Android start pairing. The node has display-only IO
  capability. It prints a fresh random 6-digit passkey on its USB serial console
  (`BLE pairing: enter passkey 123456 on the phone`) and the phone types it in. Bonds are kept in the
  node's internal flash, so a bonded phone reconnects without a passkey. `ble clear` on the CLI forgets
  every bond. The phone must then forget the node too.

### MTU and fragmentation

- The node offers ATT MTU 247 and asks for it on connect. Phones usually negotiate it: iPhones give
  185, most Android phones 247 or 517 (capped at the node's 247). At MTU 183 or more, a notification
  holds exactly one whole frame (frames are at most 180 bytes, §2).
- **Node → app.** Each notification carries up to MTU − 3 bytes of **one** frame and never spans two
  frames. A frame bigger than MTU − 3 (only when the MTU stays below 183, e.g. 23 before an exchange)
  is sent as several notifications in order. The app appends every notification to one byte stream
  and cuts frames by the magic and length prefix (§2, the same `FrameReader` logic as TCP).
- **App → node.** The app may split a frame over several writes of up to MTU − 3 bytes each (or 244,
  whichever is smaller). The node reassembles by the length prefix too, so a write may also hold
  several frames. Use write *with* response, so writes arrive in order and a lost one is reported.
  Long (queued) writes are not supported.
- **Flow control:** the node queues up to 6 KB of notifications. If the app stops reading, newer
  frames are dropped (and counted in `ble` on the CLI) rather than blocking the radio. Up to 2 KB of
  written bytes wait to be parsed. Beyond that, a write is accepted but dropped, so pace requests by
  their replies.
- On disconnect the node drops any partial frame, queued notifications and the session (`Hello` is
  needed again).

### Session

- Same as §6: subscribe to FromRadio first (write the CCCD), then send `Hello`. Events that arrived
  while no app had sent `Hello` are replayed after `NodeInfo` (§5). On the MCU the queue holds
  **32** events, not 64. It lives in RAM, so a reboot empties it, and it only fills while BLE is on
  (`ble on`).
- `NodeInfo.firmware` reads `ghostwave-rak4631 0.1.0-dev.1` or `ghostwave-t1000e 0.1.0-dev.1` (board and
  version). The MCU firmware has
  an X25519 identity only, so `NodeInfo.legacy` is true and contacts are pinned like on a legacy
  daemon. `AddContact` takes an Ed25519 key (its node ID is derived from it) or an X25519 key plus
  node ID, and saves it in flash with the serial CLI's `peer` keys (32 at most).
- `Status.battery_pct` (0–100) is present only when the node can read its battery: the T1000-E today.
  It is absent on the RAK4631, the Heltec boards and `ghostwaved`, and it is not the same as 0 %. The
  T1000-E reading follows a voltage table and runs high while charging. Older apps ignore the field.
- `SetOwnPosition` sets the node's position from the phone's GPS. It is not saved: after a reboot the
  node falls back to the position stored with `setpos` on the CLI, if any.
- The serial CLI keeps working while a phone is connected. Both drive the same router.
