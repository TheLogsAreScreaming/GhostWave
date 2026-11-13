// Host tests for the e-ink screen rules (mcu/src/eink_logic.h): the 1.5x page
// mapping onto the T-Echo panel and when the panel may refresh.
#include <cstdio>
#include <cstring>

#include "eink_logic.h"
#include "oled_logic.h"

using namespace gw::mcu::eink;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond)                                                 \
  do {                                                              \
    if (cond) {                                                     \
      ++g_pass;                                                     \
    } else {                                                        \
      ++g_fail;                                                     \
      std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); \
    }                                                               \
  } while (0)

static uint8_t g_page[128 * 64 / 8];
static void setPx(int x, int y) { g_page[y * 16 + x / 8] |= 0x80 >> (x & 7); }

static int countInk(int rotation) {
  int n = 0;
  for (int y = 0; y < 200; ++y)
    for (int x = 0; x < 200; ++x) n += inkAt(g_page, 200, 200, rotation, x, y);
  return n;
}

static void testMapping() {
  std::memset(g_page, 0, sizeof g_page);
  CHECK(countInk(0) == 0);
  setPx(0, 0);   // top-left page pixel: 2x2 panel pixels at (4, 52)
  CHECK(inkAt(g_page, 200, 200, 0, 4, 52));
  CHECK(inkAt(g_page, 200, 200, 0, 5, 53));
  CHECK(!inkAt(g_page, 200, 200, 0, 3, 52));
  CHECK(!inkAt(g_page, 200, 200, 0, 4, 51));
  CHECK(!inkAt(g_page, 200, 200, 0, 6, 52));
  CHECK(countInk(0) == 4);
  // A full page fills exactly the 192x96 window, whatever the rotation.
  std::memset(g_page, 0xFF, sizeof g_page);
  for (int r = 0; r < 4; ++r) CHECK(countInk(r) == kScaledW * kScaledH);
  CHECK(!inkAt(g_page, 200, 200, 0, 0, 0));
  CHECK(!inkAt(g_page, 200, 200, 0, 199, 199));
  // Bottom-right page pixel lands at the window's bottom-right corner.
  std::memset(g_page, 0, sizeof g_page);
  setPx(127, 63);
  // (Even page pixels get two panel pixels, odd ones one: 1.5x on average.)
  CHECK(inkAt(g_page, 200, 200, 0, 4 + 191, 52 + 95));
  CHECK(countInk(0) == 1);
}

static void testRotation() {
  std::memset(g_page, 0, sizeof g_page);
  setPx(0, 0);   // upright top-left corner of the page
  // Rotation 2: upside down, so it is at the panel's bottom-right.
  CHECK(inkAt(g_page, 200, 200, 2, 199 - 4, 199 - 52));
  // Rotation 1 (90 cw): the upright top-left sits at the panel's top-right.
  CHECK(inkAt(g_page, 200, 200, 1, 199 - 52, 4));
  // Rotation 3 (270): at the panel's bottom-left.
  CHECK(inkAt(g_page, 200, 200, 3, 52, 199 - 4));
  for (int r = 0; r < 4; ++r) CHECK(countInk(r) == 4);
}

static void testFirstIsFull() {
  RefreshPolicy p;
  CHECK(p.decide(0, true, false) == Refresh::Full);
  CHECK(p.decide(0, false, false) == Refresh::None);   // nothing to show
}

static void testUnchangedNeverRefreshes() {
  RefreshPolicy p;
  p.done(Refresh::Full, 0);
  for (uint32_t t = 0; t < 10 * RefreshPolicy::kFullEveryMs; t += 60000) CHECK(p.decide(t, false, true) == Refresh::None);
}

static void testRoutineWaits() {
  RefreshPolicy p;
  p.done(Refresh::Full, 1000);
  CHECK(p.decide(1000 + RefreshPolicy::kRoutineGapMs - 1, true, false) == Refresh::None);
  CHECK(p.decide(1000 + RefreshPolicy::kRoutineGapMs, true, false) == Refresh::Partial);
}

static void testUrgentSoon() {
  RefreshPolicy p;
  p.done(Refresh::Full, 1000);
  CHECK(p.decide(1000 + RefreshPolicy::kUrgentGapMs - 1, true, true) == Refresh::None);
  CHECK(p.decide(1000 + RefreshPolicy::kUrgentGapMs, true, true) == Refresh::Partial);
}

static void testFullAfterPartials() {
  RefreshPolicy p;
  uint32_t t = 0;
  p.done(Refresh::Full, t);
  for (int i = 0; i < RefreshPolicy::kMaxPartials; ++i) {
    t += RefreshPolicy::kRoutineGapMs;
    CHECK(p.decide(t, true, false) == Refresh::Partial);
    p.done(Refresh::Partial, t);
  }
  t += RefreshPolicy::kRoutineGapMs;
  CHECK(p.decide(t, true, false) == Refresh::Full);
  p.done(Refresh::Full, t);
  CHECK(p.partials() == 0);
}

static void testFullHourly() {
  RefreshPolicy p;
  p.done(Refresh::Full, 0);
  p.done(Refresh::Partial, RefreshPolicy::kFullEveryMs - 1000);
  CHECK(p.decide(RefreshPolicy::kFullEveryMs + 30000, true, false) == Refresh::Full);
}

static void testForcedFull() {
  RefreshPolicy p;
  p.done(Refresh::Full, 0);
  p.done(Refresh::Partial, 30000);
  p.forceFull();   // going to sleep: even an unchanged picture is redrawn cleanly
  CHECK(p.decide(30000 + RefreshPolicy::kUrgentGapMs - 1, false, false) == Refresh::None);
  CHECK(p.decide(30000 + RefreshPolicy::kUrgentGapMs, false, false) == Refresh::Full);
  p.done(Refresh::Full, 31000);
  CHECK(p.decide(90000, false, false) == Refresh::None);   // once only
}

static void testWrap() {
  RefreshPolicy p;
  const uint32_t t = 0xFFFFF000u;   // millis() about to wrap
  p.done(Refresh::Full, t);
  CHECK(p.decide(t + RefreshPolicy::kRoutineGapMs, true, false) == Refresh::Partial);
}

static void testEinkPagePeriod() {
  gw::mcu::ScreenPolicy s;
  s.setPagePeriod(gw::mcu::ScreenPolicy::kEinkPageMs);
  s.show(0, 0);
  CHECK(s.page(gw::mcu::ScreenPolicy::kPageMs, 3) == 0);   // no turn at the OLED pace
  CHECK(s.page(gw::mcu::ScreenPolicy::kEinkPageMs, 3) == 1);
  s.setPagePeriod(0);   // 0 = back to the default
  CHECK(s.page(gw::mcu::ScreenPolicy::kEinkPageMs + gw::mcu::ScreenPolicy::kPageMs, 3) == 2);
}

int main() {
  testMapping();
  testRotation();
  testFirstIsFull();
  testUnchangedNeverRefreshes();
  testRoutineWaits();
  testUrgentSoon();
  testFullAfterPartials();
  testFullHourly();
  testForcedFull();
  testWrap();
  testEinkPagePeriod();
  std::printf("eink logic: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
