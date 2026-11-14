/// Replies and reactions, carried as short text inside ordinary messages.
///
/// Every byte costs LoRa airtime, so the encoding is a few characters that
/// older apps still show as readable text:
///
/// * a reply is `↩Ab3_ the reply text`: the arrow, a 4-character reference to
///   the original, a space, then the text (8 bytes on top of the text);
/// * a reaction is `+👍↩Ab3_`: plus, one emoji from [kReactions], the arrow
///   and the reference (at most 14 bytes, no notification);
/// * taking a reaction back is `-↩Ab3_` (8 bytes).
///
/// The reference is [messageRef]: 24 bits of SHA-256 over the original's
/// sender node ID and mesh message ID, which both ends know (the sender from
/// `SendQueued`, the receiver from the incoming message). It only has to tell
/// messages apart within one conversation.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The reactions offered, in menu order. One per person per message.
const List<String> kReactions = ['👍', '❤️', '😂', '😮', '✅', '❗'];

/// Screen-reader names of [kReactions].
const Map<String, String> kReactionNames = {
  '👍': 'thumbs up',
  '❤️': 'heart',
  '😂': 'laughing',
  '😮': 'surprised',
  '✅': 'check mark',
  '❗': 'exclamation mark',
};

/// The mark that starts a reply and ends a reaction (U+21A9, 3 bytes).
const String kRefMark = '↩';

/// Characters in a reference.
const int kRefLength = 4;

/// Bytes a reply adds to its text: the mark, the reference and a space.
const int kReplyOverheadBytes = 3 + kRefLength + 1;

/// The reference to the message [msgId] sent by node [sender]: 4 URL-safe
/// base64 characters. Null when [msgId] is 0 (not yet queued by the node).
String? messageRef(int sender, int msgId) {
  if (msgId == 0) return null;
  final key = (sender & 0xFFFFFFFF) << 32 | (msgId & 0xFFFFFFFF);
  final hit = _refCache[key];
  if (hit != null) return hit;
  final b = ByteData(8)
    ..setUint32(0, sender & 0xFFFFFFFF)
    ..setUint32(4, msgId & 0xFFFFFFFF);
  final d = sha256.convert(b.buffer.asUint8List()).bytes;
  final ref = base64Url.encode(d.sublist(0, 3));
  // chat screens rebuild on every keystroke: keep recent references
  if (_refCache.length >= _refCacheSize) _refCache.remove(_refCache.keys.first);
  _refCache[key] = ref;
  return ref;
}

const int _refCacheSize = 8192;
final Map<int, String> _refCache = <int, String>{};

/// What a message's text means.
sealed class MeshText {
  const MeshText();
}

/// An ordinary message.
final class PlainText extends MeshText {
  /// Wraps [text].
  const PlainText(this.text);

  /// The text as received.
  final String text;
}

/// A reply to the message [ref], with its own [body].
final class ReplyText extends MeshText {
  /// Creates a reply.
  const ReplyText(this.ref, this.body);

  /// The original's reference.
  final String ref;

  /// The reply itself.
  final String body;
}

/// A reaction to the message [ref]; [emoji] null takes the sender's back.
final class ReactionText extends MeshText {
  /// Creates a reaction.
  const ReactionText(this.ref, this.emoji);

  /// The original's reference.
  final String ref;

  /// One of [kReactions], or null to remove.
  final String? emoji;
}

final RegExp _refChars = RegExp(r'^[A-Za-z0-9_-]{4}$');

// a bare ❤ (no variation selector) counts as ❤️: some keyboards drop it
const Map<String, String> _emojiForms = {'👍': '👍', '❤️': '❤️', '❤': '❤️', '😂': '😂', '😮': '😮', '✅': '✅', '❗': '❗'};

/// Reads [text]. Anything that is not exactly a reply or a reaction is
/// [PlainText], so a stray arrow in a normal message never hides it.
MeshText parseMeshText(String text) {
  // the shortest reply is "↩Ab3_ x" (7 code units): the arrow is one
  if (text.startsWith(kRefMark) && text.length >= 2 + kRefLength + 1) {
    final ref = text.substring(1, 1 + kRefLength);
    if (_refChars.hasMatch(ref) && text[1 + kRefLength] == ' ') {
      final body = text.substring(2 + kRefLength).trim();
      if (body.isNotEmpty) return ReplyText(ref, body);
    }
    return PlainText(text);
  }
  final mark = text.lastIndexOf(kRefMark);
  if (mark < 1 || text.length != mark + 1 + kRefLength) return PlainText(text);
  final ref = text.substring(mark + 1);
  if (!_refChars.hasMatch(ref)) return PlainText(text);
  final head = text.substring(0, mark);
  if (head == '-') return ReactionText(ref, null);
  if (!head.startsWith('+')) return PlainText(text);
  final emoji = _emojiForms[head.substring(1)];
  return emoji == null ? PlainText(text) : ReactionText(ref, emoji);
}

/// A reply to [ref] saying [body] (trimmed). Throws [ArgumentError] for an
/// empty body or a malformed reference.
String encodeReply(String ref, String body) {
  _checkRef(ref);
  final t = body.trim();
  if (t.isEmpty) throw ArgumentError.value(body, 'body', 'empty reply');
  return '$kRefMark$ref $t';
}

/// A reaction [emoji] (one of [kReactions]) to [ref]; null removes ours.
String encodeReaction(String ref, String? emoji) {
  _checkRef(ref);
  if (emoji == null) return '-$kRefMark$ref';
  if (!kReactions.contains(emoji)) throw ArgumentError.value(emoji, 'emoji', 'not an offered reaction');
  return '+$emoji$kRefMark$ref';
}

void _checkRef(String ref) {
  if (!_refChars.hasMatch(ref)) throw ArgumentError.value(ref, 'ref', 'not a message reference');
}

/// [text] for a notification or a one-line preview: a reply shows its body,
/// a reaction says what it is.
String friendlyText(String text) => switch (parseMeshText(text)) {
  PlainText(:final text) => text,
  ReplyText(:final body) => '↩ $body',
  ReactionText(emoji: final e?) => 'Reacted $e',
  ReactionText() => 'Removed a reaction',
};

/// One message as the folding sees it: who sent it, its mesh ID, its text.
class RefEntry {
  /// Creates an entry.
  const RefEntry({required this.sender, required this.msgId, required this.text, this.countable = true});

  /// Node that wrote it.
  final int sender;

  /// Mesh message ID (0 while not yet queued).
  final int msgId;

  /// Its text (for a long message, the joined text).
  final String text;

  /// False for our own reaction that failed: it never reached anyone.
  final bool countable;
}

/// A thread read for replies and reactions.
class ThreadRefs {
  ThreadRefs._(this.indexOf, this.reactions, this.meaning);

  /// Folds [entries] (oldest first). A message's reference is the one of its
  /// own (sender, msgId). The latest reaction from each sender to a message
  /// wins; a removal clears it.
  factory ThreadRefs.of(List<RefEntry> entries) {
    final index = <String, int>{};
    final meaning = <MeshText>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final ref = messageRef(e.sender, e.msgId);
      final m = parseMeshText(e.text);
      meaning.add(m);
      // reactions are not things to reply or react to
      if (ref != null && m is! ReactionText) index.putIfAbsent(ref, () => i);
    }
    final reactions = <String, Map<int, String>>{};
    for (var i = 0; i < entries.length; i++) {
      final m = meaning[i];
      if (m is! ReactionText || !entries[i].countable) continue;
      final who = reactions.putIfAbsent(m.ref, () => <int, String>{});
      if (m.emoji == null) {
        who.remove(entries[i].sender);
      } else {
        who[entries[i].sender] = m.emoji!;
      }
    }
    reactions.removeWhere((_, v) => v.isEmpty);
    return ThreadRefs._(index, reactions, meaning);
  }

  /// Entry index by reference.
  final Map<String, int> indexOf;

  /// Reactions by reference: sender → emoji.
  final Map<String, Map<int, String>> reactions;

  /// What each entry's text means, by entry index.
  final List<MeshText> meaning;

  /// Whether entry [i] is a reaction (folded, not shown as a bubble) whose
  /// message is in this thread.
  bool folded(int i) => switch (meaning[i]) {
    ReactionText(:final ref) => indexOf.containsKey(ref),
    _ => false,
  };

  /// Counts for the message with reference [ref], in [kReactions] order.
  List<(String, int)> countsFor(String? ref) {
    final who = ref == null ? null : reactions[ref];
    if (who == null) return const [];
    return [
      for (final e in kReactions)
        if (who.values.where((x) => x == e).length case final n when n > 0) (e, n),
    ];
  }
}
