/// Encrypted client link (`docs/CLIENT_PROTOCOL.md` §7): a PAKE over X25519
/// whose generator comes from the PIN, then ChaCha20-Poly1305 on every frame.
/// Plain Dart: no Flutter imports.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartChacha20;

/// Length of the Poly1305 tag on a sealed frame.
const int kLinkTag = 16;

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _a = BigInt.from(486662);

BigInt _fromLe(List<int> b) {
  var n = BigInt.zero;
  for (var i = b.length - 1; i >= 0; i--) {
    n = (n << 8) | BigInt.from(b[i]);
  }
  return n;
}

Uint8List _toLe(BigInt n) {
  final out = Uint8List(32);
  var v = n;
  final mask = BigInt.from(255);
  for (var i = 0; i < 32; i++) {
    out[i] = (v & mask).toInt();
    v >>= 8;
  }
  return out;
}

/// Elligator 2 on curve25519: maps 32 bytes to a curve point (u coordinate).
/// The top two bits of [hidden] are ignored, as in Monocypher.
Uint8List elligatorMap(List<int> hidden) {
  final r = _fromLe([...hidden.sublist(0, 31), hidden[31] & 0x3f]) % _p;
  final inverseExp = _p - BigInt.two;
  final w = (-_a * (BigInt.one + BigInt.two * r * r).modPow(inverseExp, _p)) % _p;
  final curve = (w * w * w + _a * w * w + w) % _p;
  final legendre = curve.modPow((_p - BigInt.one) >> 1, _p);
  final isSquare = legendre != _p - BigInt.one;
  return _toLe(isSquare ? w : (-w - _a) % _p);
}

Uint8List _generator(String pin, List<int> nonce) {
  final pinBytes = utf8.encode(pin);
  final h = hashing.sha512.convert([...utf8.encode('ghostwave-pake-v1'), pinBytes.length, ...pinBytes, ...nonce]).bytes;
  return elligatorMap(h);
}

final X25519 _x25519 = X25519();

Future<Uint8List> _dh(List<int> secret, List<int> point) async {
  final pair = await _x25519.newKeyPairFromSeed(secret);
  final shared = await _x25519.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: SimplePublicKey(point, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await shared.extractBytes());
}

/// [secret]'s share on the generator for [pin] and [nonce].
Future<Uint8List> linkShare(String pin, List<int> nonce, List<int> secret) => _dh(secret, _generator(pin, nonce));

/// A new random 32-byte secret for one handshake.
Uint8List newLinkSecret() {
  final rng = Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
}

/// What a handshake agrees on.
class LinkKeys {
  /// Creates the keys.
  const LinkKeys(this.clientToNode, this.nodeToClient, this.confirm);

  /// Seals what the app sends.
  final List<int> clientToNode;

  /// Seals what the node sends.
  final List<int> nodeToClient;

  /// `Hello.pin_proof`: shows the client holds the same keys.
  final List<int> confirm;
}

/// The keys from our [secret] and the peer's share, or null for a low-order
/// share (a bad peer).
Future<LinkKeys?> linkKeys({
  required List<int> secret,
  required List<int> theirShare,
  required List<int> nonce,
  required List<int> serverShare,
  required List<int> clientShare,
}) async {
  final Uint8List shared;
  try {
    shared = await _dh(secret, theirShare);
  } on ArgumentError {
    return null;
  }
  if (shared.every((b) => b == 0)) return null;
  final okm = hashing.Hmac(
    hashing.sha512,
    shared,
  ).convert([...utf8.encode('ghostwave-link-v1'), ...nonce, ...serverShare, ...clientShare]).bytes;
  final tag = hashing.Hmac(hashing.sha512, okm).convert(utf8.encode('ghostwave-link-confirm')).bytes;
  return LinkKeys(okm.sublist(0, 32), okm.sublist(32, 64), tag.sublist(0, 32));
}

/// One direction of an encrypted link. The counter advances with each frame,
/// so a replayed, dropped or reordered frame fails to open.
class LinkCipher {
  /// Creates a cipher starting at counter 0.
  LinkCipher(List<int> key) : _key = SecretKeyData(key);

  static final DartChacha20 _aead = DartChacha20.poly1305Aead();
  final SecretKeyData _key;
  int _seq = 0;

  static List<int> _nonce(int seq) {
    final b = ByteData(12)..setUint64(4, seq, Endian.little);
    return b.buffer.asUint8List();
  }

  /// Seals [plain] with the next counter value; ciphertext then tag.
  Uint8List seal(List<int> plain) {
    final box = _aead.encryptSync(plain, secretKey: _key, nonce: _nonce(_seq++));
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  /// Opens [sealed] with the next counter value, or null if it doesn't check.
  Uint8List? open(List<int> sealed) {
    if (sealed.length < kLinkTag) return null;
    final macAt = sealed.length - kLinkTag;
    try {
      final plain = _aead.decryptSync(
        SecretBox(sealed.sublist(0, macAt), nonce: _nonce(_seq), mac: Mac(sealed.sublist(macAt))),
        secretKey: _key,
      );
      _seq++;
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}
