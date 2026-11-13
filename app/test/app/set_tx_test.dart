// Transmit switch from the app (SetTx, protocol 1.8): sent only to nodes that
// know it, and the app reads the result back from the node's status.
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
import 'mesh_controller_test.dart' show settle;

/// A node with a transmit gate: off until SetTx turns it on.
FakeNode gatedNode({int minor = 8}) {
  final node = FakeNode()..protocolMinor = minor;
  var tx = false;
  node.onRequest.listen((e) {
    final (c, r) = e;
    switch (r.whichRequest()) {
      case pb.ToRadio_Request.setTx:
        tx = r.setTx.on;
        c.send(pb.FromRadio(reqId: r.reqId, ok: pb.Ok()));
      case pb.ToRadio_Request.getStatus:
        c.send(
          pb.FromRadio(
            reqId: r.reqId,
            status: pb.Status(txOff: !tx),
          ),
        );
      case pb.ToRadio_Request.listContacts:
        c.send(pb.FromRadio(reqId: r.reqId, contactsEnd: pb.ContactsEnd()));
      case pb.ToRadio_Request.listChannels:
        c.send(pb.FromRadio(reqId: r.reqId, channelsEnd: pb.ChannelsEnd()));
      case pb.ToRadio_Request.getPosition:
        c.send(pb.FromRadio(reqId: r.reqId, position: pb.OwnPosition()));
      default:
        break;
    }
  });
  return node;
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-settx.');
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

  test('a 1.8 node: turning transmit on clears the TX-off state, off sets it again', () async {
    final node = gatedNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    expect(ctl.nodeCanSetTx, isTrue);
    expect(c.read(meshProvider).txOff, isTrue, reason: 'a fresh board listens only');
    await ctl.setTransmit(true);
    expect(node.requests.where((r) => r.hasSetTx()).single.setTx.on, isTrue);
    expect(c.read(meshProvider).txOff, isFalse);
    await ctl.setTransmit(false);
    expect(c.read(meshProvider).txOff, isTrue);
  });

  test('an older node is never sent SetTx', () async {
    final node = gatedNode(minor: 7);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    expect(ctl.nodeCanSetTx, isFalse);
    await expectLater(ctl.setTransmit(true), throwsA(isA<StateError>()));
    expect(node.requests.where((r) => r.hasSetTx()), isEmpty);
  });
}
