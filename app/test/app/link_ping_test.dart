// Link ping from the app (protocol 1.9): the result event answers the request,
// both readings arrive as measured, refusals surface, older nodes are never
// asked, and the words never guess.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/ui/link_ping.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';
import 'mesh_controller_test.dart' show answeringNode, settle;

const int ridge = 0x9F219DBB;

FakeNode pingNode({int minor = 9, bool answer = true}) {
  final node = answeringNode()..protocolMinor = minor;
  node.onRequest.listen((e) {
    final (c, r) = e;
    if (!r.hasLinkPing()) return;
    if (r.linkPing.nodeId != ridge) {
      c.send(
        pb.FromRadio(
          reqId: r.reqId,
          error: pb.Error(code: pb.Error_Code.NOT_FOUND, detail: 'not heard directly: a link ping is one hop'),
        ),
      );
      return;
    }
    c
      ..send(pb.FromRadio(reqId: r.reqId, ok: pb.Ok()))
      ..send(
        pb.FromRadio(
          linkPingResult: answer
              ? pb.LinkPingResult(nodeId: ridge, answered: true, forwardRssiDbm: -97, reverseRssiDbm: -112)
              : pb.LinkPingResult(nodeId: ridge),
        ),
      );
  });
  return node;
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-ping.');
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

  test('answered: both directions as measured', () async {
    c.read(nodeLinkProvider).connect(pingNode());
    await settle();
    final o = await c.read(meshProvider.notifier).linkPing(ridge);
    expect([o.answered, o.forwardDbm, o.reverseDbm], [true, -97, -112]);
    expect(linkPingLines(o, 'Ridge'), [
      'Ridge heard you at -97 dBm, good.',
      'Your radio heard Ridge at -112 dBm, fair.',
      'This is the direct link between the two radios (one hop).',
    ]);
  });

  test('no answer: says so, with no readings', () async {
    c.read(nodeLinkProvider).connect(pingNode(answer: false));
    await settle();
    final o = await c.read(meshProvider.notifier).linkPing(ridge);
    expect([o.answered, o.forwardDbm, o.reverseDbm], [false, null, null]);
    expect(linkPingLines(o, 'Ridge').first, 'No answer from Ridge within 10 seconds.');
    expect(linkPingLines(o, 'Ridge').join(), isNot(contains('dBm')));
  });

  test('a node not heard directly is refused by the radio', () async {
    c.read(nodeLinkProvider).connect(pingNode());
    await settle();
    await expectLater(
      c.read(meshProvider.notifier).linkPing(0x12345678),
      throwsA(isA<NodeError>().having((e) => e.code, 'code', pb.Error_Code.NOT_FOUND)),
    );
  });

  test('an older node is never asked', () async {
    final node = pingNode(minor: 8);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    expect(c.read(meshProvider.notifier).nodeCanLinkPing, isFalse);
    await expectLater(c.read(meshProvider.notifier).linkPing(ridge), throwsA(isA<StateError>()));
    expect(node.requests.where((r) => r.hasLinkPing()), isEmpty);
  });
}
