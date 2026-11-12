// Field tests screen: a test keeps its notes after the screen closes, and
// deleting asks first.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/field_reports_controller.dart';
import 'package:ghostwave_app/src/ui/field_tools_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';

void main() {
  testWidgets('notes are kept after leaving a test, and delete asks first', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildGhostWaveTheme(), home: const FieldToolsScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('No tests yet. Start one before you head out.'), findsOneWidget);

    await tester.tap(find.text('New test'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ridge road');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Ridge road'), findsOneWidget);
    expect(find.textContaining('Not connected'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Test notes'), 'RAK 1 W to T1000-E');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(container.read(fieldReportsProvider).reports.single.notes, 'RAK 1 W to T1000-E');
    expect(find.textContaining('0 samples'), findsOneWidget);

    await tester.tap(find.text('Ridge road'));
    await tester.pumpAndSettle();
    expect(find.text('RAK 1 W to T1000-E'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(fieldReportsProvider).reports, hasLength(1));

    await tester.tap(find.byTooltip('Delete test'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(container.read(fieldReportsProvider).reports, isEmpty);
    expect(find.text('No tests yet. Start one before you head out.'), findsOneWidget);
  });
}
