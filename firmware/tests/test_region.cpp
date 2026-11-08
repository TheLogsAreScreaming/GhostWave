// Host tests for regions and the regulatory duty-cycle window
// (firmware/mcu/src/region.h).
#include <cstdio>
#include <utility>
#include <vector>

#include "region.h"

using namespace gw::mcu;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (cond) {                                                         \
      ++g_pass;                                                         \
    } else {                                                            \
      ++g_fail;                                                         \
      std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);     \
    }                                                                   \
  } while (0)

static const uint64_t kMin = 60000, kHour = 60 * kMin;

static void testRegions() {
  Region r = Region::Us915;
  CHECK(regionFromName("eu868", r) && r == Region::Eu868);
  CHECK(regionFromName("us915", r) && r == Region::Us915);
  CHECK(!regionFromName("mars", r) && r == Region::Us915);
  for (size_t i = 0; i < kRegionCount; ++i) {
    const RegionInfo& g = regionInfo(static_cast<Region>(i));
    CHECK(g.minMHz <= g.defaultMHz && g.defaultMHz <= g.maxMHz);
  }
  // BW125 stays inside the EU sub-band
  const RegionInfo& eu = regionInfo(Region::Eu868);
  CHECK(eu.minMHz - 0.0625f >= 869.4f - 1e-3f && eu.maxMHz + 0.0625f <= 869.65f + 1e-3f);
  CHECK(eu.dutyPermille == 100);
  CHECK(regionInfo(Region::Us915).dutyPermille == 0);
  CHECK(regionInfo(static_cast<Region>(9)).defaultMHz == regionInfo(Region::Us915).defaultMHz);
}

static void testUncapped() {
  DutyWindow d;
  CHECK(!d.capped());
  for (int i = 0; i < 100; ++i) d.record(1000, 1000000);
  CHECK(d.allows(1000, 1000000));
}

static void testCap() {
  DutyWindow d;
  d.setPermille(100);
  CHECK(d.limitMs() == 360000);
  CHECK(d.allows(0, 360000));
  CHECK(!d.allows(0, 360001));
  d.record(0, 359000);
  CHECK(d.usedMs(0) == 359000);
  CHECK(d.allows(0, 1000));
  CHECK(!d.allows(0, 1001));
  d.record(0, 1000);
  CHECK(!d.allows(0, 1));
}

// Whatever the frame timing, no 60-minute span holds more than the limit.
static void testNeverOverLimit() {
  DutyWindow d;
  d.setPermille(100);
  std::vector<std::pair<uint64_t, uint32_t>> sent;
  for (uint64_t t = 5000; t < 5 * kHour; t += 250) {
    if (d.allows(t, 300)) {
      d.record(t, 300);
      sent.push_back({t, 300});
    }
  }
  CHECK(!sent.empty());
  uint64_t worst = 0;
  size_t tail = 0;
  uint64_t sum = 0;
  for (size_t i = 0; i < sent.size(); ++i) {
    sum += sent[i].second;
    while (sent[i].first - sent[tail].first >= kHour) sum -= sent[tail++].second;
    if (sum > worst) worst = sum;
  }
  CHECK(worst <= 360000);
  CHECK(worst >= 350000);   // and the budget does get used
}

static void testAges() {
  DutyWindow d;
  d.setPermille(100);
  d.record(30 * kMin, 360000);
  CHECK(!d.allows(30 * kMin + 1, 1));
  CHECK(!d.allows(30 * kMin + kHour - 1, 1));     // still inside the hour
  CHECK(!d.allows(30 * kMin + kHour, 1));         // the last bucket's margin
  CHECK(d.allows(30 * kMin + kHour + kMin, 1));
  CHECK(d.usedMs(30 * kMin + kHour + kMin) == 0);
  // a reused bucket doesn't inherit old airtime
  d.record(30 * kMin + 61 * kMin, 5);
  CHECK(d.usedMs(30 * kMin + 61 * kMin) == 5);
}

int main() {
  testRegions();
  testUncapped();
  testCap();
  testNeverOverLimit();
  testAges();
  std::printf("%d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
