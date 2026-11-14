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
#elif GW_DISPLAY_EINK
#include <SPI.h>
#include <string.h>

#include "eink_logic.h"
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
ScreenPolicy g_policy;

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
#elif GW_DISPLAY_EINK
// A black-and-white e-ink panel (T-Echo: 1.54" 200x200, SSD1681 controller).
// The pages are drawn into the same 128x64 buffer, then sent to the panel at
// 1.5x. E-ink holds its picture with no power and wears with each refresh, so
// eink::RefreshPolicy picks when to refresh and how (partial or full), and the
// controller sleeps between refreshes. A refresh runs on its own: the loop never
// waits the ~2 s a full one takes.
// SPIM2: SPI (the radio) is SPIM3. The panel has no MISO; the pin is unused.
SPIClass g_epdSpi(NRF_SPIM2, GW_EINK_MISO, GW_EINK_SCK, GW_EINK_MOSI);
const SPISettings kEpdSpi(4000000, MSBFIRST, SPI_MODE0);
GFXcanvas1 g_d(128, 64);
constexpr int kEpdW = GW_EINK_W, kEpdH = GW_EINK_H;
uint8_t g_shownBuf[128 * 64 / 8];   // what the panel shows now (the "old" picture for a partial)
bool g_haveShown = false;
bool g_refreshing = false;          // a refresh was started and the panel may still be busy
bool g_pendingUrgent = false;       // an event is waiting to be shown
uint32_t g_epdNow = 0;
eink::RefreshPolicy g_refresh;

void epdSend(bool data, uint8_t b) {
  digitalWrite(GW_EINK_DC, data ? HIGH : LOW);
  digitalWrite(GW_EINK_CS, LOW);
  g_epdSpi.beginTransaction(kEpdSpi);
  g_epdSpi.transfer(b);
  g_epdSpi.endTransaction();
  digitalWrite(GW_EINK_CS, HIGH);
}
void epdCmd(uint8_t c) { epdSend(false, c); }
void epdData(uint8_t d) { epdSend(true, d); }
bool epdBusy() { return digitalRead(GW_EINK_BUSY) == HIGH; }
bool epdWaitIdle(uint32_t maxMs) {
  const uint32_t start = millis();
  while (epdBusy()) {
    if (millis() - start > maxMs) return false;
    delay(1);
  }
  return true;
}

// Wakes the controller out of deep sleep (a reset) and sets it up. A partial
// refresh keeps the border as it is, so the frame does not flash.
bool epdInit(bool partial) {
  digitalWrite(GW_EINK_RST, LOW);
  delay(10);
  digitalWrite(GW_EINK_RST, HIGH);
  delay(10);
  if (!epdWaitIdle(100)) return false;
  epdCmd(0x12);   // software reset
  if (!epdWaitIdle(100)) return false;
  epdCmd(0x01);   // driver output: 200 gate lines
  epdData((kEpdH - 1) & 0xFF);
  epdData((kEpdH - 1) >> 8);
  epdData(0x00);
  epdCmd(0x11);   // data entry: x then y, both increasing
  epdData(0x03);
  epdCmd(0x44);   // RAM x range, in bytes
  epdData(0x00);
  epdData(kEpdW / 8 - 1);
  epdCmd(0x45);   // RAM y range
  epdData(0x00);
  epdData(0x00);
  epdData((kEpdH - 1) & 0xFF);
  epdData((kEpdH - 1) >> 8);
  epdCmd(0x3C);   // border waveform
  epdData(partial ? 0x80 : 0x05);
  epdCmd(0x18);   // the built-in temperature sensor picks the waveform
  epdData(0x80);
  return true;
}

// Streams a 128x64 page into one of the controller's two RAMs (0x24 = the new
// picture, 0x26 = the old one), scaled and rotated. 1 = paper (white).
void epdWriteRam(uint8_t ram, const uint8_t* page) {
  epdCmd(0x4E);
  epdData(0x00);
  epdCmd(0x4F);
  epdData(0x00);
  epdData(0x00);
  epdCmd(ram);
  digitalWrite(GW_EINK_DC, HIGH);
  digitalWrite(GW_EINK_CS, LOW);
  g_epdSpi.beginTransaction(kEpdSpi);
  for (int py = 0; py < kEpdH; ++py) {
    for (int bx = 0; bx < kEpdW / 8; ++bx) {
      uint8_t b = 0xFF;
      for (int bit = 0; bit < 8; ++bit) {
        if (eink::inkAt(page, kEpdW, kEpdH, GW_EINK_ROTATION, bx * 8 + bit, py)) b &= ~(0x80 >> bit);
      }
      g_epdSpi.transfer(b);
    }
  }
  g_epdSpi.endTransaction();
  digitalWrite(GW_EINK_CS, HIGH);
}

bool panelBegin() {
  pinMode(GW_EINK_CS, OUTPUT);
  digitalWrite(GW_EINK_CS, HIGH);
  pinMode(GW_EINK_DC, OUTPUT);
  pinMode(GW_EINK_RST, OUTPUT);
  digitalWrite(GW_EINK_RST, HIGH);
  pinMode(GW_EINK_BUSY, INPUT);
#if GW_EINK_LIGHT >= 0
  pinMode(GW_EINK_LIGHT, OUTPUT);   // the front light stays off: it drains the battery
  digitalWrite(GW_EINK_LIGHT, LOW);
#endif
  g_epdSpi.begin();
  if (!epdInit(false)) return false;   // stuck busy: no panel answering
  epdCmd(0x10);                        // deep sleep until the first picture
  epdData(0x01);
  g_policy.setPagePeriod(ScreenPolicy::kEinkPageMs);
  return true;
}
// Off and dim mean nothing to e-ink: draw() puts a still picture up instead.
void panelOn(bool) {}
void panelDim(bool) {}

void present() {
  if (g_refreshing) {
    if (epdBusy()) return;   // still refreshing: try again on the next draw
    epdCmd(0x10);            // done: deep sleep (keeps the picture, ~1 uA)
    epdData(0x01);
    g_refreshing = false;
  }
  const uint8_t* page = g_d.getBuffer();
  const bool changed = !g_haveShown || memcmp(page, g_shownBuf, sizeof g_shownBuf) != 0;
  const eink::Refresh r = g_refresh.decide(g_epdNow, changed, g_pendingUrgent);
  if (r == eink::Refresh::None) return;
  const bool partial = r == eink::Refresh::Partial;
  if (!epdInit(partial)) return;
  epdWriteRam(0x26, partial ? g_shownBuf : page);
  epdWriteRam(0x24, page);
  epdCmd(0x22);   // update: clock, analog, temperature, waveform (mode 2 = partial), show, power down
  epdData(partial ? 0xFF : 0xF7);
  epdCmd(0x20);   // start; runs on its own, BUSY goes low when done
  g_refreshing = true;
  memcpy(g_shownBuf, page, sizeof g_shownBuf);
  g_haveShown = true;
  g_pendingUrgent = false;
  g_refresh.done(r, g_epdNow);
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
ScreenPolicy::Level g_shown = ScreenPolicy::Level::Bright;

uint32_t g_msgFrom = 0;
char g_msg[kTextMax + 1] = "";
bool g_msgNew = false;

constexpr uint32_t kPasskeyMs = 60000;
char g_passkey[7] = "";
volatile bool g_passkeyOn = false;   // written last, so draw() never sees half a passkey
volatile bool g_passkeyNew = false;
volatile bool g_wakeRequest = false;
volatile bool g_nextRequest = false;   // the button: next page (or just wake a dark screen)
uint8_t g_page = 0;
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

void nextPage() { g_nextRequest = true; }

void setOffAfterS(uint32_t s) {
  g_policy.setOffAfter(s * 1000u);
  g_wakeRequest = true;   // show the change: the screen lights now and counts from here
}

bool due(uint32_t now) {
  if (!g_ok) return false;
  return g_passkeyNew || g_msgNew || g_wakeRequest || g_nextRequest || static_cast<int32_t>(now - g_nextDraw) >= 0;
}

void draw(uint32_t now, const Status& s) {
  if (!g_ok) return;
  const bool sos = s.sosOwn || s.sosHeard;
  g_nextDraw = now + (sos ? kBlinkMs : kRedrawMs);
  const bool passkeyFresh = g_passkeyNew;
  g_passkeyNew = false;
  if (passkeyFresh && g_passkeyOn) g_passkeyUntil = now + kPasskeyMs;
  if (g_passkeyOn && static_cast<int32_t>(now - g_passkeyUntil) >= 0) g_passkeyOn = false;

  // A press on a lit screen turns the page; on a dark one it only wakes it.
  const bool advance = g_nextRequest && g_policy.level(now) != ScreenPolicy::Level::Off;
  if (g_nextRequest) g_wakeRequest = true;
  g_nextRequest = false;
  if (g_wakeRequest || passkeyFresh || g_passkeyOn || sos || s.rangeShow) g_policy.wake(now);
  const bool stateChanged =
      g_haveLast && (s.bleConnected != g_lastBle || s.txOn != g_lastTx || sos != g_lastSos);
#if GW_DISPLAY_EINK
  // What the reader must see now; routine changes wait (eink::RefreshPolicy).
  if (g_wakeRequest || passkeyFresh || g_msgNew || stateChanged) g_pendingUrgent = true;
  g_epdNow = now;
#endif
  g_wakeRequest = false;
  if (stateChanged) g_policy.wake(now);
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
#if GW_DISPLAY_EINK
    // Going to sleep or waking: a full refresh leaves a clean picture.
    if (level == ScreenPolicy::Level::Off || g_shown == ScreenPolicy::Level::Off) g_refresh.forceFull();
#endif
    if (level == ScreenPolicy::Level::Off) panelOn(false);
    else {
      if (g_shown == ScreenPolicy::Level::Off) panelOn(true);
      panelDim(level == ScreenPolicy::Level::Dim);
    }
    g_shown = level;
  }
  if (level == ScreenPolicy::Level::Off) {
#if GW_DISPLAY_EINK
    // E-ink keeps showing whatever it last drew. Asleep, that is the splash, not
    // numbers that go stale; present() only refreshes it once.
    View sleepView;
    sleepView.screen = Screen::Splash;
    sleepView.version = g_version;
    render(g_d, s, sleepView);
    present();
#endif
    return;
  }

  View v;
  v.version = g_version;
  v.passkey = g_passkey;
  v.msgFrom = g_msgFrom;
  v.msg = g_msg;
#if GW_DISPLAY_EINK
  v.blinkOn = true;   // e-ink never flashes: the SOS screen stays inverted
#else
  v.blinkOn = (now / kBlinkMs) % 2 == 0;
#endif
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
    if (advance) g_policy.show(static_cast<uint8_t>((g_page + 1) % v.pages), now);
    v.page = g_policy.page(now, v.pages);
    g_page = v.page;
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
