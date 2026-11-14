// My radios: the list marks the active radio, rename and forget work from the
// menu, the active radio is named in the strip and on Status, and everything
// fits 200% text on a small phone.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/radios.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/ui/connection_strip.dart';
import 'package:ghostwave_app/src/ui/my_radios_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link/fake_node.dart';

const base = 'ble:AA:BB:CC:DD:EE:01|GhostWave-a11b';
const pack = 'ble:AA:BB:CC:DD:EE:02|GhostWave-c22d';

final _radios = [
  SavedRadio(
    address: base,
    nodeName: 'Base',
    nodeId: 0x11223344,
    firmware: 'ghostwave-heltec_v3 0.1.0-dev.11',
    lastConnected: DateTime.now().subtract(const Duration(minutes: 5)),
  ),
  SavedRadio(
    address: pack,
    nickname: 'Hiking pack',
    nodeName: 'Pack',
    nodeId: 0x55667788,
    firmware: 'ghostwave-t1000e 0.1.0-dev.11',
    lastConnected: DateTime.now().subtract(const Duration(days: 2)),
  ),
];

Future<SharedPreferences> _prefs({String? active = base}) async {
  SharedPreferences.setMockInitialValues({
    RadiosNotifier.key: jsonEncode([for (final r in _radios) r.toJson()]),
    'node_address': ?active,
  });
  return SharedPreferences.getInstance();
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required SharedPreferences prefs,
  Size size = const Size(412, 892),
  double text = 1,
  LinkState? link,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        if (link != null) linkStateProvider.overrideWith((ref) => Stream.value(link)),
      ],
      child: MaterialApp(theme: buildGhostWaveTheme(), home: home),
    ),
  );
  await tester.pump();
  await tester.pump();
}

LinkUp _up() => LinkUp(
  base,
  pb.NodeInfo(nodeId: 0x11223344, name: 'Base'.codeUnits, firmware: 'ghostwave-heltec_v3 0.1.0'),
  LinkSession(FakeConnection(FakeNode())),
);

void main() {
  testWidgets('lists every radio with board, ID and the active one marked', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const MyRadiosScreen(), prefs: await _prefs());
    expect(find.textContaining('Base · Active, Disconnected'), findsOneWidget);
    expect(find.text('Hiking pack'), findsOneWidget);
    expect(find.textContaining('Heltec V3 · ID 11223344'), findsOneWidget);
    expect(find.textContaining('T1000-E · ID 55667788'), findsOneWidget);
    expect(find.textContaining('Node name Pack'), findsOneWidget);
    expect(find.textContaining('Bluetooth address AA:BB:CC:DD:EE:02'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(tester.getSemantics(find.byType(ListTile).first), isSemantics(isSelected: true));
    handle.dispose();
  });

  testWidgets('rename from the menu, then forget with its history', (tester) async {
    final prefs = await _prefs();
    await _pump(tester, const MyRadiosScreen(), prefs: prefs);
    await tester.tap(find.byTooltip('Options for Base'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The radio still calls itself Base'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Base camp');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Base camp · Active'), findsOneWidget);

    await tester.tap(find.byTooltip('Options for Hiking pack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    expect(find.text('Forget Hiking pack?'), findsOneWidget);
    expect(find.text('Also delete its chats, contacts and channels on this phone'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
    await tester.pumpAndSettle();
    expect(find.text('Hiking pack'), findsNothing);
    final saved = jsonDecode(prefs.getString(RadiosNotifier.key)!) as List<Object?>;
    expect(saved, hasLength(1));
  });

  testWidgets('200% text on a small phone: list and dialogs fit', (tester) async {
    await _pump(tester, const MyRadiosScreen(), prefs: await _prefs(), size: const Size(360, 780), text: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byTooltip('Options for Hiking pack'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Hiking pack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Options for Base'), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Base'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('no radios yet says so', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, const MyRadiosScreen(), prefs: await SharedPreferences.getInstance());
    expect(find.text('No radios yet'), findsOneWidget);
    expect(find.text('Add a Bluetooth radio'), findsOneWidget);
  });

  test('the strip names the radio only when given one', () {
    expect(connectionSummary(_up()), isNull);
    expect(connectionSummary(_up(), radio: 'Base')!.$2, 'Using Base. Tap to switch radios.');
    expect(connectionSummary(const LinkConnecting('x', 1), radio: 'Base')!.$2, startsWith('Connecting to Base…'));
    expect(connectionSummary(const LinkConnecting('x', 1))!.$2, startsWith('Connecting to your radio…'));
    expect(connectionSummary(const LinkNeedsPin('x'), radio: 'Base')!.$2, startsWith('Base needs its PIN'));
  });

  testWidgets('with two radios the strip says which one is in use, at 200% text', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: ConnectionStrip()),
      prefs: await _prefs(),
      link: _up(),
      size: const Size(360, 780),
      text: 2,
    );
    expect(find.text('Using Base. Tap to switch radios.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(ConnectionStrip));
    await tester.pumpAndSettle();
    expect(find.text('My radios'), findsOneWidget);
  });

  testWidgets('with one radio the strip stays hidden while connected', (tester) async {
    SharedPreferences.setMockInitialValues({
      RadiosNotifier.key: jsonEncode([_radios.first.toJson()]),
      'node_address': base,
    });
    await _pump(
      tester,
      const Scaffold(body: ConnectionStrip()),
      prefs: await SharedPreferences.getInstance(),
      link: _up(),
    );
    expect(find.textContaining('Using'), findsNothing);
  });

  testWidgets('status names the active radio and leads to the list', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: ActiveRadioCard()),
      prefs: await _prefs(active: pack),
      size: const Size(360, 780),
      text: 2,
    );
    expect(find.text('Radio: Hiking pack'), findsOneWidget);
    expect(find.text('T1000-E · 55667788'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(ActiveRadioCard));
    await tester.pumpAndSettle();
    expect(find.text('My radios'), findsOneWidget);
  });
}
