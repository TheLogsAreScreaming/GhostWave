// Diagnostic payload codec (ghostwave/diagnostics.h): round trips, and
// truncated, wrong-version and out-of-range payloads refused. Checks stay on
// in release builds (no assert).
#include <cstdint>
#include <cstdio>

#include "ghostwave/diagnostics.h"

using namespace gw::diag;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond)                                             \
  do {                                                          \
    if (cond) ++g_pass;                                         \
    else {                                                      \
      ++g_fail;                                                 \
      std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); \
    }                                                           \
  } while (0)

int main() {
  uint8_t b[32]{};
  Probe p;
  p.token = 0x12345678, p.origin = 42, p.target = 99, p.ttl = 3;
  CHECK(encodeProbe(p, b, sizeof b));
  Probe q;
  CHECK(decodeProbe(b, kProbeBytes, q));
  CHECK(q.token == p.token && q.origin == 42 && q.target == 99);
  CHECK(!decodeProbe(b, kProbeBytes - 1, q));
  b[0] = 9;
  CHECK(!decodeProbe(b, kProbeBytes, q));
  Probe zero;
  CHECK(!encodeProbe(zero, b, sizeof b));   // token 0 is not a probe
  Hop h;
  h.token = 7, h.node = 99, h.previous = 42, h.rxRssiDbm = -104, h.rxSnrQuarterDb = -13, h.direction = 1, h.hop = 2;
  CHECK(encodeHop(h, b, sizeof b));
  Hop j;
  CHECK(decodeHop(b, kHopBytes, j));
  CHECK(j.rxRssiDbm == -104 && j.rxSnrQuarterDb == -13 && j.direction == 1 && j.previous == 42 && j.hop == 2);
  b[18] = 2;
  CHECK(!decodeHop(b, kHopBytes, j));
  CHECK(!decodeHop(b, kProbeBytes, j));   // a probe is not a hop report
  // Traceroute (probe collects): round trips, limits, and the old link-ping
  // decoders refuse it (older nodes ignore trace frames).
  Trace t;
  t.token = 0xCAFE, t.origin = 42, t.target = 99;
  t.forward = {{7, -101}, {8, -128}};
  uint8_t tb[128]{};
  size_t n = encodeTrace(t, tb, sizeof tb);
  CHECK(n == kTraceHeader + 1 + 2 * kTraceRecord);
  Trace u;
  CHECK(decodeTrace(tb, n, u) && u.kind == Kind::Trace && u.token == 0xCAFE && u.origin == 42 && u.target == 99);
  CHECK(u.forward.size() == 2 && u.forward[0].node == 7 && u.forward[0].rssiDbm == -101 && u.forward[1].rssiDbm == -128);
  CHECK(!decodeTrace(tb, n - 1, u));   // truncated
  CHECK(!decodeTrace(tb, n + 1, u));   // trailing byte
  CHECK(!decodeProbe(tb, n, q) && !decodeHop(tb, n, j));
  t.back.push_back({5, -90});
  CHECK(encodeTrace(t, tb, sizeof tb) == 0);   // a probe carries no way back yet
  t.kind = Kind::TraceBack;
  n = encodeTrace(t, tb, sizeof tb);
  CHECK(n == kTraceHeader + 2 + 3 * kTraceRecord);
  CHECK(decodeTrace(tb, n, u) && u.kind == Kind::TraceBack && u.back.size() == 1 && u.back[0].node == 5);
  Trace full;
  full.kind = Kind::TraceBack, full.token = 1, full.origin = 2, full.target = 3;
  for (uint32_t i = 0; i < kMaxTraceHops; ++i) full.forward.push_back({10 + i, -100});
  for (uint32_t i = 0; i < kMaxTraceBack; ++i) full.back.push_back({30 + i, -110});
  n = encodeTrace(full, tb, sizeof tb);
  CHECK(n > 0 && n <= 105);   // the largest answer fits an unencrypted 128-byte frame
  CHECK(decodeTrace(tb, n, u) && u.forward.size() == kMaxTraceHops && u.back.size() == kMaxTraceBack);
  full.forward.push_back({99, 0});
  CHECK(encodeTrace(full, tb, sizeof tb) == 0);   // too many hops
  Trace bad = t;
  bad.target = bad.origin;
  CHECK(encodeTrace(bad, tb, sizeof tb) == 0);
  CHECK(clampDbm(-200) == -128 && clampDbm(300) == 127 && clampDbm(-77) == -77);
  std::printf("diagnostics: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
