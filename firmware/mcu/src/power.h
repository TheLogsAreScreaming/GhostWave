// Powering the board off from software: the `poweroff` console command and
// the app's PowerOff (protocol 1.16). The caller puts the radio to sleep and
// darkens the screen first; this switches the board's power rails off and
// stops the chip until something wakes it:
//   nRF52 (RAK, T-Echo, T114, ...): System OFF. Wakes on the reset button, on
//     plugging in USB, or on the user button where the board has one.
//   ESP32 (Heltec, T-Beam, ...): deep sleep. Wakes on the reset (RST) button,
//     or on the user button (PRG / BOOT) where it can wake the chip.
// The T1000-E keeps its own path (ui::powerOff: buzzer, button wake).
#pragma once

namespace gw {
namespace mcu {

// What brings this board back, for the console and the app.
const char* powerOnHint();

[[noreturn]] void powerOffBoard();

// Call once at boot, before the pins are set up: lets go of the pins a
// previous power-off held in place (ESP32 deep sleep keeps them held).
void releasePowerOffHolds();

}  // namespace mcu
}  // namespace gw
