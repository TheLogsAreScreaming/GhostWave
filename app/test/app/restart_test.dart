// Restarting the node from the app (Restart, protocol 1.13): offered only to
// radio boards that know it, asks first, and says what a restart keeps.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/ui/restart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show settle;

/// A radio board that answers Restart with [reply] (Ok by default).
FakeNode restartableNode({int minor = 13, String firmware = 'ghostwave-rak3401_1w 0.1.0-dev.13', pb.Error? reply}) {
  final node = FakeNode()
    ..protocolMinor = minor
    ..firmware = firmware;
  node.onRequest.listen((e) {
    final (c, r) = e;
    switch (r.whichRequest()) {
      case pb.ToRadio_Request.restart:
        c.send(reply == null ? pb.FromRadio(reqId: r.reqId, ok: pb.Ok()) : pb.FromRadio(reqId: r.reqId, error: reply));
      case pb.ToRadio_Request.listContacts:
        c.send(pb.FromRadio(reqId: r.reqId, contactsEnd: pb.ContactsEnd()));
      case pb.ToRadio_Request.listChannels:
        c.send(pb.FromRadio(reqId: r.reqId, channelsEnd: pb.ChannelsEnd()));
      case pb.ToRadio_Request.getPosition:
        c.send(pb.FromRadio(reqId: r.reqId, position: pb.OwnPosition()));
      case pb.ToRadio_Request.getStatus:
        c.send(pb.FromRadio(reqId: r.reqId, status: pb.Status()));
      default:
        break;
    }
  });
  return node;
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-restart.');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
      ],
    );
    c.listen(meshProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('a 1.13 radio board is sent Restart and answers Ok', () async {
    final node = restartableNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    expect(ctl.nodeCanRestart, isTrue);
    await ctl.restartNode();
    expect(node.requests.where((r) => r.hasRestart()), hasLength(1));
  });

  test('an older node, or a Pi node, is never sent Restart', () async {
    for (final node in [restartableNode(minor: 12), restartableNode(firmware: '')]) {
      c.read(nodeLinkProvider).connect(node);
      await settle();
      final ctl = c.read(meshProvider.notifier);
      expect(ctl.nodeCanRestart, isFalse);
      await expectLater(ctl.restartNode(), throwsA(isA<StateError>()));
      expect(node.requests.where((r) => r.hasRestart()), isEmpty);
    }
  });

  test('a refusal comes back as a NodeError', () async {
    final node = restartableNode(
      reply: pb.Error(code: pb.Error_Code.SEND_FAILED, detail: 'could not schedule a restart'),
    );
    c.read(nodeLinkProvider).connect(node);
    await settle();
    await expectLater(c.read(meshProvider.notifier).restartNode(), throwsA(isA<NodeError>()));
  });

  group('the confirm dialog', () {
    Future<void> pumpButton(WidgetTester tester, void Function(bool) done) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async => done(await confirmRestartNode(context, ref)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('says what is kept and lost; Restart sends it', (tester) async {
      final node = restartableNode();
      await tester.runAsync(() async {
        c.read(nodeLinkProvider).connect(node);
        await settle();
      });
      bool? result;
      await pumpButton(tester, (r) => result = r);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Restart the node?'), findsOneWidget);
      expect(find.textContaining('Saved settings, contacts and channels are kept'), findsOneWidget);
      expect(find.textContaining('holding for other nodes are lost'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Restart'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(node.requests.where((r) => r.hasRestart()), hasLength(1));
      expect(find.textContaining('Restarting'), findsOneWidget);
    });

    testWidgets('Cancel sends nothing', (tester) async {
      final node = restartableNode();
      await tester.runAsync(() async {
        c.read(nodeLinkProvider).connect(node);
        await settle();
      });
      bool? result;
      await pumpButton(tester, (r) => result = r);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(node.requests.where((r) => r.hasRestart()), isEmpty);
    });
  });
}
