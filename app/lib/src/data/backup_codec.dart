/// The encrypted backup file: Argon2id from a passphrase, then XChaCha20-Poly1305.
///
/// The file is JSON. `header` is a JSON string authenticated as associated
/// data, so nobody can weaken the KDF settings of an existing file. There is
/// no recovery: without the passphrase the contents cannot be read.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// `format` field of every backup header.
const String kBackupFormat = 'ghostwave-backup';

/// The newest file version this app reads and the one it writes.
const int kBackupVersion = 1;

/// Shortest passphrase the app accepts for a new backup, in characters.
const int kMinBackupPassphrase = 12;

/// Largest backup file the app will open.
const int kMaxBackupBytes = 64 * 1024 * 1024;

/// Why a backup could not be opened.
sealed class BackupException implements Exception {
  const BackupException(this.message);

  /// Text for the user.
  final String message;

  @override
  String toString() => message;
}

/// The passphrase is wrong, or the file was altered: the two look the same by design.
final class BackupWrongPassphrase extends BackupException {
  /// Creates the error.
  const BackupWrongPassphrase() : super('Wrong passphrase, or the file is damaged.');
}

/// Not a backup, or malformed.
final class BackupBadFile extends BackupException {
  /// Creates the error.
  const BackupBadFile([super.message = 'This is not a GhostWave backup file.']);
}

/// Written by a newer app.
final class BackupTooNew extends BackupException {
  /// Creates the error.
  const BackupTooNew() : super('This backup was made by a newer version of GhostWave. Update the app first.');
}

/// Argon2id cost settings.
class BackupKdf {
  /// Creates settings.
  const BackupKdf({required this.memoryKiB, required this.iterations, required this.parallelism});

  /// What new backups use: 64 MiB, 3 passes (RFC 9106's low-memory choice).
  static const standard = BackupKdf(memoryKiB: 64 * 1024, iterations: 3, parallelism: 4);

  /// Memory in KiB.
  final int memoryKiB;

  /// Passes.
  final int iterations;

  /// Lanes.
  final int parallelism;

  /// Whether a file's settings are small enough to run on a phone. The header
  /// is only authenticated after the KDF, so a hostile file must not be able
  /// to demand gigabytes first.
  bool get withinLimits =>
      memoryKiB >= 8 * parallelism &&
      memoryKiB <= 256 * 1024 &&
      iterations >= 1 &&
      iterations <= 16 &&
      parallelism >= 1 &&
      parallelism <= 8;
}

Uint8List _random(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

Future<SecretKey> _derive(String passphrase, BackupKdf kdf, List<int> salt) => Argon2id(
  memory: kdf.memoryKiB,
  iterations: kdf.iterations,
  parallelism: kdf.parallelism,
  hashLength: 32,
).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

/// Encrypts [payload] into the bytes of a backup file. Runs off the UI isolate.
Future<Uint8List> sealBackup(Map<String, Object?> payload, String passphrase, {BackupKdf kdf = BackupKdf.standard}) {
  final plain = utf8.encode(jsonEncode(payload));
  return Isolate.run(() => _seal(plain, passphrase, kdf));
}

Future<Uint8List> _seal(List<int> plain, String passphrase, BackupKdf kdf) async {
  final salt = _random(16);
  final nonce = _random(24);
  final header = jsonEncode({
    'format': kBackupFormat,
    'version': kBackupVersion,
    'cipher': 'xchacha20-poly1305',
    'kdf': {
      'name': 'argon2id',
      'memoryKiB': kdf.memoryKiB,
      'iterations': kdf.iterations,
      'parallelism': kdf.parallelism,
      'salt': base64Encode(salt),
    },
    'nonce': base64Encode(nonce),
  });
  final box = await Xchacha20.poly1305Aead().encrypt(
    plain,
    secretKey: await _derive(passphrase, kdf, salt),
    nonce: nonce,
    aad: utf8.encode(header),
  );
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({'header': header, 'ciphertext': base64Encode(box.cipherText), 'mac': base64Encode(box.mac.bytes)}),
    ),
  );
}

/// Decrypts a backup file. Throws a [BackupException]. Runs off the UI isolate.
Future<Map<String, Object?>> openBackup(List<int> file, String passphrase) {
  if (file.length > kMaxBackupBytes) throw const BackupBadFile('This file is too large to be a GhostWave backup.');
  final bytes = Uint8List.fromList(file);
  return Isolate.run(() => _open(bytes, passphrase));
}

Future<Map<String, Object?>> _open(Uint8List file, String passphrase) async {
  final String headerText;
  final Map<String, Object?> kdfJson;
  final List<int> ciphertext;
  final List<int> mac;
  final List<int> nonce;
  try {
    final outer = jsonDecode(utf8.decode(file)) as Map<String, Object?>;
    headerText = outer['header']! as String;
    final header = jsonDecode(headerText) as Map<String, Object?>;
    if (header['format'] != kBackupFormat) throw const BackupBadFile();
    if ((header['version']! as int) > kBackupVersion) throw const BackupTooNew();
    if (header['cipher'] != 'xchacha20-poly1305') throw const BackupBadFile();
    kdfJson = header['kdf']! as Map<String, Object?>;
    if (kdfJson['name'] != 'argon2id') throw const BackupBadFile();
    nonce = base64Decode(header['nonce']! as String);
    ciphertext = base64Decode(outer['ciphertext']! as String);
    mac = base64Decode(outer['mac']! as String);
  } on BackupException {
    rethrow;
  } on Object {
    throw const BackupBadFile();
  }
  final BackupKdf kdf;
  final List<int> salt;
  try {
    kdf = BackupKdf(
      memoryKiB: kdfJson['memoryKiB']! as int,
      iterations: kdfJson['iterations']! as int,
      parallelism: kdfJson['parallelism']! as int,
    );
    salt = base64Decode(kdfJson['salt']! as String);
  } on Object {
    throw const BackupBadFile();
  }
  if (!kdf.withinLimits || salt.length < 8 || nonce.length != 24 || mac.length != 16) throw const BackupBadFile();
  final List<int> plain;
  try {
    plain = await Xchacha20.poly1305Aead().decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: await _derive(passphrase, kdf, salt),
      aad: utf8.encode(headerText),
    );
  } on SecretBoxAuthenticationError {
    throw const BackupWrongPassphrase();
  }
  try {
    return jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
  } on Object {
    throw const BackupBadFile();
  }
}
