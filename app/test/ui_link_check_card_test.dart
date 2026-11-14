// Link check card: sender, timing, signal per hop and the path on a map; it
// shares as an image or text through the share gateway, reads well to a
// screen reader, and handles multi-hop results and missing positions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/preferences.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/share_gateway.dart';
import 'package:ghostwave_app/src/data/link_check.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/ui/link_check_card.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeShare implements ShareGateway {
  final List<String> texts = [];
  final List<(Uint8List, String, String?)> images = [];

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async => texts.add(text);

  @override
  Future<void> shareImage(Uint8List png, String fileName, {String? text, String? subject, Rect? origin}) async =>
      images.add((png, fileName, text));
}

final DateTime at = DateTime(2026, 11, 13, 14, 5);
const base = LinkCheckNode(nodeId: 0x11111111, name: 'Base', pos: LatLon(45, -110));
const ridge = LinkCheckNode(nodeId: 0x1A2B3C4D, name: 'Ridge', pos: LatLon(45.01, -110));

LinkCheck ping({bool answered = true, LinkCheckNode target = ridge}) => LinkCheck.linkPing(
  origin: base,
  target: target,
  at: at,
  answered: answered,
  forwardDbm: -97,
  reverseDbm: -112,
  elapsed: const Duration(milliseconds: 1400),
);

Future<FakeShare> _pump(WidgetTester tester, LinkCheck check, {double text = 1}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({'units': 'metric'});
  final prefs = await SharedPreferences.getInstance();
  final share = FakeShare();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), shareGatewayProvider.overrideWithValue(share)],
      child: MaterialApp(
        theme: buildGhostWaveTheme(),
        home: LinkCheckScreen(check: check),
      ),
    ),
  );
  await tester.pump();
  return share;
}

void main() {
  test('share text says who, when, how long, each direction and how far', () {
    expect(linkCheckText(ping(), Units.metric), '''
GhostWave link ping · 2026-11-13 14:05
From: Base (11111111)
To: Ridge (1a2b3c4d)
Answered in 1.4 s, one hop
Ridge heard Base at -97 dBm, good
Base heard Ridge at -112 dBm, fair
1.1 km, N (straight line between last known positions)''');
    final none = linkCheckText(ping(answered: false), Units.metric);
    expect(none, contains('No answer within 10 seconds'));
    expect(none, isNot(contains('dBm')));
  });

  test('multi-hop text numbers each hop and never invents a reading', () {
    final c = LinkCheck(
      kind: 'Route check',
      nodes: const [
        base,
        LinkCheckNode(nodeId: 3, name: 'Mid'),
        ridge,
      ],
      hops: const [LinkCheckHop(forwardDbm: -100), LinkCheckHop()],
      at: at,
      answered: true,
    );
    final t = linkCheckText(c, Units.metric);
    expect(t, contains('Answered, 2 hops'));
    expect(t, contains('Hop 1: Mid heard Base at -100 dBm, good'));
    expect(t, contains('Hop 2: Mid to Ridge: not measured'));
    expect(t, isNot(contains('km')), reason: 'Mid has no position');
    final scene = PathMapScene.of(c, Units.metric);
    expect(scene.geographic, isTrue);
    expect(scene.points[1], Offset.lerp(scene.points[0], scene.points[2], 0.5));
  });

  test('builds the card from a ping: our position, target from contacts', () {
    final mesh = MeshState(
      nodeId: 0x11111111,
      ownPos: const LatLon(45, -110),
      contacts: {ridge.nodeId: const Contact(nodeId: 0x1A2B3C4D, name: 'Ridge', pos: LatLon(45.01, -110))},
    );
    final c = linkCheckFromPing(
      mesh,
      const LinkIdle(),
      const LinkPingOutcome(node: 0x1A2B3C4D, answered: true, forwardDbm: -97, elapsed: Duration(seconds: 2)),
      at,
    );
    expect(
      (c.origin.name, c.origin.pos, c.target.name, c.target.pos),
      ('11111111', const LatLon(45, -110), 'Ridge', const LatLon(45.01, -110)),
    );
    expect(c.hops.single.reverseDbm, isNull);
  });

  testWidgets('card shows the result and describes the map to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, ping());
    expect(find.text('From Base (11111111)'), findsOneWidget);
    expect(find.text('To Ridge (1a2b3c4d)'), findsOneWidget);
    expect(find.text('Answered in 1.4 s, one hop'), findsOneWidget);
    expect(find.text('Ridge heard Base at -97 dBm, good'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Path map: Base to Ridge. 1.1 km, N (straight line between last known positions)'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('no positions: a path diagram, and it says so', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, ping(answered: false, target: const LinkCheckNode(nodeId: 9, name: 'Far')));
    expect(find.text('No answer within 10 seconds'), findsOneWidget);
    expect(find.textContaining('dBm'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Path diagram: Base to Far. Positions not known')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('share text, share image and copy', (tester) async {
    final share = await _pump(tester, ping());
    await tester.tap(find.text('Share text'));
    await tester.pump();
    expect(share.texts.single, startsWith('GhostWave link ping'));

    await tester.runAsync(() async {
      await tester.tap(find.text('Share image'));
      for (var i = 0; i < 50 && share.images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    final (png, name, caption) = share.images.single;
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'PNG signature');
    expect(name, 'ghostwave-link-check-1a2b3c4d-20261113-1405.png');
    expect(caption, contains('Answered in 1.4 s'));

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await tester.tap(find.byTooltip('Copy as text'));
    await tester.pump();
    expect(copied, contains('To: Ridge (1a2b3c4d)'));
  });

  testWidgets('200% text does not overflow', (tester) async {
    await _pump(tester, ping(), text: 2);
    expect(tester.takeException(), isNull);
  });
}
