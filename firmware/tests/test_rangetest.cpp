// Host tests for the range test logic (mcu/src/rangetest.h).
#include <cstdio>
#include <cstring>

#include "rangetest.h"

using gw::mcu::RangeTest;

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

static uint32_t seq(const char* s) { return gw::mcu::rangePingSeq(reinterpret_cast<const uint8_t*>(s), std::strlen(s)); }

static void testTiming() {
  RangeTest t;
  CHECK(!t.active() && !t.due(1000));
  t.start(0xAB, 30000, 1000);
  CHECK(t.active() && t.due(1000) && t.nextSeq() == 1);   // first ping goes at once
  t.onSent(77, 1000);
  CHECK(!t.due(30999) && t.due(31000) && t.nextSeq() == 2);
  t.stop();
  CHECK(!t.due(99999));
}

static void testIntervalFloor() {
  RangeTest t;
  t.start(1, 1000, 0);
  CHECK(t.intervalMs() == RangeTest::kMinIntervalMs);
}

static void testDelivery() {
  RangeTest t;
  t.start(1, 30000, 0);
  t.onSent(100, 0);
  t.onSent(200, 30000);
  CHECK(t.onDelivered(200) == 2);
  CHECK(t.onDelivered(200) == 0);   // a repeat receipt is not counted twice
  CHECK(t.onDelivered(999) == 0);   // an ordinary message's receipt
  CHECK(t.onDelivered(100) == 1);   // late receipts still match
  CHECK(t.sent() == 2 && t.delivered() == 2);
}

static void testRefusedDoesNotCount() {
  RangeTest t;
  t.start(1, 30000, 0);
  t.onSent(0, 0);
  CHECK(t.sent() == 0 && t.nextSeq() == 1 && !t.due(29999) && t.due(30000));
}

static void testStopsByItself() {
  RangeTest t;
  t.start(1, 30000, 0);
  for (uint32_t i = 1; i <= RangeTest::kMaxPings; ++i) t.onSent(i, i * 30000ull);
  CHECK(!t.active() && t.sent() == RangeTest::kMaxPings);
}

static void testParse() {
  CHECK(seq("RT 12") == 12);
  CHECK(seq("RT 1") == 1);
  CHECK(seq("RT 12 hello") == 0);
  CHECK(seq("RT ") == 0);
  CHECK(seq("hello") == 0);
  CHECK(seq("RT 99999999") == 0);
}

int main() {
  testTiming();
  testIntervalFloor();
  testDelivery();
  testRefusedDoesNotCount();
  testStopsByItself();
  testParse();
  std::printf("range test: %d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
