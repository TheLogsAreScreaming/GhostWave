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
  std::printf("diagnostics: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
