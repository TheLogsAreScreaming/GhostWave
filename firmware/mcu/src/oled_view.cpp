#ifndef GW_HOST_PREVIEW
#include "board.h"
#endif

#if defined(GW_HOST_PREVIEW) || GW_HAS_OLED

#include "oled_view.h"

#include <Adafruit_GFX.h>
#include <Fonts/FreeSansBold18pt7b.h>
#include <Fonts/FreeSansBold9pt7b.h>
#include <Fonts/TomThumb.h>

#include <cctype>
#include <cstdio>
#include <cstring>

namespace gw {
namespace mcu {
namespace oled {

namespace {

constexpr uint16_t kOn = 1, kOff = 0;
constexpr int kW = 128, kH = 64;
constexpr int kBarH = 11;   // header bar height

// Text helpers. `y` is the top of the text for the built-in and TomThumb fonts
// and the baseline for the FreeSans fonts, as Adafruit GFX does.
void text(Adafruit_GFX& g, const GFXfont* f, int x, int y, const char* s, uint16_t c = kOn) {
  g.setFont(f);
  g.setTextSize(1);
  g.setTextColor(c);
  g.setTextWrap(false);
  g.setCursor(x, y);
  g.print(s);
}

int width(Adafruit_GFX& g, const GFXfont* f, const char* s) {
  int16_t x1, y1;
  uint16_t w, h;
  g.setFont(f);
  g.setTextSize(1);
  g.getTextBounds(s, 0, 30, &x1, &y1, &w, &h);
  return static_cast<int>(w);
}

void centered(Adafruit_GFX& g, const GFXfont* f, int y, const char* s, uint16_t c = kOn) {
  text(g, f, (kW - width(g, f, s)) / 2, y, s, c);
}

// TomThumb: 3x5 capitals for labels. Its cursor sits on the baseline.
void label(Adafruit_GFX& g, int x, int y, const char* s, uint16_t c = kOn) { text(g, &TomThumb, x, y + 5, s, c); }

void bluetooth(Adafruit_GFX& g, int x, int y, uint16_t c) {
  g.drawLine(x + 2, y, x + 2, y + 8, c);
  g.drawLine(x + 2, y, x + 4, y + 2, c);
  g.drawLine(x + 4, y + 2, x, y + 6, c);
  g.drawLine(x + 2, y + 8, x + 4, y + 6, c);
  g.drawLine(x + 4, y + 6, x, y + 2, c);
}

void battery(Adafruit_GFX& g, int x, int y, uint8_t pct, uint16_t c) {
  g.drawRect(x, y, 14, 7, c);
  g.fillRect(x + 14, y + 2, 1, 3, c);
  if (pct == 0xFF) {
    g.drawLine(x + 5, y + 2, x + 8, y + 4, c);   // unknown: a slash
    return;
  }
  int fill = (pct > 100 ? 100 : pct) * 10 / 100;
  g.fillRect(x + 2, y + 2, fill, 3, c);
}

// Five bars from -120 dBm (none) to -60 dBm (all).
void signalBars(Adafruit_GFX& g, int x, int y, int rssi) {
  int bars = rssi >= -60 ? 5 : rssi <= -120 ? 0 : (rssi + 120) / 12;
  for (int i = 0; i < 5; ++i) {
    int h = 3 + i * 3;
    if (i < bars) g.fillRect(x + i * 5, y + 15 - h, 4, h, kOn);
    else g.drawRect(x + i * 5, y + 15 - h, 4, h, kOn);
  }
}

void header(Adafruit_GFX& g, const Status& s) {
  g.fillRect(0, 0, kW, kBarH, kOn);
  char name[16];
  std::snprintf(name, sizeof name, "%s", s.name && s.name[0] ? s.name : "GhostWave");
  if (std::strlen(name) > 12) name[12] = 0;
  text(g, nullptr, 2, 2, name, kOff);
  int x = kW - 2 - 15;
  battery(g, x, 2, s.batteryPct, kOff);
  x -= 15;
  // TX/RX tag: a hollow box while listening, solid while transmitting is on
  if (s.txOn) {
    g.fillRect(x, 1, 13, 9, kOff);
    label(g, x + 3, 3, "TX", kOn);
  } else {
    g.drawRect(x, 1, 13, 9, kOff);
    label(g, x + 3, 3, "RX", kOff);
  }
  if (s.bleEnabled) {
    x -= 9;
    bluetooth(g, x, 1, kOff);
    if (s.bleConnected) g.fillRect(x + 6, 4, 2, 2, kOff);
  }
}

void pageDots(Adafruit_GFX& g, const View& v) {
  if (v.pages < 2) return;
  int x = kW - 2 - (v.pages - 1) * 5;
  for (uint8_t i = 0; i < v.pages; ++i) {
    if (i == v.page) g.fillRect(x + i * 5 - 1, 61, 3, 3, kOn);
    else g.drawPixel(x + i * 5, 62, kOn);
  }
}

void stat(Adafruit_GFX& g, int x, const char* name, const char* value) {
  label(g, x, 44, name);
  text(g, nullptr, x, 52, value);
}

void statusPage(Adafruit_GFX& g, const Status& s) {
  const char* head = !s.radioOk ? "No radio" : s.txOn ? "On air" : "Listening";
  text(g, &FreeSansBold9pt7b, 0, 28, head);
  if (s.radioOk && s.txOn) {
    char dbm[12];
    std::snprintf(dbm, sizeof dbm, "%d dBm", s.outputDbm);
    text(g, nullptr, kW - 1 - width(g, nullptr, dbm), 18, dbm);
  }
  char near[24];
  if (!s.radioOk) std::snprintf(near, sizeof near, "check the radio");
  else if (!s.txOn) std::snprintf(near, sizeof near, "turn TX on in the app");
  else std::snprintf(near, sizeof near, "%lu node%s nearby", static_cast<unsigned long>(s.neighbors), s.neighbors == 1 ? "" : "s");
  text(g, nullptr, 0, 32, near);
  g.drawFastHLine(0, 41, kW, kOn);
  char v[12];
  std::snprintf(v, sizeof v, "%lu", static_cast<unsigned long>(s.tx));
  stat(g, 0, "SENT", v);
  std::snprintf(v, sizeof v, "%lu", static_cast<unsigned long>(s.rx));
  stat(g, 44, "HEARD", v);
  if (s.batteryPct == 0xFF) std::snprintf(v, sizeof v, "--");
  else std::snprintf(v, sizeof v, "%u%%", s.batteryPct);
  stat(g, 88, "BATTERY", v);
}

// Who this node is and how it is set up: what you need to pair, to add it as
// a contact, or to check two boards share a frequency.
void nodePage(Adafruit_GFX& g, const Status& s, const View& v) {
  char t[32];
  std::snprintf(t, sizeof t, "NODE  %08lx", static_cast<unsigned long>(s.nodeId));
  label(g, 0, 14, t);
  std::snprintf(t, sizeof t, "%.3f MHz %d dBm", static_cast<double>(s.freqMHz), s.outputDbm);
  text(g, nullptr, 0, 23, t);
  char reg[8] = "";
  for (int i = 0; s.region && s.region[i] && i < 7; ++i) reg[i] = static_cast<char>(std::toupper(static_cast<unsigned char>(s.region[i])));
  std::snprintf(t, sizeof t, "%s  TX %s", reg, s.txOn ? "on" : "off");
  text(g, nullptr, 0, 33, t);
  if (!s.bleEnabled) std::snprintf(t, sizeof t, "Bluetooth off");
  else if (s.bleConnected) std::snprintf(t, sizeof t, "Phone connected");
  else std::snprintf(t, sizeof t, "%s", s.bleName && s.bleName[0] ? s.bleName : "Bluetooth on");
  text(g, nullptr, 0, 43, t);
  const uint32_t h = s.uptimeS / 3600, m = (s.uptimeS / 60) % 60;
  std::snprintf(t, sizeof t, "V%s  UP %luH%02luM", v.version, static_cast<unsigned long>(h), static_cast<unsigned long>(m));
  label(g, 0, 53, t);
}

void neighborsPage(Adafruit_GFX& g, const Status& s) {
  char t[24];
  std::snprintf(t, sizeof t, "NEARBY  %lu", static_cast<unsigned long>(s.neighbors));
  label(g, 0, 14, t);
  if (!s.neighborIdCount) {
    text(g, nullptr, 0, 30, "No nodes heard yet");
    return;
  }
  for (uint8_t i = 0; i < s.neighborIdCount; ++i) {
    char id[12];
    std::snprintf(id, sizeof id, "%08lx", static_cast<unsigned long>(s.neighborIds[i]));
    int y = 23 + i * 10;
    g.fillCircle(3, y + 3, 2, kOn);
    text(g, nullptr, 10, y, id);
  }
}

void messagePage(Adafruit_GFX& g, const View& v) {
  char t[24];
  std::snprintf(t, sizeof t, "MESSAGE FROM %08lx", static_cast<unsigned long>(v.msgFrom));
  label(g, 0, 14, t);
  // word wrap at 21 columns of the 6 px built-in font, three lines
  const char* p = v.msg;
  for (int line = 0; line < 3 && *p; ++line) {
    while (*p == ' ') ++p;
    size_t n = std::strlen(p);
    size_t take = n <= 21 ? n : 21;
    if (n > 21) {
      size_t sp = take;
      while (sp > 0 && p[sp] != ' ') --sp;
      if (sp > 0) take = sp;
    }
    char buf[22];
    std::memcpy(buf, p, take);
    buf[take] = 0;
    if (line == 2 && n > take && take >= 3) std::memcpy(buf + take - 3, "...", 3);
    text(g, nullptr, 0, 24 + line * 10, buf);
    p += take;
  }
}

void rangePage(Adafruit_GFX& g, const Status& s) {
  label(g, 0, 14, s.rangeSender ? "RANGE TEST  SENDING" : "RANGE TEST  RECEIVING");
  char big[16];
  if (s.rangeSender) std::snprintf(big, sizeof big, "%lu/%lu", static_cast<unsigned long>(s.rangeDelivered), static_cast<unsigned long>(s.rangeSent));
  else std::snprintf(big, sizeof big, "#%lu", static_cast<unsigned long>(s.rangeRxSeq));
  text(g, &FreeSansBold18pt7b, 0, 50, big);
  signalBars(g, kW - 26, 24, s.rangeRssi);
  char dbm[12];
  std::snprintf(dbm, sizeof dbm, "%ddBm", s.rangeRssi);
  text(g, nullptr, kW - 1 - width(g, nullptr, dbm), 44, dbm);
  label(g, 0, 57, s.rangeSender ? "DELIVERED / SENT" : "LAST PING");
}

void sosPage(Adafruit_GFX& g, const Status& s, const View& v) {
  uint16_t fg = v.blinkOn ? kOff : kOn;
  if (v.blinkOn) g.fillRect(0, 0, kW, kH, kOn);
  centered(g, &FreeSansBold18pt7b, 34, "SOS", fg);
  char line[28];
  if (s.sosOwn) std::snprintf(line, sizeof line, "SENDING");
  else std::snprintf(line, sizeof line, "%lu ALERT%s - OPEN THE APP", static_cast<unsigned long>(s.sosHeard), s.sosHeard == 1 ? "" : "S");
  int w = width(g, &TomThumb, line);
  label(g, (kW - w) / 2, 46, line, fg);
}

void passkeyPage(Adafruit_GFX& g, const View& v) {
  centered(g, nullptr, 2, "Bluetooth pairing");
  g.drawFastHLine(20, 12, kW - 40, kOn);
  centered(g, &FreeSansBold18pt7b, 44, v.passkey);
  int w = width(g, &TomThumb, "ENTER THIS ON YOUR PHONE");
  label(g, (kW - w) / 2, 54, "ENTER THIS ON YOUR PHONE");
}

void splash(Adafruit_GFX& g, const View& v) {
  centered(g, &FreeSansBold9pt7b, 32, "GhostWave");
  g.drawFastHLine(30, 42, kW - 60, kOn);
  centered(g, nullptr, 48, v.version);
}

}  // namespace

void render(Adafruit_GFX& g, const Status& s, const View& v) {
  g.fillScreen(kOff);
  switch (v.screen) {
    case Screen::Splash: splash(g, v); break;
    case Screen::Passkey: passkeyPage(g, v); break;
    case Screen::Sos: sosPage(g, s, v); break;
    default:
      header(g, s);
      switch (v.screen) {
        case Screen::Node: nodePage(g, s, v); break;
        case Screen::Neighbors: neighborsPage(g, s); break;
        case Screen::Message: messagePage(g, v); break;
        case Screen::Range: rangePage(g, s); break;
        default: statusPage(g, s); break;
      }
      if (v.screen != Screen::Range) pageDots(g, v);
  }
  g.setFont(nullptr);
}

}  // namespace oled
}  // namespace mcu
}  // namespace gw

#endif
