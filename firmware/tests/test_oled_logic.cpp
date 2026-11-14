// Host tests for the status screen's sleep and page rules (mcu/src/oled_logic.h).
#include <cstdio>

#include "oled_logic.h"

using gw::mcu::ScreenPolicy;
using Level = ScreenPolicy::Level;

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

static void testLevels() {
  ScreenPolicy p;
  CHECK(p.level(0) == Level::Off);   // nothing has woken it yet
  p.wake(1000);
  CHECK(p.level(1000) == Level::Bright);
  CHECK(p.level(1000 + ScreenPolicy::kDimMs - 1) == Level::Bright);
  CHECK(p.level(1000 + ScreenPolicy::kDimMs) == Level::Dim);
  CHECK(p.level(1000 + ScreenPolicy::kOffMs) == Level::Off);
  p.wake(1000 + ScreenPolicy::kOffMs + 5);
  CHECK(p.level(1000 + ScreenPolicy::kOffMs + 5) == Level::Bright);
}

static void testWrap() {
  ScreenPolicy p;
  const uint32_t t = 0xFFFFFFF0u;   // millis() about to wrap
  p.wake(t);
  CHECK(p.level(t + 100) == Level::Bright);
  CHECK(p.level(t + ScreenPolicy::kDimMs) == Level::Dim);
}

static void testPages() {
  ScreenPolicy p;
  p.show(0, 0);
  CHECK(p.page(1000, 3) == 0);
  CHECK(p.page(ScreenPolicy::kPageMs, 3) == 1);
  CHECK(p.page(2 * ScreenPolicy::kPageMs, 3) == 2);
  CHECK(p.page(3 * ScreenPolicy::kPageMs, 3) == 0);
  CHECK(p.page(3 * ScreenPolicy::kPageMs, 0) == 0);
}

static void testJumpToMessage() {
  ScreenPolicy p;
  p.show(0, 0);
  p.show(2, 3000);
  CHECK(p.page(3000 + ScreenPolicy::kPageMs - 1, 3) == 2);   // stays a full period
  CHECK(p.level(3000) == Level::Bright);
}

static void testFewerPages() {
  ScreenPolicy p;
  p.show(2, 0);
  CHECK(p.page(1, 2) == 0);   // the page it was on no longer exists
}

// The app's screen timeout (1.11): shorter, longer, or never off.
static void testOffAfter() {
  ScreenPolicy p;
  p.setOffAfter(30000);   // 30 s: dims at 15 s
  p.wake(0);
  CHECK(p.level(14999) == Level::Bright);
  CHECK(p.level(15000) == Level::Dim);
  CHECK(p.level(30000) == Level::Off);
  p.setOffAfter(3600000);   // an hour: dims after the usual minute
  p.wake(0);
  CHECK(p.level(ScreenPolicy::kDimMs) == Level::Dim);
  CHECK(p.level(ScreenPolicy::kOffMs) == Level::Dim);
  CHECK(p.level(3600000) == Level::Off);
  p.setOffAfter(0);   // never off
  p.wake(0);
  CHECK(p.level(ScreenPolicy::kDimMs) == Level::Dim);
  CHECK(p.level(86400000u) == Level::Dim);
}

int main() {
  testLevels();
  testOffAfter();
  testWrap();
  testPages();
  testJumpToMessage();
  testFewerPages();
  std::printf("oled logic: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
