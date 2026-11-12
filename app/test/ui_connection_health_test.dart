// Connection health card: shows live rows while connected, ticks, and fits
// 200% text on a small phone. Troubleshooting appears for a failed link.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/ui/connection_health.dart';
import 'package:ghostwave_app/src/ui/theme.dart';

import 'link/fake_node.dart';

void main() {
  testWidgets('connected: health rows, at 200% text on a small phone', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      container.read(nodeLinkProvider).connect(FakeNode());
      for (var i = 0; i < 20 && container.read(nodeLinkProvider).state is! LinkUp; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(container.read(nodeLinkProvider).state, isA<LinkUp>());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildGhostWaveTheme(),
          home: const Scaffold(body: SingleChildScrollView(child: ConnectionHealthCard())),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Connection health'), findsOneWidget);
    expect(find.text('Last answer from the radio'), findsOneWidget);
    expect(find.text('not available on this connection'), findsOneWidget, reason: 'a non-Bluetooth link');
    expect(find.text('shown after the next check'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // ticks without errors
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.read(nodeLinkProvider).disconnect();
  });

  testWidgets('failed: what to try, opened, numbered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildGhostWaveTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TroubleshootCard(
              state: LinkFailed('GhostWave-8904', 'This phone is using an old Bluetooth pairing for this node'),
              bluetooth: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What to try'), findsOneWidget);
    expect(find.text('Forget the old pairing'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
