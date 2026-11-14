// The board's own button and status LEDs on boards without the T1000-E's
// buzzer UI (GW_HAS_UI). Pins come from GW_BUTTON_PIN / GW_LED_PIN /
// GW_LED2_PIN (board.h); a board without them builds none of this.
//
// LEDs: a short blink every 5 s says the node is running; the second LED
// (blue where there is one) stays on while a phone is connected, and a board
// with one LED blinks twice instead. While an SOS runs, the status LED flashes
// once a second.
#pragma once

#include "board.h"

#define GW_HAS_BOARD_IO (!GW_HAS_UI && (GW_BUTTON_PIN >= 0 || GW_LED_PIN >= 0))

#if GW_HAS_BOARD_IO

#include <cstdint>

#include "button_gesture.h"

namespace gw {
namespace mcu {
namespace boardio {

void begin();
// Status LEDs on or off (app setting, 1.11). Off: both stay dark.
void setLeds(bool on);
// Call every loop. Returns a button gesture, if one completed.
ButtonGesture::Event poll(uint32_t nowMs, bool sosActive, bool phoneConnected);

}  // namespace boardio
}  // namespace mcu
}  // namespace gw

#endif
