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
| 2 | the PIN handshake on `Hello` (`PinChallenge`, `Hello.pin_proof`, error `BAD_PIN`) (§7), replaced by 3 |
| 3 | that handshake also agrees keys, and the link is encrypted after it (`PinChallenge.server_share`, `Hello.client_share`, sealed frames with version byte 2) (§7). Not compatible with minor 2: both ends must be updated. |
| 11 | `GetSettings` (30), `SetSettings` (31) and `Settings` (32): the node's radio and device settings from the app: name, region, frequency, output power, channel key, require-encryption, SOS responder, Bluetooth PIN, screen timeout, status LEDs and button SOS, with the board's limits and what it has. A request changes all its fields or none (`BAD_ARGUMENT` names the field). Nodes without the hooks (ghostwaved) answer `UNKNOWN_REQUEST`. |
| 10 | `Traceroute` (29) and `TraceResult` (31): trace the path to any node through relays, both ways, with each node's own signal reading (docs/TRACEROUTE.md). `max_hops` 1–8 (0 = 5). `RATE_LIMITED` while one is out or within 30 s; `BAD_ARGUMENT` for more than 8 hops. |
| 9 | `LinkPing` (28) and `LinkPingResult` (30): ping a node heard directly and measure the link both ways (docs/TRACEROUTE.md). `NOT_FOUND` if not heard directly, `RATE_LIMITED` while one is out or within 5 s. |
| 8 | `SetTx` (27): turn the node's transmitter on or off from the app, saved, as `tx on`/`tx off`. Nodes without a transmit switch (ghostwaved) answer `UNKNOWN_REQUEST`. |
| 7 | signal strength: `rssi_dbm` on `TextMessage`, `Delivered`, `Neighbor` and `ChannelMessage`; `Status.last_rssi_dbm` and `last_heard_s` |
| 1 | group channels (`SendChannelText`, `AddChannel`, `RemoveChannel`, `ListChannels`, `ChannelMessage`, `Channel`, `ChannelsEnd`, `NodeInfo.max_channel_text_bytes`, error `CHANNEL_LIMIT`) and `SetName` |

## 1. Transports

| Transport | Status | Notes |
|---|---|---|
| TCP | done (`ghostwaved`) | Off by default. `--client-tcp 4403` listens on 127.0.0.1:4403. A host must be named explicitly to listen anywhere else (see §7). Up to 4 clients at once. |
| BLE | done (nRF52 boards; ESP32 boards from dev.10, untested) | A GhostWave GATT service: the app writes frames to ToRadio, the node notifies on FromRadio. The same frames, unchanged. Pairing required. See §9. The same service and pairing on both. |
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
- **Size limit:** a whole frame is at most **180 bytes** (`kMaxFrame`), so `len` ≤ 176 (a sealed TCP frame, §7, may be 16 bytes longer). 180 bytes fits
  one BLE write or notification at ATT MTU 185, the smallest a current iPhone negotiates. On BLE every
  frame is then a single write, with no reassembly. The length prefix still makes the stream
  self-delimiting if a transport splits it.
- **Bad length:** if `len` is 0 or over 192, the receiver reports `Error{BAD_FRAME}`. It then drops the
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
  `ghostwaved` and the nRF52 firmware keep them across restarts (`<key file>.channels`, and
  `/gw/channels` in internal flash). Share one as text or a QR code:
  `ghostwave-ch:<name, percent-encoded>:<psk, 64 hex>`. Anyone with it can read and write the
  channel. An `AddChannel` with a name already in use under another key, or a key already joined
  under another name, gets `BAD_ARGUMENT`.
- **Settings (1.11).** `GetSettings` answers with a `Settings` event: every value the board
  supports, its limits (`min/max_freq_khz` for the region, `min/max_output_dbm` at the antenna
  port) and what it has (`screen_fitted`, `leds_fitted`, `button_fitted`, `button_sos_allowed`).
  `SetSettings` carries the same message with only the fields to change; each does exactly what
  its console command does, and all are saved. `channel_key` is set-only and never reported;
  `channel_key_on = false` removes the key. Region, frequency, responder, require-encryption,
  removing the key and a new PIN take effect after a restart, which `restart_needed` reports.
  Screen timeout, LEDs, button SOS, power, name and a new key apply at once. The whole request is
  checked before anything changes; if storage fails part-way the reply is `SEND_FAILED`.
- **SetTx (1.8)** turns the node's transmitter on or off and saves it, exactly like the `tx on` /
  `tx off` console command. A fresh board listens only until this. The app asks the user to check the
  antenna and region first. `Status.tx_off` shows the result. If the switch flips but cannot be saved,
  the reply is `SEND_FAILED`.
- **RequestKey (1.4)** asks a node in radio range for its signed IDENT now, instead of waiting for
  the node's own request (DESIGN §4.5). Beacons carry no key and a node ID is only a hash, so a node
  that was only heard can't be sent a sealed DM: an app should hold a message for it until
  `PeerIdent` arrives. The reply is `Ok`, which means asked, not answered. The peer may be out of
  range or never reply. `Ok` also means the key is already held (see `ListContacts`). Asking the
  same node again within 30 s gets `RATE_LIMITED`, and `NO_IDENTITY` means this node has no signing
  key to ask with.
- **SetName** changes the IDENT name (`ghostwaved` keeps it across restarts). Nodes without an
  Ed25519 identity, such as the MCU firmware today, answer `NO_IDENTITY`. Peers see it as
  `PeerIdent{is_new = false}`. A new `Hello` returns it in `NodeInfo.name`.

### Node → app (`FromRadio`)

| # | Event | Fields | When |
|---|---|---|---|
| 10 | `NodeInfo` | `protocol_version`, `node_id`, `name`, `ed25519_pub`, `x25519_pub`, `legacy`, `firmware`, `max_text_bytes` | reply to `Hello` |
| 11 | `TextMessage` | `src`, `msg_id`, `text`, `rssi_dbm` (1.7) | a DM for us arrived |
| 12 | `Delivered` | `dest`, `msg_id`, `client_msg_id`, `rssi_dbm` (1.7) | end-to-end receipt for our DM |
| 13 | `SosAlert` | `src`, `seq`, `pos`, `accuracy_m`, `battery_pct`, `text` | a new SOS, or a newer seq of one already held |
| 14 | `SosAckReceived` | `responder`, `seq` | someone acknowledged our SOS |
| 15 | `Neighbor` | `node_id`, `pos`, `is_new`, `rssi_dbm` (1.7) | a neighbor's beacon (live only, not queued) |
| 16 | `Status` | counters, `store_size`, `neighbors`, `sos_held`, `sos_active`, `uptime_s`, `clients`, `queued`, `battery_pct`, `tx_off`, `last_rssi_dbm` + `last_heard_s` (1.7) | reply to `GetStatus` |
| 17 | `OwnPosition` | `pos` | reply to `GetPosition` |
| 18 | `Error` | `code`, `detail` | a request failed, or the stream is bad |
| 19 | `Contact` | `node_id`, `name`, `x25519_pub`, `ed25519_pub`, `pinned` | reply to `ListContacts` |
| 20 | `ContactsEnd` | `count` | ends `ListContacts` |
| 21 | `SendQueued` | `dest`, `msg_id`, `client_msg_id` | reply to `SendText` |
| 22 | `Ok` | none | success with no data |
| 29 | `SosCancelled` (1.5) | `src`, `seq`, `verified` | the source ended its SOS. `verified`: signature checked and the alert dropped; false: no key to check, the alert stays |
| 23 | `PeerIdent` | `node_id`, `name`, `is_new`, `ed25519_pub` (1.4) | a verified IDENT taught a new key, or a new name |
| 24 | `KeyChange` | `node_id`, `ed25519_pub`, `name` | a signed IDENT carries a different key (DESIGN §9.2). Warn the user. The node keeps the old key. |
| 25 | `ChannelMessage` (1.1) | `channel` (name), `src`, `msg_id`, `text`, `rssi_dbm` (1.7) | a group channel message arrived (queued like `TextMessage`) |
| 26 | `Channel` (1.1) | `name`, `psk` | reply to `ListChannels` (the key lets the app share the channel) |
| 27 | `ChannelsEnd` (1.1) | `count` | ends `ListChannels` |
| 28 | `PinChallenge` (1.2) | `nonce` (16 bytes) | reply to `Hello` on a link that needs a PIN (§7) |

`NodeInfo` (1.1) also carries `protocol_minor` and `max_channel_text_bytes`.

Notes on the events:

- **Signal (1.7):** `rssi_dbm` (`optional sint32`, whole dBm) is how strongly this node heard the
  frame that carried the event: the **last hop**, not the whole path. A relayed DM shows the relay's
  signal. On a `Delivered` it is the frame that carried the receipt. Absent from older nodes and from
  events not caused by a received frame. `Status.last_rssi_dbm` is the last good frame of any kind,
  `last_heard_s` seconds ago.

- **Matching receipts:** match `Delivered` to the UI message by `client_msg_id`, which the app chose.
  `msg_id` also works. A receipt can arrive more than once, so treat it as idempotent.
- **No receipt is not a failure.** A missing `Delivered` does not mean the message failed. DTN
  delivery can take hours, and the receipt may wait on the far side of a partition (DESIGN §5.4).
  Show the message as "sent" (queued) until `Delivered` arrives.
- **Only opened messages reach the app.** A DM sealed with a key the node cannot match (no
  key for the sender yet, and no shared channel key) is dropped on the node. So the app only
  ever sees plaintext the node could decrypt.
- **Contact.ed25519_pub** is filled for keys pinned from an Ed25519 key since the daemon started
  and, from 1.4, for keys learned from a signed IDENT since then. Otherwise only `x25519_pub` is set.

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
| 15 | `NO_KEY` | (1.6) `SendText` to a node we hold no key for, with no channel key: nothing is sent, because a DM is never sent unencrypted. The node asks for the key; retry once it is learned |

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

Encrypted-link vector: PIN `424242`, `nonce` = bytes 00..0f, node secret = bytes 20..3f, client secret = bytes 40..5f:

| Value | Hex |
|---|---|
| `server_share` | `38bf4429b49432f20f593d21ee96447c298460e41229b556954b9ed5fd9c607f` |
| `client_share` | `2a9bc7b16628c651f031472d94e225e28c6588bcb734af4098518b4019159274` |
| client-to-node key | `a0e4a8cb23d66cd1af1bd5994bed4459d222f81cca23aa512599386ef826fb72` |
| node-to-client key | `3bca5414128da4100632f07dbbdfba67910e4f9c5c9f6dcea0f7ab830a8abc3e` |
| `pin_proof` | `686c345c320e4de70c9fa8789b5735c6b5119ad7f68c23aa334074997e0b89b7` |
| `hello` sealed with the client-to-node key, counter 1 | `cf671d1055de9274ad90eb49f9ef026827366b7a89` |

## 7. Security

- **PIN on TCP (1.3):** a link bound to anything but loopback requires a PIN. `ghostwaved` makes a
  6-digit one on first use, prints it at start and keeps it in `<key file>.pin` (mode 600).
  `--client-pin PIN` (4–16 digits) sets one, and also turns the check on for loopback, which otherwise
  has none: `--client-tcp` binds to 127.0.0.1 unless a host is named.
- **Handshake:** a balanced PAKE over X25519, shaped like CPace. The PIN never crosses the link.
  1. The app sends `Hello`. The node picks a 16-byte `nonce` and a random secret `a`, and answers
     `PinChallenge{nonce, server_share}`, not `NodeInfo`. Here
     `G = Elligator2(SHA-512("ghostwave-pake-v1" || u8(len PIN) || PIN || nonce)[0..31])`
     (top two bits ignored) and `server_share = X25519(a, G)`.
  2. The app picks a random secret `b`, computes `client_share = X25519(b, G)` and
     `S = X25519(b, server_share)`, which must not be all zero. Then
     `okm = HMAC-SHA-512(S, "ghostwave-link-v1" || nonce || server_share || client_share)`. The first 32 bytes
     of `okm` key client-to-node frames and the last 32 key node-to-client frames.
     `pin_proof` = the first 32 bytes of `HMAC-SHA-512(okm, "ghostwave-link-confirm")`.
     The app sends `Hello{client_share, pin_proof}`, in clear, and encrypts everything after it.
  3. The node computes the same keys and compares the proof in constant time. It answers `NodeInfo`,
     sealed, or `BAD_PIN` in clear. Until then every other request gets `NEED_HELLO` and held events
     stay held. Each nonce works once. A sealed `NodeInfo` that opens is what proves the node knows the PIN.
- **Sealed frames:** the frame is `94 C3 len | 2 | ciphertext || tag`, ChaCha20-Poly1305 with no
  associated data. The 12-byte nonce is 4 zero bytes then a 64-bit little-endian counter that starts at
  0 and counts per direction, so it isn't sent. A plaintext of up to 175 bytes makes `len` at most 192,
  the one place a frame may pass 180 bytes; TCP has no MTU limit to respect. Once a link is sealed, a
  frame that fails to open, or any unsealed frame, ends the connection. A replayed or reordered frame
  fails to open.
- **The app refuses to go without it.** On TCP to anything but loopback, the app won't connect to a node
  that doesn't encrypt: it won't answer a `PinChallenge` that has no `server_share`, and it refuses a
  plain `NodeInfo`. Otherwise someone on the network could pose as a node with no PIN. After sending its
  proof, the app accepts only an `Error` in clear (such as `BAD_PIN`).
- **Guessing:** wrong proofs are counted across all connections. From the third in a row the node
  answers `RATE_LIMITED` for 1 s, doubling up to 5 minutes; a right PIN resets the count. Someone
  guessing can therefore also keep the owner out for a few minutes at a time.
- **What this protects (threat model).** On the network path:
  - An eavesdropper sees frame sizes and timing, and nothing else: not DMs, channel keys or positions.
    Each connection has new keys, so a PIN stolen later doesn't open recorded traffic.
  - A captured handshake gives nothing to test PIN guesses against. Guessing means connecting (limited
    above) or, for a fake node, getting one guess per connection from the app.
  - Someone who can alter traffic can't take over a session after the handshake. They can still cut it,
    or inject a false `BAD_PIN` during the handshake, which makes the app ask for the PIN again.
- **What it doesn't do.**
  - The security of the handshake is only as good as the PIN's secrecy: anyone who has the PIN can pose
    as this node or connect to it. It's shown at start and kept in `<key file>.pin`.
  - A node with no PIN (loopback by default) has a plain link. So does BLE at this layer, because pairing
    encrypts it.
  - Traffic inside the phone or node isn't covered: a compromised phone or Pi can read everything.
  - The handshake follows CPace's construction but isn't the CFRG draft byte for byte, and it hasn't had
    an independent review.
  - The radio mesh's end-to-end encryption is separate.
- **Why not on BLE:** the PIN applies to TCP only. BLE already requires an encrypted, passkey-paired link
  (below), and a second PIN would add a step with no added protection.
- **BLE:** every attribute needs an encrypted, passkey-paired link, so a phone must pair before it can
  read, write or subscribe. The default key is the public `654321` on every board, chosen so boards with
  no screen can be paired without a computer. A static key forces legacy pairing, not LE Secure
  Connections, so anyone in range who knows the key can pair, and someone recording a pairing could
  decrypt that link. Change it with `ble pin <6 digits>`. The mesh's end-to-end encryption is separate. See §9.
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
- **Security:** both characteristics and FromRadio's CCCD need an encrypted link with MITM protection
  (`SECMODE_ENC_WITH_MITM`, legacy pairing: see §7). A request before pairing gets ATT "insufficient
  authentication", which makes iOS and Android start pairing. The node has display-only IO
  capability. The passkey is fixed: `654321` unless changed with `ble pin` (takes effect on reboot), and the phone
  types it in. Bonds are kept in the
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
  version). A board first
  set up by this firmware has an Ed25519 identity, so `NodeInfo.legacy` is false and `SetName` works.
  One first set up by an older build keeps its X25519 identity: `NodeInfo.legacy` is true and
  `SetName` answers `NO_IDENTITY`. `AddContact` takes an Ed25519 key (its node ID is derived from it) or an X25519 key plus
  node ID, and saves it in flash with the serial CLI's `peer` keys (32 at most). The Ed25519 key that
  `ListContacts` reports is saved too (`/gw/edkeys`), for peers whose key was stored.
- `Status.battery_pct` (0–100) is present only when the node can read its battery: the T1000-E today.
  It is absent on the RAK4631, the Heltec boards and `ghostwaved`, and it is not the same as 0 %. The
  T1000-E reading follows a voltage table and runs high while charging. Older apps ignore the field.
- `Status.tx_off` is true while the node will not transmit: a fresh board until `tx on` on the serial
  console. It is false while the board's own SOS runs, because that overrides the gate. Older nodes
  never set it, so an app must not read false as proof the node transmits.
- `SetOwnPosition` sets the node's position from the phone's GPS. It is not saved: after a reboot the
  node falls back to the position stored with `setpos` on the CLI, if any.
- The serial CLI keeps working while a phone is connected. Both drive the same router.
