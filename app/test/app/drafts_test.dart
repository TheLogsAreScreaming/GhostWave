// Per-chat drafts (#271): kept in the encrypted history, survive a restart,
// and go with the chat when it, or all chat history, is deleted.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;

const int ann = 0xA0000001, ben = 0xB0000002;

void main() {
  late Directory dir;
  late SharedPreferences prefs;

  ProviderContainer make() => ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
    ],
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-drafts.');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async {
    // a disposed controller's last save can still be landing: retry until
    // the folder is quiet instead of racing it
    for (var i = 0; i < 20 && dir.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // a file appeared mid-delete; try again
      }
    }
  });

  Future<ProviderContainer> connected() async {
    final c = make();
    c.listen(meshProvider, (_, _) {});
    c.read(nodeLinkProvider).connect(answeringNode());
    await settle();
    return c;
  }

  test('a draft survives a restart; an empty one is removed', () async {
    final c = await connected();
    c.read(meshProvider.notifier)
      ..setDraft(ann, 'meet at the')
      ..setDraft(ben, 'x')
      ..setDraft(ben, '');
    c.read(meshProvider.notifier).flush();
    await c.read(meshStoreProvider)!.idle;
    c.dispose();

    final again = await connected();
    addTearDown(again.dispose);
    expect(again.read(meshProvider).drafts, {ann: 'meet at the'});
  });

  test('deleting a chat, or all chat history, deletes its drafts too', () async {
    final c = await connected();
    addTearDown(c.dispose);
    final ctl = c.read(meshProvider.notifier)
      ..setDraft(ann, 'one')
      ..setDraft(ben, 'two')
      ..deleteThread(ann);
    expect(c.read(meshProvider).drafts, {ben: 'two'});
    ctl.deleteAllMessages();
    expect(c.read(meshProvider).drafts, isEmpty);
  });

  test('no draft is kept before a node is connected (nothing to file it under)', () {
    final c = make();
    addTearDown(c.dispose);
    c.read(meshProvider.notifier).setDraft(ann, 'early');
    expect(c.read(meshProvider).drafts, isEmpty);
  });
}
