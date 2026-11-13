// BLE transport for the client link: nRF52 boards in ble_link.cpp (Bluefruit,
// Adafruit nRF52 core), ESP32 boards in ble_link_esp32.cpp (NimBLE). docs/CLIENT_PROTOCOL.md "BLE transport" is the spec: one
// custom service, ToRadio written by the app (write with response), FromRadio
// notified by the node, both carrying the same frames as TCP. LE Secure
// Connections pairing with a passkey printed on the serial console, bonds in
// internal flash. One app connection at a time.
//
// Bluefruit calls back from its own FreeRTOS tasks; those callbacks only copy
// bytes and bump counters. Everything else (the handler, the router) runs in
// poll(), from the GhostWave task.
#pragma once

#include "board.h"

#if GW_HAS_BLE

#include <cstddef>
#include <cstdint>
#include <string>

#include "ghostwave/client_handler.h"
#include "ghostwave/frame_chunker.h"

namespace gw {
namespace mcu {

class BleLink : public gw::client::Transport {
 public:
  // Service and characteristic UUIDs (docs/CLIENT_PROTOCOL.md).
  static constexpr const char* kServiceUuid = "47570001-eea4-45e8-ac37-ff6530d92471";
  static constexpr const char* kToRadioUuid = "47570002-eea4-45e8-ac37-ff6530d92471";
  static constexpr const char* kFromRadioUuid = "47570003-eea4-45e8-ac37-ff6530d92471";
  static constexpr uint16_t kMtu = 247;          // requested; 185 is the floor iPhones give
  static constexpr size_t kOutCap = 6 * 1024;    // queued notifications before frames are dropped

  // Starts the SoftDevice, the GATT service and pairing. `name` is the
  // advertised name. Advertises only if `enabled`.
  bool begin(const std::string& name, bool enabled, const char* pin);
  void attach(gw::client::Handler* h) { h_ = h; }
  void poll(uint64_t nowMs);

  void setEnabled(bool on);
  bool enabled() const { return enabled_; }
  bool connected() const { return open_; }
  // The advertised name, e.g. GhostWave-34e1.
  const std::string& name() const { return name_; }
  // Forgets every bonded phone (and drops the current connection).
  void clearBonds();
  // One line for the `ble` command.
  std::string describe();

  // gw::client::Transport
  void write(gw::client::Conn& c, const uint8_t* frame, size_t n) override;
  void forEachConn(const std::function<void(gw::client::Conn&)>& fn) override;
  bool holdEvents() const override { return enabled_; }
  void log(const std::string& line) override;

 private:
  void resetConn();
  void flushOut();

  gw::client::Handler* h_ = nullptr;
  bool started_ = false;
  bool enabled_ = false;
  bool open_ = false;            // a phone is connected (as of the last poll)
  uint16_t connHdl_ = 0xFFFF;
  uint32_t seenConnects_ = 0, seenDisconnects_ = 0;
  gw::client::Conn conn_;
  gw::client::FrameReader in_;
  gw::client::FrameChunker out_{kOutCap};
  uint32_t dropped_ = 0;         // frames dropped because the app stopped reading
  std::string name_;
};

}  // namespace mcu
}  // namespace gw

#endif  // GW_HAS_BLE
