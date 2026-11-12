// Trip screen: check-in buttons wait for trip contacts, and the screen fits
// 200% text on a small phone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:ghostwave_app/src/ui/trip_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget home, {double text = 1, Size size = const Size(412, 1600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(theme: buildGhostWaveTheme(), home: home),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('without trip contacts the check-in buttons and Start are off, and say why', (tester) async {
    await _pump(tester, const TripScreen());
    expect(find.text('Pick trip contacts below first.'), findsOneWidget);
    ButtonStyleButton button(String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first,
    );
    expect(button("I'm OK").onPressed, isNull);
    final start = button('Start trip');
    expect(start.onPressed, isNull);
    expect(find.text('No contacts yet. Add people in Chats first.'), findsOneWidget);
  });

  testWidgets('200% text on a small phone: screen and SOS-tab card fit', (tester) async {
    await _pump(tester, const TripScreen(), text: 2, size: const Size(360, 780));
    expect(tester.takeException(), isNull);
    await _pump(tester, const Scaffold(body: TripCard()), text: 2, size: const Size(360, 780));
    expect(find.text('Trip & check-ins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
