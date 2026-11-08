/// Encryption of the chat history files on the phone.
///
/// One random 256-bit key per install, held in the platform's secure storage
/// (Android Keystore), seals each node's history with XChaCha20-Poly1305. The
/// node ID is bound in as associated data, so one node's file cannot be passed
/// off as another's.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Length of the history key, bytes.
const int kHistoryKeyBytes = 32;

/// The key could not be read, or the history could not be prepared. Nothing is
/// overwritten while this holds; it may clear on the next start.
class HistoryLocked implements Exception {
  /// Creates the error.
  const HistoryLocked();

  @override
  String toString() => 'Chat history is locked: this phone did not release its key. Restart the app and try again.';
}

/// Holds the history key.
abstract interface class HistoryKeys {
  /// The saved key (base64), or null if none was ever saved. Throws if the
  /// storage cannot answer, which is not the same as having no key.
  Future<String?> read();

  /// Saves [key] (base64).
  Future<void> write(String key);

  /// Forgets the key (app data reset).
  Future<void> delete();
}

/// [HistoryKeys] in memory, for tests.
class MemoryHistoryKeys implements HistoryKeys {
  String? _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String key) async => _key = key;

  @override
  Future<void> delete() async => _key = null;
}

/// [HistoryKeys] in the platform's secure storage.
class SecureHistoryKeys implements HistoryKeys {
  /// Creates the store.
  const SecureHistoryKeys();

  // Its own namespace, so clearing saved PINs cannot take the key with it.
  // resetOnError is off: the default wipes the storage after one failed
  // decrypt, which would lose every chat over a passing Keystore error.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, storageNamespace: 'ghostwave_history'),
    iOptions: IOSOptions(
      accountName: 'ghostwave_history',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _name = 'history_key_v1';

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String key) => _storage.write(key: _name, value: key);

  @override
  Future<void> delete() => _storage.deleteAll();
}

/// Returns the saved key, making and saving one if there is none yet.
/// Throws [HistoryLocked] if the storage fails or returns something else.
Future<SecretKey> readOrCreateHistoryKey(HistoryKeys keys) async {
  try {
    final saved = await keys.read();
    if (saved != null) {
      final bytes = base64Decode(saved);
      if (bytes.length != kHistoryKeyBytes) throw const HistoryLocked();
      return SecretKey(bytes);
    }
    final rng = Random.secure();
    final fresh = base64Encode(List<int>.generate(kHistoryKeyBytes, (_) => rng.nextInt(256)));
    await keys.write(fresh);
    // never seal anything under a key that did not actually get saved
    if (await keys.read() != fresh) throw const HistoryLocked();
    return SecretKey(base64Decode(fresh));
  } on HistoryLocked {
    rethrow;
  } on Object {
    throw const HistoryLocked();
  }
}

final Uint8List _magic = ascii.encode('GWH1');
final Xchacha20 _cipher = Xchacha20.poly1305Aead();
const int _nonceBytes = 24;
const int _tagBytes = 16;

List<int> _aad(String nodeHex) => utf8.encode('ghostwave-history-v1:$nodeHex');

/// Seals [json] for the node [nodeHex]: magic, nonce, ciphertext, tag.
Future<Uint8List> sealHistory(String json, SecretKey key, String nodeHex) async {
  final box = await _cipher.encrypt(utf8.encode(json), secretKey: key, aad: _aad(nodeHex));
  return (BytesBuilder(copy: false)
        ..add(_magic)
        ..add(box.nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes))
      .takeBytes();
}

/// Opens a file from [sealHistory]. Throws [FormatException] if it is not one,
/// and [SecretBoxAuthenticationError] if it was changed or the key is wrong.
Future<String> openHistory(Uint8List file, SecretKey key, String nodeHex) async {
  if (file.length < _magic.length + _nonceBytes + _tagBytes) throw const FormatException('history file too short');
  for (var i = 0; i < _magic.length; i++) {
    if (file[i] != _magic[i]) throw const FormatException('not a history file');
  }
  final macAt = file.length - _tagBytes;
  final box = SecretBox(
    Uint8List.sublistView(file, _magic.length + _nonceBytes, macAt),
    nonce: Uint8List.sublistView(file, _magic.length, _magic.length + _nonceBytes),
    mac: Mac(Uint8List.sublistView(file, macAt)),
  );
  return utf8.decode(await _cipher.decrypt(box, secretKey: key, aad: _aad(nodeHex)));
}
