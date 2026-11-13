// BLE client link on the ESP32 boards (NimBLE-Arduino 1.4). The same service,
// UUIDs, frames and pairing as the nRF52 link (ble_link.cpp), so the app treats
// both alike: legacy pairing with MITM and a static 6-digit passkey (default
// 654321), bonds kept in NVS, one phone at a time.
//
// NimBLE calls back from its host task; those callbacks only copy bytes and
// bump counters. The handler and router run in poll(), from loop().
#include "ble_link.h"

#if GW_HAS_BLE && defined(ARDUINO_ARCH_ESP32)

#include <Arduino.h>
#include <NimBLEDevice.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "oled.h"

extern "C" int os_msys_num_free(void);   // NimBLE's free buffer count

namespace gw {
namespace mcu {

namespace {

SemaphoreHandle_t g_rxLock = nullptr;
std::vector<uint8_t> g_rx;                // written bytes not yet parsed
constexpr size_t kRxCap = 2048;           // ~11 full frames
volatile uint32_t g_rxOverflows = 0;
volatile uint32_t g_connects = 0, g_disconnects = 0;
volatile uint16_t g_connHdl = 0xFFFF;
volatile bool g_secure = false;           // encrypted with MITM: the passkey was checked
volatile bool g_bonded = false;
volatile uint16_t g_mtu = 23;
uint32_t g_pin = 654321;
bool g_advertise = false;

NimBLEServer* g_server = nullptr;
NimBLECharacteristic* g_fromRadio = nullptr;

// The stack only asks for the passkey when the static one is NimBLE's default
// 123456 (NimBLEServer.cpp, BLE_SM_IOACT_DISP), so that is what it is given;
// this callback then supplies the real key and puts it on the screen.
constexpr uint32_t kAskMeForThePasskey = 123456;

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, ble_gap_conn_desc* desc) override {
    g_secure = false;
    g_bonded = false;
    g_mtu = 23;
    g_connHdl = desc->conn_handle;
    ++g_connects;
  }

  void onDisconnect(NimBLEServer*, ble_gap_conn_desc*) override {
    xSemaphoreTake(g_rxLock, portMAX_DELAY);
    g_rx.clear();   // bytes from the old connection must not reach the next one
    xSemaphoreGive(g_rxLock);
    g_secure = false;
    g_connHdl = 0xFFFF;
    ++g_disconnects;
    if (g_advertise) NimBLEDevice::startAdvertising();
  }

  void onMTUChange(uint16_t mtu, ble_gap_conn_desc*) override { g_mtu = mtu; }

  uint32_t onPassKeyRequest() override {
    char digits[7];
    std::snprintf(digits, sizeof digits, "%06lu", static_cast<unsigned long>(g_pin));
    Serial.printf("BLE pairing: enter passkey %s on the phone\n", digits);
#if GW_HAS_OLED
    gw::mcu::oled::showPasskey(reinterpret_cast<const uint8_t*>(digits));
#endif
    return g_pin;
  }

  void onAuthenticationComplete(ble_gap_conn_desc* desc) override {
#if GW_HAS_OLED
    gw::mcu::oled::clearPasskey();
#endif
    g_secure = desc->sec_state.encrypted && desc->sec_state.authenticated;
    g_bonded = desc->sec_state.bonded;
    if (g_secure) Serial.printf("BLE link encrypted%s\n", g_bonded ? " (bonded phone)" : "");
    else Serial.println("BLE pairing failed or not authenticated: the link stays closed");
  }
};

class ToRadioCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    if (!g_secure) return;   // the stack already refuses unauthenticated writes; belt and braces
    NimBLEAttValue v = c->getValue();
    xSemaphoreTake(g_rxLock, portMAX_DELAY);
    if (g_rx.size() + v.length() <= kRxCap) g_rx.insert(g_rx.end(), v.data(), v.data() + v.length());
    else ++g_rxOverflows;   // the app is writing faster than the node parses: drop
    xSemaphoreGive(g_rxLock);
  }
};

ServerCallbacks g_serverCb;
ToRadioCallbacks g_toRadioCb;

}  // namespace

bool BleLink::begin(const std::string& name, bool enabled, const char* pin) {
  name_ = name;
  g_rxLock = xSemaphoreCreateMutex();
  g_rx.reserve(kRxCap);
  g_pin = static_cast<uint32_t>(std::strtoul(pin, nullptr, 10));

  NimBLEDevice::init(name_);
  NimBLEDevice::setMTU(kMtu);
  NimBLEDevice::setPower(ESP_PWR_LVL_P3);
  // Bond, MITM, no LE Secure Connections: a static passkey means legacy
  // pairing, as on the nRF52 (CLIENT_PROTOCOL §7).
  NimBLEDevice::setSecurityAuth(true, true, false);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY);
  NimBLEDevice::setSecurityPasskey(kAskMeForThePasskey);

  g_server = NimBLEDevice::createServer();
  g_server->setCallbacks(&g_serverCb, false);
  g_server->advertiseOnDisconnect(false);   // onDisconnect decides, so `ble off` sticks

  NimBLEService* svc = g_server->createService(kServiceUuid);
  // Writing ToRadio and subscribing to FromRadio both need an encrypted, MITM
  // link, so nothing passes before pairing.
  NimBLECharacteristic* toRadio = svc->createCharacteristic(
      kToRadioUuid, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::WRITE_AUTHEN, kMtu - 3);
  toRadio->setCallbacks(&g_toRadioCb);
  g_fromRadio = svc->createCharacteristic(
      kFromRadioUuid, NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::READ_AUTHEN, kMtu - 3);
  if (!svc->start()) return false;

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(kServiceUuid);   // 128-bit UUID in the advertisement
  adv->setScanResponse(true);          // the name goes in the scan response
  adv->setMinInterval(160);            // 100 ms (0.625 ms units)
  adv->setMaxInterval(320);
  started_ = true;
  setEnabled(enabled);
  return true;
}

void BleLink::setEnabled(bool on) {
  enabled_ = on;
  g_advertise = on;
  if (!started_) return;
  if (on) {
    if (g_connHdl == 0xFFFF) NimBLEDevice::startAdvertising();
  } else {
    NimBLEDevice::stopAdvertising();
    uint16_t hdl = g_connHdl;
    if (hdl != 0xFFFF) g_server->disconnect(hdl);
  }
}

void BleLink::clearBonds() {
  if (!started_) return;
  uint16_t hdl = g_connHdl;
  if (hdl != 0xFFFF) {
    g_server->disconnect(hdl);
    for (int i = 0; i < 50 && g_connHdl != 0xFFFF; ++i) delay(10);
  }
  NimBLEDevice::deleteAllBonds();
}

std::string BleLink::describe() {
  char b[200];
  if (!started_) return "BLE failed to start";
  if (!open_) {
    std::snprintf(b, sizeof b, "BLE %s, \"%s\", no phone connected", enabled_ ? "on (advertising)" : "off",
                  name_.c_str());
  } else {
    std::snprintf(b, sizeof b, "BLE %s, \"%s\", phone connected: %s%s, MTU %u, %s, %u bytes queued, %lu dropped",
                  enabled_ ? "on" : "off", name_.c_str(), g_secure ? "encrypted" : "not paired yet",
                  g_bonded ? " + bonded" : "", static_cast<unsigned>(g_mtu),
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
    if (open_) Serial.println("BLE phone disconnected");
    open_ = false;
    connHdl_ = 0xFFFF;
    resetConn();
  }
  uint32_t c = g_connects;
  if (c != seenConnects_) {
    seenConnects_ = c;
    uint16_t hdl = g_connHdl;
    if (hdl != 0xFFFF) {
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
    g_server->disconnect(connHdl_);
    conn_.closing = false;   // the disconnect callback finishes the job
  }
}

void BleLink::flushOut() {
  // Only to a paired, subscribed phone.
  if (!g_secure || !g_fromRadio || g_fromRadio->getSubscribedCount() == 0) return;
  size_t chunk = g_mtu > 3 ? g_mtu - 3 : 20;
  // At most 8 a turn so the radio keeps being served, and only while NimBLE
  // has buffers: notify() drops a packet it cannot queue, without saying so.
  for (int i = 0; i < 8 && os_msys_num_free() > 4; ++i) {
    const uint8_t* p;
    size_t n;
    if (!out_.peek(chunk, p, n)) return;
    g_fromRadio->notify(p, n);
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

#endif  // GW_HAS_BLE && ARDUINO_ARCH_ESP32
