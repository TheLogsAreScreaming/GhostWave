// ghostwaved's group channels: the portable gw::ChannelBook, kept in a file
// next to the identity key (<key file>.channels, mode 600) so joined channels
// survive a restart.
#pragma once

#include <string>

#include "ghostwave/channel_book.h"

class ChannelStore : public gw::ChannelBook {
 public:
  using Entry = gw::ChannelBook::Entry;

  // `path` empty: kept in memory only.
  ChannelStore(gw::Router& router, std::string path) : gw::ChannelBook(router), path_(std::move(path)) {}

  // Reads the file (a missing file is an empty list) and joins its channels.
  // False with `err` set on a malformed or unreadable file.
  bool load(std::string& err);

 protected:
  bool persist() const override;

 private:
  std::string path_;
};

using ChannelEntry = ChannelStore::Entry;
