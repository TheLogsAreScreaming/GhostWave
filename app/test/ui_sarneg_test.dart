// SARNEG: setting the code word, encoding from the chat composer, and
// tap-to-decode under a received message.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/sarneg_controller.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/sarneg.dart';
import 'package:ghostwave_app/src/ui/chat_screen.dart';
import 'package:ghostwave_app/src/ui/sarneg_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int me = 0x11223344, bob = 0x0B0B0B0B;

class SeededMesh extends MeshController {
  SeededMesh(this.initial);

  final MeshState initial;

  @override
  MeshState build() => initial;
}

final DateTime t0 = DateTime(2026, 11, 21, 9);

void main() {
  Future<(ProviderContainer, MemorySarnegStore)> pump(
    WidgetTester tester,
    Widget screen, {
    SarnegKeySet? keys,
    List<ChatMessage> thread = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = MemorySarnegStore(keys == null ? null : jsonEncode(keys.toJson()));
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sarnegStoreProvider.overrideWithValue(store),
        sarnegClockProvider.overrideWithValue(() => t0),
        meshProvider.overrideWith(
          () => SeededMesh(
            MeshState(
              nodeId: me,
              contacts: {bob: const Contact(nodeId: bob, name: 'bob', pinned: true)},
              messages: {bob: thread},
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: buildGhostWaveTheme(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return (c, store);
  }

  testWidgets('a bad word is refused, a good one is saved', (tester) async {
    final (c, store) = await pump(tester, const SarnegScreen());
    expect(find.text('No code word on this phone yet.'), findsOneWidget);
    await tester.tap(find.text('Type a word'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'blackhorsb');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('No letter may appear twice'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'black horse');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.read(sarnegProvider).value?.word, 'BLACKHORSE');
    expect(store.value, contains('BLACKHORSE'));
    // hidden until asked for
    expect(find.text('BLACKHORSE'), findsNothing);
    await tester.tap(find.byTooltip('Show the word'));
    await tester.pump();
    expect(find.text('BLACKHORSE'), findsOneWidget);
  });

  testWidgets('the refusal is shown in full on a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, const SarnegScreen());
    final button = find.text('Type a word', skipOffstage: false);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'helloworld');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final text = find.text('No letter may appear twice');
    expect(text, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse);
  });

  testWidgets('the composer button puts the coded numbers in the message', (tester) async {
    await pump(
      tester,
      const ChatScreen(peer: bob),
      keys: SarnegKeySet(word: 'BLACKHORSE'),
    );
    await tester.enterText(find.byType(TextField).last, '17S 4823');
    await tester.tap(find.byTooltip('Send numbers in SARNEG'));
    await tester.pumpAndSettle();
    expect(find.text('[SARNEG] LRs KSAC'), findsOneWidget); // the preview
    await tester.tap(find.text('Put in message'));
    await tester.pumpAndSettle();
    final composer = tester.widget<TextField>(find.byType(TextField).last);
    expect(composer.controller!.text, '[SARNEG] LRs KSAC');
  });

  testWidgets('a received SARNEG message decodes with the word for its day', (tester) async {
    final keys = SarnegKeySet(word: 'BLACKHORSE', daily: {'2026-11-21': 'CUMBERLAND'});
    final msg = ChatMessage(
      peer: bob,
      outgoing: false,
      text: '[SARNEG] ${SarnegCodec('CUMBERLAND').encode('906.875')}',
      at: t0,
      msgId: 9,
      state: MsgState.delivered,
      clientMsgId: 0,
    );
    await pump(
      tester,
      const ChatScreen(peer: bob),
      keys: keys,
      thread: [msg],
    );
    expect(find.text('SARNEG · tap to decode'), findsOneWidget);
    await tester.tap(find.text('SARNEG · tap to decode'));
    await tester.pump();
    expect(find.text('Decoded: 906.875'), findsOneWidget);
  });

  testWidgets('without a word the sheet points to the setup', (tester) async {
    await pump(tester, const ChatScreen(peer: bob));
    await tester.tap(find.byTooltip('Send numbers in SARNEG'));
    await tester.pumpAndSettle();
    expect(find.text('Set the code word'), findsOneWidget);
  });
}
