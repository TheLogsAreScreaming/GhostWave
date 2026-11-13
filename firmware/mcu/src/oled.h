// Status screen on a 128x64 I2C OLED (SSD1306: RAK1921, Heltec V3/V4, T3-S3,
// T-LoRa, T-Beam add-on; SH1106: T-Beam Supreme), on boards with GW_HAS_OLED.
// Pins come from GW_OLED_SDA / GW_OLED_SCL / GW_OLED_RST (board.h).
// Shows what the node is doing without a phone. It is optional: with no screen
// on the bus, begin() returns false and everything else does nothing. What it
// draws is in oled_view.cpp.
#pragma once

#include "board.h"

#if GW_HAS_OLED

#include <cstddef>
#include <cstdint>

#include "oled_view.h"

namespace gw {
namespace mcu {
namespace oled {

// `version` shows on the splash screen at power-on.
bool begin(const char* version);
void noteMessage(uint32_t src, const uint8_t* text, size_t len);
// Pairing: fills the screen with the 6-digit passkey until pairing ends or a
// minute passes. Safe to call from the BLE task.
void showPasskey(const uint8_t digits[6]);
void clearPasskey();
// Wakes the screen (the `display` console command).
void wake();
// Whether draw() has work to do now; once a second at most (twice while an SOS
// flashes), unless something new happened, so filling Status and the I2C
// transfer cannot crowd the radio.
bool due(uint32_t nowMs);
void draw(uint32_t nowMs, const Status& s);

}  // namespace oled
}  // namespace mcu
}  // namespace gw

#endif
