import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/main.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link/fake_node.dart';

void main() {
  testWidgets('first launch opens Connect', (tester) async {
    SharedPreferences.setMockInitialValues({'walkthrough_done': true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: const GhostWaveApp()),
    );
    await tester.pump();
    expect(find.text('Connect to a node'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('a bad address is refused', (tester) async {
    SharedPreferences.setMockInitialValues({'walkthrough_done': true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: const GhostWaveApp()),
    );
    await tester.enterText(find.byType(TextField), 'not an address');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.textContaining('Use host:port'), findsOneWidget);
  });

  testWidgets('a saved address opens the tabs', (tester) async {
    SharedPreferences.setMockInitialValues({'node_address': '127.0.0.1:1'});
    final prefs = await SharedPreferences.getInstance();
    final node = FakeNode();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          transportFactoryProvider.overrideWithValue((_) => node),
        ],
        child: const GhostWaveApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Online'), findsWidgets);
    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Map'), findsWidgets);
    expect(find.text('SOS'), findsWidgets);
    expect(find.text('Me'), findsWidgets);
    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets('a node that wants a PIN: asks, then connects and remembers it', (tester) async {
    SharedPreferences.setMockInitialValues({'node_address': '127.0.0.1:1', 'asked_notifications': true});
    final prefs = await SharedPreferences.getInstance();
    final node = FakeNode()..pin = '424242';
    final pins = MemoryPinStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          transportFactoryProvider.overrideWithValue((_) => node),
          pinStoreProvider.overrideWithValue(pins),
        ],
        child: const GhostWaveApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enter the node\'s PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '424242');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await pins.read(node.label), '424242');
    expect(find.text('Online'), findsWidgets);
  });
}
