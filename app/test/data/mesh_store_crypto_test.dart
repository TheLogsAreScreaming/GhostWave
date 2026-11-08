import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/history_crypto.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';

/// Key storage that can be told to fail, as a Keystore error would.
class FlakyKeys extends MemoryHistoryKeys {
  bool failing = false;

  @override
  Future<String?> read() {
    if (failing) throw StateError('keystore');
    return super.read();
  }
}

const _secret = 'meet at the north trailhead';

StoredMesh _mesh(String text) => StoredMesh(
  messages: {
    7: [ChatMessage(peer: 7, text: text, outgoing: true, at: DateTime.utc(2026, 11, 8))],
  },
);

void main() {
  late Directory dir;
  late FlakyKeys keys;
  late MeshStore store;

  File file(String name) => File('${dir.path}/$name');
  List<String> names() => [for (final f in dir.listSync()) f.uri.pathSegments.last]..sort();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-store.');
    keys = FlakyKeys();
    store = MeshStore(dir, keys);
  });
  tearDown(() => dir.delete(recursive: true));

  test('a saved history is sealed on disk and reads back after a restart', () async {
    await store.save(1, _mesh(_secret));
    final raw = file('node_00000001.gwh').readAsBytesSync();
    expect(latin1.decode(raw), isNot(contains('north trailhead')));
    expect(names(), ['node_00000001.gwh']);
    final loaded = await MeshStore(dir, keys).load(1);
    expect(loaded.messages[7]!.single.text, _secret);
    expect(loaded.problem, HistoryProblem.none);
  });

  test('two saves of the same data use different nonces', () async {
    await store.save(1, _mesh(_secret));
    final a = file('node_00000001.gwh').readAsBytesSync();
    await store.save(1, _mesh(_secret));
    expect(file('node_00000001.gwh').readAsBytesSync(), isNot(a));
  });

  test('old plaintext files are sealed and the plaintext is removed', () async {
    file('node_00000001.json').writeAsStringSync(jsonEncode(_mesh(_secret).toJson()));
    file('node_00000002.json').writeAsStringSync('{damaged');
    file('node_00000003.json.bad').writeAsStringSync(_secret);
    file('node_00000004.json.tmp').writeAsStringSync(_secret);
    final loaded = await store.load(1);
    expect(loaded.messages[7]!.single.text, _secret);
    expect(names(), ['node_00000001.gwh']);
  });

  test('a file changed on disk is set aside, not trusted', () async {
    await store.save(1, _mesh(_secret));
    final f = file('node_00000001.gwh');
    final b = f.readAsBytesSync();
    b[40] ^= 1;
    f.writeAsBytesSync(b);
    final loaded = await store.load(1);
    expect(loaded.messages, isEmpty);
    expect(loaded.problem, HistoryProblem.unreadable);
    expect(names(), ['node_00000001.gwh.bad']);
  });

  test('one node\'s file cannot stand in for another\'s', () async {
    await store.save(1, _mesh(_secret));
    file('node_00000001.gwh').renameSync('${dir.path}/node_00000002.gwh');
    expect((await store.load(2)).problem, HistoryProblem.unreadable);
  });

  test('a lost key reads as unreadable and new chats still save', () async {
    await store.save(1, _mesh(_secret));
    final later = MeshStore(dir, FlakyKeys());
    expect((await later.load(1)).problem, HistoryProblem.unreadable);
    await later.save(1, _mesh('new'));
    expect((await later.load(1)).messages[7]!.single.text, 'new');
    expect(names(), containsAll(['node_00000001.gwh', 'node_00000001.gwh.bad']));
  });

  test('while the key is unavailable, nothing is overwritten', () async {
    await store.save(1, _mesh(_secret));
    final before = file('node_00000001.gwh').readAsBytesSync();
    final later = MeshStore(dir, keys);
    keys.failing = true;
    final loaded = await later.load(1);
    expect(loaded.problem, HistoryProblem.locked);
    await expectLater(later.save(1, _mesh('x')), throwsA(isA<HistoryLocked>()));
    // even once the key is back, this session started from an empty view
    keys.failing = false;
    await expectLater(later.save(1, _mesh('x')), throwsA(isA<HistoryLocked>()));
    expect(file('node_00000001.gwh').readAsBytesSync(), before);
    // the next load opens it again
    expect((await later.load(1)).messages[7]!.single.text, _secret);
  });

  test('plaintext from an old version stays put while the key is unavailable', () async {
    file('node_00000001.json').writeAsStringSync(jsonEncode(_mesh(_secret).toJson()));
    keys.failing = true;
    expect((await store.load(1)).problem, HistoryProblem.locked);
    expect(names(), ['node_00000001.json']);
    keys.failing = false;
    expect((await store.load(1)).messages[7]!.single.text, _secret);
  });

  test('a backup is refused while the key is unavailable', () async {
    await store.save(1, _mesh(_secret));
    final later = MeshStore(dir, keys);
    keys.failing = true;
    await expectLater(later.exportAll(), throwsA(isA<HistoryLocked>()));
  });

  test('export and replace go through the sealed files', () async {
    await store.save(1, _mesh(_secret));
    final all = await store.exportAll();
    expect(all.keys, ['00000001']);
    await store.save(2, _mesh('later'));
    await store.replaceAll(all);
    expect(names(), ['node_00000001.gwh']);
    expect((await store.load(1)).messages[7]!.single.text, _secret);
  });

  test('reset deletes the files and the key', () async {
    await store.save(1, _mesh(_secret));
    await store.deleteAll();
    expect(names(), isEmpty);
    expect(await keys.read(), isNull);
    await store.save(1, _mesh('fresh'));
    expect((await store.load(1)).messages[7]!.single.text, 'fresh');
  });

  test('a stored key of the wrong length is treated as locked', () async {
    await keys.write(base64Encode(Uint8List(8)));
    expect((await store.load(1)).problem, HistoryProblem.locked);
  });
}
