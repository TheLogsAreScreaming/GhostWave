// Shortcuts and the widget open the right place, and only open it; the widget
// is told the link state. Privacy & data deletes chat history only on confirm.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/main.dart';
import 'package:ghostwave_app/src/app/home_surfaces.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/ui/privacy_screen.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link/fake_node.dart';

class FakeSurfaces implements HomeSurfacesPlatform {
  final StreamController<LaunchAction> launches = StreamController<LaunchAction>.broadcast();
  final List<WidgetText> shown = <WidgetText>[];

  @override
  Stream<LaunchAction> get actions => launches.stream;

  @override
  Future<void> showOnWidget(WidgetText text) async => shown.add(text);
}

Future<FakeSurfaces> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'node_address': '127.0.0.1:1', 'asked_notifications': true});
  final prefs = await SharedPreferences.getInstance();
  final surfaces = FakeSurfaces();
  final node = FakeNode();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        transportFactoryProvider.overrideWithValue((_) => node),
        homeSurfacesProvider.overrideWithValue(surfaces),
      ],
      child: const GhostWaveApp(),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  return surfaces;
}

void main() {
  setUpAll(() {
    // the map's tile cache asks path_provider for a directory
    final tmp = Directory.systemTemp.createTempSync('gw_ui_surfaces').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
  });

  testWidgets('shortcuts open SOS, Check in and Chats; the widget hears the link', (tester) async {
    final s = await _pumpApp(tester);
    expect(s.shown, isNotEmpty);
    expect(s.shown.last.status, startsWith('Connected to'));

    s.launches.add(LaunchAction.sos);
    await tester.pumpAndSettle();
    expect(find.textContaining('hold for 3 seconds'), findsWidgets, reason: 'the SOS tab, nothing sent');

    s.launches.add(LaunchAction.checkin);
    await tester.pumpAndSettle();
    expect(find.text('Trip & check-ins'), findsWidgets);

    s.launches.add(LaunchAction.chats);
    await tester.pumpAndSettle();
    expect(find.text('Trip & check-ins'), findsNothing, reason: 'the trip page was closed');
    expect(find.text('Chats'), findsWidgets);
  });

  testWidgets('Privacy & data: delete chat history asks first and keeps contacts', (tester) async {
    tester.view.physicalSize = const Size(412, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final ctl = c.read(meshProvider.notifier);
    await ctl.sendText(1, 'hello');
    c.read(meshProvider.notifier).state = c
        .read(meshProvider)
        .copyWith(contacts: {1: const Contact(nodeId: 1, name: 'Ann')});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: buildGhostWaveTheme(), home: const PrivacyScreen()),
      ),
    );
    expect(find.text('No accounts, no tracking'), findsOneWidget);
    await tester.tap(find.text('Delete chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(meshProvider).messages[1], hasLength(1));
    await tester.tap(find.text('Delete chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(c.read(meshProvider).messages, isEmpty);
    expect(c.read(meshProvider).contacts.keys, [1]);
  });
}
