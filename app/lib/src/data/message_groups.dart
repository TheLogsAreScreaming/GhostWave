/// Puts the parts of split messages back together for display. The parts stay
/// separate [ChatMessage]s underneath, each with its own delivery state, retry
/// and receipt; only the chat view joins them.
library;

import 'message_split.dart';
import 'models.dart';

/// Parts of one message further apart than this are not joined: the tag is
/// one byte, so after a while it can come round again.
const Duration kPartWindow = Duration(hours: 1);

/// One row of a chat thread.
sealed class ChatItem {
  const ChatItem();

  /// When the row sorts (its first message).
  DateTime get at;

  /// Sent by us.
  bool get outgoing;
}

/// An ordinary message, or a part that could not be grouped.
class SingleItem extends ChatItem {
  /// Wraps [message].
  const SingleItem(this.message);

  /// The message.
  final ChatMessage message;

  @override
  DateTime get at => message.at;

  @override
  bool get outgoing => message.outgoing;
}

/// The parts of one long message, shown as one bubble.
class LongMessageItem extends ChatItem {
  /// Creates the row.
  LongMessageItem({required this.total, required this.parts});

  /// How many parts the message has.
  final int total;

  /// The parts received or sent so far, by 1-based index.
  final Map<int, ChatMessage> parts;

  @override
  DateTime get at => parts.values.map((m) => m.at).reduce((a, b) => a.isBefore(b) ? a : b);

  @override
  bool get outgoing => parts.values.first.outgoing;

  /// Indices not received (or not written) yet.
  List<int> get missing => [
    for (var i = 1; i <= total; i++)
      if (!parts.containsKey(i)) i,
  ];

  /// The whole text, with a marker where a part is missing.
  String get text => [
    for (var i = 1; i <= total; i++)
      parts.containsKey(i) ? parsePart(parts[i]!.text)!.body : '[part $i of $total not received yet]',
  ].join(' ');

  /// The weakest state among the parts: failed, then pending, sent, delivered.
  MsgState get state {
    final states = parts.values.map((m) => m.state).toSet();
    for (final s in const [MsgState.failed, MsgState.pending, MsgState.sent]) {
      if (states.contains(s)) return s;
    }
    return MsgState.delivered;
  }

  /// The first failure, if any part failed.
  String? get error => parts.values.map((m) => m.error).firstWhere((e) => e != null, orElse: () => null);

  /// Whether any part was held while no app was connected.
  bool get replayed => parts.values.any((m) => m.replayed);

  /// The weakest signal among the parts that carry one: the link is only as
  /// good as its worst hop. Null if none do.
  int? get rssiDbm {
    int? worst;
    for (final m in parts.values) {
      final d = m.rssiDbm;
      if (d != null && (worst == null || d < worst)) worst = d;
    }
    return worst;
  }
}

/// [thread] (oldest first) as display rows (oldest first). Tagged parts with the
/// same sender direction, tag and total, within [kPartWindow] of the group's
/// first part, become one [LongMessageItem] placed where its first part was. A
/// part seen again with the same text is dropped; the same index with other
/// text starts a new message. Anything else stays a [SingleItem].
List<ChatItem> groupThread(List<ChatMessage> thread) {
  final items = <ChatItem>[];
  final open = <String, LongMessageItem>{};
  for (final m in thread) {
    final p = parsePart(m.text);
    if (p == null) {
      items.add(SingleItem(m));
      continue;
    }
    final key = '${m.outgoing}:${p.group}:${p.total}';
    var g = open[key];
    if (g != null && m.at.difference(g.at).abs() > kPartWindow) g = null;
    final same = g?.parts[p.index];
    if (same != null) {
      if (same.text == m.text) continue; // the same part again (a retry or a replay)
      g = null; // the tag came round: a different message
    }
    if (g == null) {
      g = LongMessageItem(total: p.total, parts: {});
      open[key] = g;
      items.add(g);
    }
    g.parts.putIfAbsent(p.index, () => m);
  }
  return items;
}
