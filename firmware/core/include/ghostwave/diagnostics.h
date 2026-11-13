// GhostWave diagnostic probe payload codec. Independent of transport and radio driver.
// This is a proposed protocol extension: do not transmit until firmware dispatch is wired.
#pragma once
#include <cstddef>
#include <cstdint>
namespace gw { namespace diag {
constexpr uint8_t kVersion = 1;
constexpr size_t kProbeBytes = 14;
constexpr size_t kHopBytes = 20;
constexpr uint8_t kMaxTtl = 15;
enum class Kind : uint8_t { Probe = 1, Reply = 2, Hop = 3 };
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
}} // namespace gw::diag
