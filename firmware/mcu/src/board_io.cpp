#include "board_io.h"

#if GW_HAS_BOARD_IO

#include <Arduino.h>

#include "led_pattern.h"

namespace gw {
namespace mcu {
namespace boardio {

namespace {

#if GW_BUTTON_PIN >= 0
ButtonGesture g_button;
#endif
bool g_ledsOn = true;

void led(int pin, int onLevel, bool on) {
  if (pin >= 0) digitalWrite(pin, on ? onLevel : !onLevel);
}

}  // namespace

void begin() {
#if GW_BUTTON_PIN >= 0
  pinMode(GW_BUTTON_PIN, GW_BUTTON_ACTIVE_LOW ? INPUT_PULLUP : INPUT_PULLDOWN);
#endif
#if GW_LED_PIN >= 0
  pinMode(GW_LED_PIN, OUTPUT);
  led(GW_LED_PIN, GW_LED_ON, false);
#endif
#if GW_LED2_PIN >= 0
  pinMode(GW_LED2_PIN, OUTPUT);
  led(GW_LED2_PIN, GW_LED2_ON, false);
#endif
}

void setLeds(bool on) { g_ledsOn = on; }

ButtonGesture::Event poll(uint32_t now, bool sosActive, bool phoneConnected) {
  LedState st = ledState(now, sosActive, phoneConnected, GW_LED2_PIN >= 0);
  if (!g_ledsOn) st = LedState{false, false};
  led(GW_LED_PIN, GW_LED_ON, st.status);
  led(GW_LED2_PIN, GW_LED2_ON, st.link);
#if GW_BUTTON_PIN >= 0
  const bool pressed = digitalRead(GW_BUTTON_PIN) == (GW_BUTTON_ACTIVE_LOW ? LOW : HIGH);
  return g_button.update(pressed, now);
#else
  return ButtonGesture::Event::None;
#endif
}

}  // namespace boardio
}  // namespace mcu
}  // namespace gw

#endif
