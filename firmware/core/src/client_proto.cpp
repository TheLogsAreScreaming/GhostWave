// GhostWave client protocol codec (docs/CLIENT_PROTOCOL.md). Field numbers
// must match proto/ghostwave.proto.
#include "ghostwave/client_proto.h"

#include <cmath>
#include <cstring>

namespace gw {
namespace client {

namespace {

enum WireType : int { kVarint = 0, kFixed64 = 1, kLen = 2, kFixed32 = 5 };

// ---------------------------------------------------------------- writer --

struct Writer {
  Bytes& b;
  void varint(uint64_t v) {
    while (v >= 0x80) {
      b.push_back(static_cast<uint8_t>(v | 0x80));
      v >>= 7;
    }
    b.push_back(static_cast<uint8_t>(v));
  }
  void tag(uint32_t f, int wt) { varint(static_cast<uint64_t>(f) << 3 | static_cast<uint32_t>(wt)); }
  // proto3: scalars at their default value are not sent
  void u32(uint32_t f, uint32_t v) {
    if (v) tag(f, kVarint), varint(v);
  }
  void u64(uint32_t f, uint64_t v) {
    if (v) tag(f, kVarint), varint(v);
  }
  void opt(uint32_t f, const OptU32& v) {
    if (v.has) tag(f, kVarint), varint(v.v);
  }
  void boolean(uint32_t f, bool v) {
    if (v) tag(f, kVarint), varint(1);
  }
  void optSint(uint32_t f, const OptI32& v) {
    if (v.has) tag(f, kVarint), varint((static_cast<uint32_t>(v.v) << 1) ^ static_cast<uint32_t>(v.v >> 31));
  }
  void sint(uint32_t f, int32_t v) {
    uint32_t z = (static_cast<uint32_t>(v) << 1) ^ static_cast<uint32_t>(v >> 31);
    if (z) tag(f, kVarint), varint(z);
  }
  void fx32(uint32_t f, uint32_t v) {
    if (!v) return;
    tag(f, kFixed32);
    for (int i = 0; i < 4; ++i) b.push_back(static_cast<uint8_t>(v >> (8 * i)));
  }
  void bytes(uint32_t f, const uint8_t* p, size_t n) {
    if (!n) return;
    tag(f, kLen);
    varint(n);
    b.insert(b.end(), p, p + n);
  }
  void bytes(uint32_t f, const Bytes& v) { bytes(f, v.data(), v.size()); }
  // Repeated scalars, packed (proto3's default encoding).
  void packedFx32(uint32_t f, const std::vector<uint32_t>& v) {
    if (v.empty()) return;
    tag(f, kLen);
    varint(4 * v.size());
    for (uint32_t x : v)
      for (int i = 0; i < 4; ++i) b.push_back(static_cast<uint8_t>(x >> (8 * i)));
  }
  void packedSint(uint32_t f, const std::vector<int32_t>& v) {
    if (v.empty()) return;
    Bytes sub;
    Writer w{sub};
    for (int32_t x : v) w.varint((static_cast<uint32_t>(x) << 1) ^ static_cast<uint32_t>(x >> 31));
    bytes(f, sub);
  }
  void str(uint32_t f, const std::string& s) { bytes(f, reinterpret_cast<const uint8_t*>(s.data()), s.size()); }
  // proto3 `optional`: sent whenever present, even at the default.
  void optBool(uint32_t f, const OptBool& v) {
    if (v.has) tag(f, kVarint), varint(v.v ? 1 : 0);
  }
  void bytesAlways(uint32_t f, const uint8_t* p, size_t n) {
    tag(f, kLen);
    varint(n);
    b.insert(b.end(), p, p + n);
  }
  // Sub-messages are always sent, even empty: presence is meaningful (oneof,
  // Position = fix).
  void msg(uint32_t f, const Bytes& sub) {
    tag(f, kLen);
    varint(sub.size());
    b.insert(b.end(), sub.begin(), sub.end());
  }
  void pos(uint32_t f, const Pos& p) {
    if (!p.valid) return;
    Bytes sub;
    Writer w{sub};
    w.sint(1, p.latE7);
    w.sint(2, p.lonE7);
    msg(f, sub);
  }
};

// ---------------------------------------------------------------- reader --

struct Reader {
  const uint8_t* p;
  const uint8_t* e;

  bool varint(uint64_t& v) {
    v = 0;
    for (int shift = 0; shift < 64; shift += 7) {
      if (p == e) return false;
      uint8_t c = *p++;
      v |= static_cast<uint64_t>(c & 0x7F) << shift;
      if (!(c & 0x80)) return true;
    }
    return false;   // more than 10 bytes
  }
  bool skip(int wt) {
    uint64_t n;
    switch (wt) {
      case kVarint: return varint(n);
      case kFixed64: n = 8; break;
      case kFixed32: n = 4; break;
      case kLen:
        if (!varint(n)) return false;
        break;
      default: return false;   // groups (3, 4) and reserved types
    }
    if (n > static_cast<uint64_t>(e - p)) return false;
    p += n;
    return true;
  }
};

// A field value handed to a message's field handler.
struct Field {
  int wt;
  uint64_t v = 0;               // varint / fixed32
  const uint8_t* data = nullptr;   // length-delimited
  size_t len = 0;

  bool u32(uint32_t& out) const {
    if (wt != kVarint) return false;
    out = static_cast<uint32_t>(v);
    return true;
  }
  bool u64(uint64_t& out) const {
    if (wt != kVarint) return false;
    out = v;
    return true;
  }
  bool opt(OptU32& out) const {
    if (wt != kVarint) return false;
    out.set(static_cast<uint32_t>(v));
    return true;
  }
  bool optSint(OptI32& out) const {
    if (wt != kVarint) return false;
    const auto z = static_cast<uint32_t>(v);
    out.set(static_cast<int32_t>((z >> 1) ^ (~(z & 1) + 1)));
    return true;
  }
  bool boolean(bool& out) const {
    if (wt != kVarint) return false;
    out = v != 0;
    return true;
  }
  bool sint(int32_t& out) const {
    if (wt != kVarint) return false;
    uint32_t z = static_cast<uint32_t>(v);
    out = static_cast<int32_t>((z >> 1) ^ (~(z & 1) + 1));
    return true;
  }
  bool fx32(uint32_t& out) const {
    if (wt != kFixed32) return false;
    out = static_cast<uint32_t>(v);
    return true;
  }
  // A repeated fixed32: packed, or one element per field.
  bool repFx32(std::vector<uint32_t>& out) const {
    if (wt == kFixed32) {
      out.push_back(static_cast<uint32_t>(v));
      return true;
    }
    if (wt != kLen || len % 4) return false;
    for (size_t i = 0; i < len; i += 4)
      out.push_back(uint32_t(data[i]) | (uint32_t(data[i + 1]) << 8) | (uint32_t(data[i + 2]) << 16) |
                    (uint32_t(data[i + 3]) << 24));
    return true;
  }
  // A repeated sint32: packed, or one element per field.
  bool repSint(std::vector<int32_t>& out) const {
    auto unzig = [](uint64_t z64) {
      const auto z = static_cast<uint32_t>(z64);
      return static_cast<int32_t>((z >> 1) ^ (~(z & 1) + 1));
    };
    if (wt == kVarint) {
      out.push_back(unzig(v));
      return true;
    }
    if (wt != kLen) return false;
    Reader r{data, data + len};
    while (r.p != r.e) {
      uint64_t z;
      if (!r.varint(z)) return false;
      out.push_back(unzig(z));
    }
    return true;
  }
  bool optBool(OptBool& out) const {
    if (wt != kVarint) return false;
    out.set(v != 0);
    return true;
  }
  bool bytes(Bytes& out) const {
    if (wt != kLen) return false;
    out.assign(data, data + len);
    return true;
  }
  bool str(std::string& out) const {
    if (wt != kLen) return false;
    out.assign(reinterpret_cast<const char*>(data), len);
    return true;
  }
};

// Calls on(fieldNumber, Field) for each field; `on` returns 1 if handled, 0
// if unknown (skipped), -1 on a type mismatch.
template <class F>
bool parse(const uint8_t* p, size_t n, F on) {
  Reader r{p, p + n};
  while (r.p != r.e) {
    uint64_t key;
    if (!r.varint(key)) return false;
    uint32_t f = static_cast<uint32_t>(key >> 3);
    int wt = static_cast<int>(key & 7);
    if (f == 0 || key >> 32) return false;
    Field fv{wt};
    if (wt == kVarint) {
      if (!r.varint(fv.v)) return false;
    } else if (wt == kFixed32) {
      if (r.e - r.p < 4) return false;
      for (int i = 0; i < 4; ++i) fv.v |= static_cast<uint64_t>(r.p[i]) << (8 * i);
      r.p += 4;
    } else if (wt == kLen) {
      uint64_t len;
      if (!r.varint(len) || len > static_cast<uint64_t>(r.e - r.p)) return false;
      fv.data = r.p;
      fv.len = static_cast<size_t>(len);
      r.p += len;
    } else if (!r.skip(wt)) {
      return false;
    }
    int res = on(f, fv);
    if (res < 0) return false;
  }
  return true;
}

bool parsePos(const Field& f, Pos& out) {
  if (f.wt != kLen) return false;
  out = Pos{};
  out.valid = true;
  return parse(f.data, f.len, [&](uint32_t n, const Field& v) -> int {
    switch (n) {
      case 1: return v.sint(out.latE7) ? 1 : -1;
      case 2: return v.sint(out.lonE7) ? 1 : -1;
      default: return 0;
    }
  });
}

inline int ok(bool b) { return b ? 1 : -1; }

void writeSettings(Writer& s, const SettingsMsg& t) {
  if (t.hasName) s.bytesAlways(1, t.name.data(), t.name.size());
  if (t.hasRegion) s.bytesAlways(2, reinterpret_cast<const uint8_t*>(t.region.data()), t.region.size());
  s.opt(3, t.freqKhz);
  s.optSint(4, t.outputDbm);
  s.bytes(5, t.channelKey);
  s.optBool(6, t.channelKeyOn);
  s.optBool(7, t.requireEncryption);
  s.optBool(8, t.responder);
  if (t.hasBlePin) s.bytesAlways(9, reinterpret_cast<const uint8_t*>(t.blePin.data()), t.blePin.size());
  s.opt(10, t.screenOffS);
  s.optBool(11, t.leds);
  s.optBool(12, t.buttonSos);
  s.opt(20, t.minFreqKhz);
  s.opt(21, t.maxFreqKhz);
  s.optSint(22, t.minOutputDbm);
  s.optSint(23, t.maxOutputDbm);
  s.boolean(24, t.hasScreen);
  s.boolean(25, t.hasLeds);
  s.boolean(26, t.hasButton);
  s.boolean(27, t.buttonSosAllowed);
  s.boolean(28, t.restartNeeded);
}

int readSettings(uint32_t g, const Field& x, SettingsMsg& t) {
  switch (g) {
    case 1: t.hasName = true; return ok(x.bytes(t.name));
    case 2: t.hasRegion = true; return ok(x.str(t.region));
    case 3: return ok(x.opt(t.freqKhz));
    case 4: return ok(x.optSint(t.outputDbm));
    case 5: return ok(x.bytes(t.channelKey));
    case 6: return ok(x.optBool(t.channelKeyOn));
    case 7: return ok(x.optBool(t.requireEncryption));
    case 8: return ok(x.optBool(t.responder));
    case 9: t.hasBlePin = true; return ok(x.str(t.blePin));
    case 10: return ok(x.opt(t.screenOffS));
    case 11: return ok(x.optBool(t.leds));
    case 12: return ok(x.optBool(t.buttonSos));
    case 20: return ok(x.opt(t.minFreqKhz));
    case 21: return ok(x.opt(t.maxFreqKhz));
    case 22: return ok(x.optSint(t.minOutputDbm));
    case 23: return ok(x.optSint(t.maxOutputDbm));
    case 24: return ok(x.boolean(t.hasScreen));
    case 25: return ok(x.boolean(t.hasLeds));
    case 26: return ok(x.boolean(t.hasButton));
    case 27: return ok(x.boolean(t.buttonSosAllowed));
    case 28: return ok(x.boolean(t.restartNeeded));
    default: return 0;
  }
}

}  // namespace

Pos posFromDegrees(double lat, double lon, bool valid) {
  Pos p;
  p.valid = valid;
  if (valid) {
    p.latE7 = static_cast<int32_t>(std::lround(lat * 1e7));
    p.lonE7 = static_cast<int32_t>(std::lround(lon * 1e7));
  }
  return p;
}

bool SettingsMsg::operator==(const SettingsMsg& o) const {
  return hasName == o.hasName && name == o.name && hasRegion == o.hasRegion && region == o.region &&
         freqKhz == o.freqKhz && outputDbm == o.outputDbm && channelKey == o.channelKey &&
         channelKeyOn == o.channelKeyOn && requireEncryption == o.requireEncryption && responder == o.responder &&
         hasBlePin == o.hasBlePin && blePin == o.blePin && screenOffS == o.screenOffS && leds == o.leds &&
         buttonSos == o.buttonSos && minFreqKhz == o.minFreqKhz && maxFreqKhz == o.maxFreqKhz &&
         minOutputDbm == o.minOutputDbm && maxOutputDbm == o.maxOutputDbm && hasScreen == o.hasScreen &&
         hasLeds == o.hasLeds && hasButton == o.hasButton && buttonSosAllowed == o.buttonSosAllowed &&
         restartNeeded == o.restartNeeded;
}

bool StatusInfo::operator==(const StatusInfo& o) const {
  return tx == o.tx && rx == o.rx && rxBad == o.rxBad && rxAuthFail == o.rxAuthFail &&
         delivered == o.delivered && forwarded == o.forwarded && stored == o.stored &&
         airMs == o.airMs && storeSize == o.storeSize && neighbors == o.neighbors &&
         sosHeld == o.sosHeld && sosActive == o.sosActive && uptimeS == o.uptimeS &&
         clients == o.clients && queued == o.queued && batteryPct == o.batteryPct && txOff == o.txOff &&
         lastRssiDbm == o.lastRssiDbm && lastHeardS == o.lastHeardS;
}

// ------------------------------------------------------------- ToRadio --

bool encodeTo(const ToRadio& m, Bytes& out) {
  out.clear();
  Writer w{out};
  w.u32(1, m.reqId);
  Bytes sub;
  Writer s{sub};
  switch (m.kind) {
    case ToKind::None: return true;
    case ToKind::Hello:
      s.u32(1, m.protocolVersion);
      s.str(2, m.clientName);
      s.bytes(3, m.clientShare);
      s.bytes(4, m.pinProof);
      break;
    case ToKind::SendText:
      s.fx32(1, m.dest);
      s.bytes(2, m.text);
      s.u32(3, m.clientMsgId);
      break;
    case ToKind::AddContact:
      s.fx32(1, m.nodeId);
      s.bytes(2, m.ed25519Pub);
      s.bytes(3, m.x25519Pub);
      s.str(4, m.name);
      break;
    case ToKind::SetKnownPosition:
      s.fx32(1, m.nodeId);
      s.pos(2, m.pos);
      break;
    case ToKind::SosStart:
      s.bytes(1, m.text);
      s.opt(2, m.batteryPct);
      s.opt(3, m.accuracyM);
      break;
    case ToKind::SosAck: s.fx32(1, m.nodeId); break;
    case ToKind::SetOwnPosition: s.pos(1, m.pos); break;
    case ToKind::SendChannelText:
      s.str(1, m.channel);
      s.bytes(2, m.text);
      s.u32(3, m.clientMsgId);
      break;
    case ToKind::AddChannel:
      s.str(1, m.channel);
      s.bytes(2, m.psk);
      break;
    case ToKind::RemoveChannel: s.str(1, m.channel); break;
    case ToKind::SetName: s.str(1, m.name); break;
    case ToKind::RequestKey: s.fx32(1, m.nodeId); break;
    case ToKind::SetTx: s.boolean(1, m.on); break;
    case ToKind::LinkPing: s.fx32(1, m.nodeId); break;
    case ToKind::Traceroute:
      s.fx32(1, m.nodeId);
      s.u32(2, m.maxHops);
      break;
    case ToKind::SetSettings: writeSettings(s, m.settings); break;
    case ToKind::GetSettings:
    case ToKind::ListChannels:
    case ToKind::ListContacts:
    case ToKind::SosStop:
    case ToKind::GetStatus:
    case ToKind::GetPosition: break;
    default: return false;
  }
  w.msg(static_cast<uint32_t>(m.kind), sub);
  return true;
}

bool decodeTo(const uint8_t* p, size_t n, ToRadio& m) {
  m = ToRadio{};
  return parse(p, n, [&](uint32_t f, const Field& v) -> int {
    if (f == 1) return ok(v.u32(m.reqId));
    if (f < 10 || f > static_cast<uint32_t>(ToKind::SetSettings)) return 0;   // newer requests: ignored
    if (v.wt != kLen) return -1;
    ToKind k = static_cast<ToKind>(f);
    m.kind = k;
    return ok(parse(v.data, v.len, [&](uint32_t g, const Field& x) -> int {
      switch (k) {
        case ToKind::Hello:
          if (g == 1) return ok(x.u32(m.protocolVersion));
          if (g == 2) return ok(x.str(m.clientName));
          if (g == 3) return ok(x.bytes(m.clientShare));
          if (g == 4) return ok(x.bytes(m.pinProof));
          return 0;
        case ToKind::SendText:
          if (g == 1) return ok(x.fx32(m.dest));
          if (g == 2) return ok(x.bytes(m.text));
          if (g == 3) return ok(x.u32(m.clientMsgId));
          return 0;
        case ToKind::AddContact:
          if (g == 1) return ok(x.fx32(m.nodeId));
          if (g == 2) return ok(x.bytes(m.ed25519Pub));
          if (g == 3) return ok(x.bytes(m.x25519Pub));
          if (g == 4) return ok(x.str(m.name));
          return 0;
        case ToKind::SetKnownPosition:
          if (g == 1) return ok(x.fx32(m.nodeId));
          if (g == 2) return ok(parsePos(x, m.pos));
          return 0;
        case ToKind::SosStart:
          if (g == 1) return ok(x.bytes(m.text));
          if (g == 2) return ok(x.opt(m.batteryPct));
          if (g == 3) return ok(x.opt(m.accuracyM));
          return 0;
        case ToKind::SosAck:
          if (g == 1) return ok(x.fx32(m.nodeId));
          return 0;
        case ToKind::SetOwnPosition:
          if (g == 1) return ok(parsePos(x, m.pos));
          return 0;
        case ToKind::SendChannelText:
          if (g == 1) return ok(x.str(m.channel));
          if (g == 2) return ok(x.bytes(m.text));
          if (g == 3) return ok(x.u32(m.clientMsgId));
          return 0;
        case ToKind::AddChannel:
          if (g == 1) return ok(x.str(m.channel));
          if (g == 2) return ok(x.bytes(m.psk));
          return 0;
        case ToKind::RemoveChannel:
          if (g == 1) return ok(x.str(m.channel));
          return 0;
        case ToKind::SetName:
          if (g == 1) return ok(x.str(m.name));
          return 0;
        case ToKind::RequestKey:
          if (g == 1) return ok(x.fx32(m.nodeId));
          return 0;
        case ToKind::SetTx:
          if (g == 1) return ok(x.boolean(m.on));
          return 0;
        case ToKind::LinkPing:
          if (g == 1) return ok(x.fx32(m.nodeId));
          return 0;
        case ToKind::Traceroute:
          if (g == 1) return ok(x.fx32(m.nodeId));
          if (g == 2) return ok(x.u32(m.maxHops));
          return 0;
        case ToKind::SetSettings: return readSettings(g, x, m.settings);
        default: return 0;
      }
    }));
  });
}

// ----------------------------------------------------------- FromRadio --

bool encodeFrom(const FromRadio& m, Bytes& out) {
  out.clear();
  Writer w{out};
  w.u32(1, m.reqId);
  w.boolean(2, m.replayed);
  Bytes sub;
  Writer s{sub};
  switch (m.kind) {
    case FromKind::None: return true;
    case FromKind::NodeInfo:
      s.u32(1, m.protocolVersion);
      s.fx32(2, m.nodeId);
      s.str(3, m.name);
      s.bytes(4, m.ed25519Pub);
      s.bytes(5, m.x25519Pub);
      s.boolean(6, m.legacy);
      s.str(7, m.firmware);
      s.u32(8, m.maxTextBytes);
      s.u32(9, m.protocolMinor);
      s.u32(10, m.maxChannelTextBytes);
      break;
    case FromKind::Text:
      s.fx32(1, m.src);
      s.fx32(2, m.msgId);
      s.bytes(3, m.text);
      s.pos(4, m.pos);
      s.optSint(5, m.rssiDbm);
      break;
    case FromKind::Delivered:
    case FromKind::SendQueued:
      s.fx32(1, m.dest);
      s.fx32(2, m.msgId);
      s.u32(3, m.clientMsgId);
      if (m.kind == FromKind::Delivered) s.optSint(4, m.rssiDbm);
      break;
    case FromKind::Sos:
      s.fx32(1, m.src);
      s.u32(2, m.seq);
      s.pos(3, m.pos);
      s.opt(4, m.accuracyM);
      s.opt(5, m.batteryPct);
      s.bytes(6, m.text);
      break;
    case FromKind::SosAck:
      s.fx32(1, m.src);
      s.u32(2, m.seq);
      break;
    case FromKind::SosCancelled:
      s.fx32(1, m.src);
      s.u32(2, m.seq);
      s.boolean(3, m.verified);
      break;
    case FromKind::LinkPingResult:
      s.fx32(1, m.nodeId);
      s.boolean(2, m.answered);
      s.optSint(3, m.rssiDbm);
      s.optSint(4, m.reverseDbm);
      break;
    case FromKind::TraceResult:
      s.fx32(1, m.nodeId);
      s.boolean(2, m.answered);
      s.packedFx32(3, m.fwdNodes);
      s.packedSint(4, m.fwdRssi);
      s.packedFx32(5, m.backNodes);
      s.packedSint(6, m.backRssi);
      break;
    case FromKind::Settings: writeSettings(s, m.settings); break;
    case FromKind::Neighbor:
      s.fx32(1, m.nodeId);
      s.pos(2, m.pos);
      s.boolean(3, m.isNew);
      s.optSint(4, m.rssiDbm);
      break;
    case FromKind::Status: {
      const StatusInfo& t = m.status;
      s.u32(1, t.tx);
      s.u32(2, t.rx);
      s.u32(3, t.rxBad);
      s.u32(4, t.rxAuthFail);
      s.u32(5, t.delivered);
      s.u32(6, t.forwarded);
      s.u32(7, t.stored);
      s.u64(8, t.airMs);
      s.u32(9, t.storeSize);
      s.u32(10, t.neighbors);
      s.u32(11, t.sosHeld);
      s.boolean(12, t.sosActive);
      s.u32(13, t.uptimeS);
      s.u32(14, t.clients);
      s.u32(15, t.queued);
      s.opt(16, t.batteryPct);
      s.boolean(17, t.txOff);
      s.optSint(18, t.lastRssiDbm);
      s.opt(19, t.lastHeardS);
      break;
    }
    case FromKind::Position: s.pos(1, m.pos); break;
    case FromKind::Error:
      s.u32(1, static_cast<uint32_t>(m.error));
      s.str(2, m.detail);
      break;
    case FromKind::Contact:
      s.fx32(1, m.nodeId);
      s.str(2, m.name);
      s.bytes(3, m.x25519Pub);
      s.bytes(4, m.ed25519Pub);
      s.boolean(5, m.pinned);
      break;
    case FromKind::ContactsEnd: s.u32(1, m.count); break;
    case FromKind::Ok: break;
    case FromKind::PeerIdent:
      s.fx32(1, m.nodeId);
      s.str(2, m.name);
      s.boolean(3, m.isNew);
      s.bytes(4, m.ed25519Pub);
      break;
    case FromKind::KeyChange:
      s.fx32(1, m.nodeId);
      s.bytes(2, m.ed25519Pub);
      s.str(3, m.name);
      break;
    case FromKind::ChannelMessage:
      s.str(1, m.channel);
      s.fx32(2, m.src);
      s.fx32(3, m.msgId);
      s.bytes(4, m.text);
      s.pos(5, m.pos);
      s.optSint(6, m.rssiDbm);
      break;
    case FromKind::Channel:
      s.str(1, m.channel);
      s.bytes(2, m.psk);
      break;
    case FromKind::ChannelsEnd: s.u32(1, m.count); break;
    case FromKind::PinChallenge: s.bytes(1, m.nonce); s.bytes(2, m.serverShare); break;
    default: return false;
  }
  w.msg(static_cast<uint32_t>(m.kind), sub);
  return true;
}

bool decodeFrom(const uint8_t* p, size_t n, FromRadio& m) {
  m = FromRadio{};
  return parse(p, n, [&](uint32_t f, const Field& v) -> int {
    if (f == 1) return ok(v.u32(m.reqId));
    if (f == 2) return ok(v.boolean(m.replayed));
    if (f < 10 || f > static_cast<uint32_t>(FromKind::Settings)) return 0;   // newer events: ignored
    if (v.wt != kLen) return -1;
    FromKind k = static_cast<FromKind>(f);
    m.kind = k;
    StatusInfo& t = m.status;
    return ok(parse(v.data, v.len, [&](uint32_t g, const Field& x) -> int {
      switch (k) {
        case FromKind::NodeInfo:
          switch (g) {
            case 1: return ok(x.u32(m.protocolVersion));
            case 2: return ok(x.fx32(m.nodeId));
            case 3: return ok(x.str(m.name));
            case 4: return ok(x.bytes(m.ed25519Pub));
            case 5: return ok(x.bytes(m.x25519Pub));
            case 6: return ok(x.boolean(m.legacy));
            case 7: return ok(x.str(m.firmware));
            case 8: return ok(x.u32(m.maxTextBytes));
            case 9: return ok(x.u32(m.protocolMinor));
            case 10: return ok(x.u32(m.maxChannelTextBytes));
          }
          return 0;
        case FromKind::Text:
          switch (g) {
            case 1: return ok(x.fx32(m.src));
            case 2: return ok(x.fx32(m.msgId));
            case 3: return ok(x.bytes(m.text));
            case 4: return ok(parsePos(x, m.pos));
            case 5: return ok(x.optSint(m.rssiDbm));
          }
          return 0;
        case FromKind::Delivered:
        case FromKind::SendQueued:
          switch (g) {
            case 1: return ok(x.fx32(m.dest));
            case 2: return ok(x.fx32(m.msgId));
            case 3: return ok(x.u32(m.clientMsgId));
            case 4: return k == FromKind::Delivered ? ok(x.optSint(m.rssiDbm)) : 0;
          }
          return 0;
        case FromKind::Sos:
          switch (g) {
            case 1: return ok(x.fx32(m.src));
            case 2: return ok(x.u32(m.seq));
            case 3: return ok(parsePos(x, m.pos));
            case 4: return ok(x.opt(m.accuracyM));
            case 5: return ok(x.opt(m.batteryPct));
            case 6: return ok(x.bytes(m.text));
          }
          return 0;
        case FromKind::SosAck:
          if (g == 1) return ok(x.fx32(m.src));
          if (g == 2) return ok(x.u32(m.seq));
          return 0;
        case FromKind::SosCancelled:
          if (g == 1) return ok(x.fx32(m.src));
          if (g == 2) return ok(x.u32(m.seq));
          if (g == 3) return ok(x.boolean(m.verified));
          return 0;
        case FromKind::LinkPingResult:
          if (g == 1) return ok(x.fx32(m.nodeId));
          if (g == 2) return ok(x.boolean(m.answered));
          if (g == 3) return ok(x.optSint(m.rssiDbm));
          if (g == 4) return ok(x.optSint(m.reverseDbm));
          return 0;
        case FromKind::TraceResult:
          switch (g) {
            case 1: return ok(x.fx32(m.nodeId));
            case 2: return ok(x.boolean(m.answered));
            case 3: return ok(x.repFx32(m.fwdNodes));
            case 4: return ok(x.repSint(m.fwdRssi));
            case 5: return ok(x.repFx32(m.backNodes));
            case 6: return ok(x.repSint(m.backRssi));
          }
          return 0;
        case FromKind::Settings: return readSettings(g, x, m.settings);
        case FromKind::Neighbor:
          if (g == 1) return ok(x.fx32(m.nodeId));
          if (g == 2) return ok(parsePos(x, m.pos));
          if (g == 3) return ok(x.boolean(m.isNew));
          if (g == 4) return ok(x.optSint(m.rssiDbm));
          return 0;
        case FromKind::Status:
          switch (g) {
            case 1: return ok(x.u32(t.tx));
            case 2: return ok(x.u32(t.rx));
            case 3: return ok(x.u32(t.rxBad));
            case 4: return ok(x.u32(t.rxAuthFail));
            case 5: return ok(x.u32(t.delivered));
            case 6: return ok(x.u32(t.forwarded));
            case 7: return ok(x.u32(t.stored));
            case 8: return ok(x.u64(t.airMs));
            case 9: return ok(x.u32(t.storeSize));
            case 10: return ok(x.u32(t.neighbors));
            case 11: return ok(x.u32(t.sosHeld));
            case 12: return ok(x.boolean(t.sosActive));
            case 13: return ok(x.u32(t.uptimeS));
            case 14: return ok(x.u32(t.clients));
            case 15: return ok(x.u32(t.queued));
            case 16: return ok(x.opt(t.batteryPct));
            case 17: return ok(x.boolean(t.txOff));
            case 18: return ok(x.optSint(t.lastRssiDbm));
            case 19: return ok(x.opt(t.lastHeardS));
          }
          return 0;
        case FromKind::Position:
          if (g == 1) return ok(parsePos(x, m.pos));
          return 0;
        case FromKind::Error:
          if (g == 1) {
            uint32_t c;
            if (!x.u32(c)) return -1;
            m.error = static_cast<ErrorCode>(c);
            return 1;
          }
          if (g == 2) return ok(x.str(m.detail));
          return 0;
        case FromKind::Contact:
          switch (g) {
            case 1: return ok(x.fx32(m.nodeId));
            case 2: return ok(x.str(m.name));
            case 3: return ok(x.bytes(m.x25519Pub));
            case 4: return ok(x.bytes(m.ed25519Pub));
            case 5: return ok(x.boolean(m.pinned));
          }
          return 0;
        case FromKind::ContactsEnd:
          if (g == 1) return ok(x.u32(m.count));
          return 0;
        case FromKind::PeerIdent:
          if (g == 1) return ok(x.fx32(m.nodeId));
          if (g == 2) return ok(x.str(m.name));
          if (g == 3) return ok(x.boolean(m.isNew));
          if (g == 4) return ok(x.bytes(m.ed25519Pub));
          return 0;
        case FromKind::KeyChange:
          if (g == 1) return ok(x.fx32(m.nodeId));
          if (g == 2) return ok(x.bytes(m.ed25519Pub));
          if (g == 3) return ok(x.str(m.name));
          return 0;
        case FromKind::ChannelMessage:
          switch (g) {
            case 1: return ok(x.str(m.channel));
            case 2: return ok(x.fx32(m.src));
            case 3: return ok(x.fx32(m.msgId));
            case 4: return ok(x.bytes(m.text));
            case 5: return ok(parsePos(x, m.pos));
            case 6: return ok(x.optSint(m.rssiDbm));
          }
          return 0;
        case FromKind::Channel:
          if (g == 1) return ok(x.str(m.channel));
          if (g == 2) return ok(x.bytes(m.psk));
          return 0;
        case FromKind::ChannelsEnd:
          if (g == 1) return ok(x.u32(m.count));
          return 0;
        case FromKind::PinChallenge:
          if (g == 2) return ok(x.bytes(m.serverShare));
          if (g == 1) return ok(x.bytes(m.nonce));
          return 0;
        default: return 0;
      }
    }));
  });
}

// --------------------------------------------------------------- frames --

bool frame(const uint8_t* pb, size_t n, Bytes& out, uint8_t version) {
  size_t len = n + 1;
  if (len > kMaxBody) return false;
  out.reserve(out.size() + kFrameHeader + len);
  out.push_back(kMagic0);
  out.push_back(kMagic1);
  out.push_back(static_cast<uint8_t>(len & 0xFF));
  out.push_back(static_cast<uint8_t>(len >> 8));
  out.push_back(version);
  out.insert(out.end(), pb, pb + n);
  return true;
}

bool frameTo(const ToRadio& m, Bytes& out) {
  Bytes pb;
  return encodeTo(m, pb) && frame(pb.data(), pb.size(), out);
}

bool frameFrom(const FromRadio& m, Bytes& out) {
  Bytes pb;
  return encodeFrom(m, pb) && frame(pb.data(), pb.size(), out);
}

void FrameReader::push(const uint8_t* p, size_t n) { buf_.insert(buf_.end(), p, p + n); }

FrameReader::Result FrameReader::next(uint8_t& version, Bytes& body) {
  {
    // find a magic
    size_t i = 0;
    while (i < buf_.size() && !(buf_[i] == kMagic0 && (i + 1 == buf_.size() || buf_[i + 1] == kMagic1))) ++i;
    if (i) {
      skipped_ += i;
      buf_.erase(buf_.begin(), buf_.begin() + static_cast<std::ptrdiff_t>(i));
    }
    if (buf_.size() < kFrameHeader) return Result::None;
    size_t len = buf_[2] | static_cast<size_t>(buf_[3]) << 8;
    if (len == 0 || len > kMaxSecureBody) {
      // drop this magic and resynchronise on the next one
      buf_.erase(buf_.begin());
      ++skipped_;
      return Result::BadLength;
    }
    if (buf_.size() < kFrameHeader + len) return Result::None;
    version = buf_[kFrameHeader];
    body.assign(buf_.begin() + kFrameHeader + 1, buf_.begin() + static_cast<std::ptrdiff_t>(kFrameHeader + len));
    buf_.erase(buf_.begin(), buf_.begin() + static_cast<std::ptrdiff_t>(kFrameHeader + len));
    return Result::Frame;
  }
}

}  // namespace client
}  // namespace gw
