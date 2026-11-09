// What the RAK1921 status screen draws, as a pure function of the node's state.
// Kept apart from the I2C driver so a host program can render it to an image
// (tools/oled_preview) and the layout can be checked without a board.
#pragma once

#include <cstddef>
#include <cstdint>

class Adafruit_GFX;

namespace gw {
namespace mcu {
namespace oled {

constexpr size_t kNeighborRows = 4;

struct Status {
  const char* name;
  uint32_t nodeId;
  bool radioOk;
  bool txOn;
  bool sosOwn;
  uint32_t sosHeard;
  int outputDbm;
  uint32_t neighbors;
  uint32_t tx, rx;
  bool bleEnabled, bleConnected;
  uint8_t batteryPct;                 // 0xFF = unknown
  uint32_t neighborIds[kNeighborRows];
  uint8_t neighborIdCount;
  bool rangeShow, rangeSender;       // range test: show its page; this node is the one pinging
  uint32_t rangeSent, rangeDelivered, rangeRxSeq, rangeRxCount;
  int rangeRssi;                     // dBm, the last frame heard
};

enum class Screen : uint8_t { Splash, Status, Neighbors, Message, Range, Sos, Passkey };

struct View {
  Screen screen = Screen::Status;
  uint8_t page = 0, pages = 1;       // page dots on the normal screens
  const char* version = "";          // splash
  const char* passkey = "";          // 6 digits
  uint32_t msgFrom = 0;
  const char* msg = "";
  bool blinkOn = true;               // SOS flashes
};

void render(Adafruit_GFX& g, const Status& s, const View& v);

}  // namespace oled
}  // namespace mcu
}  // namespace gw
