// Telemetry from neighbors' beacons (protocol 1.12): live events and
// GetTelemetry replies land in MeshState.telemetry with only what the node
// reported; an older node is never asked; NOT_FOUND is "none", not an error.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;

const int ridge = 0x9F219DBB;
final DateTime now = DateTime(2026, 11, 14, 12);

FakeNode telemetryNode({int minor = 12}) {
  final node = answeringNode()..protocolMinor = minor;
  node.onRequest.listen((e) {
    final (c, r) = e;
    if (!r.hasGetTelemetry()) return;
    if (r.getTelemetry.nodeId != ridge) {
      c.send(
        pb.FromRadio(
          reqId: r.reqId,
          error: pb.Error(code: pb.Error_Code.NOT_FOUND, detail: 'no telemetry heard from that node'),
        ),
      );
      return;
    }
    c.send(
      pb.FromRadio(
        reqId: r.reqId,
        nodeTelemetry: pb.NodeTelemetry(nodeId: ridge, batteryPct: 64, batteryMv: 3801, uptimeS: 7200, ageS: 120),
      ),
    );
  });
  return node;
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-telemetry.');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    c.listen(meshProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('GetTelemetry: the reply is kept, dated by its age', () async {
    final node = telemetryNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    expect(ctl.nodeCanTelemetry, isTrue);
    final t = await ctl.requestTelemetry(ridge);
    expect(t, isNotNull);
    expect([t!.batteryPct, t.batteryMv, t.uptime], [64, 3801, const Duration(hours: 2)]);
    expect(t.heardAt, now.subtract(const Duration(minutes: 2)));
    expect(t.uptimeAt(now), const Duration(hours: 2, minutes: 2));
    expect(c.read(meshProvider).telemetry[ridge], same(t));
    expect(node.requests.where((r) => r.hasGetTelemetry()).single.getTelemetry.nodeId, ridge);
  });

  test('NOT_FOUND means none, not an error', () async {
    c.read(nodeLinkProvider).connect(telemetryNode());
    await settle();
    expect(await c.read(meshProvider.notifier).requestTelemetry(0x12345678), isNull);
    expect(c.read(meshProvider).telemetry, isEmpty);
  });

  test('a live beacon event keeps only the fields the node reported', () async {
    final node = telemetryNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    node.last.send(pb.FromRadio(nodeTelemetry: pb.NodeTelemetry(nodeId: 0x0C0FFEE0, uptimeS: 30, rssiDbm: -101)));
    await settle();
    final t = c.read(meshProvider).telemetry[0x0C0FFEE0]!;
    expect([t.batteryPct, t.batteryMv, t.uptime, t.heardAt], [null, null, const Duration(seconds: 30), now]);
    expect(t.isEmpty, isFalse);
  });

  test('an older node is never asked', () async {
    final node = telemetryNode(minor: 10);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    expect(c.read(meshProvider.notifier).nodeCanTelemetry, isFalse);
    expect(await c.read(meshProvider.notifier).requestTelemetry(ridge), isNull);
    expect(node.requests.where((r) => r.hasGetTelemetry()), isEmpty);
  });
}
