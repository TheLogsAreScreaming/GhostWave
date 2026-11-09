#include "radio.h"

#include <Arduino.h>
#include <RadioLib.h>
#include <SPI.h>

#include "board.h"
#include "platform.h"

namespace gw {
namespace mcu {

namespace {

// Private: keeps other meshes' frames out at the PHY. On the SX1262 RadioLib
// writes it as 0x2444 (setSyncWord(0x24, controlBits 0x44)); on the LR1110
// SetLoRaSyncWord takes the same one-byte form (0x12 private / 0x34 public map
// to the SX126x's 0x1424 / 0x3444), so both chips put the same sync symbols
// on the air and hear each other.
constexpr uint8_t kSyncWord = 0x24;

#if GW_RADIO_LR1110
constexpr int kMinDriveDbm = -17;     // LR1110: low-power PA from -17, high-power PA to +22
constexpr int kMaxDriveDbm = 22;
LR1110 g_sx(new Module(kPinLoraCs, kPinLoraDio1, kPinLoraRst, kPinLoraBusy, SPI));

// T1000-E RF switch on LR1110 DIO5..DIO8, from meshtastic/firmware
// variants/nrf52840/tracker-t1000-e/rfswitch.h; the same bits as Seeed's SDK
// rfswitch_cfg (RFSW0..3 = DIO5..8: rx 0+3, tx 0+1+3, tx_hp 1+3, gnss 2).
const uint32_t kRfSwitchPins[Module::RFSWITCH_MAX_PINS] = {RADIOLIB_LR11X0_DIO5, RADIOLIB_LR11X0_DIO6,
                                                           RADIOLIB_LR11X0_DIO7, RADIOLIB_LR11X0_DIO8, RADIOLIB_NC};
const Module::RfSwitchMode_t kRfSwitchTable[] = {
    // mode                 DIO5  DIO6  DIO7  DIO8
    {LR11x0::MODE_STBY, {LOW, LOW, LOW, LOW}},
    {LR11x0::MODE_RX, {HIGH, LOW, LOW, HIGH}},
    {LR11x0::MODE_TX, {HIGH, HIGH, LOW, HIGH}},
    {LR11x0::MODE_TX_HP, {LOW, HIGH, LOW, HIGH}},
    {LR11x0::MODE_TX_HF, {LOW, LOW, LOW, LOW}},
    {LR11x0::MODE_GNSS, {LOW, LOW, HIGH, LOW}},
    {LR11x0::MODE_WIFI, {LOW, LOW, LOW, LOW}},
    END_OF_MODE_TABLE,
};
#elif defined(GW_RADIO_SX1276)
constexpr int kMinDriveDbm = 2;       // PA_BOOST range. Kept to 17: +20 dBm is rated for 1% duty only
constexpr int kMaxDriveDbm = 17;
// For an SX1276 the IRQ argument is DIO0 and the GPIO argument is DIO1.
SX1276 g_sx(new Module(kPinLoraCs, kPinLoraDio1, kPinLoraRst, kPinLoraBusy, SPI));
#else
constexpr int kMinDriveDbm = -9;      // SX1262 high-power PA range
constexpr int kMaxDriveDbm = 22;
SX1262 g_sx(new Module(kPinLoraCs, kPinLoraDio1, kPinLoraRst, kPinLoraBusy, GW_LORA_SPI));
#endif

// SX1262 drive for `out` dBm at the antenna port.
int driveFor(int out) {
#if GW_HAS_KCT8103L || GW_HAS_PA_CURVE
  // Highest drive whose drive + FEM gain does not exceed the target; same
  // search as Meshtastic's LoRaFEMInterface::powerConversion.
  for (int d = static_cast<int>(sizeof kPaGainDb) - 1; d >= 0; --d)
    if (d + kPaGainDb[d] <= out) return d;
  int d = out - kPaGainDb[0];
  return d < kMinDriveDbm ? kMinDriveDbm : d;
#else
  if (out < kMinDriveDbm) return kMinDriveDbm;
  return out > kMaxDriveDbm ? kMaxDriveDbm : out;
#endif
}

}  // namespace

int16_t McuRadio::begin(const Phy& phy, float freqMHz, int outputDbm, uint16_t dutyPermille) {
  phy_ = phy;
  maxFrameMs_ = airtimeMs(phy, kMaxFrame);
  duty_.setPermille(dutyPermille);
#if GW_HAS_KCT8103L
  // Power-up order from Meshtastic's LoRaFEMInterface::init: LDO, then chip
  // enable, LNA on for receive.
  pinMode(kPinFemPower, OUTPUT);
  digitalWrite(kPinFemPower, HIGH);
  delay(1);
  pinMode(kPinFemCsd, OUTPUT);
  digitalWrite(kPinFemCsd, HIGH);
  pinMode(kPinFemCtx, OUTPUT);
  femRx();
#endif
#if GW_HAS_ANT_POWER
  pinMode(kPinAntPower, OUTPUT);
  digitalWrite(kPinAntPower, HIGH);   // antenna switch powered; DIO2 picks TX/RX
  delay(1);
#endif
#if GW_NRF52
  GW_LORA_SPI.begin();   // the SX1262 bus: the variant's default SPI, except on the 1 W module
#else
  SPI.begin(kPinLoraSck, kPinLoraMiso, kPinLoraMosi, kPinLoraCs);
#endif
  outputDbm_ = outputDbm > kMaxOutputDbm ? kMaxOutputDbm : outputDbm;
  driveDbm_ = driveFor(outputDbm_);
#if GW_RADIO_LR1110
  g_sx.setRfSwitchTable(kRfSwitchPins, kRfSwitchTable);   // before begin(): it drives standby
  int16_t st = g_sx.begin(freqMHz, phy.bwHz / 1000.0f, phy.sf, 4 + phy.cr, kSyncWord, driveDbm_,
                          phy.preamble, kTcxoVolts);
  if (st != RADIOLIB_ERR_NONE) return st;
  st = g_sx.setCRC(2);   // LoRa: any length > 0 = payload CRC on
#elif defined(GW_RADIO_SX1276)
  int16_t st = g_sx.begin(freqMHz, phy.bwHz / 1000.0f, phy.sf, 4 + phy.cr, kSyncWord, driveDbm_, phy.preamble, 0);
  if (st != RADIOLIB_ERR_NONE) return st;
  st = g_sx.setCRC(true);
#else
  int16_t st = g_sx.begin(freqMHz, phy.bwHz / 1000.0f, phy.sf, 4 + phy.cr, kSyncWord, driveDbm_,
                          phy.preamble, kTcxoVolts, false);
  if (st != RADIOLIB_ERR_NONE) return st;
  st = g_sx.setDio2AsRfSwitch(true);
#ifdef GW_LORA_RXEN
  g_sx.setRfSwitchPins(GW_LORA_RXEN, RADIOLIB_NC);   // LNA enable; DIO2 still drives the switch
#endif
  if (st == RADIOLIB_ERR_NONE) st = g_sx.setCRC(2);
#endif
  if (st == RADIOLIB_ERR_NONE) st = g_sx.startReceive();
  return st;
}

int McuRadio::setOutputDbm(int dbm) {
  outputDbm_ = dbm > kMaxOutputDbm ? kMaxOutputDbm : dbm;
  driveDbm_ = driveFor(outputDbm_);
  g_sx.setOutputPower(driveDbm_);
  g_sx.startReceive();
  return outputDbm_;
}

void McuRadio::femRx() {
#if GW_HAS_KCT8103L
  digitalWrite(kPinFemCtx, LOW);    // receive through the LNA
#endif
}

void McuRadio::femTx() {
#if GW_HAS_KCT8103L
  digitalWrite(kPinFemCtx, HIGH);   // PA path (CPS follows DIO2)
#endif
}

void McuRadio::sleep() { g_sx.sleep(); }

bool McuRadio::channelBusy() {
  if (txGate_ && !txGate_()) return false;   // transmit() refuses it: no need for a CAD
  if (!duty_.allows(nowMs(), maxFrameMs_)) {
    const uint64_t now = nowMs();
    if (!dutyHolding_) {
      dutyHolding_ = true;
      dutyHeldSince_ = now;
      Serial.println("duty-cycle cap reached: holding transmissions");
    }
    if (now - dutyHeldSince_ < kDutyHoldMs) return true;
  } else {
    dutyHolding_ = false;
  }
  if (digitalRead(kPinLoraDio1)) return true;   // a frame is waiting to be read
  int16_t r = g_sx.scanChannel();                // CAD
  g_sx.startReceive();
  return r != RADIOLIB_CHANNEL_FREE;
}

bool McuRadio::transmit(const uint8_t* buf, size_t len) {
  if (!buf || len == 0 || len > 255) {
    ++txErrors_;
    return false;
  }
  if (txGate_ && !txGate_()) {
    // Refused, not held: the router's queue has no limit, and a frame sent
    // hours later, once someone types `tx on`, would be stale.
    ++txRefused_;
    return false;
  }
  const uint32_t air = airtimeMs(phy_, len);
  if (!duty_.allows(nowMs(), air)) {
    ++dutyDropped_;
    return false;
  }
  duty_.record(nowMs(), air);   // before the attempt: a failed transmit may still have radiated
  femTx();
  int16_t st = g_sx.transmit(buf, len);
  femRx();
  g_sx.startReceive();
  if (st != RADIOLIB_ERR_NONE) {
    ++txErrors_;
    Serial.printf("tx failed: %d\n", st);
  }
  return st == RADIOLIB_ERR_NONE;
}

bool McuRadio::poll(uint8_t* buf, size_t cap, size_t& len, float& rssiDbm) {
  len = 0;
  rssiDbm = 0;
  if (!buf || cap == 0 || !digitalRead(kPinLoraDio1)) return false;
  const size_t received = g_sx.getPacketLength();
  bool ok = false;
  if (received > 0 && received <= cap) {
    int16_t st = g_sx.readData(buf, received);
    if (st == RADIOLIB_ERR_NONE) {
      rssiDbm = g_sx.getRSSI();
      len = received;
      ok = true;
    } else {
      // Count failed reads, not just CRC mismatches, for field diagnostics.
      ++crcErrors_;
    }
  } else if (received > cap || received > 255) {
    ++crcErrors_;
  }
  g_sx.startReceive();
  return ok;
}

}  // namespace mcu
}  // namespace gw
