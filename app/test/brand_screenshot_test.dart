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
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:shared_preferences/shared_preferences.dart';

import 'app/mesh_controller_test.dart' show answeringNode;
import 'link/fake_node.dart';
import 'support/history_keys.dart';

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

Future<void> _pumpApp(
  WidgetTester tester,
  GlobalKey key,
  List<Override> overrides, {
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size * 2;
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

  // A connected node with contacts, a nearby node, chats and an SOS, for the screens people use most.
  Future<FakeNode> populated(WidgetTester tester, GlobalKey key, {Size size = const Size(412, 892)}) async {
    SharedPreferences.setMockInitialValues({'node_address': '192.168.1.20:47800', 'walkthrough_done': true});
    final prefs = await SharedPreferences.getInstance();
    final dir = Directory.systemTemp.createTempSync('gw_shots_store');
    final node = answeringNode(
      contacts: [
        pb.Contact(nodeId: 0x1A2B3C4D, name: 'Ridge'.codeUnits, pinned: true),
        pb.Contact(nodeId: 0x0B0B0B0B, name: 'Basecamp'.codeUnits),
        pb.Contact(nodeId: 0x7E57C0DE, name: 'Kestrel'.codeUnits, pinned: true),
      ],
    );
    await _pumpApp(tester, key, [
      sharedPrefsProvider.overrideWithValue(prefs),
      meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
      transportFactoryProvider.overrideWithValue((_) => node),
    ], size: size);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    void text(int src, int id, String t) => node.last.send(
      pb.FromRadio(
        text: pb.TextMessage(src: src, msgId: id, text: t.codeUnits),
      ),
    );
    text(0x1A2B3C4D, 1, 'At the saddle, wind picking up. Heading down the east ridge.');
    text(0x0B0B0B0B, 2, 'Copy. Weather window closes around 3.');
    text(0x1A2B3C4D, 3, 'Water at the lake is fine.');
    node.last.send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: 0x5EED1234, isNew: true)));
    final ctl = ProviderScope.containerOf(tester.element(find.byType(GhostWaveApp))).read(meshProvider.notifier);
    await tester.runAsync(() async {
      await ctl.sendText(0x1A2B3C4D, 'Nice. Meet at the trailhead at 4?');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return node;
  }

  testWidgets('chats, a chat, map and status', skip: skip != false, (tester) async {
    final key = GlobalKey();
    await populated(tester, key);
    await _shot(tester, key, 'chats');
    await tester.tap(find.text('Ridge').first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    await _shot(tester, key, 'chat');
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Status').last);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _shot(tester, key, 'status');
  });

  testWidgets('desktop width', skip: skip != false, (tester) async {
    final key = GlobalKey();
    await populated(tester, key, size: const Size(1280, 800));
    await _shot(tester, key, 'desktop_chats');
    await tester.tap(find.text('Ridge').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, key, 'desktop_chat_open');
  });
}
