#include "oled.h"

#if GW_HAS_OLED

#include <Adafruit_GFX.h>
#include <Arduino.h>
#if GW_DISPLAY_TFT
#include <SPI.h>
#if GW_TFT_ST7735
#include <Adafruit_ST7735.h>
#else
#include <Adafruit_ST7789.h>
#endif
#else
#include <Wire.h>
#if GW_OLED_SH1106
#include <Adafruit_SH110X.h>
#else
#include <Adafruit_SSD1306.h>
#endif
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

#if GW_DISPLAY_TFT
// A colour TFT (Wireless Tracker V2, T114, T-Deck). The pages are drawn into a
// 128x64 one-bit buffer exactly as on the OLED, then copied onto the panel,
// centred and scaled by the largest whole factor that fits.
#if GW_TFT_SHARES_LORA_SPI
SPIClass& tftBus() { return SPI; }
#elif defined(ARDUINO_ARCH_ESP32)
SPIClass g_tftSpi(HSPI);
SPIClass& tftBus() { return g_tftSpi; }
#else
// SPIM2: SPI (the radio) is SPIM3 and SPI1 is never started on these boards.
// The panel has no MISO; P1.15 is unconnected, and as an input it is harmless.
SPIClass g_tftSpi(NRF_SPIM2, 47, GW_TFT_SCK, GW_TFT_MOSI);
SPIClass& tftBus() { return g_tftSpi; }
#endif
#if GW_TFT_ST7735
Adafruit_ST7735 g_tft(&tftBus(), GW_TFT_CS, GW_TFT_DC, GW_TFT_RST);
#else
Adafruit_ST7789 g_tft(&tftBus(), GW_TFT_CS, GW_TFT_DC, GW_TFT_RST);
#endif
GFXcanvas1 g_d(128, 64);
constexpr int kScale = (GW_TFT_W >= 256 && GW_TFT_H >= 128) ? 2 : 1;
constexpr int kX0 = (GW_TFT_W - 128 * kScale) / 2;
constexpr int kY0 = (GW_TFT_H - 64 * kScale) / 2;
constexpr uint16_t kInk = 0xFFFF;   // white
constexpr uint16_t kPaper = 0x0000;

void backlight(uint8_t level) {
#if GW_TFT_BL >= 0
  // level 0..255; an active-low backlight takes the inverse duty.
  analogWrite(GW_TFT_BL, GW_TFT_BL_ON == HIGH ? level : 255 - level);
#else
  (void)level;
#endif
}

bool panelBegin() {
#if GW_TFT_POWER >= 0
  pinMode(GW_TFT_POWER, OUTPUT);
  digitalWrite(GW_TFT_POWER, GW_TFT_POWER_ON);
  delay(20);
#endif
#if GW_TFT_SHARES_LORA_SPI
  // The radio is not started yet: keep it off the bus while the panel starts.
  pinMode(kPinLoraCs, OUTPUT);
  digitalWrite(kPinLoraCs, HIGH);
  SPI.begin(kPinLoraSck, kPinLoraMiso, kPinLoraMosi);
#elif defined(ARDUINO_ARCH_ESP32)
  g_tftSpi.begin(GW_TFT_SCK, -1, GW_TFT_MOSI, GW_TFT_CS);
#endif
#if GW_TFT_ST7735
  g_tft.initR(INITR_MINI160x80);
#else
  g_tft.init(GW_TFT_W < GW_TFT_H ? GW_TFT_W : GW_TFT_H, GW_TFT_W < GW_TFT_H ? GW_TFT_H : GW_TFT_W);
#endif
  g_tft.setRotation(1);   // landscape
  g_tft.fillScreen(kPaper);
  backlight(255);
  return true;   // SPI has no acknowledge: a fitted panel is assumed
}
void panelOn(bool on) {
  g_tft.enableDisplay(on);
  backlight(on ? 255 : 0);
}
void panelDim(bool dim) { backlight(dim ? 24 : 255); }

// Copies the one-bit buffer to the panel, a scaled row at a time.
void present() {
  static uint16_t row[128 * kScale];
  const uint8_t* buf = g_d.getBuffer();
  g_tft.startWrite();
  g_tft.setAddrWindow(kX0, kY0, 128 * kScale, 64 * kScale);
  for (int y = 0; y < 64; ++y) {
    for (int x = 0; x < 128; ++x) {
      const bool on = buf[y * 16 + x / 8] & (0x80 >> (x & 7));
      for (int k = 0; k < kScale; ++k) row[x * kScale + k] = on ? kInk : kPaper;
    }
    for (int k = 0; k < kScale; ++k) g_tft.writePixels(row, 128 * kScale);
  }
  g_tft.endWrite();
}
#else
// The panel: SSD1306 (RAK1921, Heltec, T3-S3, T-Beam add-on, Wio Tracker L1)
// or SH1106 (T-Beam Supreme). Only switching it on, off and dimming differ;
// render() draws on either through Adafruit_GFX.
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
void present() { g_d.display(); }
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
#if GW_DISPLAY_TFT
  g_ok = panelBegin();
#else
#if GW_OLED_RST >= 0
  // Heltec boards wire the panel's reset to a GPIO: it stays blank until pulsed.
  pinMode(GW_OLED_RST, OUTPUT);
  digitalWrite(GW_OLED_RST, LOW);
  delay(10);
  digitalWrite(GW_OLED_RST, HIGH);
  delay(10);
#endif
#if GW_OLED_SDA >= 0
#if defined(ARDUINO_ARCH_ESP32)
  Wire.begin(GW_OLED_SDA, GW_OLED_SCL);
#else
  Wire.setPins(GW_OLED_SDA, GW_OLED_SCL);
  Wire.begin();
#endif
#else
  Wire.begin();
#endif
  Wire.beginTransmission(kAddress);
  if (Wire.endTransmission() != 0) return false;   // no screen fitted
  g_ok = panelBegin();
  if (g_ok) Wire.setClock(400000);
#endif
  if (g_ok) {
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
  present();
}

}  // namespace oled
}  // namespace mcu
}  // namespace gw

#endif
