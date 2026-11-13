#include "ghostwave/diagnostics.h"
#include <cassert>
#include <cstdint>
using namespace gw::diag;
int main() {
  uint8_t b[32]{};
  Probe p; p.token=0x12345678; p.origin=42; p.target=99; p.ttl=3;
  assert(encodeProbe(p,b,sizeof b));
  Probe q; assert(decodeProbe(b,kProbeBytes,q));
  assert(q.token==p.token && q.origin==42 && q.target==99);
  assert(!decodeProbe(b,kProbeBytes-1,q));
  b[0]=9; assert(!decodeProbe(b,kProbeBytes,q));
  Hop h; h.token=7; h.node=99; h.previous=42; h.rxRssiDbm=-104; h.rxSnrQuarterDb=-13; h.direction=1; h.hop=2;
  assert(encodeHop(h,b,sizeof b));
  Hop j; assert(decodeHop(b,kHopBytes,j));
  assert(j.rxRssiDbm==-104 && j.rxSnrQuarterDb==-13 && j.direction==1 && j.previous==42);
  b[18]=2; assert(!decodeHop(b,kHopBytes,j));
  return 0;
}
