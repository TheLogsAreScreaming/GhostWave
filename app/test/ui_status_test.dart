// Status: headline tiles say their state in words, every counter is still listed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/ui/status_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, pb.Status s, {Size size = const Size(412, 892), double text = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [nodeStatusProvider.overrideWith((ref) async => s), sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(theme: buildGhostWaveTheme(), home: const StatusScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('transmit off and an active SOS read as words, not just colour', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, pb.Status(txOff: true, sosActive: true, neighbors: 3, uptimeS: 3725));
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('01:02:05'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Transmit: OFF, type tx on')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('every counter is still there', (tester) async {
    await _pump(tester, pb.Status(), size: const Size(412, 2400));
    for (final label in [
      'SOS alerts held',
      'Store (carry-forward)',
      'Apps connected',
      'Events queued for apps',
      'Frames sent',
      'Frames received',
      'Received, bad',
      'Received, auth failed',
      'Delivered to us',
      'Forwarded',
      'Stored for later',
      'Airtime',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('200% text on a small phone does not overflow', (tester) async {
    await _pump(tester, pb.Status(txOff: true), size: const Size(360, 780), text: 2);
    expect(tester.takeException(), isNull);
  });
}
