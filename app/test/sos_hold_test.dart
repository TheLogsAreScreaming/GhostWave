// The SOS hold button inside a scrolling list, as on the SOS tab: a drifting
// thumb must not let the list steal the hold.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/ui/sos_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';

Future<ScrollController> pumpInList(WidgetTester tester, VoidCallback onConfirmed) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGhostWaveTheme(),
      home: Scaffold(
        body: ListView(
          controller: scroll,
          children: [
            const SizedBox(height: 40),
            Center(child: HoldToConfirmButton(onConfirmed: onConfirmed)),
            const SizedBox(height: 2000), // scrollable, like a long alert list
          ],
        ),
      ),
    ),
  );
  return scroll;
}

/// Holds the button for [total], moving the finger [drift] down in even steps.
Future<TestGesture> hold(WidgetTester tester, {required Duration total, double drift = 0, bool release = true}) async {
  final g = await tester.startGesture(tester.getCenter(find.byType(HoldToConfirmButton)) - const Offset(0, 14));
  const steps = 30;
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(0, drift / steps));
    await tester.pump(total ~/ steps);
  }
  if (release) await g.up();
  await tester.pump();
  return g;
}

void main() {
  testWidgets('a 3 s hold that drifts 25 px still fires, and the list does not scroll', (tester) async {
    var fired = 0;
    final scroll = await pumpInList(tester, () => fired++);
    await hold(tester, total: const Duration(milliseconds: 3300), drift: 25);
    expect(fired, 1);
    expect(scroll.offset, 0, reason: 'the hold owns the gesture');
  });

  testWidgets('letting go early does not fire and says to keep holding', (tester) async {
    var fired = 0;
    await pumpInList(tester, () => fired++);
    await hold(tester, total: const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(fired, 0);
    // the hint shows right after release, then fades
    await hold(tester, total: const Duration(milliseconds: 500));
    expect(find.text('Keep holding for 3 seconds'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(fired, 0);
  });

  testWidgets('drifting past the slop cancels', (tester) async {
    var fired = 0;
    await pumpInList(tester, () => fired++);
    final g = await hold(tester, total: const Duration(seconds: 1), drift: kSosHoldSlop + 20, release: false);
    expect(find.textContaining('Moved too far'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // still pressed, but the hold was cancelled
    expect(fired, 0);
    await g.up();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('screen readers: the tap action opens a confirm dialog', (tester) async {
    final handle = tester.ensureSemantics();
    var fired = 0;
    await pumpInList(tester, () => fired++);
    final node = tester.getSemantics(find.byType(HoldToConfirmButton));
    expect(node.label, contains('double-tap to confirm'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    // what TalkBack / VoiceOver invoke on double-tap
    final sem = tester.widget<Semantics>(
      find.descendant(
        of: find.byType(HoldToConfirmButton),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.onTap != null),
      ),
    );
    sem.properties.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Send SOS?'), findsOneWidget);
    await tester.tap(find.text('Send SOS'));
    await tester.pumpAndSettle();
    expect(fired, 1);
    handle.dispose();
  });
}
