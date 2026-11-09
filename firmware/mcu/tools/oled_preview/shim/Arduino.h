// Host stand-in for the bits of Arduino that Adafruit GFX uses (preview only).
#pragma once
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include "Print.h"
#define PROGMEM
#define pgm_read_byte(a) (*(const uint8_t*)(a))
#define pgm_read_word(a) (*(const uint16_t*)(a))
#define pgm_read_dword(a) (*(const uint32_t*)(a))
#define pgm_read_pointer(a) (*(void* const*)(a))
typedef bool boolean;
#ifndef min
#define min(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef _swap_int16_t
#endif
class __FlashStringHelper;
#define radians(deg) ((deg) * 0.017453292519943295)
// Adafruit GFX's String overloads only need the name and c_str().
class String {
 public:
  String(const char* s = "") : s_(s) {}
  const char* c_str() const { return s_; }
  unsigned length() const { return static_cast<unsigned>(std::strlen(s_)); }
 private:
  const char* s_;
};
