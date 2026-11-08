// The few things main.cpp needs that differ between the ESP32 and nRF52
// Arduino cores.
#pragma once

#include <Arduino.h>

#include <cstddef>
#include <cstdint>

#include "board.h"

#if GW_NRF52
#include <malloc.h>
#else
#include <esp_timer.h>
#endif

namespace gw {
namespace mcu {

#if GW_NRF52

// millis() is 32-bit; widened here. Called at least every few ms from the
// main loop, so a wrap (every 49.7 days) is never missed.
inline uint64_t nowMs() {
  static uint32_t last = 0, wraps = 0;
  uint32_t m = millis();
  if (m < last) ++wraps;
  last = m;
  return static_cast<uint64_t>(wraps) << 32 | m;
}

// newlib heap (FreeRTOS heap_3 and every new/malloc share it).
extern "C" char* sbrk(int);
extern "C" char __HeapLimit;
inline size_t freeHeap() {
  struct mallinfo mi = mallinfo();
  char* top = sbrk(0);
  size_t untouched = top < &__HeapLimit ? static_cast<size_t>(&__HeapLimit - top) : 0;
  return mi.fordblks + untouched;
}
inline size_t minFreeHeap() { return 0; }    // not tracked on this core
inline size_t largestFreeBlock() { return 0; }

inline void reboot() { NVIC_SystemReset(); }

#else

inline uint64_t nowMs() { return static_cast<uint64_t>(esp_timer_get_time() / 1000); }
inline size_t freeHeap() { return ESP.getFreeHeap(); }
inline size_t minFreeHeap() { return ESP.getMinFreeHeap(); }
inline size_t largestFreeBlock() { return ESP.getMaxAllocHeap(); }
inline void reboot() { ESP.restart(); }

#endif

}  // namespace mcu
}  // namespace gw
