// GhostWave diagnostic payload codec (packet type Diag): the one-hop link
// ping (Probe / Hop) and the multi-hop traceroute (Trace / TraceBack, see
// docs/TRACEROUTE.md). Independent of transport and radio driver.
#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>
namespace gw { namespace diag {
constexpr uint8_t kVersion = 1;
constexpr size_t kProbeBytes = 14;
constexpr size_t kHopBytes = 20;
constexpr uint8_t kMaxTtl = 15;
enum class Kind : uint8_t { Probe = 1, Reply = 2, Hop = 3, Trace = 4, TraceBack = 5 };
struct Probe {
  Kind kind = Kind::Probe;
  uint32_t token = 0;
  uint32_t origin = 0;
  uint32_t target = 0;
  uint8_t ttl = 1;
};
struct Hop {
  uint32_t token = 0;
  uint32_t node = 0;
  uint32_t previous = 0;
  int16_t rxRssiDbm = 0;
  int16_t rxSnrQuarterDb = 0;
  uint8_t direction = 0; // 0 forward, 1 reverse
  uint8_t hop = 0;
};
inline void put32(uint8_t* b, uint32_t x) { for(int i=0;i<4;++i)b[i]=static_cast<uint8_t>(x>>(8*i)); }
inline uint32_t get32(const uint8_t* b) { return uint32_t(b[0])|(uint32_t(b[1])<<8)|(uint32_t(b[2])<<16)|(uint32_t(b[3])<<24); }
inline void put16(uint8_t* b, int16_t x) { uint16_t u=static_cast<uint16_t>(x); b[0]=uint8_t(u); b[1]=uint8_t(u>>8); }
inline int16_t get16(const uint8_t* b) { return static_cast<int16_t>(uint16_t(b[0])|(uint16_t(b[1])<<8)); }
inline bool encodeProbe(const Probe& p, uint8_t* b, size_t n) {
  if (!b || n<kProbeBytes || !p.token || !p.origin || !p.target || !p.ttl || p.ttl>kMaxTtl ||
      (p.kind!=Kind::Probe && p.kind!=Kind::Reply)) return false;
  b[0]=kVersion; b[1]=static_cast<uint8_t>(p.kind); put32(b+2,p.token);
  put32(b+6,p.origin); put32(b+10,p.target); return true;
}
// TTL travels in the existing packet header (hopsLeft), not the probe payload.
inline bool decodeProbe(const uint8_t* b, size_t n, Probe& p) {
  if (!b || n!=kProbeBytes || b[0]!=kVersion || (b[1]!=1 && b[1]!=2)) return false;
  Probe v; v.kind=static_cast<Kind>(b[1]); v.token=get32(b+2);
  v.origin=get32(b+6); v.target=get32(b+10);
  if (!v.token || !v.origin || !v.target) return false;
  p=v; return true;
}
inline bool encodeHop(const Hop& h, uint8_t* b, size_t n) {
  if (!b || n<kHopBytes || !h.token || !h.node || h.direction>1 || h.hop>kMaxTtl) return false;
  b[0]=kVersion; b[1]=static_cast<uint8_t>(Kind::Hop);
  put32(b+2,h.token); put32(b+6,h.node); put32(b+10,h.previous);
  put16(b+14,h.rxRssiDbm); put16(b+16,h.rxSnrQuarterDb);
  b[18]=h.direction; b[19]=h.hop; return true;
}
inline bool decodeHop(const uint8_t* b, size_t n, Hop& h) {
  if (!b || n!=kHopBytes || b[0]!=kVersion || b[1]!=3 || b[18]>1 || b[19]>kMaxTtl) return false;
  Hop v; v.token=get32(b+2); v.node=get32(b+6); v.previous=get32(b+10);
  v.rxRssiDbm=get16(b+14); v.rxSnrQuarterDb=get16(b+16);
  v.direction=b[18]; v.hop=b[19];
  if (!v.token || !v.node) return false;
  h=v; return true;
}

// ---------------------------------------------------------------- traceroute --
// The probe collects the path as it goes: each relay appends its node ID and
// the RSSI it heard the previous transmitter at (5 bytes). The target appends
// its own record and answers once with a TraceBack carrying that forward list;
// the TraceBack collects the way back the same way. Every reading is taken by
// the node that received the frame; nothing is inferred.
//
//   0 version | 1 kind | 2 token(4) | 6 origin(4) | 10 target(4)
//   14 forward count | forward records (id 4, rssi int8)...
//   TraceBack only: back count | back records...
constexpr size_t kTraceHeader = 14;
constexpr size_t kTraceRecord = 5;
// Forward records (relays + the target) and back records (relays) together
// fit a 128-byte frame: 14 + 2 + 5 * (8 + 7) = 91 <= 105 payload bytes.
constexpr uint8_t kMaxTraceHops = 8;
constexpr size_t kMaxTraceBack = kMaxTraceHops - 1;   // the origin adds its own reading locally

struct TraceHop {
  uint32_t node = 0;
  int8_t rssiDbm = 0;   // how strongly `node` heard the frame it received
};
struct Trace {
  Kind kind = Kind::Trace;
  uint32_t token = 0, origin = 0, target = 0;
  std::vector<TraceHop> forward, back;
};

inline int8_t clampDbm(int dbm) { return static_cast<int8_t>(dbm < -128 ? -128 : dbm > 127 ? 127 : dbm); }

inline size_t traceSize(const Trace& t) {
  return kTraceHeader + 1 + kTraceRecord * t.forward.size() +
         (t.kind == Kind::TraceBack ? 1 + kTraceRecord * t.back.size() : 0);
}

// Returns the encoded length, 0 if invalid or too big for `n`.
inline size_t encodeTrace(const Trace& t, uint8_t* b, size_t n) {
  if (!b || !t.token || !t.origin || !t.target || t.origin == t.target) return 0;
  if (t.kind != Kind::Trace && t.kind != Kind::TraceBack) return 0;
  if (t.forward.size() > kMaxTraceHops || t.back.size() > kMaxTraceBack) return 0;
  if (t.kind == Kind::Trace && !t.back.empty()) return 0;
  if (t.kind == Kind::TraceBack && t.forward.empty()) return 0;   // the target's own record at least
  const size_t len = traceSize(t);
  if (n < len) return 0;
  b[0] = kVersion;
  b[1] = static_cast<uint8_t>(t.kind);
  put32(b + 2, t.token);
  put32(b + 6, t.origin);
  put32(b + 10, t.target);
  size_t o = kTraceHeader;
  auto list = [&](const std::vector<TraceHop>& v) {
    b[o++] = static_cast<uint8_t>(v.size());
    for (const TraceHop& h : v) {
      put32(b + o, h.node);
      b[o + 4] = static_cast<uint8_t>(h.rssiDbm);
      o += kTraceRecord;
    }
  };
  list(t.forward);
  if (t.kind == Kind::TraceBack) list(t.back);
  return o;
}

inline bool decodeTrace(const uint8_t* b, size_t n, Trace& t) {
  if (!b || n < kTraceHeader + 1 || b[0] != kVersion || (b[1] != 4 && b[1] != 5)) return false;
  Trace v;
  v.kind = static_cast<Kind>(b[1]);
  v.token = get32(b + 2);
  v.origin = get32(b + 6);
  v.target = get32(b + 10);
  if (!v.token || !v.origin || !v.target || v.origin == v.target) return false;
  size_t o = kTraceHeader;
  auto list = [&](std::vector<TraceHop>& out, size_t max) {
    if (o >= n) return false;
    const size_t c = b[o++];
    if (c > max || n - o < c * kTraceRecord) return false;
    for (size_t i = 0; i < c; ++i, o += kTraceRecord) {
      TraceHop h;
      h.node = get32(b + o);
      h.rssiDbm = static_cast<int8_t>(b[o + 4]);
      if (!h.node) return false;
      out.push_back(h);
    }
    return true;
  };
  if (!list(v.forward, kMaxTraceHops)) return false;
  if (v.kind == Kind::TraceBack && (v.forward.empty() || !list(v.back, kMaxTraceBack))) return false;
  if (o != n) return false;
  t = v;
  return true;
}
}} // namespace gw::diag
