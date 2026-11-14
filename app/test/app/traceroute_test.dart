// Traceroute from the app (protocol 1.10): the result event answers the
// request, every hop arrives as measured both ways, refusals surface, older
// nodes are never asked, and the words never guess.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/path_trace.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/ui/theme.dart';
import 'package:ghostwave_app/src/ui/trace_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;

const int ridge = 0x9F219DBB;
const int relayA = 0x0000A001;
const int relayB = 0x0000B002;

FakeNode traceNode({int minor = 10, bool answer = true}) {
  final node = answeringNode()..protocolMinor = minor;
  node.onRequest.listen((e) {
    final (c, r) = e;
    if (!r.hasTraceroute()) return;
    if (r.traceroute.maxHops > 8) {
      c.send(
        pb.FromRadio(
          reqId: r.reqId,
          error: pb.Error(code: pb.Error_Code.BAD_ARGUMENT, detail: 'max_hops is 1 to 8'),
        ),
      );
      return;
    }
    c
      ..send(pb.FromRadio(reqId: r.reqId, ok: pb.Ok()))
      ..send(
        pb.FromRadio(
          traceResult: answer
              ? pb.TraceResult(
                  nodeId: r.traceroute.nodeId,
                  answered: true,
                  forwardNodes: [relayA, r.traceroute.nodeId],
                  forwardRssiDbm: [-101, -118],
                  backNodes: [relayB, node.nodeId],
                  backRssiDbm: [-96, -104],
                )
              : pb.TraceResult(nodeId: r.traceroute.nodeId),
        ),
      );
  });
  return node;
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-trace.');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
      ],
    );
    c.listen(meshProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  String nameOf(int id) => switch (id) {
    ridge => 'Ridge',
    relayA => 'Pass',
    relayB => 'Saddle',
    _ => 'You',
  };

  test('answered: every hop both ways, as measured', () async {
    final node = traceNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final t = await c.read(meshProvider.notifier).traceroute(ridge, maxHops: 6);
    expect(node.requests.where((r) => r.hasTraceroute()).single.traceroute.maxHops, 6);
    expect(t.answered, isTrue);
    expect(t.out, const [TraceStep(node: relayA, rssiDbm: -101), TraceStep(node: ridge, rssiDbm: -118)]);
    expect(t.back.map((s) => s.rssiDbm), [-96, -104]);
    expect(t.relaysOut, [relayA]);
    expect(t.relaysBack, [relayB]);
    expect(t.sameWayBack, isFalse);
    expect(t.weakest, const TraceStep(node: ridge, rssiDbm: -118));
    expect(traceSummary(t, nameOf), 'Reached Ridge: 2 hops each way. Weakest link: -118 dBm, weak at Ridge.');
    expect(traceHopLines(t.out, 0, nameOf), [
      'You → Pass: heard at -101 dBm, good',
      'Pass → Ridge: heard at -118 dBm, weak',
    ]);
    expect(traceHopLines(t.back, ridge, nameOf), [
      'Ridge → Saddle: heard at -96 dBm, good',
      'Saddle → You: heard at -104 dBm, good',
    ]);
  });

  test('no answer: says so, with no hops and no readings', () async {
    c.read(nodeLinkProvider).connect(traceNode(answer: false));
    await settle();
    final t = await c.read(meshProvider.notifier).traceroute(ridge);
    expect([t.answered, t.out, t.back, t.weakest], [false, isEmpty, isEmpty, null]);
    expect(traceSummary(t, nameOf), 'No answer from Ridge. The path is unknown.');
    expect(traceSummary(t, nameOf), isNot(contains('dBm')));
  });

  test('a refusal from the radio surfaces', () async {
    c.read(nodeLinkProvider).connect(traceNode());
    await settle();
    await expectLater(
      c.read(meshProvider.notifier).traceroute(ridge, maxHops: 9),
      throwsA(isA<NodeError>().having((e) => e.code, 'code', pb.Error_Code.BAD_ARGUMENT)),
    );
  });

  test('an older node is never asked', () async {
    final node = traceNode(minor: 9);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    expect(c.read(meshProvider.notifier).nodeCanTrace, isFalse);
    await expectLater(c.read(meshProvider.notifier).traceroute(ridge), throwsA(isA<StateError>()));
    expect(node.requests.where((r) => r.hasTraceroute()), isEmpty);
  });

  test('a trace survives a JSON round trip, and a broken one is refused', () {
    final t = PathTrace(
      target: ridge,
      answered: true,
      at: DateTime.utc(2026, 11, 13, 12),
      out: const [
        TraceStep(node: relayA, rssiDbm: -101),
        TraceStep(node: ridge, rssiDbm: -118),
      ],
      back: const [
        TraceStep(node: relayA, rssiDbm: -99),
        TraceStep(node: 1, rssiDbm: -100),
      ],
    );
    final back = PathTrace.fromJson(t.toJson())!;
    expect([back.target, back.answered, back.out, back.back, back.at.toUtc()], [ridge, true, t.out, t.back, t.at]);
    expect(back.sameWayBack, isTrue);
    expect(PathTrace.fromJson({'target': 1}), isNull);
    expect(PathTrace.fromJson({...t.toJson(), 'out': 'x'}), isNull);
    final none = PathTrace.fromJson(PathTrace.unanswered(target: ridge, at: t.at).toJson())!;
    expect([none.answered, none.out], [false, isEmpty]);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1600); // every hop on screen at once
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildGhostWaveTheme(),
          home: const TraceRouteScreen(node: ridge),
        ),
      ),
    );
  }

  testWidgets('the screen: an older radio is told, not asked', (tester) async {
    await tester.runAsync(() async {
      c.read(nodeLinkProvider).connect(traceNode(minor: 9));
      await settle();
    });
    await pumpScreen(tester);
    expect(find.textContaining('needs newer firmware'), findsOneWidget);
    expect(find.text('Trace route'), findsNothing);
  });

  testWidgets('the screen: trace, then both ways listed hop by hop', (tester) async {
    await tester.runAsync(() async {
      c.read(nodeLinkProvider).connect(traceNode());
      await settle();
    });
    await pumpScreen(tester);
    await tester.tap(find.text('Trace route'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 hops each way'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.textContaining('heard at -118 dBm, weak'), findsOneWidget);
    expect(find.textContaining('came back a different way'), findsOneWidget);
  });
}
