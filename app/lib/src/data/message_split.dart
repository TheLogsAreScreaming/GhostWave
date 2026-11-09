/// Splits a long direct message into parts that each fit one radio message.
library;

import 'dart:convert';

/// The most parts one message may become. Each part costs airtime and is
/// delivered on its own.
const int kMaxMessageParts = 8;

/// Bytes the "(1/8) " label takes from each part.
const int _labelBytes = 6;

/// [text] as the messages to send: itself if it fits [maxBytes] UTF-8 bytes,
/// otherwise parts labelled "(1/3) ", in order. Breaks at a space where it
/// can and never inside a character. The list can be longer than
/// [kMaxMessageParts]; the caller refuses that.
List<String> splitMessage(String text, int maxBytes) {
  if (utf8.encode(text).length <= maxBytes) return [text];
  final room = maxBytes - _labelBytes;
  final parts = <String>[];
  var rest = text.runes.toList();
  while (rest.isNotEmpty) {
    var bytes = 0, end = 0, lastSpace = -1;
    while (end < rest.length) {
      final size = utf8.encode(String.fromCharCode(rest[end])).length;
      if (bytes + size > room) break;
      bytes += size;
      if (rest[end] == 0x20 || rest[end] == 0x0A) lastSpace = end;
      end++;
    }
    final whole = end == rest.length;
    final cut = !whole && lastSpace >= end ~/ 2 ? lastSpace + 1 : end;
    final part = String.fromCharCodes(rest, 0, cut).trim();
    if (part.isNotEmpty) parts.add(part);
    rest = rest.sublist(cut);
  }
  return [for (var i = 0; i < parts.length; i++) '(${i + 1}/${parts.length}) ${parts[i]}'];
}
