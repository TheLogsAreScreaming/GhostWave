#include "oled.h"

#if GW_HAS_OLED

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Arduino.h>
#include <Wire.h>

#include "oled_logic.h"

namespace gw {
namespace mcu {
namespace oled {

namespace {

constexpr uint8_t kAddress = 0x3C;
constexpr uint32_t kRedrawMs = 1000;
constexpr size_t kTextMax = 63;   // three lines of 21 characters
constexpr int kBodyY = 13;
enum Page : uint8_t { kStatusPage, kNeighborPage, kMessagePage };

Adafruit_SSD1306 g_d(128, 64, &Wire, -1);
bool g_ok = false;
uint32_t g_nextDraw = 0;
ScreenPolicy g_policy;
ScreenPolicy::Level g_shown = ScreenPolicy::Level::Bright;

uint32_t g_msgFrom = 0;
char g_msg[kTextMax + 1] = "";
bool g_msgNew = false;

constexpr uint32_t kPasskeyMs = 60000;
char g_passkey[7] = "";
volatile bool g_passkeyOn = false;   // written last, so draw() never sees half a passkey
volatile bool g_passkeyNew = false;
volatile bool g_wakeRequest = false;
uint32_t g_passkeyUntil = 0;

bool g_lastBle = false, g_lastTx = false, g_lastSos = false, g_haveLast = false;

void drawBluetooth(int x, bool connected) {
  // the rune, 5 x 9
  g_d.drawLine(x + 2, 0, x + 2, 8, SSD1306_WHITE);
  g_d.drawLine(x + 2, 0, x + 4, 2, SSD1306_WHITE);
  g_d.drawLine(x + 4, 2, x, 6, SSD1306_WHITE);
  g_d.drawLine(x + 2, 8, x + 4, 6, SSD1306_WHITE);
  g_d.drawLine(x + 4, 6, x, 2, SSD1306_WHITE);
  if (connected) g_d.fillRect(x + 6, 3, 2, 3, SSD1306_WHITE);
}

void drawBattery(int x, uint8_t pct) {
  g_d.drawRect(x, 1, 13, 7, SSD1306_WHITE);
  g_d.fillRect(x + 13, 3, 2, 3, SSD1306_WHITE);
  if (pct == 0xFF) {
    g_d.setCursor(x + 4, 1);
    g_d.print('?');
  } else {
    g_d.fillRect(x + 2, 3, (pct > 100 ? 100 : pct) * 9 / 100, 3, SSD1306_WHITE);
  }
}

void drawBar(const Status& s) {
  g_d.setTextSize(1);
  g_d.setCursor(0, 0);
  char name[11];
  snprintf(name, sizeof name, "%s", s.name[0] ? s.name : "GhostWave");
  g_d.print(name);
  if (s.bleEnabled) drawBluetooth(84, s.bleConnected);
  // TX state as an inverted tag when transmitting
  if (s.txOn) {
    g_d.fillRect(94, 0, 15, 9, SSD1306_WHITE);
    g_d.setTextColor(SSD1306_BLACK);
    g_d.setCursor(96, 1);
    g_d.print("TX");
    g_d.setTextColor(SSD1306_WHITE);
  } else {
    g_d.setCursor(96, 1);
    g_d.print("RX");
  }
  drawBattery(112, s.batteryPct);
  g_d.drawFastHLine(0, 10, 128, SSD1306_WHITE);
}

void drawStatus(const Status& s) {
  g_d.setCursor(0, kBodyY);
  g_d.setTextSize(2);
  if (!s.radioOk) g_d.print("NO RADIO");
  else if (s.txOn) g_d.printf("TX %ddBm", s.outputDbm);
  else g_d.print("RX ONLY");
  g_d.setTextSize(1);
  g_d.setCursor(0, kBodyY + 19);
  g_d.printf("Node %08lx\n", static_cast<unsigned long>(s.nodeId));
  g_d.printf("Near %lu", static_cast<unsigned long>(s.neighbors));
  if (s.batteryPct != 0xFF) g_d.printf("   Batt %u%%", s.batteryPct);
  g_d.printf("\nSent %lu Heard %lu", static_cast<unsigned long>(s.tx), static_cast<unsigned long>(s.rx));
}

void drawNeighbors(const Status& s) {
  g_d.setCursor(0, kBodyY);
  g_d.printf("Neighbors: %lu\n", static_cast<unsigned long>(s.neighbors));
  if (!s.neighborIdCount) {
    g_d.print("\nNone heard yet");
    return;
  }
  for (uint8_t i = 0; i < s.neighborIdCount; ++i) {
    g_d.setCursor(0, kBodyY + 10 + i * 10);
    g_d.printf("%08lx", static_cast<unsigned long>(s.neighborIds[i]));
  }
}

void drawMessage() {
  g_d.setCursor(0, kBodyY);
  g_d.printf("From %08lx\n", static_cast<unsigned long>(g_msgFrom));
  g_d.setCursor(0, kBodyY + 12);
  g_d.print(g_msg);
}

void drawSos(const Status& s) {
  g_d.setCursor(0, kBodyY);
  g_d.setTextSize(3);
  g_d.print("SOS");
  g_d.setTextSize(1);
  g_d.setCursor(0, kBodyY + 28);
  if (s.sosOwn) g_d.print("Sending. Stop it\nfrom app or console.");
  else g_d.printf("Alerts held: %lu\nOpen the app.", static_cast<unsigned long>(s.sosHeard));
}

void drawPasskey() {
  g_d.setTextSize(1);
  g_d.setCursor(0, 0);
  g_d.print("Bluetooth pairing\nEnter on phone:");
  g_d.setTextSize(3);   // 18 px per character: six digits fill 108 of 128
  g_d.setCursor(10, 32);
  g_d.print(g_passkey);
  g_d.setTextSize(1);
}

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
    g_policy.wake(millis());
  }
  return g_ok;
}

void noteMessage(uint32_t src, const uint8_t* text, size_t len) {
  g_msgFrom = src;
  size_t n = len < kTextMax ? len : kTextMax;
  for (size_t i = 0; i < n; ++i) g_msg[i] = text[i] >= 0x20 && text[i] < 0x7F ? static_cast<char>(text[i]) : '?';
  g_msg[n] = 0;
  g_msgNew = true;
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

void wake() { g_wakeRequest = true; }

bool due(uint32_t now) {
  if (!g_ok) return false;
  return g_passkeyNew || g_msgNew || g_wakeRequest || static_cast<int32_t>(now - g_nextDraw) >= 0;
}

void draw(uint32_t now, const Status& s) {
  if (!g_ok) return;
  g_nextDraw = now + kRedrawMs;
  const bool passkeyFresh = g_passkeyNew;
  g_passkeyNew = false;
  if (passkeyFresh && g_passkeyOn) g_passkeyUntil = now + kPasskeyMs;
  if (g_passkeyOn && static_cast<int32_t>(now - g_passkeyUntil) >= 0) g_passkeyOn = false;

  const bool sos = s.sosOwn || s.sosHeard;
  if (g_wakeRequest || passkeyFresh || g_passkeyOn || sos) g_policy.wake(now);
  g_wakeRequest = false;
  if (g_haveLast && (s.bleConnected != g_lastBle || s.txOn != g_lastTx || sos != g_lastSos)) g_policy.wake(now);
  g_lastBle = s.bleConnected;
  g_lastTx = s.txOn;
  g_lastSos = sos;
  g_haveLast = true;
  if (g_msgNew) {
    g_msgNew = false;
    g_policy.show(kMessagePage, now);
  }

  const ScreenPolicy::Level level = g_policy.level(now);
  if (level != g_shown) {
    if (level == ScreenPolicy::Level::Off) g_d.ssd1306_command(SSD1306_DISPLAYOFF);
    else {
      if (g_shown == ScreenPolicy::Level::Off) g_d.ssd1306_command(SSD1306_DISPLAYON);
      g_d.dim(level == ScreenPolicy::Level::Dim);
    }
    g_shown = level;
  }
  if (level == ScreenPolicy::Level::Off) return;

  g_d.clearDisplay();
  if (g_passkeyOn) {
    drawPasskey();
  } else {
    drawBar(s);
    if (sos) {
      drawSos(s);
    } else {
      switch (g_policy.page(now, g_msg[0] ? 3 : 2)) {
        case kNeighborPage: drawNeighbors(s); break;
        case kMessagePage: drawMessage(); break;
        default: drawStatus(s); break;
      }
    }
  }
  g_d.display();
}

}  // namespace oled
}  // namespace mcu
}  // namespace gw

#endif
