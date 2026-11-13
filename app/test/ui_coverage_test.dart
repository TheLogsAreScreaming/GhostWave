// Coverage walk screen: fits 200% text on a small phone, and Start waits for
// a node and a connection.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/ui/coverage_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('200% text on a small phone; Start is off with no node chosen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(theme: buildGhostWaveTheme(), home: const CoverageScreen()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final start = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text('Start walk'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first,
    );
    expect(start.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
