#include "ble_link.h"

#if GW_HAS_BLE

#include <Arduino.h>
#include <bluefruit.h>

#include "oled.h"

#include <cstdio>
#include <cstring>
#include <vector>

namespace gw {
namespace mcu {

namespace {

// State shared with Bluefruit's callback tasks. Writes land in g_rx under
// g_rxLock; connects / disconnects are counted and picked up by poll().
BLEService g_svc(BleLink::kServiceUuid);
BLECharacteristic g_toRadio(BleLink::kToRadioUuid);
BLECharacteristic g_fromRadio(BleLink::kFromRadioUuid);

SemaphoreHandle_t g_rxLock = nullptr;
std::vector<uint8_t> g_rx;                 // written bytes not yet parsed
constexpr size_t kRxCap = 2048;            // ~11 full frames
volatile uint32_t g_rxOverflows = 0;
volatile uint32_t g_connects = 0, g_disconnects = 0;
volatile uint16_t g_connHdl = BLE_CONN_HANDLE_INVALID;
volatile uint8_t g_lastReason = 0;

void onWrite(uint16_t, BLECharacteristic*, uint8_t* data, uint16_t len) {
  xSemaphoreTake(g_rxLock, portMAX_DELAY);
  if (g_rx.size() + len <= kRxCap) g_rx.insert(g_rx.end(), data, data + len);
  else ++g_rxOverflows;   // the app is writing faster than the node parses: drop
  xSemaphoreGive(g_rxLock);
}

void onConnect(uint16_t hdl) {
  g_connHdl = hdl;
  ++g_connects;
  if (BLEConnection* c = Bluefruit.Connection(hdl)) {
    c->requestMtuExchange(BleLink::kMtu);   // phones usually ask first; harmless if so
    c->requestDataLengthUpdate();
  }
}

void onDisconnect(uint16_t, uint8_t reason) {
  xSemaphoreTake(g_rxLock, portMAX_DELAY);
  g_rx.clear();   // bytes from the old connection must not reach the next one
  xSemaphoreGive(g_rxLock);
  g_lastReason = reason;
  g_connHdl = BLE_CONN_HANDLE_INVALID;
  ++g_disconnects;
}

bool onPasskey(uint16_t, uint8_t const passkey[6], bool) {
  Serial.printf("BLE pairing: enter passkey %.6s on the phone\n", reinterpret_cast<const char*>(passkey));
#if GW_HAS_OLED
  gw::mcu::oled::showPasskey(passkey);
#endif
  return true;
}

void onPairComplete(uint16_t, uint8_t status) {
#if GW_HAS_OLED
  gw::mcu::oled::clearPasskey();
#endif
  if (status == BLE_GAP_SEC_STATUS_SUCCESS) Serial.println("BLE pairing done, phone bonded");
  else Serial.printf("BLE pairing failed (status %u)\n", status);
}

void onSecured(uint16_t hdl) {
  BLEConnection* c = Bluefruit.Connection(hdl);
  Serial.printf("BLE link encrypted%s\n", c && c->bonded() ? " (bonded phone)" : "");
}

}  // namespace

bool BleLink::begin(const std::string& name, bool enabled) {
  name_ = name;
  g_rxLock = xSemaphoreCreateMutex();
  g_rx.reserve(kRxCap);

  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);   // ATT MTU up to 247, 3 queued notifications
  if (!Bluefruit.begin(1, 0)) return false;
  Bluefruit.setName(name_.c_str());
  Bluefruit.setTxPower(0);
  Bluefruit.autoConnLed(false);
  Bluefruit.Periph.setConnectCallback(onConnect);
  Bluefruit.Periph.setDisconnectCallback(onDisconnect);

  // LE Secure Connections, MITM by passkey entry: the node displays (on the
  // serial console), the phone types it in. Bonds go to InternalFS.
  Bluefruit.Security.setIOCaps(true, false, false);
  Bluefruit.Security.setMITM(true);
  Bluefruit.Security.setPairPasskeyCallback(onPasskey);
  Bluefruit.Security.setPairCompleteCallback(onPairComplete);
  Bluefruit.Security.setSecuredCallback(onSecured);

  g_svc.begin();
  // Every attribute, the notify CCCD included, needs an LESC + MITM link, so
  // nothing can be read, written or subscribed to before pairing.
  g_toRadio.setProperties(CHR_PROPS_WRITE);
  g_toRadio.setPermission(SECMODE_ENC_WITH_LESC_MITM, SECMODE_ENC_WITH_LESC_MITM);
  g_toRadio.setMaxLen(kMtu - 3);
  g_toRadio.setWriteCallback(onWrite, false);   // straight from the BLE task: it only copies
  g_toRadio.begin();
  g_fromRadio.setProperties(CHR_PROPS_NOTIFY);
  g_fromRadio.setPermission(SECMODE_ENC_WITH_LESC_MITM, SECMODE_NO_ACCESS);
  g_fromRadio.setMaxLen(kMtu - 3);
  g_fromRadio.begin();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addService(g_svc);   // 128-bit UUID: 18 of the 31 bytes
  Bluefruit.ScanResponse.addName();          // so the name goes in the scan response
  Bluefruit.Advertising.setInterval(160, 1600);   // 100 ms for 30 s, then 1 s (0.625 ms units)
  Bluefruit.Advertising.setFastTimeout(30);
  started_ = true;
  setEnabled(enabled);
  return true;
}

void BleLink::setEnabled(bool on) {
  enabled_ = on;
  if (!started_) return;
  Bluefruit.Advertising.restartOnDisconnect(on);
  if (on) {
    if (!Bluefruit.Advertising.isRunning() && g_connHdl == BLE_CONN_HANDLE_INVALID) Bluefruit.Advertising.start(0);
  } else {
    Bluefruit.Advertising.stop();
    uint16_t hdl = g_connHdl;
    if (hdl != BLE_CONN_HANDLE_INVALID) Bluefruit.disconnect(hdl);
  }
}

void BleLink::clearBonds() {
  if (!started_) return;
  uint16_t hdl = g_connHdl;
  if (hdl != BLE_CONN_HANDLE_INVALID) {
    Bluefruit.disconnect(hdl);
    for (int i = 0; i < 50 && g_connHdl != BLE_CONN_HANDLE_INVALID; ++i) delay(10);
  }
  Bluefruit.Periph.clearBonds();
}

std::string BleLink::describe() {
  char b[200];
  if (!started_) return "BLE failed to start";
  if (!open_) {
    std::snprintf(b, sizeof b, "BLE %s, \"%s\", no phone connected", enabled_ ? "on (advertising)" : "off",
                  name_.c_str());
  } else {
    BLEConnection* c = Bluefruit.Connection(connHdl_);
    std::snprintf(b, sizeof b, "BLE %s, \"%s\", phone connected: %s%s, MTU %u, %s, %u bytes queued, %lu dropped",
                  enabled_ ? "on" : "off", name_.c_str(), c && c->secured() ? "encrypted" : "not paired yet",
                  c && c->bonded() ? " + bonded" : "", c ? c->getMtu() : 0,
                  conn_.hello ? "app session open" : "no Hello yet", static_cast<unsigned>(out_.pendingBytes()),
                  static_cast<unsigned long>(dropped_));
  }
  return b;
}

void BleLink::resetConn() {
  conn_ = gw::client::Conn();
  conn_.peer = "ble";
  in_ = gw::client::FrameReader();
  out_.clear();
}

void BleLink::poll(uint64_t now) {
  if (!started_) return;
  // Disconnects first: a disconnect and a reconnect can both land between polls.
  uint32_t d = g_disconnects;
  if (d != seenDisconnects_) {
    seenDisconnects_ = d;
    if (open_) Serial.printf("BLE phone disconnected (reason 0x%02x)\n", g_lastReason);
    open_ = false;
    connHdl_ = BLE_CONN_HANDLE_INVALID;
    resetConn();
  }
  uint32_t c = g_connects;
  if (c != seenConnects_) {
    seenConnects_ = c;
    uint16_t hdl = g_connHdl;
    if (hdl != BLE_CONN_HANDLE_INVALID) {
      resetConn();
      open_ = true;
      connHdl_ = hdl;
      Serial.println("BLE phone connected");
    }
  }
  if (!open_) return;

  uint8_t buf[256];
  for (;;) {
    size_t n = 0;
    xSemaphoreTake(g_rxLock, portMAX_DELAY);
    n = g_rx.size() < sizeof buf ? g_rx.size() : sizeof buf;
    if (n) {
      std::memcpy(buf, g_rx.data(), n);
      g_rx.erase(g_rx.begin(), g_rx.begin() + n);
    }
    xSemaphoreGive(g_rxLock);
    if (!n) break;
    in_.push(buf, n);
    if (h_) h_->receive(conn_, in_, now);
  }
  if (in_.buffered() > 2 * gw::client::kMaxFrame) in_ = gw::client::FrameReader();   // stuck garbage
  flushOut();
  if (conn_.closing && out_.pendingBytes() == 0) {
    Bluefruit.disconnect(connHdl_);
    conn_.closing = false;   // the disconnect callback finishes the job
  }
}

void BleLink::flushOut() {
  BLEConnection* c = Bluefruit.Connection(connHdl_);
  if (!c || !g_fromRadio.notifyEnabled(connHdl_)) return;
  size_t chunk = c->getMtu() > 3 ? c->getMtu() - 3 : 20;
  // At most 8 notifications a turn so the radio side keeps being served.
  for (int i = 0; i < 8; ++i) {
    const uint8_t* p;
    size_t n;
    if (!out_.peek(chunk, p, n)) return;
    // n <= MTU - 3, so notify() sends it whole or not at all.
    if (!g_fromRadio.notify(connHdl_, p, static_cast<uint16_t>(n))) return;
    out_.pop(n);
  }
}

void BleLink::write(gw::client::Conn&, const uint8_t* frame, size_t n) {
  if (!open_) return;
  if (!out_.push(frame, n)) ++dropped_;   // app not reading notifications
}

void BleLink::forEachConn(const std::function<void(gw::client::Conn&)>& fn) {
  if (open_) fn(conn_);
}

void BleLink::log(const std::string& line) { Serial.println(line.c_str()); }

}  // namespace mcu
}  // namespace gw

#endif  // GW_HAS_BLE
