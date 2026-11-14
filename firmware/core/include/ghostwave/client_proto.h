// GhostWave client protocol: the link an app (phone, desktop, script) uses to
// drive a node (docs/CLIENT_PROTOCOL.md, schema in proto/ghostwave.proto).
//
// Frame:  0x94 0xC3 len_lo len_hi | version | protobuf ToRadio / FromRadio
//         len counts the version byte and the protobuf bytes.
//
// This is a small hand-written protobuf codec for exactly the messages in the
// schema, so the core needs no protoc / nanopb step and the MCU firmware can
// reuse it over BLE. Apps use any protobuf library with the .proto file.
// Portable: no exceptions, no I/O, no OS calls.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace gw {
namespace client {

constexpr uint8_t kMagic0 = 0x94;
constexpr uint8_t kMagic1 = 0xC3;
constexpr uint8_t kProtocolVersion = 1;
// Minor version, reported in NodeInfo.protocol_minor. 1: group channels and
// SetName. Additions only: a 1.0 client ignores what it does not know.
// 2: the PIN handshake on Hello (PinChallenge, BAD_PIN).
// 3: that handshake also agrees keys, and the link is encrypted after it.
// 5: SosCancelled.
// 6: NO_KEY: a DM is never sent unencrypted.
// 10: Traceroute / TraceResult (multi-hop).
// 11: GetSettings / SetSettings / Settings (radio and device settings).
constexpr uint32_t kProtocolMinor = 11;
constexpr size_t kFrameHeader = 4;
// Whole frame, header included. 180 fits one BLE write at ATT MTU 185 (the
// smallest a current iPhone negotiates), so a frame is never split there.
constexpr size_t kMaxFrame = 180;
constexpr size_t kMaxBody = kMaxFrame - kFrameHeader;   // version byte + protobuf
// Frames after a PIN handshake (docs/CLIENT_PROTOCOL.md §7): this version byte,
// then the sealed protobuf. TCP only, so the BLE limit above doesn't apply.
constexpr uint8_t kSecureVersion = 2;
constexpr size_t kLinkTag = 16;
constexpr size_t kMaxSecureBody = kMaxBody + kLinkTag;

enum class ErrorCode : uint32_t {
  None = 0,
  BadFrame = 1,        // bad magic, bad length or undecodable protobuf
  BadVersion = 2,      // frame version byte (or Hello.protocol_version) unsupported
  UnknownRequest = 3,  // a ToRadio with no request this node understands
  NeedHello = 4,       // request before Hello
  BadArgument = 5,
  TooLong = 6,         // text does not fit one radio frame
  RateLimited = 7,     // SOS started again within a minute
  NotFound = 8,        // e.g. SOS ack for an originator we hold no SOS from
  KeyRejected = 9,     // contact key low-order, wrong for the ID, or table full
  SendFailed = 10,
  TooManyClients = 11,
  NoIdentity = 12,     // operation needs an Ed25519 identity (legacy node)
  ChannelLimit = 13,   // AddChannel: no room for another channel
  BadPin = 14,         // Hello: wrong pin_proof
  NoKey = 15,          // SendText: no key for the peer yet; the node asked for it (1.6)
};

// A fix in 1e-7 degrees. `valid` false = no fix (field absent on the wire).
struct Pos {
  bool valid = false;
  int32_t latE7 = 0;
  int32_t lonE7 = 0;
  bool operator==(const Pos& o) const {
    return valid == o.valid && (!valid || (latE7 == o.latE7 && lonE7 == o.lonE7));
  }
};
Pos posFromDegrees(double lat, double lon, bool valid = true);
inline double latDeg(const Pos& p) { return p.latE7 * 1e-7; }
inline double lonDeg(const Pos& p) { return p.lonE7 * 1e-7; }

// Optional uint32: protobuf proto3 `optional`.
struct OptU32 {
  bool has = false;
  uint32_t v = 0;
  void set(uint32_t x) { has = true, v = x; }
  bool operator==(const OptU32& o) const { return has == o.has && (!has || v == o.v); }
};

// Optional int32 (proto3 `optional sint32`): signal readings, which are negative.
struct OptI32 {
  bool has = false;
  int32_t v = 0;
  void set(int32_t x) { has = true, v = x; }
  bool operator==(const OptI32& o) const { return has == o.has && (!has || v == o.v); }
};

using Bytes = std::vector<uint8_t>;

// Optional bool (proto3 `optional bool`): false and absent differ.
struct OptBool {
  bool has = false;
  bool v = false;
  void set(bool x) { has = true, v = x; }
  bool operator==(const OptBool& o) const { return has == o.has && (!has || v == o.v); }
};

// Settings (1.11): a request changes only the fields present; an event holds
// every value and limit the node supports (proto/ghostwave.proto).
struct SettingsMsg {
  bool hasName = false;
  Bytes name;                  // empty with hasName = clear the name
  bool hasRegion = false;
  std::string region;          // "us915" / "eu868"
  OptU32 freqKhz;
  OptI32 outputDbm;
  Bytes channelKey;            // request only: 32 bytes
  OptBool channelKeyOn;        // event: a key is set; request: false = remove it
  OptBool requireEncryption, responder;
  bool hasBlePin = false;
  std::string blePin;
  OptU32 screenOffS;           // 0 = never
  OptBool leds, buttonSos;
  OptU32 minFreqKhz, maxFreqKhz;   // report-only from here
  OptI32 minOutputDbm, maxOutputDbm;
  bool hasScreen = false, hasLeds = false, hasButton = false, buttonSosAllowed = false;
  bool restartNeeded = false;
  bool operator==(const SettingsMsg& o) const;
};

// ------------------------------------------------------------- app -> node --

enum class ToKind : uint8_t {
  None = 0,   // no request field, or only fields this version does not know
  Hello = 10,
  SendText = 11,
  AddContact = 12,
  ListContacts = 13,
  SetKnownPosition = 14,
  SosStart = 15,
  SosStop = 16,
  SosAck = 17,
  GetStatus = 18,
  GetPosition = 19,
  SetOwnPosition = 20,
  SendChannelText = 21,   // 1.1
  AddChannel = 22,
  RemoveChannel = 23,
  ListChannels = 24,
  SetName = 25,
  RequestKey = 26,        // 1.4
  SetTx = 27,             // 1.8
  LinkPing = 28,          // 1.9
  Traceroute = 29,        // 1.10
  GetSettings = 30,       // 1.11
  SetSettings = 31,       // 1.11
};

struct ToRadio {
  uint32_t reqId = 0;   // echoed in the reply; 0 = caller does not care
  ToKind kind = ToKind::None;
  // Hello
  uint32_t protocolVersion = 0;
  std::string clientName;
  Bytes clientShare, pinProof;   // Hello (1.3), answering PinChallenge
  // SendText: dest, text, clientMsgId
  uint32_t dest = 0;
  Bytes text;            // also SosStart text
  uint32_t clientMsgId = 0;
  // AddContact: nodeId, ed25519Pub (or x25519Pub for a legacy node), name
  // SetKnownPosition: nodeId, pos.   SosAck: nodeId.   SetOwnPosition: pos.
  uint32_t nodeId = 0;
  Bytes ed25519Pub, x25519Pub;
  std::string name;
  Pos pos;
  // SosStart: text, batteryPct, accuracyM
  OptU32 batteryPct, accuracyM;
  // SetTx: on
  bool on = false;
  // Traceroute: nodeId, maxHops (0 = the node's default)
  uint32_t maxHops = 0;
  // SendChannelText: channel, text, clientMsgId.  AddChannel: channel, psk.
  // RemoveChannel: channel.  SetName: name.
  std::string channel;
  Bytes psk;
  // SetSettings
  SettingsMsg settings;
};

// ------------------------------------------------------------- node -> app --

enum class FromKind : uint8_t {
  None = 0,
  NodeInfo = 10,
  Text = 11,
  Delivered = 12,
  Sos = 13,
  SosAck = 14,
  Neighbor = 15,
  Status = 16,
  Position = 17,
  Error = 18,
  Contact = 19,
  ContactsEnd = 20,
  SendQueued = 21,
  Ok = 22,
  PeerIdent = 23,
  KeyChange = 24,
  ChannelMessage = 25,   // 1.1
  Channel = 26,
  ChannelsEnd = 27,
  PinChallenge = 28,   // 1.2
  SosCancelled = 29,   // 1.5
  LinkPingResult = 30,   // 1.9
  TraceResult = 31,      // 1.10
  Settings = 32,         // 1.11
};

struct StatusInfo {
  uint32_t tx = 0, rx = 0, rxBad = 0, rxAuthFail = 0, delivered = 0, forwarded = 0, stored = 0;
  uint64_t airMs = 0;
  uint32_t storeSize = 0, neighbors = 0, sosHeld = 0;
  bool sosActive = false;
  uint32_t uptimeS = 0;
  uint32_t clients = 0, queued = 0;
  OptU32 batteryPct;   // absent: the node cannot read its battery
  bool txOff = false;  // the node is not transmitting right now
  OptI32 lastRssiDbm;  // the last good frame heard (1.7); absent: none yet
  OptU32 lastHeardS;   // seconds since then (1.7)
  bool operator==(const StatusInfo& o) const;
};

struct FromRadio {
  uint32_t reqId = 0;   // the request this answers; 0 for unsolicited events
  bool replayed = false;   // held while no client was connected, sent on Hello
  FromKind kind = FromKind::None;
  // NodeInfo: protocolVersion, nodeId, name, ed25519Pub, x25519Pub, legacy,
  //           firmware, maxTextBytes
  uint32_t protocolVersion = 0;
  uint32_t nodeId = 0;      // also Neighbor / Contact / PeerIdent / KeyChange id
  std::string name;         // also Contact / PeerIdent / KeyChange
  Bytes ed25519Pub, x25519Pub;
  bool legacy = false;
  std::string firmware;
  uint32_t maxTextBytes = 0;
  uint32_t protocolMinor = 0;           // NodeInfo (1.1)
  uint32_t maxChannelTextBytes = 0;     // NodeInfo (1.1)
  Bytes nonce, serverShare;             // PinChallenge (1.3)
  // ChannelMessage: channel, src, msgId, text, pos.  Channel: channel, psk.
  // ChannelsEnd: count
  std::string channel;
  Bytes psk;
  // Text: src, msgId, text, pos (sender position if the frame carried one)
  // Delivered: dest, msgId, clientMsgId.  SendQueued: dest, msgId, clientMsgId
  uint32_t src = 0, dest = 0, msgId = 0, clientMsgId = 0;
  Bytes text;               // also Sos text
  Pos pos;                  // also Sos / Neighbor / Position
  // Sos: src, seq, pos, accuracyM, batteryPct, text.  SosAck: src (responder), seq
  uint32_t seq = 0;
  OptU32 accuracyM, batteryPct;
  // Neighbor: nodeId, pos, isNew.  PeerIdent: nodeId, name, isNew
  bool isNew = false;
  // Contact: nodeId, name, x25519Pub, ed25519Pub (if known), pinned.
  // ContactsEnd: count
  bool pinned = false;
  // SosCancelled: src, seq, verified (signature checked against the key we hold)
  bool verified = false;
  // LinkPingResult: nodeId, answered, rssiDbm (forward), reverseDbm
  bool answered = false;
  OptI32 reverseDbm;
  // TraceResult: nodeId (the target), answered, the way out (relays, then the
  // target) and the way back (relays, then this node), each with the signal
  // that node heard the frame at. Empty when unanswered.
  std::vector<uint32_t> fwdNodes, backNodes;
  std::vector<int32_t> fwdRssi, backRssi;
  uint32_t count = 0;
  StatusInfo status;
  // Text / Delivered / Neighbor / ChannelMessage: signal of the frame that
  // carried it, as this node heard it (the last hop). 1.7; absent on older nodes.
  OptI32 rssiDbm;
  // Settings (1.11)
  SettingsMsg settings;
  // Error
  ErrorCode error = ErrorCode::None;
  std::string detail;
};

// ------------------------------------------------------------------ codec --

// Protobuf bytes only (no frame header). Decode: false on malformed input;
// unknown fields are skipped, an unknown request leaves kind None.
bool encodeTo(const ToRadio& m, Bytes& out);
bool decodeTo(const uint8_t* p, size_t n, ToRadio& m);
bool encodeFrom(const FromRadio& m, Bytes& out);
bool decodeFrom(const uint8_t* p, size_t n, FromRadio& m);

// Whole frames. Appends to `out`; false (out unchanged) if the body would
// exceed kMaxBody.
bool frameTo(const ToRadio& m, Bytes& out);
bool frameFrom(const FromRadio& m, Bytes& out);
// Wraps an already-encoded protobuf body.
bool frame(const uint8_t* pb, size_t n, Bytes& out, uint8_t version = kProtocolVersion);

// Reassembles frames from a byte stream (TCP, serial, BLE writes). Garbage
// before a magic is skipped; a header with a bad length is reported once and
// skipped byte by byte until the next magic.
class FrameReader {
 public:
  enum class Result { None, Frame, BadLength };
  void push(const uint8_t* p, size_t n);
  // Frame: `version` and `body` (protobuf bytes, version stripped) are set.
  Result next(uint8_t& version, Bytes& body);
  size_t buffered() const { return buf_.size(); }
  size_t skipped() const { return skipped_; }

 private:
  Bytes buf_;
  size_t skipped_ = 0;
};

}  // namespace client
}  // namespace gw
