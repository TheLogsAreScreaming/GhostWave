#include "oled.h"

#if GW_HAS_OLED

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Arduino.h>
#include <Wire.h>

namespace gw {
namespace mcu {
namespace oled {

namespace {

constexpr uint8_t kAddress = 0x3C;
constexpr uint32_t kRedrawMs = 1000;
constexpr size_t kTextMax = 42;   // two lines of 21 characters

Adafruit_SSD1306 g_d(128, 64, &Wire, -1);
bool g_ok = false;
uint32_t g_nextDraw = 0;
uint32_t g_msgFrom = 0;
char g_msg[kTextMax + 1] = "";

}  // namespace

bool begin() {
  Wire.begin();
  Wire.beginTransmission(kAddress);
  if (Wire.endTransmission() != 0) return false;   // no screen fitted
  g_ok = g_d.begin(SSD1306_SWITCHCAPVCC, kAddress);
  if (g_ok) {
    Wire.setClock(400000);
    g_d.setTextColor(SSD1306_WHITE);
    g_d.setTextWrap(true);
  }
  return g_ok;
}

void noteMessage(uint32_t src, const uint8_t* text, size_t len) {
  g_msgFrom = src;
  size_t n = len < kTextMax ? len : kTextMax;
  for (size_t i = 0; i < n; ++i) g_msg[i] = text[i] >= 0x20 && text[i] < 0x7F ? static_cast<char>(text[i]) : '?';
  g_msg[n] = 0;
}

void poll(uint32_t now, const Status& s) {
  if (!g_ok || static_cast<int32_t>(now - g_nextDraw) < 0) return;
  g_nextDraw = now + kRedrawMs;
  g_d.clearDisplay();
  g_d.setCursor(0, 0);
  g_d.printf("%s %08lx\n", s.name[0] ? s.name : "GhostWave", static_cast<unsigned long>(s.nodeId));
  if (s.sosOwn) g_d.print("** SOS SENDING **\n");
  else if (s.sosHeard) g_d.printf("** SOS HEARD: %lu **\n", static_cast<unsigned long>(s.sosHeard));
  else if (!s.radioOk) g_d.print("RADIO FAILED\n");
  else if (!s.txOn) g_d.print("TX OFF: receive only\n");
  else g_d.printf("TX on  %d dBm\n", s.outputDbm);
  g_d.printf("Neighbors %lu\n", static_cast<unsigned long>(s.neighbors));
  g_d.printf("Sent %lu  Heard %lu\n", static_cast<unsigned long>(s.tx), static_cast<unsigned long>(s.rx));
  if (g_msg[0]) {
    g_d.printf("\nFrom %08lx\n%s", static_cast<unsigned long>(g_msgFrom), g_msg);
  }
  g_d.display();
}

}  // namespace oled
}  // namespace mcu
}  // namespace gw

#endif
