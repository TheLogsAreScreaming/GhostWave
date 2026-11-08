// Host tests for the T1000-E button gestures and battery curve
// (firmware/mcu/src/button_gesture.h): a ~3 s hold starts an SOS, a double
// press stops it, a single press is a status chirp; bounce is ignored.
#include <cstdio>
#include <vector>

#include "button_gesture.h"

using gw::mcu::ButtonGesture;
using Ev = ButtonGesture::Event;

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

namespace {

// Runs a press script: (level, duration ms) segments, sampled every 2 ms,
// then 2 s released. Returns the events with their times.
struct Hit {
  Ev ev;
  uint32_t at;
};
std::vector<Hit> run(const std::vector<std::pair<bool, uint32_t>>& script, uint32_t start = 1000) {
  ButtonGesture b;
  std::vector<Hit> out;
  uint32_t t = start;
  auto feed = [&](bool level, uint32_t ms) {
    for (uint32_t done = 0; done < ms; done += 2, t += 2) {   // wrap-safe
      Ev e = b.update(level, t);
      if (e != Ev::None) out.push_back({e, t});
    }
  };
  for (auto& s : script) feed(s.first, s.second);
  feed(false, 2000);
  return out;
}

void testLong() {
  auto h = run({{false, 100}, {true, 5000}});
  CHECK(h.size() == 1 && h[0].ev == Ev::Long);
  // fires while still held, ~3 s (+ debounce) after the press
  CHECK(!h.empty() && h[0].at >= 1100 + 3000 && h[0].at <= 1100 + 3000 + 40);
  // just under 3 s: nothing (a medium press)
  h = run({{true, 2900}});
  CHECK(h.empty());
}

void testDoubleAndSingle() {
  auto h = run({{true, 120}, {false, 150}, {true, 120}});
  CHECK(h.size() == 1 && h[0].ev == Ev::Double);
  h = run({{true, 120}});
  CHECK(h.size() == 1 && h[0].ev == Ev::Single);
  // single fires only after the double-press window
  CHECK(!h.empty() && h[0].at > 1000 + 120 + ButtonGesture::kGapMs);
  // two clicks too far apart: two singles
  h = run({{true, 100}, {false, 800}, {true, 100}});
  CHECK(h.size() == 2 && h[0].ev == Ev::Single && h[1].ev == Ev::Single);
  // a long press, then a double press (SOS on, then off)
  h = run({{true, 3500}, {false, 500}, {true, 100}, {false, 100}, {true, 100}});
  CHECK(h.size() == 2 && h[0].ev == Ev::Long && h[1].ev == Ev::Double);
  // a medium press (1 s) does not count as a click
  h = run({{true, 1000}, {false, 100}, {true, 100}});
  CHECK(h.size() == 1 && h[0].ev == Ev::Single);
}

void testBounce() {
  // contact bounce shorter than the debounce time around one click
  auto h = run({{true, 4}, {false, 4}, {true, 4}, {false, 6}, {true, 120}, {false, 6}, {true, 6}});
  CHECK(h.size() == 1 && h[0].ev == Ev::Single);
  // a 10 ms glitch is not a press
  h = run({{true, 10}});
  CHECK(h.empty());
  // millis() wrap in the middle of a hold
  h = run({{true, 3500}}, 0xFFFFFFFFu - 1000);
  CHECK(h.size() == 1 && h[0].ev == Ev::Long);
}

void testBattery() {
  using gw::mcu::batteryPercent;
  CHECK(batteryPercent(0) == 0xFF);
  CHECK(batteryPercent(4300) == 100);
  CHECK(batteryPercent(4190) == 100);
  CHECK(batteryPercent(4042) == 90);
  CHECK(batteryPercent(3820) == 60);
  CHECK(batteryPercent(3100) == 0);
  CHECK(batteryPercent(2900) == 0);
  CHECK(batteryPercent(3852) == 65);   // halfway 3820..3885
  uint8_t last = 0;
  bool mono = true;
  for (uint32_t mv = 3000; mv <= 4300; mv += 5) {
    uint8_t p = batteryPercent(mv);
    if (p < last || p > 100) mono = false;
    last = p;
  }
  CHECK(mono);
}

}  // namespace

int main() {
  testLong();
  testDoubleAndSingle();
  testBounce();
  testBattery();
  std::printf("button gesture: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
