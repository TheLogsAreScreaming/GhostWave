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
      }
      name = truncateUtf8(name.trim(), kMaxContactNameBytes);
    }
    return ContactCard(nodeId: id, ed25519Pub: key, name: name);
  }
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
