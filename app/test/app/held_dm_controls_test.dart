// Held DMs (protocol 1.15): take one back with CancelSend while the node still
// holds it, and get a notification when one that waited is finally delivered.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/ui/chat_screen.dart';
import 'package:ghostwave_app/src/ui/message_bubble.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show bob, settle;
import 'phone_qol_test.dart' show RecordingAlerts;

/// A 1.15 node that holds every DM, and answers CancelSend as told.
class HoldingNode {
  HoldingNode({int minor = 15}) {
    node.protocolMinor = minor;
    node.onRequest.listen((e) {
      final (c, r) = e;
      final id = r.reqId;
      switch (r.whichRequest()) {
        case pb.ToRadio_Request.listContacts:
          c.send(
            pb.FromRadio(
              reqId: id,
              contact: pb.Contact(nodeId: bob, name: 'bob'.codeUnits, pinned: true),
            ),
          );
          c.send(pb.FromRadio(reqId: id, contactsEnd: pb.ContactsEnd(count: 1)));
        case pb.ToRadio_Request.sendText:
          c.send(
            pb.FromRadio(
              reqId: id,
              sendQueued: pb.SendQueued(
                dest: r.sendText.dest,
                msgId: 0x3000 + r.sendText.clientMsgId % 1000,
                clientMsgId: r.sendText.clientMsgId,
                held: true,
              ),
            ),
          );
        case pb.ToRadio_Request.cancelSend:
          cancels.add(r.cancelSend.msgId);
          c.send(
            gone || (cancelLimit != null && cancels.length > cancelLimit!)
                ? pb.FromRadio(
                    reqId: id,
                    error: pb.Error(code: pb.Error_Code.NOT_FOUND),
                  )
                : pb.FromRadio(
                    reqId: id,
                    sendCancelled: pb.SendCancelled(msgId: r.cancelSend.msgId, copiesOut: copiesOut),
                  ),
          );
        default:
          break;
      }
    });
  }

  final FakeNode node = FakeNode();
  final List<int> cancels = [];
  bool copiesOut = false;
  bool gone = false;

  /// Takes back only this many; later ones are already gone (NOT_FOUND).
  int? cancelLimit;
}

void main() {
  late Directory dir;
  late ProviderContainer c;
  late RecordingAlerts alerts;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-heldctl.');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    alerts = RecordingAlerts();
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        meshAlertsProvider.overrideWithValue(alerts),
      ],
    );
    c.listen(meshProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  MeshController ctl() => c.read(meshProvider.notifier);
  ChatMessage only() => c.read(meshProvider).messages[bob]!.single;

  Future<HoldingNode> connectAndSend({int minor = 15}) async {
    final n = HoldingNode(minor: minor);
    c.read(nodeLinkProvider).connect(n.node);
    await settle();
    await ctl().sendText(bob, 'see you at camp');
    await settle();
    expect(only().state, MsgState.sent);
    expect(only().held, isTrue);
    return n;
  }

  test('cancel: the node takes it back, and it is marked failed so it can be sent again', () async {
    final n = await connectAndSend();
    expect(ctl().nodeCanCancelSend, isTrue);
    expect(await ctl().cancelHeld(only()), isFalse);
    await settle();
    expect(n.cancels, [only().msgId]);
    expect(only().state, MsgState.failed);
    expect(only().held, isFalse);
    expect(only().error, 'Cancelled: not sent');
  });

  test('cancel after copies were passed on: says so, and a receipt still marks it delivered', () async {
    final n = await connectAndSend()
      ..copiesOut = true;
    expect(await ctl().cancelHeld(only()), isTrue);
    await settle();
    expect(only().state, MsgState.failed);
    expect(only().error, contains('may still arrive'));
    n.node.last.send(
      pb.FromRadio(
        delivered: pb.Delivered(dest: bob, msgId: only().msgId, clientMsgId: only().clientMsgId),
      ),
    );
    await settle();
    expect(only().state, MsgState.delivered);
  });

  test('too late: NOT_FOUND leaves the message as it was', () async {
    final n = await connectAndSend()
      ..gone = true;
    await expectLater(
      ctl().cancelHeld(only()),
      throwsA(isA<NodeError>().having((e) => e.code, 'code', pb.Error_Code.NOT_FOUND)),
    );
    await settle();
    expect(n.cancels, hasLength(1));
    expect(only().state, MsgState.sent);
    expect(only().held, isTrue);
  });

  test('a node older than 1.15 cannot cancel', () async {
    await connectAndSend(minor: 14);
    expect(ctl().nodeCanCancelSend, isFalse);
  });

  test('a held DM that gets delivered while the app is in the background notifies once', () async {
    final n = await connectAndSend();
    c.read(appForegroundProvider.notifier).set(foreground: false);
    final m = only();
    final receipt = pb.FromRadio(
      delivered: pb.Delivered(dest: bob, msgId: m.msgId, clientMsgId: m.clientMsgId),
    );
    n.node.last.send(receipt);
    await settle();
    expect(only().state, MsgState.delivered);
    expect(alerts.shown, ['radio Delivered to bob: see you at camp']);
    n.node.last.send(receipt); // receipts can repeat
    await settle();
    expect(alerts.shown, hasLength(1));
  });

  test('no notification while the app is in the foreground', () async {
    final n = await connectAndSend();
    final m = only();
    n.node.last.send(
      pb.FromRadio(
        delivered: pb.Delivered(dest: bob, msgId: m.msgId, clientMsgId: m.clientMsgId),
      ),
    );
    await settle();
    expect(alerts.shown, isEmpty, reason: 'foreground: the chat shows it');
  });

  group('a long message (several parts)', () {
    Future<HoldingNode> sendLong() async {
      final n = HoldingNode();
      c.read(nodeLinkProvider).connect(n.node);
      await settle();
      await ctl().sendMessage(bob, 'meet at the north trailhead after the storm passes, bring water', 30);
      await settle();
      return n;
    }

    List<ChatMessage> parts() => c.read(meshProvider).messages[bob]!;

    Future<void> pumpCancel(WidgetTester tester) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(cancelHeldDms(context, ctl(), parts())),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> tapCancel(WidgetTester tester) async {
      await pumpCancel(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('go'));
        await settle();
      });
      await tester.pump();
    }

    testWidgets('Cancel sending takes back every held part', (tester) async {
      late HoldingNode n;
      await tester.runAsync(() async => n = await sendLong());
      expect(parts().length, greaterThan(1));
      expect(parts().every((p) => p.held), isTrue);
      await tapCancel(tester);
      expect(n.cancels, hasLength(parts().length));
      expect(parts().every((p) => p.state == MsgState.failed), isTrue);
      expect(find.text('Cancelled. It was not sent.'), findsOneWidget);
    });

    testWidgets('some parts already gone: says how many were taken back', (tester) async {
      late HoldingNode n;
      await tester.runAsync(() async => n = (await sendLong())..cancelLimit = 1);
      final total = parts().length;
      await tapCancel(tester);
      expect(n.cancels, hasLength(total));
      expect(parts().where((p) => p.state == MsgState.failed), hasLength(1));
      expect(find.text('Cancelled 1 of $total parts. The rest were already passed on or delivered.'), findsOneWidget);
    });

    testWidgets('all gone: too late', (tester) async {
      await tester.runAsync(() async => (await sendLong()).gone = true);
      await tapCancel(tester);
      expect(parts().every((p) => p.state == MsgState.sent), isTrue);
      expect(find.text('Too late: it was already passed on or delivered.'), findsOneWidget);
    });
  });

  group('bubble menu', () {
    Future<void> pumpBubble(WidgetTester tester, {required bool held, VoidCallback? onCancel}) => tester.pumpWidget(
      MaterialApp(
        theme: buildGhostWaveTheme(),
        home: Scaffold(
          body: MessageBubble(
            outgoing: true,
            text: 'hi',
            at: DateTime(2026, 11, 25, 9),
            state: MsgState.sent,
            held: held,
            onCancel: onCancel,
            onDelete: () {},
          ),
        ),
      ),
    );

    testWidgets('a held DM offers Cancel sending', (tester) async {
      var cancelled = 0;
      await pumpBubble(tester, held: true, onCancel: () => cancelled++);
      await tester.longPress(find.text('hi'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel sending'), findsOneWidget);
      await tester.tap(find.text('Cancel sending'));
      await tester.pumpAndSettle();
      expect(cancelled, 1);
    });

    testWidgets('a DM that is not held does not', (tester) async {
      await pumpBubble(tester, held: false, onCancel: () {});
      await tester.longPress(find.text('hi'));
      await tester.pumpAndSettle();
      expect(find.text('Copy text'), findsOneWidget);
      expect(find.text('Cancel sending'), findsNothing);
    });
  });
}
