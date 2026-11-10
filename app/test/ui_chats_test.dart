// Chats: one pane on phones, list and conversation side by side on wide windows.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/main.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/ui/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/mesh_controller_test.dart' show answeringNode;
import 'support/history_keys.dart';

const int ridge = 0x1A2B3C4D;

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'node_address': '127.0.0.1:1', 'asked_notifications': true});
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('gw_ui_chats');
  addTearDown(() => dir.deleteSync(recursive: true));
  final node = answeringNode(
    contacts: [pb.Contact(nodeId: ridge, name: 'Ridge'.codeUnits, pinned: true)],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        transportFactoryProvider.overrideWithValue((_) => node),
      ],
      child: const GhostWaveApp(),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // the map's tile cache asks path_provider for a directory
    final tmp = Directory.systemTemp.createTempSync('gw_ui_chats_cache').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
  });

  testWidgets('a phone opens a chat as its own page', (tester) async {
    await _pumpAt(tester, const Size(412, 892));
    expect(find.text('Pick a conversation'), findsNothing);
    await tester.tap(find.text('Ridge'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('People'), findsNothing, reason: 'the list is behind the chat page');
  });

  testWidgets('a wide window shows the list and the chat side by side', (tester) async {
    await _pumpAt(tester, const Size(1280, 800));
    expect(find.text('Pick a conversation'), findsOneWidget);
    await tester.tap(find.text('Ridge'));
    await tester.pump();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('People'), findsOneWidget, reason: 'the list stays visible');
    expect(find.byType(BackButton), findsNothing, reason: 'nothing to go back to in a pane');
    expect(
      tester.widget<ListTile>(find.ancestor(of: find.text('Ridge').first, matching: find.byType(ListTile))).selected,
      isTrue,
    );
  });
}
