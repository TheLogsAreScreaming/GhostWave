// Renders a few screens off-screen with the bundled fonts and the real theme,
// and saves them as PNGs, to review the brand without a phone or emulator.
// Opt-in, not a golden comparison (text rendering differs between machines):
//
//   SCREENSHOT_DIR=/tmp/shots flutter test test/brand_screenshot_test.dart
@Tags(['screenshot'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/main.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link/fake_node.dart';

final String? _outDir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await family('Space Grotesk', [
    'assets/fonts/space_grotesk/SpaceGrotesk-Medium.ttf',
    'assets/fonts/space_grotesk/SpaceGrotesk-Bold.ttf',
  ]);
  await family('Inter', [
    'assets/fonts/inter/Inter-Regular.ttf',
    'assets/fonts/inter/Inter-Medium.ttf',
    'assets/fonts/inter/Inter-SemiBold.ttf',
  ]);
  await family('JetBrains Mono', [
    'assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf',
    'assets/fonts/jetbrains_mono/JetBrainsMono-Medium.ttf',
  ]);
  // Material icons ship with the SDK, not as an app asset.
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    final bytes = icons.readAsBytesSync();
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _pumpApp(WidgetTester tester, GlobalKey key, List<Override> overrides) async {
  tester.view.physicalSize = const Size(412 * 2, 892 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ProviderScope(overrides: overrides, child: const GhostWaveApp()),
    ),
  );
  await tester.runAsync(() async {
    final ctx = key.currentContext!;
    await precacheImage(const AssetImage('assets/brand/logo.png'), ctx);
  });
  await tester.pump();
  await tester.pump();
}

void main() {
  final skip = _outDir == null ? 'set SCREENSHOT_DIR to save screenshots' : false;

  setUpAll(() async {
    if (_outDir == null) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    // the map's tile cache asks path_provider for a directory
    final tmp = Directory.systemTemp.createTempSync('gw_shots').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
    await _loadFonts();
  });

  testWidgets('connect screen', skip: skip != false, (tester) async {
    SharedPreferences.setMockInitialValues({'walkthrough_done': true});
    final prefs = await SharedPreferences.getInstance();
    final key = GlobalKey();
    await _pumpApp(tester, key, [sharedPrefsProvider.overrideWithValue(prefs)]);
    await _shot(tester, key, 'connect');
  });

  testWidgets('SOS and Me tabs', skip: skip != false, (tester) async {
    SharedPreferences.setMockInitialValues({'node_address': '192.168.1.20:47800'});
    final prefs = await SharedPreferences.getInstance();
    final node = FakeNode();
    final key = GlobalKey();
    await _pumpApp(tester, key, [
      sharedPrefsProvider.overrideWithValue(prefs),
      transportFactoryProvider.overrideWithValue((_) => node),
    ]);
    await tester.tap(find.text('SOS').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, key, 'sos');
    await tester.tap(find.text('Me').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, key, 'me');
  });
}
