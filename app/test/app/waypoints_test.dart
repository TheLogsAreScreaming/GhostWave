// Waypoints through the controller: ours are sent as one DM or channel post,
// edits go to the same place with the same ID, a delete sends a removal;
// received ones land in the book (and only their sender can change them), the
// hidden flag and the whole book survive a restart in the encrypted history,
// and the notification reads as a waypoint.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/mesh_alerts.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/waypoint_actions.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/waypoints.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';
import '../link/fake_node.dart';
import 'mesh_controller_test.dart' show answeringNode, bob, settle;
import 'phone_qol_test.dart' show RecordingAlerts;

void main() {
  late Directory dir;
  late SharedPreferences prefs;
  late RecordingAlerts alerts;

  Future<ProviderContainer> make() async {
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir, testHistoryKeys)),
        meshAlertsProvider.overrideWithValue(alerts),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 14, 9)),
      ],
    );
    c.listen(meshProvider, (_, _) {});
    return c;
  }

  /// A 1.1 node with bob as a contact and the channel "crew".
  Future<FakeNode> connect(ProviderContainer c) async {
    final node = answeringNode(
      contacts: [pb.Contact(nodeId: bob, name: 'bob'.codeUnits)],
    )..protocolMinor = 1;
    node.onRequest.listen((e) {
      final (conn, r) = e;
      switch (r.whichRequest()) {
        case pb.ToRadio_Request.listChannels:
          conn.send(
            pb.FromRadio(
              reqId: r.reqId,
              channel: pb.Channel(name: 'crew', psk: List<int>.filled(32, 7)),
            ),
          );
          conn.send(pb.FromRadio(reqId: r.reqId, channelsEnd: pb.ChannelsEnd(count: 1)));
        case pb.ToRadio_Request.sendChannelText:
          final s = r.sendChannelText;
          conn.send(
            pb.FromRadio(
              reqId: r.reqId,
              sendQueued: pb.SendQueued(
                dest: 0xFFFFFFFF,
                msgId: 0x7000 + s.clientMsgId % 1000,
                clientMsgId: s.clientMsgId,
              ),
            ),
          );
        default:
          break;
      }
    });
    c.read(nodeLinkProvider).connect(node);
    for (var i = 0; i < 200 && c.read(meshProvider).nodeId == null; i++) {
      await settle();
    }
    await settle();
    return node;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-wp.');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    alerts = RecordingAlerts();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  List<String> dmTexts(FakeNode n) => [
    for (final r in n.requests)
      if (r.hasSendText()) utf8.decode(r.sendText.text),
  ];
  List<String> channelTexts(FakeNode n) => [
    for (final r in n.requests)
      if (r.hasSendChannelText()) utf8.decode(r.sendChannelText.text),
  ];

  test('ours to a contact: sent, edited with the same ID, deleted with a removal', () async {
    final c = await make();
    addTearDown(c.dispose);
    final n = await connect(c);
    final wp = c.read(waypointActionsProvider);
    final w = await wp.create(
      kind: WaypointKind.camp,
      name: 'Low camp',
      pos: const LatLon(45.5, -110.25),
      note: 'flat spot',
      to: const ToContact(bob),
    );
    await settle();
    expect(dmTexts(n).single, '[WP ${w.id} camp] Low camp · 45.50000,-110.25000 · flat spot');
    expect(c.read(meshProvider).waypoints.byKey[w.key]!.peer, bob);

    await wp.edit(w.key, name: 'High camp', kind: WaypointKind.meet);
    await settle();
    expect(dmTexts(n).last, '[WP ${w.id} meet] High camp · 45.50000,-110.25000 · flat spot');
    expect(c.read(meshProvider).waypoints.byKey[w.key]!.name, 'High camp');

    await wp.delete(w.key);
    await settle();
    expect(dmTexts(n).last, '[WP ${w.id} removed] High camp');
    expect(c.read(meshProvider).waypoints.isEmpty, isTrue);
    expect(dmTexts(n), hasLength(3));
  });

  test('kept on this phone: nothing is sent until shared; sharing to a channel', () async {
    final c = await make();
    addTearDown(c.dispose);
    final n = await connect(c);
    final wp = c.read(waypointActionsProvider);
    final w = await wp.create(kind: WaypointKind.water, name: 'Spring', pos: const LatLon(1, 2));
    await wp.edit(w.key, note: 'slow trickle');
    await settle();
    expect(dmTexts(n), isEmpty);
    expect(channelTexts(n), isEmpty);
    await wp.share(w.key, const ToChannel('crew'));
    await settle();
    expect(channelTexts(n).single, '[WP ${w.id} water] Spring · 1.00000,2.00000 · slow trickle');
    expect(c.read(meshProvider).waypoints.byKey[w.key]!.channel, 'crew');
    expect(c.read(meshProvider).channelMessages['crew']!.single.outgoing, isTrue);
  });

  test('a note too long for the radio is cut, and the saved pin matches what was sent', () async {
    final c = await make();
    addTearDown(c.dispose);
    final n = await connect(c);
    final w = await c
        .read(waypointActionsProvider)
        .create(
          kind: WaypointKind.hazard,
          name: 'Bees',
          pos: const LatLon(1, 2),
          note: 'x' * 120,
          to: const ToContact(bob),
        );
    await settle();
    final sent = dmTexts(n).single;
    expect(utf8.encode(sent).length, lessThanOrEqualTo(kWaypointDefaultDmBytes));
    expect((parseWaypoint(sent)! as WaypointPut).note, w.note);
    expect(w.note.length, lessThan(120));
  });

  test('received: DM and channel pins land in the book; only the sender edits or removes', () async {
    final c = await make();
    addTearDown(c.dispose);
    final n = await connect(c);
    c.read(appForegroundProvider.notifier).set(foreground: false);
    void dm(int msgId, String t) => n.last.send(
      pb.FromRadio(
        text: pb.TextMessage(src: bob, msgId: msgId, text: utf8.encode(t)),
      ),
    );
    void post(int src, int msgId, String t) => n.last.send(
      pb.FromRadio(
        channelMessage: pb.ChannelMessage(channel: 'crew', src: src, msgId: msgId, text: utf8.encode(t)),
      ),
    );
    dm(1, '[WP 0a0a water] Spring · 45.00000,-110.00000 · cold');
    post(0xC0C0C0C0, 2, '[WP 0a0a hazard] Bees · 45.10000,-110.10000');
    post(n.nodeId, 3, '[WP 0a0a parking] Echo of ours · 1.00000,2.00000');
    await settle();
    var book = c.read(meshProvider).waypoints;
    expect(book.byKey.keys.toSet(), {waypointKey(bob, '0a0a'), waypointKey(0xC0C0C0C0, '0a0a')});
    final spring = book.byKey[waypointKey(bob, '0a0a')]!;
    expect((spring.kind, spring.note, spring.peer, spring.mine), (WaypointKind.water, 'cold', bob, false));
    expect(book.byKey[waypointKey(0xC0C0C0C0, '0a0a')]!.channel, 'crew');
    expect(alerts.shown, contains('text bob: Waypoint: Water · Spring'));
    expect(alerts.shown.any((s) => s.contains('Waypoint: Hazard · Bees')), isTrue);

    // someone else's removal with the same ID changes nothing of bob's
    post(0xC0C0C0C0, 4, '[WP 0a0a removed] Bees');
    dm(5, '[WP 0a0a water] Spring moved · 45.20000,-110.00000');
    await settle();
    book = c.read(meshProvider).waypoints;
    expect(book.byKey.keys, [waypointKey(bob, '0a0a')]);
    expect(book.byKey.values.single.pos.lat, closeTo(45.2, 1e-9));
    expect(alerts.shown.any((s) => s.endsWith('Waypoint removed: Bees')), isTrue);
  });

  test('hidden flag and the whole book survive a restart (encrypted history)', () async {
    var c = await make();
    var n = await connect(c);
    final mine = await c
        .read(waypointActionsProvider)
        .create(kind: WaypointKind.camp, name: 'Base', pos: const LatLon(3, 4), to: const ToContact(bob));
    n.last.send(
      pb.FromRadio(
        text: pb.TextMessage(src: bob, msgId: 9, text: utf8.encode('[WP beef other] Cairn · 5.00000,6.00000')),
      ),
    );
    await settle();
    c.read(waypointActionsProvider).setHidden(waypointKey(bob, 'beef'), true);
    c.read(meshProvider.notifier).flush();
    await c.read(meshStoreProvider)!.idle;
    c.dispose();

    final raw = File('${dir.path}/node_${n.nodeId.toRadixString(16).padLeft(8, '0')}.gwh').readAsBytesSync();
    expect(utf8.decode(raw, allowMalformed: true), isNot(contains('Cairn')), reason: 'sealed, not plain JSON');

    c = await make();
    addTearDown(c.dispose);
    n = await connect(c);
    final book = c.read(meshProvider).waypoints;
    expect(book.byKey[mine.key]!.name, 'Base');
    expect(book.byKey[mine.key]!.peer, bob);
    expect(book.byKey[waypointKey(bob, 'beef')]!.hidden, isTrue);
  });

  test('others\' pins can be hidden or forgotten, never edited or deleted as ours', () async {
    final c = await make();
    addTearDown(c.dispose);
    final n = await connect(c);
    n.last.send(
      pb.FromRadio(
        text: pb.TextMessage(src: bob, msgId: 9, text: utf8.encode('[WP beef other] Cairn · 5.00000,6.00000')),
      ),
    );
    await settle();
    final key = waypointKey(bob, 'beef');
    final wp = c.read(waypointActionsProvider);
    expect(await wp.edit(key, name: 'Mine now'), isNull);
    await wp.delete(key);
    await wp.share(key, const ToChannel('crew'));
    await settle();
    expect(c.read(meshProvider).waypoints.byKey[key]!.name, 'Cairn');
    expect(dmTexts(n), isEmpty);
    expect(channelTexts(n), isEmpty);
    wp.forget(key);
    expect(c.read(meshProvider).waypoints.isEmpty, isTrue);
  });
}
