#pragma once
#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
class Print {
 public:
  virtual ~Print() {}
  virtual size_t write(uint8_t) = 0;
  virtual size_t write(const uint8_t* b, size_t n) {
    size_t k = 0;
    while (n--) k += write(*b++);
    return k;
  }
  size_t print(const char* s) { return write(reinterpret_cast<const uint8_t*>(s), std::strlen(s)); }
  size_t print(char c) { return write(static_cast<uint8_t>(c)); }
  size_t printf(const char* f, ...) {
    char b[256];
    va_list a;
    va_start(a, f);
    std::vsnprintf(b, sizeof b, f, a);
    va_end(a);
    return print(b);
  }
};
