import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/backup_codec.dart';

const cheap = BackupKdf(memoryKiB: 64, iterations: 1, parallelism: 1);
const pass = 'correct horse battery';

Map<String, Object?> decode(List<int> f) => jsonDecode(utf8.decode(f)) as Map<String, Object?>;

List<int> encode(Map<String, Object?> j) => utf8.encode(jsonEncode(j));

void main() {
  final payload = <String, Object?>{'hello': 'wörld', 'n': 3};

  test('round trip', () async {
    final f = await sealBackup(payload, pass, kdf: cheap);
    expect(await openBackup(f, pass), payload);
  });

  test('nothing readable in the file', () async {
    final f = await sealBackup({'secret': 'campsite-coordinates'}, pass, kdf: cheap);
    expect(utf8.decode(f), isNot(contains('campsite')));
  });

  test('each file gets a new salt and nonce', () async {
    final a = decode(await sealBackup(payload, pass, kdf: cheap));
    final b = decode(await sealBackup(payload, pass, kdf: cheap));
    expect(a['header'], isNot(b['header']));
    expect(a['ciphertext'], isNot(b['ciphertext']));
  });

  test('new backups use the strong settings', () {
    expect(BackupKdf.standard.memoryKiB, 65536);
    expect(BackupKdf.standard.iterations, 3);
    expect(BackupKdf.standard.withinLimits, isTrue);
  });

  test('wrong passphrase', () async {
    final f = await sealBackup(payload, pass, kdf: cheap);
    expect(openBackup(f, 'wrong passphrase'), throwsA(isA<BackupWrongPassphrase>()));
  });

  test('altered ciphertext is refused', () async {
    final j = decode(await sealBackup(payload, pass, kdf: cheap));
    final c = base64Decode(j['ciphertext']! as String);
    c[0] ^= 1;
    j['ciphertext'] = base64Encode(c);
    expect(openBackup(encode(j), pass), throwsA(isA<BackupWrongPassphrase>()));
  });

  test('a changed header is refused, even with valid settings', () async {
    final j = decode(await sealBackup(payload, pass, kdf: cheap));
    j['header'] = (j['header']! as String).replaceFirst('"cipher"', ' "cipher"');
    expect(openBackup(encode(j), pass), throwsA(isA<BackupWrongPassphrase>()));
  });

  Future<List<int>> withHeader(void Function(Map<String, Object?>) edit) async {
    final j = decode(await sealBackup(payload, pass, kdf: cheap));
    final h = jsonDecode(j['header']! as String) as Map<String, Object?>;
    edit(h);
    j['header'] = jsonEncode(h);
    return encode(j);
  }

  test('a newer version says so', () async {
    expect(openBackup(await withHeader((h) => h['version'] = 2), pass), throwsA(isA<BackupTooNew>()));
  });

  test('a file demanding huge memory is refused before the KDF', () async {
    final f = await withHeader((h) => (h['kdf']! as Map<String, Object?>)['memoryKiB'] = 1 << 30);
    expect(openBackup(f, pass), throwsA(isA<BackupBadFile>()));
  });

  test('not a backup', () {
    expect(openBackup(utf8.encode('hello'), pass), throwsA(isA<BackupBadFile>()));
    expect(openBackup(encode({'header': '{}'}), pass), throwsA(isA<BackupBadFile>()));
  });
}
