/// The contact card a QR code carries, and small text helpers.
///
/// Card text (this app's spec, following GhostWave `CLIENT_PROTOCOL.md` §8):
///
/// ```
/// ghostwave:<node id, 8 hex>:<ed25519 public key, 64 hex>[:<name, percent-encoded>]
/// ```
/// e.g. `ghostwave:1a2b3c4d:9f…e0:Bob`. Hex is case-insensitive. The node
/// only needs the ID and key (`AddContact`); the name is a local label.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Scheme prefix of a card.
const String kCardScheme = 'ghostwave:';

/// Largest contact name the node keeps (`AddContact.name`), in UTF-8 bytes.
const int kMaxContactNameBytes = 32;

/// A parsed contact card.
class ContactCard {
  /// Creates a card.
  ContactCard({required this.nodeId, required this.ed25519Pub, this.name = ''})
    : assert(ed25519Pub.length == 32, 'ed25519 key is 32 bytes');

  /// The node ID (32-bit).
  final int nodeId;

  /// The node's Ed25519 public key (32 bytes).
  final Uint8List ed25519Pub;

  /// Display name, possibly empty.
  final String name;

  /// The text a QR code carries.
  String encode() {
    final base = '$kCardScheme${nodeIdHex(nodeId)}:${hexEncode(ed25519Pub)}';
    return name.isEmpty ? base : '$base:${Uri.encodeComponent(name)}';
  }

  /// Parses card text (whitespace around it is ignored). Returns null if it is
  /// not a valid card.
  static ContactCard? tryParse(String text) {
    final s = text.trim();
    if (s.length < kCardScheme.length || s.substring(0, kCardScheme.length).toLowerCase() != kCardScheme) {
      return null;
    }
    final parts = s.substring(kCardScheme.length).split(':');
    if (parts.length < 2) return null;
    final idHex = parts[0];
    final keyHex = parts[1];
    if (idHex.length != 8 || keyHex.length != 64) return null;
    final id = int.tryParse(idHex, radix: 16);
    final key = hexDecode(keyHex);
    if (id == null || key == null || id == 0) return null;
    var name = '';
    if (parts.length > 2) {
      final raw = parts.sublist(2).join(':');
      try {
        name = Uri.decodeComponent(raw);
      } on ArgumentError {
        name = raw;
      } on FormatException {
        // percent-escapes that are not UTF-8
        name = raw;
      }
      name = truncateUtf8(name.trim(), kMaxContactNameBytes);
    }
    return ContactCard(nodeId: id, ed25519Pub: key, name: name);
  }
}

/// Scheme prefix of a group channel card (protocol 1.1).
const String kChannelScheme = 'ghostwave-ch:';

/// Longest channel name the node keeps, in UTF-8 bytes.
const int kMaxChannelNameBytes = 16;

/// The channel card format this app reads and writes.
///
/// Format 1 is the text below. It may carry an explicit `?v=1` at the end;
/// without it a card is format 1, so cards made before the marker existed (and
/// by `gwclient` and the node console) still read. A later format must bump
/// this number, and this app refuses any other `v` instead of guessing.
const int kChannelCardFormat = 1;

/// A group channel to share or join: name and 32-byte key.
///
/// ```
/// ghostwave-ch:<name, percent-encoded>:<psk, 64 hex>[?v=1]
/// ```
/// Anyone with this text can read and write the channel: share it like a password.
class ChannelCard {
  /// Creates a card.
  ChannelCard({required this.name, required this.psk}) : assert(psk.length == 32, 'channel key is 32 bytes');

  /// Channel name (1..16 bytes UTF-8).
  final String name;

  /// The pre-shared key.
  final Uint8List psk;

  /// The text a QR code carries: format 1, written without the `?v=1` marker
  /// so apps and tools that predate the marker read it too.
  String encode() => '$kChannelScheme${Uri.encodeComponent(name)}:${hexEncode(psk)}';

  /// Parses card text; null if it is not a valid channel card.
  static ChannelCard? tryParse(String text) => switch (parse(text)) {
    ChannelCardOk(:final card) => card,
    ChannelCardRejected() => null,
  };

  /// Parses card text and says why it was refused.
  static ChannelCardResult parse(String text) {
    final s = text.trim();
    if (s.length < kChannelScheme.length || s.substring(0, kChannelScheme.length).toLowerCase() != kChannelScheme) {
      return const ChannelCardRejected(ChannelCardProblem.notAChannelCard);
    }
    var rest = s.substring(kChannelScheme.length);
    final q = rest.indexOf('?');
    if (q >= 0) {
      final query = rest.substring(q + 1);
      rest = rest.substring(0, q);
      final m = RegExp(r'^v=([0-9]{1,6})$').firstMatch(query);
      if (m == null) return const ChannelCardRejected(ChannelCardProblem.badVersion);
      final v = int.parse(m.group(1)!);
      if (v > kChannelCardFormat) return const ChannelCardRejected(ChannelCardProblem.newerFormat);
      if (v != kChannelCardFormat) return const ChannelCardRejected(ChannelCardProblem.badVersion);
    }
    final colon = rest.lastIndexOf(':');
    if (colon < 0) return const ChannelCardRejected(ChannelCardProblem.badKey);
    final key = hexDecode(rest.substring(colon + 1));
    if (key == null || key.length != 32) return const ChannelCardRejected(ChannelCardProblem.badKey);
    String name;
    try {
      name = Uri.decodeComponent(rest.substring(0, colon));
    } on ArgumentError {
      return const ChannelCardRejected(ChannelCardProblem.badName);
    } on FormatException {
      // percent-escapes that are not UTF-8
      return const ChannelCardRejected(ChannelCardProblem.badName);
    }
    if (!validChannelName(name)) return const ChannelCardRejected(ChannelCardProblem.badName);
    return ChannelCardOk(ChannelCard(name: name, psk: key));
  }
}

/// Why a channel card was refused.
enum ChannelCardProblem {
  /// Not `ghostwave-ch:` text at all.
  notAChannelCard('Not a GhostWave channel card'),

  /// A `v` this app does not know, or a malformed marker.
  badVersion('This channel card has an unknown format marker'),

  /// Made by a newer GhostWave app.
  newerFormat('This channel card was made by a newer GhostWave app. Update the app to join it.'),

  /// The key is missing or not 64 hex digits.
  badKey('The channel key in this card is missing or damaged'),

  /// The name is empty, too long, badly encoded or has control characters.
  badName('The channel name in this card is not valid');

  const ChannelCardProblem(this.message);

  /// What to tell the user.
  final String message;
}

/// The outcome of [ChannelCard.parse].
sealed class ChannelCardResult {
  const ChannelCardResult();
}

/// A valid card.
final class ChannelCardOk extends ChannelCardResult {
  /// Wraps [card].
  const ChannelCardOk(this.card);

  /// The card.
  final ChannelCard card;
}

/// A refused card.
final class ChannelCardRejected extends ChannelCardResult {
  /// Refused for [problem].
  const ChannelCardRejected(this.problem);

  /// Why.
  final ChannelCardProblem problem;
}

/// Whether [name] is a usable channel name: 1..16 bytes, no control characters.
bool validChannelName(String name) {
  if (name.isEmpty || utf8Length(name) > kMaxChannelNameBytes) return false;
  return !name.codeUnits.any((c) => c < 0x20 || c == 0x7F);
}

/// A node ID as 8 lowercase hex digits.
String nodeIdHex(int id) => (id & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

/// Lowercase hex of [bytes].
String hexEncode(List<int> bytes) => bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join();

/// Decodes hex (even length, case-insensitive), or null.
Uint8List? hexDecode(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) return null;
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// UTF-8 byte count of [s]: what the node's text limit counts.
int utf8Length(String s) => utf8.encode(s).length;

/// The longest prefix of [s] that fits [maxBytes] of UTF-8 without splitting
/// a character.
String truncateUtf8(String s, int maxBytes) {
  if (utf8Length(s) <= maxBytes) return s;
  var used = 0;
  final out = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8Length(ch);
    if (used + n > maxBytes) break;
    used += n;
    out.write(ch);
  }
  return out.toString();
}

/// Text from the air: usually UTF-8, not guaranteed.
String decodeLenient(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
