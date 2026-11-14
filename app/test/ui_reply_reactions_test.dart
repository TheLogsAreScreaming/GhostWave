// Replies and reactions in the chat screens: quotes, reaction chips, the
// long-press menu, swipe to reply, jumping to the original, and large text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/message_refs.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/ui/channel_screens.dart';
import 'package:ghostwave_app/src/ui/chat_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int me = 0x11223344, bob = 0x0B0B0B0B, cat = 0x0C0C0C0C;

/// The real controller, starting from [initial] instead of a node.
class SeededMesh extends MeshController {
  SeededMesh(this.initial);

  final MeshState initial;

  @override
  MeshState build() => initial;
}

final DateTime t0 = DateTime(2026, 11, 14, 9);

ChatMessage dm(bool out, int msgId, String text, [int minute = 0]) => ChatMessage(
  peer: bob,
  outgoing: out,
  text: text,
  at: t0.add(Duration(minutes: minute)),
  msgId: msgId,
  state: out ? MsgState.sent : MsgState.delivered,
  clientMsgId: out ? msgId : 0,
);

void main() {
  final orig = messageRef(bob, 77)!;

  MeshState seeded(List<ChatMessage> thread, {Map<String, List<ChannelMessage>> channels = const {}}) => MeshState(
    nodeId: me,
    contacts: {
      bob: const Contact(nodeId: bob, name: 'bob', pinned: true),
      cat: const Contact(nodeId: cat, name: 'cat', pinned: true),
    },
    messages: {bob: thread},
    channels: {for (final c in channels.keys) c: GroupChannel(name: c, pskHex: '00' * 32)},
    channelMessages: channels,
  );

  Future<ProviderContainer> pump(WidgetTester tester, MeshState state, Widget screen) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), meshProvider.overrideWith(() => SeededMesh(state))],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: buildGhostWaveTheme(), home: screen),
      ),
    );
    await tester.pump();
    await tester.pump();
    return c;
  }

  List<ChatMessage> basic() => [
    dm(false, 77, 'camp at the saddle at 5?'),
    dm(true, 500, encodeReaction(orig, '👍'), 1),
    dm(false, 78, encodeReaction(orig, '👍'), 2),
    dm(true, 501, encodeReply(orig, 'yes, see you there'), 3),
  ];

  testWidgets('quote above a reply, reaction counts under the original, raw codes hidden', (tester) async {
    await pump(tester, seeded(basic()), const ChatScreen(peer: bob));
    expect(find.text('yes, see you there'), findsOneWidget);
    // the quote: sender and snippet
    expect(find.text('camp at the saddle at 5?'), findsNWidgets(2));
    expect(find.bySemanticsLabel(RegExp('^Reply to bob: camp at the saddle')), findsOneWidget);
    // two people chose 👍: one chip, count 2, ours included
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.bySemanticsLabel('thumbs up, 2, including you'), findsOneWidget);
    expect(find.textContaining('↩'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press: pick a reaction; tap our chip to take it back', (tester) async {
    final c = await pump(tester, seeded(basic()), const ChatScreen(peer: bob));
    await tester.longPress(find.text('yes, see you there'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('React with laughing'));
    await tester.pumpAndSettle();
    final mine = c.read(meshProvider).messages[bob]!.last;
    expect(mine.text, encodeReaction(messageRef(me, 501)!, '😂'));
    expect(mine.state, MsgState.pending);
    expect(find.text('😂'), findsOneWidget, reason: 'our pending reaction shows at once');

    // our 👍 on the original: tapping the chip takes it back
    await tester.tap(find.bySemanticsLabel('thumbs up, 2, including you'));
    await tester.pumpAndSettle();
    expect(c.read(meshProvider).messages[bob]!.last.text, encodeReaction(orig, null));
    expect(find.bySemanticsLabel('thumbs up, 1'), findsOneWidget);
  });

  testWidgets('long-press Reply, then send: the reply carries the reference', (tester) async {
    final c = await pump(tester, seeded(basic()), const ChatScreen(peer: bob));
    // the bubble, not the quote of it (the list is reversed: newest first)
    await tester.longPress(find.text('camp at the saddle at 5?').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Replying to bob'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'bringing rope');
    await tester.pump();
    // the counter includes the reply's 8 bytes
    expect(find.text('${'bringing rope'.length + kReplyOverheadBytes} / 73 bytes'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(c.read(meshProvider).messages[bob]!.last.text, '↩$orig bringing rope');
    expect(find.text('Replying to bob'), findsNothing);
  });

  testWidgets('swipe a bubble to reply; cancel keeps the text', (tester) async {
    await pump(tester, seeded(basic()), const ChatScreen(peer: bob));
    await tester.drag(find.text('camp at the saddle at 5?').last, const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(find.text('Replying to bob'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'draft');
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pumpAndSettle();
    expect(find.text('Replying to bob'), findsNothing);
    expect(find.text('draft'), findsOneWidget);
  });

  testWidgets('a message not yet queued by the node cannot be replied or reacted to', (tester) async {
    await pump(tester, seeded([dm(true, 0, 'still on the phone')]), const ChatScreen(peer: bob));
    await tester.longPress(find.text('still on the phone'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsNothing);
    expect(find.bySemanticsLabel('React with thumbs up'), findsNothing);
    expect(find.text('Copy text'), findsOneWidget);
  });

  testWidgets('tapping a quote scrolls far up to the original and marks it', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final thread = [
      dm(false, 77, 'THE ORIGINAL'),
      for (var i = 0; i < 80; i++) dm(i.isEven, 1000 + i, 'filler $i', 1 + i),
      dm(true, 2000, encodeReply(orig, 'answering the first one'), 100),
    ];
    await pump(tester, seeded(thread), const ChatScreen(peer: bob));
    expect(find.text('THE ORIGINAL'), findsOneWidget, reason: 'only the quote is built');
    await tester.tap(find.bySemanticsLabel(RegExp('^Reply to bob: THE ORIGINAL')));
    await tester.pumpAndSettle();
    // the reply (and its quote) scrolled away; the original bubble is on screen
    expect(find.text('answering the first one'), findsNothing);
    expect(find.text('THE ORIGINAL'), findsOneWidget);
    final box = tester.getRect(find.text('THE ORIGINAL'));
    expect(box.top, greaterThanOrEqualTo(0));
    expect(box.bottom, lessThanOrEqualTo(800));
    await tester.pump(const Duration(seconds: 2)); // the mark fades
  });

  testWidgets('a reply whose original is not on this phone says so', (tester) async {
    await pump(tester, seeded([dm(false, 9, encodeReply('zzzz', 'about that'))]), const ChatScreen(peer: bob));
    expect(find.text('about that'), findsOneWidget);
    expect(find.text('Original message not on this phone'), findsOneWidget);
  });

  testWidgets('200% text on a small phone with quotes, reactions and the reply bar', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final thread = [
      ...basic(),
      dm(false, 79, encodeReaction(orig, '❤️'), 4),
      dm(false, 80, encodeReply(messageRef(me, 501)!, 'a long answer ' * 8), 5),
    ];
    await pump(tester, seeded(thread), const ChatScreen(peer: bob));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('yes, see you there'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('yes, see you there'), const Offset(90, 0));
    await tester.pumpAndSettle();
    // swiping the newest bubble (bob's long reply, quoting ours) answers bob
    expect(find.text('Replying to bob'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel: sender names in quotes, reactions from several people', (tester) async {
    final o = messageRef(cat, 9)!;
    ChannelMessage ch(int src, int id, String text, [int minute = 0]) => ChannelMessage(
      channel: 'crew',
      outgoing: src == me,
      src: src == me ? 0 : src,
      text: text,
      at: t0.add(Duration(minutes: minute)),
      msgId: id,
      state: src == me ? MsgState.sent : MsgState.delivered,
    );
    final c = await pump(
      tester,
      seeded(
        const [],
        channels: {
          'crew': [
            ch(cat, 9, 'who has a rope?'),
            ch(bob, 10, encodeReaction(o, '❗'), 1),
            ch(me, 11, encodeReaction(o, '❗'), 2),
            ch(bob, 12, encodeReply(o, 'I do'), 3),
          ],
        },
      ),
      const ChannelChatScreen(channel: 'crew'),
    );
    expect(find.bySemanticsLabel(RegExp('^Reply to cat: who has a rope')), findsOneWidget);
    expect(find.bySemanticsLabel('exclamation mark, 2, including you'), findsOneWidget);
    await tester.longPress(find.text('I do'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Replying to bob'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'great');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(c.read(meshProvider).channelMessages['crew']!.last.text, '↩${messageRef(bob, 12)} great');
    expect(tester.takeException(), isNull);
  });
}
