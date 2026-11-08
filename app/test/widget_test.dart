import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/main.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link/fake_node.dart';

void main() {
  testWidgets('first launch opens Connect', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: const GhostWaveApp()),
    );
    await tester.pump();
    expect(find.text('Connect to a node'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('a bad address is refused', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
}
