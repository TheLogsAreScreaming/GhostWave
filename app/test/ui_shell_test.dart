// The adaptive shell: navigation chosen by window width, one header for the link state.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/main.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link/fake_node.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'node_address': '127.0.0.1:1', 'asked_notifications': true});
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
}

void main() {
  test('window size classes follow Material 3', () {
    expect(WindowSizeClass.of(412), WindowSizeClass.compact);
    expect(WindowSizeClass.of(600), WindowSizeClass.medium);
    expect(WindowSizeClass.of(839), WindowSizeClass.medium);
    expect(WindowSizeClass.of(840), WindowSizeClass.expanded);
    expect(WindowSizeClass.of(1280), WindowSizeClass.large);
  });

  testWidgets('a phone gets the bottom bar', (tester) async {
    await _pumpAt(tester, const Size(412, 892));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a tablet gets a rail with labels', (tester) async {
    await _pumpAt(tester, const Size(800, 1000));
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.all);
  });

  testWidgets('a desktop window gets the labelled sidebar, and tabs still switch', (tester) async {
    await _pumpAt(tester, const Size(1280, 800));
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
    await tester.tap(find.text('Status').last);
    await tester.pump();
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 4);
  });

  testWidgets('the link state shows once, as a word, and the header is one button', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpAt(tester, const Size(412, 892));
    expect(find.text('Online'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Online\. ')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the header and bottom bar take 200% text on a small phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpAt(tester, const Size(360, 780));
    expect(tester.takeException(), isNull);
    expect(find.text('Online'), findsOneWidget);
  });
}
