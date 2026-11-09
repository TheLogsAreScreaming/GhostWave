// RAK1921 status screen (128x64 SSD1306 on I2C), on boards with GW_HAS_OLED.
// Shows what the node is doing without a phone. It is optional: with no screen
// on the bus, begin() returns false and everything else does nothing.
#pragma once

#include "board.h"

#if GW_HAS_OLED

#include <cstddef>
#include <cstdint>

namespace gw {
namespace mcu {
namespace oled {

struct Status {
  const char* name;
  uint32_t nodeId;
  bool radioOk;
  bool txOn;
  bool sosOwn;
  uint32_t sosHeard;
  int outputDbm;
  uint32_t neighbors;
  uint32_t tx, rx;
};

bool begin();
void noteMessage(uint32_t src, const uint8_t* text, size_t len);
// Pairing: fills the screen with the 6-digit passkey until pairing ends or a
// minute passes. Safe to call from the BLE task.
void showPasskey(const uint8_t digits[6]);
void clearPasskey();
// Redraws at most once a second, so the I2C transfer cannot crowd the radio.
void poll(uint32_t nowMs, const Status& s);

}  // namespace oled
}  // namespace mcu
}  // namespace gw

#endif
