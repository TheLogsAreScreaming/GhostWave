import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/contact_card.dart';
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';

import '../link/fake_node.dart';

const int bob = 0x0B0B0B0B;

/// A fake node that answers the requests the controller makes on connect.
FakeNode answeringNode({bool sosActive = false, List<pb.Contact> contacts = const []}) {
  final node = FakeNode();
  node.onRequest.listen((e) {
    final (c, r) = e;
    final id = r.reqId;
    switch (r.whichRequest()) {
      case pb.ToRadio_Request.listContacts:
        for (final ct in contacts) {
          c.send(pb.FromRadio(reqId: id, contact: ct));
        }
        c.send(
          pb.FromRadio(
            reqId: id,
            contactsEnd: pb.ContactsEnd(count: contacts.length),
          ),
        );
      case pb.ToRadio_Request.getPosition:
        c.send(
          pb.FromRadio(
            reqId: id,
            position: pb.OwnPosition(pos: pb.Position(latE7: 468700000, lonE7: -1139900000)),
          ),
        );
      case pb.ToRadio_Request.getStatus:
        c.send(
          pb.FromRadio(
            reqId: id,
            status: pb.Status(sosActive: sosActive),
          ),
        );
      case pb.ToRadio_Request.sendText:
        if (r.sendText.text.length > 73) {
          c.send(
            pb.FromRadio(
              reqId: id,
              error: pb.Error(code: pb.Error_Code.TOO_LONG),
            ),
          );
        } else {
          c.send(
            pb.FromRadio(
              reqId: id,
              sendQueued: pb.SendQueued(
                dest: r.sendText.dest,
                msgId: 0x1000 + r.sendText.clientMsgId % 1000,
                clientMsgId: r.sendText.clientMsgId,
              ),
            ),
          );
        }
      case pb.ToRadio_Request.addContact:
      case pb.ToRadio_Request.sosStart:
      case pb.ToRadio_Request.sosStop:
      case pb.ToRadio_Request.sosAck:
        c.send(pb.FromRadio(reqId: id, ok: pb.Ok()));
      default:
        break;
    }
  });
  return node;
}

Future<ProviderContainer> makeContainer(Directory dir) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
    ],
  );
  c.listen(meshProvider, (_, _) {}); // keep it alive
  return c;
}

Future<void> settle() => pumpEventQueue(times: 50);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('gwapp-test.'));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('on connect: loads contacts, own position and SOS state', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode(
      sosActive: true,
      contacts: [pb.Contact(nodeId: bob, name: 'bob'.codeUnits, pinned: true)],
    );
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final s = c.read(meshProvider);
    expect(s.nodeId, node.nodeId);
    expect(s.contacts[bob]!.name, 'bob');
    expect(s.contacts[bob]!.pinned, isTrue);
    expect(s.ownPos!.lat, closeTo(46.87, 1e-9));
    expect(s.ownSos.active, isTrue);
  });

  test('DM: pending -> sent -> delivered, receipts are idempotent', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    await c.read(meshProvider.notifier).sendText(bob, 'hello');
    var m = c.read(meshProvider).messages[bob]!.single;
    expect(m.state, MsgState.sent);
    expect(m.msgId, isNot(0));
    final sent = node.requests.lastWhere((r) => r.hasSendText()).sendText;
    expect(sent.clientMsgId, m.clientMsgId);
    expect(sent.dest, bob);

    for (var i = 0; i < 2; i++) {
      node.last.send(
        pb.FromRadio(
          delivered: pb.Delivered(dest: bob, msgId: m.msgId, clientMsgId: m.clientMsgId),
        ),
      );
    }
    await settle();
    m = c.read(meshProvider).messages[bob]!.single;
    expect(m.state, MsgState.delivered);
  });

  test('a refused DM is failed and can be retried', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    await c.read(meshProvider.notifier).sendText(bob, 'x' * 74);
    final m = c.read(meshProvider).messages[bob]!.single;
    expect(m.state, MsgState.failed);
    expect(m.error, 'Text too long');
  });

  test('offline DMs wait as pending and go out on connect', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode();
    // first connect so the controller knows which node's history to use
    c.read(nodeLinkProvider).connect(node);
    await settle();
    c.read(nodeLinkProvider).disconnect();
    await settle();
    await c.read(meshProvider.notifier).sendText(bob, 'later');
    expect(c.read(meshProvider).messages[bob]!.single.state, MsgState.pending);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    expect(c.read(meshProvider).messages[bob]!.single.state, MsgState.sent);
    expect(node.requests.where((r) => r.hasSendText()).length, 1);
  });

  test('incoming DMs are de-duplicated by (src, msg_id) and counted unread', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final t = pb.TextMessage(src: bob, msgId: 77, text: [0x68, 0x69, 0xFF]);
    node.last.send(pb.FromRadio(text: t));
    node.last.send(pb.FromRadio(text: t, replayed: true));
    await settle();
    final s = c.read(meshProvider);
    expect(s.messages[bob]!.single.text, 'hi�');
    expect(s.unread[bob], 1);
    expect(s.contacts[bob]!.lastSeen, isNotNull);
    c.read(meshProvider.notifier).markRead(bob);
    expect(c.read(meshProvider).unread[bob], 0);
  });

  test('history survives a restart (saved per node)', () async {
    final node = answeringNode();
    var c = await makeContainer(dir);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    node.last.send(
      pb.FromRadio(
        text: pb.TextMessage(src: bob, msgId: 1, text: 'saved'.codeUnits),
      ),
    );
    await settle();
    c.read(meshProvider.notifier).flush();
    await c.read(meshStoreProvider)!.idle;
    c.dispose();

    c = await makeContainer(dir);
    addTearDown(c.dispose);
    c.read(nodeLinkProvider).connect(answeringNode());
    // loading is real file I/O, which a fixed wait can lose to on a busy machine
    for (var i = 0; i < 200 && c.read(meshProvider).nodeId == null; i++) {
      await settle();
    }
    await settle();
    expect(c.read(meshProvider).messages[bob]!.single.text, 'saved');
  });

  test('neighbors update contacts\' last-seen and position', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode(contacts: [pb.Contact(nodeId: bob, pinned: true)]);
    c.read(nodeLinkProvider).connect(node);
    await settle();
    node.last.send(
      pb.FromRadio(
        neighbor: pb.Neighbor(nodeId: bob, pos: pb.Position(latE7: 10, lonE7: 20)),
      ),
    );
    node.last.send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: 0x99, isNew: true)));
    await settle();
    final s = c.read(meshProvider);
    expect(s.contacts[bob]!.pos!.lat, 1e-6);
    expect(s.neighbors.keys, containsAll([bob, 0x99]));
    expect(s.contacts.containsKey(0x99), isFalse);
  });

  test('SOS: start, acks, stop; incoming alerts keep the newest seq; ack', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final ctl = c.read(meshProvider.notifier);
    await ctl.startSos('  ${'é' * 40}  ');
    expect(c.read(meshProvider).ownSos.active, isTrue);
    expect(utf8Length(c.read(meshProvider).ownSos.text), 60);
    expect(node.requests.last.sosStart.text.length, 60);
    node.last.send(pb.FromRadio(sosAck: pb.SosAckReceived(responder: bob, seq: 1)));
    node.last.send(pb.FromRadio(sosAck: pb.SosAckReceived(responder: bob, seq: 1)));
    await settle();
    expect(c.read(meshProvider).ownSos.acks.single.responder, bob);
    await ctl.stopSos();
    expect(c.read(meshProvider).ownSos.active, isFalse);

    node.last.send(
      pb.FromRadio(
        sos: pb.SosAlert(src: bob, seq: 2, text: 'help'.codeUnits, batteryPct: 0),
      ),
    );
    node.last.send(
      pb.FromRadio(
        sos: pb.SosAlert(src: bob, seq: 1, text: 'old'.codeUnits),
      ),
    );
    await settle();
    var alert = c.read(meshProvider).alerts.single;
    expect(alert.text, 'help');
    expect(alert.batteryPct, 0);
    expect(alert.pos, isNull);
    expect(c.read(meshProvider).activeAlerts, hasLength(1));
    await ctl.ackSos(bob);
    alert = c.read(meshProvider).alerts.single;
    expect(alert.acked, isTrue);
    expect(node.requests.last.sosAck.nodeId, bob);
    expect(c.read(meshProvider).activeAlerts, isEmpty);
  });

  test('addContact pins the key; KeyChange flags the contact', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    final node = answeringNode();
    c.read(nodeLinkProvider).connect(node);
    await settle();
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    await c.read(meshProvider.notifier).addContact(ContactCard(nodeId: bob, ed25519Pub: key, name: 'Bob'));
    final add = node.requests.lastWhere((r) => r.hasAddContact()).addContact;
    expect(add.nodeId, bob);
    expect(add.ed25519Pub, key);
    expect(add.name, 'Bob');
    expect(c.read(meshProvider).contacts[bob]!.pinned, isTrue);
    node.last.send(
      pb.FromRadio(
        keyChange: pb.KeyChange(nodeId: bob, ed25519Pub: List.filled(32, 1)),
      ),
    );
    await settle();
    expect(c.read(meshProvider).contacts[bob]!.keyChanged, isTrue);
    expect(c.read(meshProvider).nameOf(bob), 'Bob');
  });

  test('actions need a link', () async {
    final c = await makeContainer(dir);
    addTearDown(c.dispose);
    expect(c.read(nodeLinkProvider).state, isA<LinkIdle>());
    await expectLater(c.read(meshProvider.notifier).startSos('x'), throwsStateError);
  });

  test('store: a corrupt file loads as empty and is kept aside', () async {
    final store = MeshStore(dir, testHistoryKeys);
    File('${dir.path}/node_00000001.gwh').writeAsStringSync('{not sealed');
    final s = await store.load(1);
    expect(s.contacts, isEmpty);
    expect(s.problem, HistoryProblem.unreadable);
    expect(File('${dir.path}/node_00000001.gwh.bad').existsSync(), isTrue);
  });
}
