// Button, buzzer, LED and battery on boards that have them (T1000-E,
// GW_HAS_UI). Non-blocking: poll() from the main loop.
#pragma once

#include "board.h"

#if GW_HAS_UI

#include <cstdint>

#include "button_gesture.h"

namespace gw {
namespace mcu {
namespace ui {

enum class Sound {
  Alive,        // single press: one short chirp
  Message,      // a DM arrived
  SosOn,        // our SOS started (button, CLI or app)
  SosAcked,     // a responder acked our SOS
  SosOff,       // our SOS stopped
  Refused,      // e.g. SOS rate limited
  HoldProgress, // held for 1 s and 2 s on the way to a long press
};

void begin();
// Returns a button gesture, if one completed. `sosActive` makes the LED blink.
ButtonGesture::Event poll(uint32_t nowMs, bool sosActive);
void play(Sound s);
// Whether USB power is present (the node then stays on).
bool usbPowered();
// Quiets the peripherals and enters System OFF. A button press or USB power
// wakes the node, which then boots normally. Does not return.
[[noreturn]] void powerOff();
// Battery: millivolts (0 = no reading yet) and percent (0xFF = unknown).
uint32_t batteryMv();
uint8_t batteryPct();

}  // namespace ui
}  // namespace mcu
}  // namespace gw

#endif
