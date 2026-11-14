// Replies, reactions, and Reply / Mark read from a message notification.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/notification_actions.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/message_refs.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show bob, settle;
import 'messaging_test.dart' show ChannelNode;
import 'phone_qol_test.dart' show RecordingAlerts;

const int me = 0x11223344; // FakeNode's default ID

Uint8List psk() => Uint8List.fromList(List<int>.generate(32, (i) => i));

void main() {
  late Directory dir;
  late ProviderContainer c;
  late RecordingAlerts alerts;
  late StreamController<NotificationActionEvent> taps;
  late SharedPreferences prefs;
  var locked = false;

  Future<void> make({Map<String, Object> saved = const {}}) async {
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    alerts = RecordingAlerts();
    taps = StreamController<NotificationActionEvent>.broadcast();
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        meshAlertsProvider.overrideWithValue(alerts),
        notificationActionSourceProvider.overrideWithValue(taps.stream),
        appLockedProvider.overrideWith((ref) => locked),
      ],
    );
    c.listen(meshProvider, (_, _) {});
    c.listen(notificationActionsProvider, (_, _) {});
  }

  setUp(() async {
    locked = false;
    dir = await Directory.systemTemp.createTemp('gwapp-reply.');
    await make();
  });
  tearDown(() async {
    c.dispose();
    await taps.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  MeshController ctl() => c.read(meshProvider.notifier);
  MeshState mesh() => c.read(meshProvider);

  Future<ChannelNode> connect() async {
    final n = ChannelNode()..channels['crew'] = psk();
    c.read(nodeLinkProvider).connect(n.node);
    await settle();
    return n;
  }

  void incoming(ChannelNode n, int msgId, String text) => n.node.last.send(
    pb.FromRadio(
      text: pb.TextMessage(src: bob, msgId: msgId, text: utf8.encode(text)),
    ),
  );

  List<String> sentTexts(ChannelNode n) => [
    for (final r in n.requests(pb.ToRadio_Request.sendText)) utf8.decode(r.sendText.text),
  ];

  group('DM replies and reactions', () {
    test('a reply carries the original reference; a reaction is quiet', () async {
      final n = await connect();
      c.read(appForegroundProvider.notifier).set(foreground: false);
      incoming(n, 77, 'camp at 5?');
      await settle();
      expect(mesh().unread[bob], 1);
      expect(alerts.shown, hasLength(1));

      final ref = messageRef(bob, 77)!;
      await ctl().sendReply(bob, ref, 'yes, see you', 73);
      await ctl().react(bob, ref, '👍');
      await settle();
      expect(sentTexts(n), ['↩$ref yes, see you', '+👍↩$ref']);

      // bob reacts to our reply: folded, no unread, no notification
      final ours = mesh().messages[bob]!.firstWhere((m) => m.outgoing);
      ctl().markRead(bob);
      incoming(n, 78, encodeReaction(messageRef(me, ours.msgId)!, '❤️'));
      await settle();
      expect(mesh().unread[bob], 0);
      expect(alerts.shown, hasLength(1), reason: 'reactions never notify');

      // a reply from bob notifies with friendly text and a thread to reply to
      incoming(n, 79, encodeReply(messageRef(me, ours.msgId)!, 'great'));
      await settle();
      expect(alerts.shown.last, 'text ${mesh().nameOf(bob)}: ↩ great');
      final thread = alerts.threads.last!;
      expect(thread.node, me);
      expect(thread.target, const DmThread(bob));
      expect(thread.inlineReply, isTrue);
      expect(NotificationThread.parse(thread.payload)!.target, const DmThread(bob));
    });

    test('a reaction storm makes no notifications and no unread', () async {
      final n = await connect();
      c.read(appForegroundProvider.notifier).set(foreground: false);
      incoming(n, 1, 'x');
      await settle();
      final ref = messageRef(bob, 1)!;
      for (var i = 0; i < 200; i++) {
        incoming(n, 1000 + i, encodeReaction(ref, kReactions[i % kReactions.length]));
      }
      await settle();
      expect(alerts.shown, hasLength(1));
      expect(mesh().unread[bob], 1);
    });

    test('changing a reaction before it leaves the phone replaces it', () async {
      // no link: everything stays pending
      final n = await connect();
      c.read(nodeLinkProvider).disconnect();
      await settle();
      final ref = messageRef(bob, 5)!;
      await ctl().react(bob, ref, '👍');
      await ctl().react(bob, ref, '😂');
      await ctl().react(bob, ref, null);
      final pending = mesh().messages[bob]!.where((m) => m.outgoing).toList();
      expect(pending.map((m) => m.text), ['-↩$ref'], reason: 'only the latest choice is kept');
      expect(n.requests(pb.ToRadio_Request.sendText), isEmpty);
    });

    test('a locked app offers Open instead of an inline reply', () async {
      locked = true;
      c.dispose();
      await make();
      final n = await connect();
      c.read(appForegroundProvider.notifier).set(foreground: false);
      incoming(n, 3, 'hello');
      await settle();
      expect(alerts.threads.single!.inlineReply, isFalse);
    });
  });

  group('channel replies and reactions', () {
    test('reply and reaction go out as channel text; incoming reactions are quiet', () async {
      final n = await connect();
      c.read(appForegroundProvider.notifier).set(foreground: false);
      n.node.last.send(
        pb.FromRadio(
          channelMessage: pb.ChannelMessage(channel: 'crew', src: bob, msgId: 9, text: utf8.encode('rope?')),
        ),
      );
      await settle();
      expect(alerts.threads.single!.target, const ChannelThread('crew'));
      final ref = messageRef(bob, 9)!;
      await ctl().sendChannelReply('crew', ref, 'I have one', 73);
      await ctl().reactInChannel('crew', ref, '✅');
      await settle();
      expect(
        [for (final r in n.requests(pb.ToRadio_Request.sendChannelText)) utf8.decode(r.sendChannelText.text)],
        ['↩$ref I have one', '+✅↩$ref'],
      );
      ctl().markChannelRead('crew');
      n.node.last.send(
        pb.FromRadio(
          channelMessage: pb.ChannelMessage(
            channel: 'crew',
            src: 0x0C0C0C0C,
            msgId: 10,
            text: utf8.encode(encodeReaction(ref, '👍')),
          ),
        ),
      );
      await settle();
      expect(mesh().channelUnread['crew'], 0);
      expect(alerts.shown, hasLength(1));
    });

    test('a channel reply that does not fit is refused, not cut', () async {
      await connect();
      expect(() => ctl().sendChannelReply('crew', 'abcd', 'x' * 70, 73), throwsArgumentError);
      expect(mesh().channelMessages['crew'] ?? const [], isEmpty);
    });
  });

  test('Android: the action receiver is declared and private', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      RegExp(r'flutterlocalnotifications\.ActionBroadcastReceiver"\s+android:exported="false"').hasMatch(manifest),
      isTrue,
    );
  });

  group('notification actions', () {
    NotificationActionEvent tap(String action, ChatTarget t, [String? input, int node = me]) => NotificationActionEvent(
      action: action,
      thread: NotificationThread(node: node, target: t),
      input: input,
    );

    test('Reply sends the typed text and clears unread; Mark read only clears', () async {
      final n = await connect();
      incoming(n, 1, 'there?');
      incoming(n, 2, 'hello?');
      await settle();
      expect(mesh().unread[bob], 2);
      taps.add(tap(kMarkReadAction, const DmThread(bob)));
      await settle();
      expect(mesh().unread[bob], 0);
      expect(sentTexts(n), isEmpty);

      incoming(n, 3, 'again');
      await settle();
      taps.add(tap(kReplyAction, const DmThread(bob), '  on my way  '));
      await settle();
      expect(sentTexts(n), ['on my way']);
      expect(mesh().unread[bob], 0);
      expect(mesh().messages[bob]!.last.state, MsgState.sent);
    });

    test('Reply to a channel', () async {
      final n = await connect();
      taps.add(tap(kReplyAction, const ChannelThread('crew'), 'coming'));
      await settle();
      expect(utf8.decode(n.requests(pb.ToRadio_Request.sendChannelText).single.sendChannelText.text), 'coming');
    });

    test('a long DM reply is split; one too long for 8 parts becomes a draft', () async {
      final n = await connect();
      incoming(n, 1, 'hi'); // bob is known now
      await settle();
      taps.add(tap(kReplyAction, const DmThread(bob), 'word ' * 30));
      await settle();
      expect(sentTexts(n).length, greaterThan(1));
      final huge = 'x' * 2000;
      taps.add(tap(kReplyAction, const DmThread(bob), huge));
      await settle();
      expect(mesh().drafts[bob], huge);
      expect(alerts.shown.last, contains('too long'));
    });

    test('a channel reply over the limit is not sent and the user is told', () async {
      final n = await connect();
      taps.add(tap(kReplyAction, const ChannelThread('crew'), 'y' * 200));
      await settle();
      expect(n.requests(pb.ToRadio_Request.sendChannelText), isEmpty);
      expect(alerts.shown.last, contains('Reply not sent'));
    });

    test('while the app is locked a reply is kept as a draft, not sent', () async {
      locked = true;
      c.dispose();
      await make();
      final n = await connect();
      taps.add(tap(kReplyAction, const DmThread(bob), 'secret'));
      await settle();
      expect(sentTexts(n), isEmpty);
      expect(mesh().drafts[bob], 'secret');
      expect(alerts.shown.last, contains('locked'));
    });

    test('empty input, junk payloads and other actions do nothing', () async {
      final n = await connect();
      taps.add(tap(kReplyAction, const DmThread(bob), '   '));
      taps.add(tap(kReplyAction, const DmThread(bob)));
      await settle();
      expect(sentTexts(n), isEmpty);
      for (final m in <Object?>[
        null,
        42,
        {'a': 'reply', 'p': 'sos:5', 'i': 'x'},
        {'a': 'delete', 'p': 'msg:11223344:dm:0b0b0b0b', 'i': 'x'},
        {'a': 'reply', 'p': 'msg:11223344:dm:zzzz', 'i': 'x'},
        {'a': 'reply', 'p': 'msg:11223344:ch:%E0%A4', 'i': 'x'},
        {'a': 'reply', 'p': 'msg:11223344:ch:', 'i': 'x'},
        {'a': 'reply', 'p': 'msg:1122:dm:0b0b0b0b', 'i': 'x'},
        {'a': 'reply', 'p': 'msg:11223344:ch:${'a' * 200}', 'i': 'x'},
      ]) {
        expect(NotificationActionEvent.fromMap(m), isNull, reason: '$m');
      }
    });

    test('payloads round-trip, channel names with odd characters included', () {
      for (final t in [const DmThread(0xFFFFFFFF), const DmThread(1), const ChannelThread('trail: crew/2 #ü')]) {
        final p = NotificationThread(node: 0xDEADBEEF, target: t).payload;
        final back = NotificationThread.parse(p)!;
        expect(back.node, 0xDEADBEEF);
        expect(back.target, t);
        final e = NotificationActionEvent.fromMap(
          NotificationActionEvent(action: kReplyAction, thread: back, input: 'hi').toMap(),
        )!;
        expect(e.thread.target, t);
        expect(e.input, 'hi');
      }
    });

    test('a reply saved while the app was closed is sent when its node connects', () async {
      // what the background isolate saves when the app is not running
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      await queueReply(p, tap(kReplyAction, const DmThread(bob), 'from the shade'));
      await queueReply(p, tap(kReplyAction, const DmThread(bob), 'other node', 0x99999999));
      final saved = Map<String, Object>.of({kQueuedRepliesKey: p.getStringList(kQueuedRepliesKey)!});
      c.dispose();
      await make(saved: saved);
      await connect();
      await settle();
      // in the outbox: it goes out like any message once bob's key is known
      expect([for (final m in mesh().messages[bob]!) m.text], ['from the shade']);
      // the other node's reply waits for that node
      expect(prefs.getStringList(kQueuedRepliesKey), hasLength(1));
    });

    test('a tap for a node that is not connected is saved for it', () async {
      await connect();
      taps.add(tap(kReplyAction, const DmThread(bob), 'later', 0x55555555));
      taps.add(tap(kMarkReadAction, const DmThread(bob), null, 0x55555555));
      await settle();
      final left = prefs.getStringList(kQueuedRepliesKey)!;
      expect(left, hasLength(1));
      expect(NotificationActionEvent.fromMap(jsonDecode(left.single))!.thread.node, 0x55555555);
    });

    test('the saved queue keeps only the newest replies and drops junk', () async {
      for (var i = 0; i < kMaxQueuedReplies + 5; i++) {
        await queueReply(prefs, tap(kReplyAction, const DmThread(bob), 'r$i', 0x77777777));
      }
      await prefs.setStringList(kQueuedRepliesKey, ['{not json', '[]', ...prefs.getStringList(kQueuedRepliesKey)!]);
      final got = await takeQueuedReplies(prefs, 0x77777777);
      expect(got, hasLength(kMaxQueuedReplies));
      expect(got.first.input, 'r5');
      expect(prefs.getStringList(kQueuedRepliesKey), isEmpty);
    });
  });
}
