// Chat polish: the connection strip says what's happening (and hides while
// connected), delivery badges read as words, and a chat fits 200% text on a
// small phone with the keyboard open.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/ui/channel_screens.dart';
import 'package:ghostwave_app/src/ui/chat_screen.dart';
import 'package:ghostwave_app/src/ui/connection_strip.dart';
import 'package:ghostwave_app/src/ui/message_bubble.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('strip wording per link state; nothing while connected', () {
    expect(connectionSummary(null), isNull);
    expect(connectionSummary(const LinkIdle())!.$2, startsWith('Not connected.'));
    expect(connectionSummary(const LinkConnecting('n', 1))!.$2, startsWith('Connecting'));
    expect(connectionSummary(const LinkWaiting('n', 'x', Duration(seconds: 5)))!.$2, contains('Retrying in 5 s'));
    expect(connectionSummary(const LinkNeedsPin('n'))!.$2, contains('PIN'));
    expect(connectionSummary(const LinkFailed('n', 'x'))!.$2, contains('Tap for what to do'));
    for (final s in [const LinkIdle(), const LinkWaiting('n', 'x', Duration.zero), const LinkFailed('n', 'x')]) {
      expect(connectionSummary(s)!.$2, anyOf(contains('wait on this phone'), contains('Tap')));
    }
  });

  Future<void> bubble(WidgetTester tester, MessageBubble b) => tester.pumpWidget(
    MaterialApp(
      theme: buildGhostWaveTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 380, child: b)),
      ),
    ),
  );

  testWidgets('delivery badges are words; partial delivery of a long message is counted', (tester) async {
    final at = DateTime(2026, 11, 12, 9, 30);
    await bubble(tester, MessageBubble(outgoing: true, text: 'hi', at: at, state: MsgState.delivered, onDelete: () {}));
    expect(find.text('delivered'), findsOneWidget);
    await bubble(tester, MessageBubble(outgoing: true, text: 'hi', at: at, state: MsgState.pending, onDelete: () {}));
    expect(find.text('saved on phone'), findsOneWidget);
    await bubble(
      tester,
      MessageBubble(
        outgoing: true,
        text: 'long',
        at: at,
        state: MsgState.sent,
        progress: '2 of 3 delivered',
        onDelete: () {},
      ),
    );
    expect(find.text('2 of 3 delivered'), findsOneWidget);
  });

  testWidgets('a chat at 200% text on a small phone, keyboard open, offline', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(theme: buildGhostWaveTheme(), home: const ChatScreen(peer: 0x1A2B3C4D)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Messages wait on this phone'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a channel chat at 200% text on a small phone, keyboard open, offline', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: buildGhostWaveTheme(),
          home: const ChannelChatScreen(channel: 'crew'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
