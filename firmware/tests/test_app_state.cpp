// Host tests for the flash records of app-joined channels, pinned contact
// keys and keys learned over the air (firmware/mcu/src/app_state.h).
#include <cstdio>

#include "app_state.h"
#include "ghostwave/channel_book.h"
#include "ghostwave/router.h"

using namespace gw::mcu;
using namespace gw::mcu::app_state;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (cond) {                                                         \
      ++g_pass;                                                         \
    } else {                                                            \
      ++g_fail;                                                         \
      std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);     \
    }                                                                   \
  } while (0)

namespace {

AppKey key(uint8_t v) {
  AppKey k;
  k.fill(v);
  return k;
}

std::vector<SavedChannel> channels(size_t n) {
  std::vector<SavedChannel> v;
  for (size_t i = 0; i < n; ++i) v.push_back({std::string(1 + i, static_cast<char>('a' + i)), key(static_cast<uint8_t>(i + 1))});
  return v;
}

std::map<uint32_t, AppKey> edKeys(size_t n) {
  std::map<uint32_t, AppKey> m;
  for (size_t i = 0; i < n; ++i) m[static_cast<uint32_t>(0x1000 + i)] = key(static_cast<uint8_t>(i));
  return m;
}

// Damaged-record checks need a good CRC, so the decoder's own checks are what fails.
void reseal(std::vector<uint8_t>& b) {
  b.resize(b.size() - 4);
  putCrc(b);
}

void testChannels() {
  CHECK(kMaxChannels == gw::kMaxGroupChannels);
  CHECK(kMaxChannelName == gw::ChannelBook::kNameMax);
  for (size_t n : {size_t(0), size_t(1), kMaxChannels}) {
    std::vector<SavedChannel> out;
    CHECK(decodeChannels(encodeChannels(channels(n)), out));
    CHECK(out.size() == n);
    for (size_t i = 0; i < out.size() && i < n; ++i) {
      CHECK(out[i].name == channels(n)[i].name);
      CHECK(out[i].key == channels(n)[i].key);
    }
  }
  std::vector<SavedChannel> longest{{std::string(kMaxChannelName, 'x'), key(9)}};
  std::vector<SavedChannel> out;
  CHECK(decodeChannels(encodeChannels(longest), out) && out[0].name.size() == kMaxChannelName);
  CHECK(encodeChannels(channels(kMaxChannels + 1)).empty());
  CHECK(encodeChannels({{"", key(1)}}).empty());
  CHECK(encodeChannels({{std::string(kMaxChannelName + 1, 'x'), key(1)}}).empty());
}

void testEdKeys() {
  for (size_t n : {size_t(0), size_t(1), kMaxEdKeys}) {
    std::map<uint32_t, AppKey> out;
    CHECK(decodeEdKeys(encodeEdKeys(edKeys(n)), out));
    CHECK(out == edKeys(n));
  }
  CHECK(encodeEdKeys(edKeys(kMaxEdKeys + 1)).empty());
}

std::vector<LearnedKey> learned(size_t n) {
  std::vector<LearnedKey> v;
  for (size_t i = 0; i < n; ++i) {
    LearnedKey k;
    k.id = static_cast<uint32_t>(0x2000 + (n - i));   // not in ID order: the list keeps its own order
    k.edPub = key(static_cast<uint8_t>(i + 7));
    k.name = std::string(i % (gw::kIdentNameMax + 1), static_cast<char>('a' + i % 26));
    v.push_back(k);
  }
  return v;
}

void testLearnedKeys() {
  for (size_t n : {size_t(0), size_t(1), size_t(5), kMaxLearnedKeys}) {
    std::vector<LearnedKey> out;
    CHECK(decodeLearnedKeys(encodeLearnedKeys(learned(n)), out));
    CHECK(out == learned(n));
  }
  CHECK(encodeLearnedKeys(learned(kMaxLearnedKeys + 1)).empty());
  std::vector<LearnedKey> bad = learned(2);
  bad[1].name = std::string(gw::kIdentNameMax + 1, 'x');
  CHECK(encodeLearnedKeys(bad).empty());
  bad = learned(2);
  bad[1].id = bad[0].id;
  CHECK(encodeLearnedKeys(bad).empty());

  const std::vector<uint8_t> good = encodeLearnedKeys(learned(3));
  std::vector<LearnedKey> kept = learned(1), out = kept;
  for (size_t i = 0; i < good.size(); ++i) {   // any single damaged byte
    std::vector<uint8_t> b = good;
    b[i] ^= 0x40;
    CHECK(!decodeLearnedKeys(b, out));
  }
  for (size_t n = 0; n < good.size(); ++n) {   // any torn write
    std::vector<uint8_t> b(good.begin(), good.begin() + static_cast<long>(n));
    CHECK(!decodeLearnedKeys(b, out));
  }
  CHECK(out == kept);   // a failed load leaves the list alone
  std::map<uint32_t, AppKey> m;
  CHECK(!decodeEdKeys(good, m));   // not mistaken for the pinned-key file
  CHECK(!decodeLearnedKeys(encodeEdKeys(edKeys(2)), out));
  std::vector<uint8_t> b = good;
  b[5] = b[6] = b[7] = b[8] = 0;   // node id 0
  reseal(b);
  CHECK(!decodeLearnedKeys(b, out));
  b = good;
  b[41] = static_cast<uint8_t>(gw::kIdentNameMax + 1);   // first name length over the limit
  reseal(b);
  CHECK(!decodeLearnedKeys(b, out));
}

void testDamage() {
  const std::vector<uint8_t> good = encodeChannels(channels(3));
  std::vector<SavedChannel> kept = channels(1), out = kept;
  for (size_t i = 0; i < good.size(); ++i) {   // any single damaged byte
    std::vector<uint8_t> b = good;
    b[i] ^= 0x40;
    CHECK(!decodeChannels(b, out));
  }
  for (size_t n = 0; n < good.size(); ++n) {   // any torn write
    std::vector<uint8_t> b(good.begin(), good.begin() + static_cast<long>(n));
    CHECK(!decodeChannels(b, out));
  }
  CHECK(out.size() == 1 && out[0].name == kept[0].name);   // failures leave `out` alone

  std::vector<uint8_t> b = good;
  b[4] = kMaxChannels + 1;
  reseal(b);
  CHECK(!decodeChannels(b, out));
  b = good;
  b[5] = 200;   // name runs past the end
  reseal(b);
  CHECK(!decodeChannels(b, out));
  b = good;
  b.insert(b.end() - 4, 0);   // trailing junk
  reseal(b);
  CHECK(!decodeChannels(b, out));

  const std::vector<uint8_t> goodEd = encodeEdKeys(edKeys(2));
  std::map<uint32_t, AppKey> m;
  CHECK(!decodeChannels(goodEd, out));   // the two files can't be mistaken for each other
  CHECK(!decodeEdKeys(good, m));
  for (size_t i = 0; i < goodEd.size(); ++i) {
    b = goodEd;
    b[i] ^= 0x01;
    CHECK(!decodeEdKeys(b, m));
  }
  b = goodEd;
  b[5] = b[6] = b[7] = b[8] = 0;   // node id 0
  reseal(b);
  CHECK(!decodeEdKeys(b, m));
  b = goodEd;
  std::copy(b.begin() + 5, b.begin() + 9, b.begin() + 41);   // same id twice
  reseal(b);
  CHECK(!decodeEdKeys(b, m));
  CHECK(m.empty());
}

}  // namespace

int main() {
  CHECK(validNodeName(""));
  CHECK(validNodeName("ridge-9"));
  CHECK(validNodeName("123456789"));
  CHECK(!validNodeName("1234567890"));
  CHECK(!validNodeName(std::string("a\nb")));
  CHECK(!validNodeName(std::string(1, '\x7f')));

  testChannels();
  testEdKeys();
  testDamage();
  testLearnedKeys();
  std::printf("%d passed, %d failed\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
