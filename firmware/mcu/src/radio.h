// The board's LoRa radio (SX1262, or the LR1110 on the T1000-E) behind
// gw::RadioPort, with the board's front end (if any).
#pragma once

#include <cstddef>
#include <cstdint>

#include "ghostwave/router.h"
#include "ghostwave/util.h"
#include "region.h"

namespace gw {
namespace mcu {

class McuRadio : public RadioPort {
 public:
  // "Trail" preset (DESIGN §5, matches ghostwaved): SF/CR/preamble from `phy`,
  // BW125, sync word 0x24, CRC on. Returns the RadioLib status (0 = ok).
  // `dutyPermille`: the region's cap on airtime in any hour; 0 = none.
  int16_t begin(const Phy& phy, float freqMHz, int outputDbm, uint16_t dutyPermille);
  // Output at the antenna port, clamped to kMaxOutputDbm. Returns the value used.
  int setOutputDbm(int dbm);
  int outputDbm() const { return outputDbm_; }
  int driveDbm() const { return driveDbm_; }

  // Called before every transmission; null means always allowed. While it
  // returns false, frames are refused (receive carries on).
  void setTxGate(bool (*open)()) { txGate_ = open; }
  uint32_t txRefused() const { return txRefused_; }

  bool channelBusy() override;
  bool transmit(const uint8_t* buf, size_t len) override;

  // Non-blocking: true and fills buf/len/rssi when a good frame was received.
  bool poll(uint8_t* buf, size_t cap, size_t& len, float& rssiDbm);

  // Puts the radio in its lowest-power state, before the node powers off.
  void sleep();

  uint32_t crcErrors() const { return crcErrors_; }
  uint32_t txErrors() const { return txErrors_; }
  const DutyWindow& duty() const { return duty_; }
  uint32_t dutyDropped() const { return dutyDropped_; }

 private:
  void femRx();
  void femTx();

  int outputDbm_ = 0, driveDbm_ = 0;
  uint32_t crcErrors_ = 0, txErrors_ = 0;
  bool (*txGate_)() = nullptr;
  uint32_t txRefused_ = 0;

  // The router retries after "busy" but discards a frame on a failed
  // transmit, and its queue has no limit. So: at the cap, report busy for up
  // to kDutyHoldMs (old airtime ages out each minute), then let frames fail.
  static constexpr uint64_t kDutyHoldMs = 60000;
  Phy phy_;
  uint32_t maxFrameMs_ = 0;
  DutyWindow duty_;
  uint64_t dutyHeldSince_ = 0;
  bool dutyHolding_ = false;
  uint32_t dutyDropped_ = 0;
};

}  // namespace mcu
}  // namespace gw
