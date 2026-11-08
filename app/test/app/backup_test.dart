import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/backup.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/backup_codec.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/ui/backup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pass = 'correct horse battery';
const nodeHex = '11223344';
const nodeId = 0x11223344;

class FakeFiles implements BackupFiles {
  Uint8List? saved;
  String? name;

  @override
  bool get supported => true;

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    name = suggestedName;
    saved = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => saved;
}

void main() {
  late Directory dir;
  late FakeFiles files;
  late MemoryPinStore pins;
  late MeshStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-backup.');
    files = FakeFiles();
    pins = MemoryPinStore();
    store = MeshStore(dir);
  });
  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<ProviderContainer> container(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        meshStoreProvider.overrideWithValue(store),
        pinStoreProvider.overrideWithValue(pins),
        backupFilesProvider.overrideWithValue(files),
        backupKdfProvider.overrideWithValue(const BackupKdf(memoryKiB: 64, iterations: 1, parallelism: 1)),
      ],
    );
    addTearDown(c.dispose);
    c.read(meshProvider);
    return c;
  }

  test('backup then restore brings everything back and drops what came later', () async {
    final c = await container({
      'units': 'imperial',
      'recent_nodes': '[]',
      'background_link': true,
      'share_location': true,
    });
    await store.save(nodeId, const StoredMesh());
    await pins.write('10.0.0.5:4403', '123456');
    c.read(recentNodesProvider.notifier).touch('10.0.0.5:4403');
    final backup = c.read(backupProvider);

    expect(await backup.create(pass, now: DateTime.utc(2026, 11, 8)), isTrue);
    expect(files.name, 'ghostwave-2026-11-08.gwbackup');

    // later changes
    await store.save(0x55667788, const StoredMesh());
    await pins.write('10.0.0.5:4403', '999999');
    await pins.write('10.0.0.9:4403', '111111');
    final prefs = c.read(sharedPrefsProvider);
    await prefs.setString('units', 'metric');

    await backup.restore(await backup.read(files.saved!, pass));

    expect((await store.exportAll()).keys, [nodeHex]);
    expect(await pins.read('10.0.0.5:4403'), '123456');
    expect(await pins.read('10.0.0.9:4403'), isNull);
    expect(prefs.getString('units'), 'imperial');
    expect(c.read(recentNodesProvider).single.address, '10.0.0.5:4403');
    // per-phone consents stay as they were on this phone
    expect(prefs.getBool('background_link'), isTrue);
    expect(dir.existsSync() && Directory('${dir.path}/restore_staging').existsSync(), isFalse);
  });

  test('the backup carries no field for the node identity', () async {
    final c = await container({});
    await store.save(nodeId, const StoredMesh());
    final b = c.read(backupProvider);
    await b.create(pass);
    final data = await b.read(files.saved!, pass);
    expect(data.toJson().keys, unorderedEquals(['payloadVersion', 'prefs', 'pins', 'nodes']));
  });

  test('a wrong passphrase changes nothing', () async {
    final c = await container({'units': 'imperial'});
    await store.save(nodeId, const StoredMesh());
    final b = c.read(backupProvider);
    await b.create(pass);
    await expectLater(b.read(files.saved!, 'not the passphrase'), throwsA(isA<BackupWrongPassphrase>()));
    expect((await store.exportAll()).keys, [nodeHex]);
  });

  group('malformed payloads are refused before anything changes', () {
    Map<String, Object?> good() => {
      'prefs': <String, Object?>{},
      'pins': <String, Object?>{},
      'nodes': <String, Object?>{},
    };

    test('good one parses', () => expect(BackupData.parse(good()).nodes, isEmpty));
    test('path in a node id', () {
      final j = good()..['nodes'] = {'../../evil': <String, Object?>{}};
      expect(() => BackupData.parse(j), throwsA(isA<BackupBadFile>()));
    });
    test('unknown prefs are ignored', () {
      final j = good()..['prefs'] = {'background_link': true, 'units': 'metric'};
      expect(BackupData.parse(j).prefs, {'units': 'metric'});
    });
    test('missing section', () {
      expect(() => BackupData.parse({'prefs': <String, Object?>{}}), throwsA(isA<BackupBadFile>()));
    });
  });

  testWidgets('the screen says the identity is not included and there is no recovery', (t) async {
    final c = await t.runAsync(() => container({}));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c!,
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    expect(find.textContaining('does not include your node'), findsOneWidget);
    expect(find.textContaining('new identity'), findsOneWidget);
    expect(find.textContaining('forget the passphrase'), findsOneWidget);
  });

  testWidgets('a short or mismatched passphrase cannot be used', (t) async {
    final c = await t.runAsync(() => container({}));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c!,
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await t.tap(find.text('Create backup'));
    await t.pumpAndSettle();
    FilledButton create() => t.widget(find.widgetWithText(FilledButton, 'Create').last);
    await t.enterText(find.byKey(const Key('passphrase')), 'short');
    await t.enterText(find.byKey(const Key('passphrase2')), 'short');
    await t.pump();
    expect(create().onPressed, isNull);
    await t.enterText(find.byKey(const Key('passphrase')), pass);
    await t.enterText(find.byKey(const Key('passphrase2')), '$pass!');
    await t.pump();
    expect(create().onPressed, isNull);
    await t.enterText(find.byKey(const Key('passphrase2')), pass);
    await t.pump();
    expect(create().onPressed, isNotNull);
  });
}
