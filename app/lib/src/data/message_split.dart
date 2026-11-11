/// Splits a long direct message into parts that each fit one radio message,
/// and reads those parts back.
library;

import 'dart:convert';
import 'dart:math';

/// The most parts one message may become. Each part costs airtime and is
/// delivered on its own.
const int kMaxMessageParts = 8;

/// Bytes the "(1/8#a7) " label takes from each part.
const int _labelBytes = 9;

final Random _rng = Random.secure();

/// [text] as the messages to send: itself if it fits [maxBytes] UTF-8 bytes,
/// otherwise parts labelled "(1/3#a7) ", in order. The two hex digits after
/// `#` are the same on every part of one message, so the receiver can put the
/// parts back together even when two long messages interleave; older apps just
/// show the labels. Breaks at a space where it can and never inside a
/// character. The list can be longer than [kMaxMessageParts]; the caller
/// refuses that. [group] fixes the tag (tests); otherwise it is random.
List<String> splitMessage(String text, int maxBytes, {int? group}) {
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
  final tag = ((group ?? _rng.nextInt(256)) & 0xFF).toRadixString(16).padLeft(2, '0');
  return [for (var i = 0; i < parts.length; i++) '(${i + 1}/${parts.length}#$tag) ${parts[i]}'];
}

/// One part of a split message, as read back from its text.
class MessagePart {
  /// Creates a part.
  const MessagePart({required this.index, required this.total, required this.group, required this.body});

  /// 1-based position.
  final int index;

  /// How many parts the message has.
  final int total;

  /// The tag shared by every part of one message (0-255).
  final int group;

  /// The text after the label.
  final String body;
}

final RegExp _label = RegExp(r'^\(([1-9])/([1-9])#([0-9a-f]{2})\) ');

/// [text] as a tagged part, or null. Untagged "(1/3) " parts from older apps
/// return null: they cannot be grouped without guessing, so they show as sent.
MessagePart? parsePart(String text) {
  final m = _label.firstMatch(text);
  if (m == null) return null;
  final index = int.parse(m.group(1)!), total = int.parse(m.group(2)!);
  if (total < 2 || total > kMaxMessageParts || index > total) return null;
  return MessagePart(index: index, total: total, group: int.parse(m.group(3)!, radix: 16), body: text.substring(m.end));
}
