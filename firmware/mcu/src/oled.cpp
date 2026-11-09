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

constexpr uint32_t kPasskeyMs = 60000;
char g_passkey[7] = "";
volatile bool g_passkeyOn = false;     // written last, so poll() never sees half a passkey
volatile bool g_passkeyNew = false;
uint32_t g_passkeyUntil = 0;

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

void showPasskey(const uint8_t digits[6]) {
  g_passkeyOn = false;
  for (int i = 0; i < 6; ++i) g_passkey[i] = static_cast<char>(digits[i]);
  g_passkey[6] = 0;
  g_passkeyNew = true;
  g_passkeyOn = true;
}

void clearPasskey() {
  g_passkeyOn = false;
  g_passkeyNew = true;   // redraw now rather than leave a stale code up
}

void poll(uint32_t now, const Status& s) {
  if (!g_ok) return;
  const bool fresh = g_passkeyNew;
  if (!fresh && static_cast<int32_t>(now - g_nextDraw) < 0) return;
  g_passkeyNew = false;
  g_nextDraw = now + kRedrawMs;
  if (fresh && g_passkeyOn) g_passkeyUntil = now + kPasskeyMs;
  if (g_passkeyOn && static_cast<int32_t>(now - g_passkeyUntil) >= 0) g_passkeyOn = false;
  g_d.clearDisplay();
  if (g_passkeyOn) {
    g_d.setTextSize(1);
    g_d.setCursor(0, 0);
    g_d.print("Bluetooth pairing\nEnter on phone:");
    g_d.setTextSize(3);   // 18 px per character: six digits fill 108 of 128
    g_d.setCursor(10, 32);
    g_d.print(g_passkey);
    g_d.setTextSize(1);
    g_d.display();
    return;
  }
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
