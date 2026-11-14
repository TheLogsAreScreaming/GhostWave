// Node settings screen: fits 200% text on a small phone, shows the board's
// real power range, and keeps button SOS off where the board forbids it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/ui/node_settings_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

pb.Settings boardSettings({bool sosAllowed = true}) => pb.Settings(
  name: 'ridge'.codeUnits,
  region: 'us915',
  freqKhz: 914875,
  minFreqKhz: 902063,
  maxFreqKhz: 927938,
  outputDbm: 20,
  minOutputDbm: -1,
  maxOutputDbm: 29,
  channelKeyOn: true,
  requireEncryption: false,
  responder: true,
  blePin: '654321',
  screenOffS: 600,
  leds: true,
  buttonSos: true,
  screenFitted: true,
  ledsFitted: true,
  buttonFitted: true,
  buttonSosAllowed: sosAllowed,
  restartNeeded: true,
);

Future<void> show(WidgetTester tester, pb.Settings s) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: buildGhostWaveTheme(),
        home: NodeSettingsScreen(initial: s),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('words for power, timeouts and keys', () {
    expect(powerLabel(30), '30 dBm (1.0 W)');
    expect(powerLabel(20), '20 dBm (100 mW)');
    expect(powerLabel(0), '0 dBm (1.0 mW)');
    expect(screenTimeoutLabel(0), 'Never (dims only)');
    expect(screenTimeoutLabel(300), '5 minutes');
    expect(screenTimeoutLabel(3600), '1 hour');
    expect(parseKeyHex('ab' * 32)!.length, 32);
    expect(parseKeyHex('ab' * 31), isNull);
    expect(parseKeyHex('zz' * 32), isNull);
    expect(keyHex([0, 15, 255]), '000fff');
  });

  testWidgets('200% text on a small phone, every section, the board power range', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester, boardSettings());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('restarts'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(Slider), 300);
    expect(find.textContaining('20 dBm (100 mW)'), findsWidgets);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect([slider.min, slider.max], [-1, 29]);
    await tester.scrollUntilVisible(find.text('Hold the button for SOS'), 300);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('button SOS stays off and locked where the board forbids it', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await show(tester, boardSettings(sosAllowed: false));
    final sw = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Hold the button for SOS'));
    expect(sw.value, isFalse);
    expect(sw.onChanged, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
