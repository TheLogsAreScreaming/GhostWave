// Renders the RAK1921 screens (mcu/src/oled_view.cpp) to PBM images, so the
// layout can be checked without a board. Built and run by preview.sh.
#include <Adafruit_GFX.h>

#include <cstdio>
#include <string>

#include "oled_view.h"

using namespace gw::mcu::oled;

static void save(GFXcanvas1& c, const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "wb");
  std::fprintf(f, "P1\n128 64\n");
  for (int y = 0; y < 64; ++y) {
    for (int x = 0; x < 128; ++x) std::fputc(c.getPixel(x, y) ? '1' : '0', f);
    std::fputc('\n', f);
  }
  std::fclose(f);
}

int main(int argc, char** argv) {
  std::string dir = argc > 1 ? argv[1] : ".";
  GFXcanvas1 c(128, 64);
  Status s{};
  s.name = "Ridge Base";
  s.nodeId = 0xb6888904;
  s.radioOk = true;
  s.txOn = true;
  s.outputDbm = 20;
  s.neighbors = 2;
  s.tx = 1523;
  s.rx = 1488;
  s.bleEnabled = true;
  s.bleConnected = true;
  s.batteryPct = 87;
  s.neighborIds[0] = 0x9f219dbb;
  s.neighborIds[1] = 0x07afcfa7;
  s.neighborIdCount = 2;
  s.rangeSent = 24;
  s.rangeDelivered = 22;
  s.rangeRssi = -97;
  View v;
  v.pages = 3;
  v.version = "0.1.0-dev.9";
  v.passkey = "654321";
  v.msgFrom = 0x9f219dbb;
  v.msg = "At the north trailhead, heading up the ridge. Back by 6.";
  struct Shot {
    const char* name;
    Screen screen;
    uint8_t page;
  } shots[] = {{"1-splash", Screen::Splash, 0},       {"2-status", Screen::Status, 0},
               {"3-neighbors", Screen::Neighbors, 1}, {"4-message", Screen::Message, 2},
               {"5-range", Screen::Range, 0},         {"6-passkey", Screen::Passkey, 0},
               {"7-sos", Screen::Sos, 0}};
  for (auto& sh : shots) {
    v.screen = sh.screen;
    v.page = sh.page;
    if (sh.screen == Screen::Range) s.rangeSender = true;
    s.sosOwn = sh.screen == Screen::Sos;
    render(c, s, v);
    save(c, dir + "/" + sh.name + ".pbm");
  }
  s.txOn = false;
  s.bleConnected = false;
  s.batteryPct = 0xFF;
  v.screen = Screen::Status;
  v.page = 0;
  render(c, s, v);
  save(c, dir + "/8-status-listening.pbm");
  s.sosOwn = false;
  s.sosHeard = 1;
  v.screen = Screen::Sos;
  render(c, s, v);
  save(c, dir + "/9-sos-heard.pbm");
  return 0;
}
