// Waypoint screens: drop one from the editor, list them with words a screen
// reader can use, hide someone else's from the sheet, navigate with the
// phone's position, and fit 200% text in both light and dark themes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/location_share.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/waypoints.dart';
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:ghostwave_app/src/ui/waypoint_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/journal_seed.dart';

final DateTime now = DateTime(2026, 11, 14, 9);
const int ann = 0xA0000001;

class _FakePositions implements PositionSource {
  _FakePositions(this.fix);

  final LatLon? fix;

  @override
  Future<LocationAccess> ensureAccess() async => fix == null ? LocationAccess.deniedForever : LocationAccess.granted;

  @override
  Stream<LatLon> watch({required int distanceFilterM}) => fix == null ? const Stream.empty() : Stream.value(fix!);

  @override
  Future<void> openSettings(LocationAccess why) async {}
}

WaypointBook seededBook() => const WaypointBook()
    .put(
      Waypoint(
        id: '0001',
        kind: WaypointKind.camp,
        name: 'Base camp',
        pos: const LatLon(45.01, -110),
        at: now.subtract(const Duration(hours: 2)),
        channel: 'crew',
      ),
    )
    .receive(
      ann,
      const WaypointPut(id: '0a0a', kind: WaypointKind.water, name: 'Spring', pos: LatLon(45, -110.01), note: 'cold'),
      now.subtract(const Duration(minutes: 5)),
      peer: ann,
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget home, {
  double text = 1,
  Size size = const Size(412, 892),
  ThemeData? theme,
  WaypointBook? book,
  LatLon? phone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({'units': 'metric'});
  final prefs = await SharedPreferences.getInstance();
  final seed = journalSeedState(now).copyWith(ownPos: const LatLon(45, -110), waypoints: book ?? seededBook());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
        meshProvider.overrideWith(() => SeededMesh(seed)),
        positionSourceProvider.overrideWithValue(_FakePositions(phone)),
      ],
      child: MaterialApp(theme: theme ?? buildGhostWaveTheme(), home: home),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// A page with a button that opens the new-waypoint editor at [pos].
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => unawaited(openNewWaypoint(context, pos: const LatLon(46.5, -111.25))),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  testWidgets('editor: pick a kind, name it, save on this phone', (tester) async {
    final c = await _pump(tester, const _Host(), book: const WaypointBook());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('New waypoint'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Latitude'), findsOneWidget);
    expect(find.text('46.50000'), findsOneWidget);
    await tester.tap(find.text('Hazard'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Washout');
    await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'), 'Road gone\nwalk around');
    await tester.pump();
    await tester.ensureVisible(find.text('Save waypoint'));
    await tester.tap(find.text('Save waypoint'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final w = c.read(meshProvider).waypoints.all.single;
    expect(
      (w.kind, w.name, w.note, w.mine, w.shared),
      (WaypointKind.hazard, 'Washout', 'Road gone walk around', true, false),
    );
    expect(w.pos.lat, closeTo(46.5, 1e-9));
    expect(find.text('Waypoint saved on this phone'), findsOneWidget);
  });

  testWidgets('editor: a bad latitude turns Save off and says why', (tester) async {
    await _pump(tester, const _Host(), book: const WaypointBook());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Latitude'), '123');
    await tester.pump();
    expect(find.textContaining('Enter a latitude (-90 to 90)'), findsOneWidget);
    final save = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text('Save waypoint'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('list: names, kinds, who and distance read out; hide someone else\'s', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await _pump(tester, const WaypointsScreen());
    expect(find.text('Spring'), findsOneWidget);
    expect(find.text('Base camp'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Waypoint, Water: Spring\. from .+\. cold\. 790 m W')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Waypoint, Camp: Base camp\. yours')), findsOneWidget);

    await tester.tap(find.text('Spring'));
    await tester.pumpAndSettle();
    expect(find.text('Hide from my map'), findsOneWidget);
    expect(find.text('Edit'), findsNothing, reason: 'not ours');
    await tester.tap(find.text('Hide from my map'));
    await tester.pumpAndSettle();
    expect(c.read(meshProvider).waypoints.byKey[waypointKey(ann, '0a0a')]!.hidden, isTrue);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    expect(find.text('Spring'), findsNothing);
    await tester.tap(find.text('Show hidden (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Spring'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    handle.dispose();
  });

  testWidgets('sheet for ours: edit, delete, no hide', (tester) async {
    await _pump(tester, const WaypointsScreen());
    await tester.tap(find.text('Base camp'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Share'), findsNothing, reason: 'already sent to #crew');
    expect(find.text('Yours, sent to #crew.'), findsOneWidget);
    expect(find.text('Hide from my map'), findsNothing);
  });

  testWidgets('navigate: distance and bearing from the phone, else the node', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      WaypointNavigateScreen(waypointKey: waypointKey(ann, '0a0a')),
      phone: const LatLon(45, -109.99),
    );
    await tester.pumpAndSettle();
    expect(find.text("From your phone's GPS."), findsOneWidget);
    expect(find.text('1.6 km'), findsOneWidget);
    expect(find.text('W · bearing 270°'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^1\.6 km away, W, bearing 270 degrees')), findsOneWidget);
    handle.dispose();

    await _pump(tester, WaypointNavigateScreen(waypointKey: waypointKey(ann, '0a0a')));
    await tester.pumpAndSettle();
    expect(find.textContaining("uses your node's position"), findsOneWidget);
    expect(find.text('790 m'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  for (final (name, theme) in [('dark', buildGhostWaveTheme()), ('light', ThemeData.light(useMaterial3: true))]) {
    testWidgets('200% text on a small phone, $name theme: every waypoint screen fits', (tester) async {
      const small = Size(360, 780);
      await _pump(tester, const WaypointsScreen(), text: 2, size: small, theme: theme);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Spring'), 200);
      unawaited(showWaypointDetails(tester.element(find.text('Spring')), waypointKey(ann, '0a0a')));
      await tester.pumpAndSettle();
      expect(find.text('Hide from my map'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _pump(tester, const _Host(), text: 2, size: small, theme: theme);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _pump(
        tester,
        WaypointNavigateScreen(waypointKey: waypointKey(ann, '0a0a')),
        text: 2,
        size: small,
        theme: theme,
        phone: const LatLon(45.2, -110.3),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _pump(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox.square(dimension: 44, child: WaypointMarker(waypoint: seededBook().all.first)),
          ),
        ),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
