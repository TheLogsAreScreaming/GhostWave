// Host tests for the status LEDs (mcu/src/led_pattern.h): the "running" blink,
// the phone-connected signal on one or two LEDs, and the SOS flash.
#include <cstdio>

#include "led_pattern.h"

using namespace gw::mcu;

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

// Milliseconds the status LED is lit across one 5 s period.
static int litMs(bool sos, bool phone, bool hasLink) {
  int n = 0;
  for (uint32_t t = 10000; t < 10000 + kLedPeriodMs; ++t) n += ledState(t, sos, phone, hasLink).status;
  return n;
}

static void testRunningBlink() {
  CHECK(litMs(false, false, true) == static_cast<int>(kLedBlinkMs));
  CHECK(litMs(false, false, false) == static_cast<int>(kLedBlinkMs));
  CHECK(ledState(10000, false, false, true).status);
  CHECK(!ledState(10000 + kLedBlinkMs, false, false, true).status);
  CHECK(!ledState(12500, false, false, true).status);
}

static void testPhoneLinkLed() {
  CHECK(ledState(12345, false, true, true).link);
  CHECK(!ledState(12345, false, false, true).link);
  CHECK(!ledState(12345, false, true, false).link);   // no second LED to light
  CHECK(litMs(false, true, true) == static_cast<int>(kLedBlinkMs));   // status LED unchanged
}

static void testOneLedDoubleBlink() {
  CHECK(litMs(false, true, false) == static_cast<int>(2 * kLedBlinkMs));
  CHECK(ledState(10000 + 4 * kLedBlinkMs, false, true, false).status);
  CHECK(!ledState(10000 + 2 * kLedBlinkMs, false, true, false).status);   // a gap between the blinks
}

static void testSos() {
  CHECK(litMs(true, false, true) == static_cast<int>(5 * kLedSosOnMs));
  CHECK(ledState(7000, true, false, true).status);
  CHECK(!ledState(7000 + kLedSosOnMs, true, false, true).status);
  CHECK(ledState(7000, true, true, true).link);   // the phone LED keeps saying connected
}

int main() {
  testRunningBlink();
  testPhoneLinkLed();
  testOneLedDoubleBlink();
  testSos();
  std::printf("led pattern: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
