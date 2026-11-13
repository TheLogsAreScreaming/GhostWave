#include "oled.h"

#if GW_HAS_OLED

#include <Adafruit_GFX.h>
#include <Arduino.h>
#include <Wire.h>
#if GW_OLED_SH1106
#include <Adafruit_SH110X.h>
#else
#include <Adafruit_SSD1306.h>
#endif

#include "oled_logic.h"

namespace gw {
namespace mcu {
namespace oled {

namespace {

constexpr uint8_t kAddress = 0x3C;
constexpr uint32_t kRedrawMs = 1000;
constexpr uint32_t kBlinkMs = 500;
constexpr uint32_t kSplashMs = 2000;
constexpr size_t kTextMax = 63;   // three lines of 21 characters
enum Page : uint8_t { kStatusPage, kNodePage, kNeighborPage, kMessagePage };

// The panel: SSD1306 (RAK1921, Heltec, T3-S3, T-Beam add-on) or SH1106
// (T-Beam Supreme). Only switching it on, off and dimming differ; render()
// draws on either through Adafruit_GFX.
#if GW_OLED_SH1106
Adafruit_SH1106G g_d(128, 64, &Wire, -1);
bool panelBegin() { return g_d.begin(kAddress, true); }
void panelOn(bool on) { g_d.oled_command(on ? SH110X_DISPLAYON : SH110X_DISPLAYOFF); }
void panelDim(bool dim) { g_d.setContrast(dim ? 0x08 : 0x7F); }
#else
Adafruit_SSD1306 g_d(128, 64, &Wire, -1);
bool panelBegin() { return g_d.begin(SSD1306_SWITCHCAPVCC, kAddress); }
void panelOn(bool on) { g_d.ssd1306_command(on ? SSD1306_DISPLAYON : SSD1306_DISPLAYOFF); }
void panelDim(bool dim) { g_d.dim(dim); }
#endif
bool g_ok = false;
uint32_t g_nextDraw = 0;
uint32_t g_splashUntil = 0;
const char* g_version = "";
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

}  // namespace

bool begin(const char* version) {
  g_version = version ? version : "";
  // The board has just switched its display power on (Vext on Heltec boards).
  delay(50);
#if GW_OLED_RST >= 0
  // Heltec boards wire the panel's reset to a GPIO: it stays blank until pulsed.
  pinMode(GW_OLED_RST, OUTPUT);
  digitalWrite(GW_OLED_RST, LOW);
  delay(10);
  digitalWrite(GW_OLED_RST, HIGH);
  delay(10);
#endif
#if GW_OLED_SDA >= 0
  Wire.begin(GW_OLED_SDA, GW_OLED_SCL);
#else
  Wire.begin();
#endif
  Wire.beginTransmission(kAddress);
  if (Wire.endTransmission() != 0) return false;   // no screen fitted
  g_ok = panelBegin();
  if (g_ok) {
    Wire.setClock(400000);
    g_policy.wake(millis());
    g_splashUntil = millis() + kSplashMs;
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
  const bool sos = s.sosOwn || s.sosHeard;
  g_nextDraw = now + (sos ? kBlinkMs : kRedrawMs);
  const bool passkeyFresh = g_passkeyNew;
  g_passkeyNew = false;
  if (passkeyFresh && g_passkeyOn) g_passkeyUntil = now + kPasskeyMs;
  if (g_passkeyOn && static_cast<int32_t>(now - g_passkeyUntil) >= 0) g_passkeyOn = false;

  if (g_wakeRequest || passkeyFresh || g_passkeyOn || sos || s.rangeShow) g_policy.wake(now);
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
    if (level == ScreenPolicy::Level::Off) panelOn(false);
    else {
      if (g_shown == ScreenPolicy::Level::Off) panelOn(true);
      panelDim(level == ScreenPolicy::Level::Dim);
    }
    g_shown = level;
  }
  if (level == ScreenPolicy::Level::Off) return;

  View v;
  v.version = g_version;
  v.passkey = g_passkey;
  v.msgFrom = g_msgFrom;
  v.msg = g_msg;
  v.blinkOn = (now / kBlinkMs) % 2 == 0;
  if (g_passkeyOn) {
    v.screen = Screen::Passkey;
  } else if (sos) {
    v.screen = Screen::Sos;
  } else if (static_cast<int32_t>(now - g_splashUntil) < 0) {
    v.screen = Screen::Splash;
  } else if (s.rangeShow) {
    v.screen = Screen::Range;
  } else {
    v.pages = g_msg[0] ? 4 : 3;
    v.page = g_policy.page(now, v.pages);
    v.screen = v.page == kNodePage       ? Screen::Node
               : v.page == kNeighborPage ? Screen::Neighbors
               : v.page == kMessagePage  ? Screen::Message
                                         : Screen::Status;
  }
  render(g_d, s, v);
  g_d.display();
}

}  // namespace oled
}  // namespace mcu
}  // namespace gw

#endif
