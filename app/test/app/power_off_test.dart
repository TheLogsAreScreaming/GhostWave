// Powering the node off from the app (PowerOff, protocol 1.16): offered only
// to radio boards that know it, asks first, says how to turn it back on, and
// shows the node's reason when it refuses (during an SOS).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/ui/restart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show settle;

/// A radio board that answers PowerOff with [reply] (Ok by default).
FakeNode powerableNode({int minor = 16, String firmware = 'ghostwave-rak3401_1w 0.1.0-dev.17', pb.Error? reply}) {
  final node = FakeNode()
    ..protocolMinor = minor
    ..firmware = firmware;
  node.onRequest.listen((e) {
    final (c, r) = e;
    switch (r.whichRequest()) {
      case pb.ToRadio_Request.powerOff:
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
    dir = await Directory.systemTemp.createTemp('gwapp-poweroff.');
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

  test('a 1.16 radio board is sent PowerOff and answers Ok', () async {
    final node = powerableNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    expect(ctl.nodeCanPowerOff, isTrue);
    await ctl.powerOffNode();
    expect(node.requests.where((r) => r.hasPowerOff()), hasLength(1));
  });

  test('an older node, or a Pi node, is never sent PowerOff', () async {
    for (final node in [powerableNode(minor: 15), powerableNode(firmware: '')]) {
      c.read(nodeLinkProvider).connect(node);
      await settle();
      final ctl = c.read(meshProvider.notifier);
      expect(ctl.nodeCanPowerOff, isFalse);
      await expectLater(ctl.powerOffNode(), throwsA(isA<StateError>()));
      expect(node.requests.where((r) => r.hasPowerOff()), isEmpty);
    }
  });

  group('the confirm dialog', () {
    Future<void> pumpButton(WidgetTester tester, void Function(bool) done) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async => done(await confirmPowerOffNode(context, ref)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    Future<bool?> confirm(WidgetTester tester, FakeNode node) async {
      await tester.runAsync(() async {
        c.read(nodeLinkProvider).connect(node);
        await settle();
      });
      bool? result;
      await pumpButton(tester, (r) => result = r);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Power off the node?'), findsOneWidget);
      expect(find.textContaining('press its reset button'), findsOneWidget);
      expect(find.textContaining('Saved settings, contacts and channels are kept'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Power off'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('says how to turn it back on; Power off sends it', (tester) async {
      final node = powerableNode();
      expect(await confirm(tester, node), isTrue);
      expect(node.requests.where((r) => r.hasPowerOff()), hasLength(1));
      expect(find.text('Powering off.'), findsOneWidget);
    });

    testWidgets('during an SOS the node says no, and the app shows why', (tester) async {
      final node = powerableNode(
        reply: pb.Error(code: pb.Error_Code.SEND_FAILED, detail: 'not powering off during an SOS: stop it first'),
      );
      expect(await confirm(tester, node), isFalse);
      expect(find.textContaining('Not powered off'), findsOneWidget);
    });

    testWidgets('Cancel sends nothing', (tester) async {
      final node = powerableNode();
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
      expect(node.requests.where((r) => r.hasPowerOff()), isEmpty);
    });
  });
}
