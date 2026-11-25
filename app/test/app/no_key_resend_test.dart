// A contact the phone knows, but whose key the node lost (it rebooted before
// it could save learned keys): the node refuses the DM with NO_KEY and asks for
// the key. The DM waits on the phone and goes out once the node learns it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/message_groups.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/ui/message_bubble.dart';
import 'package:ghostwave_app/src/ui/theme.dart';

import '../link/fake_node.dart';
import 'mesh_controller_test.dart' show bob, makeContainer, settle;

/// A node that knows bob as a contact but has no key for him until [learn].
class KeylessNode {
  KeylessNode() {
    node.onRequest.listen((e) {
      final (c, r) = e;
      final id = r.reqId;
      switch (r.whichRequest()) {
        case pb.ToRadio_Request.listContacts:
          c.send(
            pb.FromRadio(
              reqId: id,
              contact: pb.Contact(nodeId: bob, name: 'bob'.codeUnits),
            ),
          );
          c.send(pb.FromRadio(reqId: id, contactsEnd: pb.ContactsEnd(count: 1)));
        case pb.ToRadio_Request.sendText:
          c.send(
            hasKey
                ? pb.FromRadio(
                    reqId: id,
                    sendQueued: pb.SendQueued(
                      dest: r.sendText.dest,
                      msgId: 0x2000 + sends,
                      clientMsgId: r.sendText.clientMsgId,
                    ),
                  )
                : pb.FromRadio(
                    reqId: id,
                    error: pb.Error(code: refusal),
                  ),
          );
          sends++;
        case pb.ToRadio_Request.requestKey:
          c.send(pb.FromRadio(reqId: id, ok: pb.Ok()));
        default:
          break;
      }
    });
  }

  final FakeNode node = FakeNode();
  bool hasKey = false;
  pb.Error_Code refusal = pb.Error_Code.NO_KEY;
  int sends = 0;

  /// The node hears bob's IDENT.
  void learn({bool isNew = true}) {
    hasKey = true;
    node.last.send(
      pb.FromRadio(
        peerIdent: pb.PeerIdent(nodeId: bob, name: 'bob'.codeUnits, isNew: isNew),
      ),
    );
  }
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('gwapp-nokey.'));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('NO_KEY: the DM waits for the key instead of failing, then goes out by itself', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final n = KeylessNode();
    c.read(nodeLinkProvider).connect(n.node);
    await settle();
    expect(c.read(meshProvider).contacts.containsKey(bob), isTrue);

    await c.read(meshProvider.notifier).sendText(bob, 'hello');
    await settle();
    var m = c.read(meshProvider).messages[bob]!.single;
    expect(m.state, MsgState.pending);
    expect(m.awaitingKey, isTrue);
    expect(m.error, isNull);
    expect(n.sends, 1);

    n.learn();
    await settle();
    m = c.read(meshProvider).messages[bob]!.single;
    expect(n.sends, 2, reason: 'sent again once the node learned the key');
    expect(m.state, MsgState.sent);
    expect(m.awaitingKey, isFalse);
  });

  test('the node learning a key it had lost (not a new contact) also sends', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final n = KeylessNode();
    c.read(nodeLinkProvider).connect(n.node);
    await settle();
    await c.read(meshProvider.notifier).sendText(bob, 'hello');
    await settle();
    n.learn(isNew: false);
    await settle();
    expect(c.read(meshProvider).messages[bob]!.single.state, MsgState.sent);
  });

  test('other refusals still fail, with their reason', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final n = KeylessNode()..refusal = pb.Error_Code.TOO_LONG;
    c.read(nodeLinkProvider).connect(n.node);
    await settle();
    await c.read(meshProvider.notifier).sendText(bob, 'hello');
    await settle();
    final m = c.read(meshProvider).messages[bob]!.single;
    expect(m.state, MsgState.failed);
    expect(m.awaitingKey, isFalse);
    expect(m.error, 'Text too long');
    n.learn();
    await settle();
    expect(n.sends, 1, reason: 'a failed message is only sent again by Retry');
  });

  test('the waiting state survives a restart of the app', () {
    final m = ChatMessage(
      peer: bob,
      outgoing: true,
      text: 'hi',
      at: DateTime(2026, 11, 25),
      state: MsgState.pending,
      awaitingKey: true,
    );
    expect(ChatMessage.fromJson(m.toJson()).awaitingKey, isTrue);
    expect(m.copyWith(state: MsgState.sent).toJson().containsKey('awaitKey'), isTrue);
    expect(ChatMessage.fromJson(m.copyWith(awaitingKey: false).toJson()).awaitingKey, isFalse);
  });

  test('a long message waits for the key if any part does', () {
    ChatMessage part(int i, {bool waiting = false}) => ChatMessage(
      peer: bob,
      outgoing: true,
      text: '($i/2#a7) part $i',
      at: DateTime(2026, 11, 25),
      state: waiting ? MsgState.pending : MsgState.sent,
      clientMsgId: i,
      awaitingKey: waiting,
    );
    expect(LongMessageItem(total: 2, parts: {1: part(1), 2: part(2, waiting: true)}).awaitingKey, isTrue);
    expect(LongMessageItem(total: 2, parts: {1: part(1), 2: part(2)}).awaitingKey, isFalse);
  });

  testWidgets('the bubble says it is waiting for their key', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildGhostWaveTheme(),
        home: Scaffold(
          body: MessageBubble(
            outgoing: true,
            text: 'hi',
            at: DateTime(2026, 11, 25, 9),
            state: MsgState.pending,
            awaitingKey: true,
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.text('waiting for their key'), findsOneWidget);
    expect(find.byIcon(Icons.key), findsOneWidget);
  });
}
