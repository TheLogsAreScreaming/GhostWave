#include "power.h"

#include <Arduino.h>

#include "board.h"

#if !GW_NRF52
#include <driver/gpio.h>
#include <driver/rtc_io.h>
#include <esp_sleep.h>
#endif

namespace gw {
namespace mcu {

namespace {

void ledsOff() {
#if GW_LED_PIN >= 0
  pinMode(GW_LED_PIN, OUTPUT);
  digitalWrite(GW_LED_PIN, !GW_LED_ON);
#endif
#if GW_LED2_PIN >= 0
  pinMode(GW_LED2_PIN, OUTPUT);
  digitalWrite(GW_LED2_PIN, !GW_LED2_ON);
#endif
}

// Rails the board switched on at boot (gwSetup, radio.cpp), off again.
void railsOff() {
#if GW_HAS_KCT8103L
  digitalWrite(kPinFemCsd, LOW);
  digitalWrite(kPinFemPower, LOW);
#endif
#if GW_HAS_ANT_POWER
  digitalWrite(kPinAntPower, LOW);
#endif
#if GW_GPS_EN >= 0
  digitalWrite(GW_GPS_EN, !GW_GPS_EN_ON);
#endif
#if defined(GW_BOARD_RAK4631) || defined(GW_BOARD_RAK3401_1W)
  digitalWrite(kPin3v3SEnable, LOW);
#elif !defined(GW_BOARD_T1000E)
  if (kPinVext >= 0) digitalWrite(kPinVext, kVextOn ? LOW : HIGH);
#endif
}

#if GW_BUTTON_PIN >= 0
// The press (or a serial line holding the pin) must be over, or the button
// wakes the board the moment it sleeps. False if it is still down after 3 s.
bool buttonReleased() {
  pinMode(GW_BUTTON_PIN, GW_BUTTON_ACTIVE_LOW ? INPUT_PULLUP : INPUT_PULLDOWN);
  const int idle = GW_BUTTON_ACTIVE_LOW ? HIGH : LOW;
  for (uint32_t waited = 0; waited < 3000; waited += 10) {
    if (digitalRead(GW_BUTTON_PIN) == idle) {
      delay(100);
      return digitalRead(GW_BUTTON_PIN) == idle;
    }
    delay(10);
  }
  return false;
}
#endif

}  // namespace

#if GW_NRF52

const char* powerOnHint() {
#if GW_BUTTON_PIN >= 0
  return "press its button or its reset button, or unplug USB and plug it back in";
#else
  return "press its reset button, or unplug USB and plug it back in";
#endif
}

void releasePowerOffHolds() {}   // System OFF holds nothing over a wake (it is a reset)

[[noreturn]] void powerOffBoard() {
  ledsOff();
  railsOff();
#if GW_BUTTON_PIN >= 0
  if (buttonReleased())
    nrf_gpio_cfg_sense_input(g_ADigitalPinMap[GW_BUTTON_PIN],
                             GW_BUTTON_ACTIVE_LOW ? NRF_GPIO_PIN_PULLUP : NRF_GPIO_PIN_PULLDOWN,
                             GW_BUTTON_ACTIVE_LOW ? NRF_GPIO_PIN_SENSE_LOW : NRF_GPIO_PIN_SENSE_HIGH);
#endif
  delay(20);
  uint8_t sd = 0;
  sd_softdevice_is_enabled(&sd);
  if (sd) sd_power_system_off();
  else NRF_POWER->SYSTEMOFF = 1;
  for (;;) delay(1000);   // not reached on hardware
}

#else  // ESP32

namespace {
// Pins held at their power-off level through deep sleep.
void holdPin(int pin) {
  if (pin >= 0) gpio_hold_en(static_cast<gpio_num_t>(pin));
}
void releasePin(int pin) {
  if (pin >= 0) gpio_hold_dis(static_cast<gpio_num_t>(pin));
}
}  // namespace

// The user button wakes the chip only if it reads released before sleeping
// (on the Heltec V3 an open serial port can hold PRG down through DTR).
const char* powerOnHint() {
#if GW_BUTTON_PIN >= 0
  return "press its reset (RST) button or its user (PRG / BOOT) button";
#else
  return "press its reset (RST) button, or unplug it and plug it back in";
#endif
}

void releasePowerOffHolds() {
  releasePin(kPinVext);
  releasePin(kPinLoraCs);
#if GW_LED_PIN >= 0
  releasePin(GW_LED_PIN);
#endif
#if GW_HAS_KCT8103L
  releasePin(kPinFemPower);
  releasePin(kPinFemCsd);
#endif
  gpio_deep_sleep_hold_dis();
#if GW_BUTTON_PIN >= 0
  if (rtc_gpio_is_valid_gpio(static_cast<gpio_num_t>(GW_BUTTON_PIN)))
    rtc_gpio_deinit(static_cast<gpio_num_t>(GW_BUTTON_PIN));   // a digital input again after a button wake
#endif
}

[[noreturn]] void powerOffBoard() {
  ledsOff();
  railsOff();
  // The radio sleeps until its select line falls: keep it high, and the rails
  // and LED where they were set, through deep sleep.
  pinMode(kPinLoraCs, OUTPUT);
  digitalWrite(kPinLoraCs, HIGH);
  holdPin(kPinLoraCs);
  holdPin(kPinVext);
#if GW_LED_PIN >= 0
  holdPin(GW_LED_PIN);
#endif
#if GW_HAS_KCT8103L
  holdPin(kPinFemPower);
  holdPin(kPinFemCsd);
#endif
  gpio_deep_sleep_hold_en();
  esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);
#if GW_BUTTON_PIN >= 0
  const gpio_num_t b = static_cast<gpio_num_t>(GW_BUTTON_PIN);
  if (GW_BUTTON_ACTIVE_LOW && rtc_gpio_is_valid_gpio(b) && buttonReleased()) {
    rtc_gpio_pullup_en(b);
    rtc_gpio_pulldown_dis(b);
    esp_sleep_enable_ext0_wakeup(b, 0);
  }
#endif
  delay(20);
  esp_deep_sleep_start();
}

#endif

}  // namespace mcu
}  // namespace gw
