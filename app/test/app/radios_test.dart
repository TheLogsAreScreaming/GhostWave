// Several radios: remembering, switching, renaming, forgetting, and keeping
// each radio's history apart.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/background_link.dart';
import 'package:ghostwave_app/src/app/backup.dart';
import 'package:ghostwave_app/src/app/mesh_controller.dart';
import 'package:ghostwave_app/src/app/providers.dart';
import 'package:ghostwave_app/src/app/radios.dart';
import 'package:ghostwave_app/src/data/backup_codec.dart';
import 'package:ghostwave_app/src/data/mesh_store.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/link/transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/fake_node.dart';
import '../support/history_keys.dart';

const int alice = 0x0A0A0A0A;
const String addrA = '10.0.0.1:47800';
const String addrB = '10.0.0.2:47800';

Future<void> settle() => pumpEventQueue(times: 60);

void main() {
  late Directory dir;
  late MeshStore store;
  late MemoryPinStore pins;
  late FakeNode radioA;
  late FakeNode radioB;
  var now = DateTime(2026, 11, 14, 9);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gwapp-radios.');
    store = MeshStore(dir, testHistoryKeys);
    pins = MemoryPinStore();
    radioA = answering(0x11223344)
      ..name = 'Base'
      ..firmware = 'ghostwave-heltec_v3 0.1.0-dev.11';
    radioB = answering(0x55667788)
      ..name = 'Pack'
      ..firmware = 'ghostwave-rak3401_1w 0.1.0-dev.11';
    now = DateTime(2026, 11, 14, 9);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<ProviderContainer> container([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        meshStoreProvider.overrideWithValue(store),
        pinStoreProvider.overrideWithValue(pins),
        clockProvider.overrideWithValue(() => now),
        transportFactoryProvider.overrideWithValue((TcpAddress a) => a.toString() == addrA ? radioA : radioB),
        backupFilesProvider.overrideWithValue(FakeFiles()),
        backupKdfProvider.overrideWithValue(const BackupKdf(memoryKiB: 64, iterations: 1, parallelism: 1)),
      ],
    );
    addTearDown(c.dispose);
    c
      ..listen(meshProvider, (_, _) {})
      ..listen(radiosProvider, (_, _) {})
      ..listen(nodeAddressProvider, (_, _) {});
    return c;
  }

  Future<void> connect(ProviderContainer c, String address) async {
    await c.read(nodeAddressProvider.notifier).connectAddress(address);
    await settle();
  }

  group('SavedRadio', () {
    test('board names come from the firmware string', () {
      expect(boardFromFirmware('ghostwave-heltec_v3 0.1.0-dev.11'), 'Heltec V3');
      expect(boardFromFirmware('ghostwave-rak3401_1w 0.1.0'), 'RAK3401 1 W');
      expect(boardFromFirmware('ghostwave-t1000e 0.1.0'), 'T1000-E');
      expect(boardFromFirmware('ghostwave-new_board 1'), 'new board');
      expect(boardFromFirmware('pi-daemon 1.0'), isNull);
      expect(boardFromFirmware('ghostwave-'), isNull);
    });

    test('JSON round trip keeps every field; junk is dropped', () {
      final r = SavedRadio(
        address: 'ble:AA:BB:CC:DD:EE:FF|GhostWave-a11b',
        nickname: 'Truck',
        nodeName: 'N1',
        nodeId: 0x9d66916b,
        firmware: 'ghostwave-t1000e 0.1.0',
        lastConnected: DateTime(2026, 11, 14, 8, 30),
      );
      final back = SavedRadio.tryFromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(back.address, r.address);
      expect(back.nickname, 'Truck');
      expect(back.nodeName, 'N1');
      expect(back.nodeId, 0x9d66916b);
      expect(back.board, 'T1000-E');
      expect(back.bluetoothId, 'AA:BB:CC:DD:EE:FF');
      expect(back.lastConnected, r.lastConnected);
      expect(back.displayName, 'Truck');
      expect(SavedRadio.tryFromJson({'a': 5}), isNull);
      expect(SavedRadio.tryFromJson('x'), isNull);
    });

    test('display name falls back to node name, advertised name, then ID', () {
      expect(const SavedRadio(address: 'ble:1|GhostWave-a11b').displayName, 'GhostWave-a11b');
      expect(const SavedRadio(address: addrA, nodeId: 0x11223344).displayName, '11223344');
      expect(const SavedRadio(address: addrA, nodeName: 'Base').displayName, 'Base');
      expect(const SavedRadio(address: addrA).displayName, addrA);
    });
  });

  test('each radio is remembered with its name, ID, board and time', () async {
    final c = await container();
    await connect(c, addrA);
    now = now.add(const Duration(hours: 1));
    await c.read(radiosProvider.notifier).switchTo(addrB);
    await settle();
    final list = c.read(radiosProvider);
    expect(list.map((r) => r.address), [addrB, addrA], reason: 'most recent first');
    expect(list.first.nodeName, 'Pack');
    expect(list.first.nodeId, 0x55667788);
    expect(list.first.board, 'RAK3401 1 W');
    expect(list.first.lastConnected, now);
    expect(list.last.board, 'Heltec V3');
    expect(c.read(activeRadioProvider)!.address, addrB);
  });

  test('the list survives a restart; a damaged one is ignored', () async {
    final c = await container();
    await connect(c, addrA);
    c.read(radiosProvider.notifier).rename(addrA, 'Base camp');
    final saved = c.read(sharedPrefsProvider).getString(RadiosNotifier.key)!;
    final c2 = await container({RadiosNotifier.key: saved});
    final r = c2.read(radiosProvider).single;
    expect(r.nickname, 'Base camp');
    expect(r.nodeId, radioA.nodeId);
    expect(r.board, 'Heltec V3');
    final c3 = await container({RadiosNotifier.key: '{oops'});
    expect(c3.read(radiosProvider), isEmpty);
  });

  test('first start after the update lists radios from the recent nodes', () async {
    final c = await container({
      'recent_nodes': jsonEncode([
        {'a': addrA, 't': 1000, 'n': 'Base', 'id': 0x11223344},
        {'a': '10.0.0.9:47800', 't': 900}, // never answered: not a radio
      ]),
    });
    final r = c.read(radiosProvider).single;
    expect(r.address, addrA);
    expect(r.nodeName, 'Base');
  });

  test('switching lets go of the old radio and shows only the new one\'s history', () async {
    final c = await container();
    await connect(c, addrA);
    radioA.last.send(
      pb.FromRadio(
        text: pb.TextMessage(src: alice, msgId: 1, text: 'hi from A'.codeUnits),
      ),
    );
    await settle();
    expect(c.read(meshProvider).messages[alice], hasLength(1));
    final connA = radioA.last;

    await c.read(radiosProvider.notifier).switchTo(addrB);
    expect(connA.closed, isTrue, reason: 'old radio disconnected before the new one opens');
    await settle();
    expect(c.read(nodeLinkProvider).state, isA<LinkUp>());
    expect((c.read(nodeLinkProvider).state as LinkUp).info.nodeId, radioB.nodeId);
    final onB = c.read(meshProvider);
    expect(onB.nodeId, radioB.nodeId);
    expect(onB.messages[alice], isNull, reason: 'A\'s chats are not shown on B');
    // auto-reconnect at the next start follows the active radio
    expect(c.read(sharedPrefsProvider).getString('node_address'), addrB);

    await c.read(radiosProvider.notifier).switchTo(addrA);
    await settle();
    expect(c.read(meshProvider).nodeId, radioA.nodeId);
    expect(c.read(meshProvider).messages[alice]!.single.text, 'hi from A');
    // each history is in its own file, sealed for its own node ID
    expect((await store.exportAll()).keys, unorderedEquals(['11223344', '55667788']));
  });

  test('a message typed while switching waits in the new radio\'s outbox', () async {
    final c = await container();
    await connect(c, addrA);
    await c.read(radiosProvider.notifier).switchTo(addrB);
    await settle();
    await c.read(radiosProvider.notifier).switchTo(addrA);
    await settle();
    // B is shown as soon as the switch starts, before it answers
    radioB.failOpens = 100;
    await c.read(radiosProvider.notifier).switchTo(addrB);
    expect(c.read(meshProvider).nodeId, radioB.nodeId);
    await c.read(meshProvider.notifier).sendText(alice, 'via B');
    expect(c.read(meshProvider).messages[alice]!.single.state, MsgState.pending);
    c.read(meshProvider.notifier).flush();
    await store.idle;
    final onA = await store.load(radioA.nodeId);
    expect(onA.messages[alice], isNull, reason: 'nothing leaked into A\'s history');
    final onB = await store.load(radioB.nodeId);
    expect(onB.messages[alice]!.single.text, 'via B');
  });

  test('loading a history waits for a save still being written', () async {
    final saving = store.save(0x11223344, const StoredMesh(drafts: {alice: 'unsent'}));
    final got = await store.load(0x11223344);
    await saving;
    expect(got.drafts[alice], 'unsent');
  });

  test('tapping the active, connected radio does nothing', () async {
    final c = await container();
    await connect(c, addrA);
    final opens = radioA.opens;
    await c.read(radiosProvider.notifier).switchTo(addrA);
    await settle();
    expect(radioA.opens, opens);
  });

  test('rename sets, trims, caps and clears the nickname', () async {
    final c = await container();
    await connect(c, addrA);
    final n = c.read(radiosProvider.notifier)..rename(addrA, '  Truck  ');
    expect(c.read(radiosProvider).single.displayName, 'Truck');
    n.rename(addrA, 'x' * 50);
    expect(c.read(radiosProvider).single.nickname, hasLength(kRadioNicknameMax));
    n.rename(addrA, '');
    expect(c.read(radiosProvider).single.displayName, 'Base');
  });

  test('forgetting the active radio disconnects it and stops reconnecting', () async {
    final c = await container();
    await pins.write(addrA, '123456');
    await connect(c, addrA);
    await c.read(radiosProvider.notifier).forget(addrA);
    await settle();
    expect(c.read(radiosProvider), isEmpty);
    expect(c.read(nodeLinkProvider).state, isA<LinkIdle>());
    expect(c.read(nodeAddressProvider), isNull);
    expect(c.read(sharedPrefsProvider).getString('node_address'), isNull);
    expect(c.read(recentNodesProvider).where((r) => r.address == addrA), isEmpty);
    expect(await pins.read(addrA), isNull);
    // its history stays unless asked
    c.read(meshProvider.notifier).flush();
    expect((await store.exportAll()).keys, ['11223344']);
  });

  test('forgetting another radio with its history deletes only that history', () async {
    final c = await container();
    await connect(c, addrA);
    await c.read(radiosProvider.notifier).switchTo(addrB);
    await settle();
    c.read(meshProvider.notifier).flush();
    await store.idle;
    expect((await store.exportAll()).keys, hasLength(2));
    await c.read(radiosProvider.notifier).forget(addrA, deleteHistory: true);
    expect(c.read(radiosProvider).single.address, addrB);
    expect(c.read(nodeLinkProvider).state, isA<LinkUp>(), reason: 'the active radio stays connected');
    expect((await store.exportAll()).keys, ['55667788']);
  });

  test('backup carries the radio list and restore brings it back', () async {
    final c = await container();
    await connect(c, addrA);
    c.read(radiosProvider.notifier).rename(addrA, 'Base camp');
    final backup = c.read(backupProvider);
    expect(await backup.create('correct horse battery'), isTrue);
    final file = (c.read(backupFilesProvider) as FakeFiles).saved!;
    await c.read(radiosProvider.notifier).forget(addrA);
    expect(c.read(radiosProvider), isEmpty);
    await backup.restore(await backup.read(file, 'correct horse battery'));
    await settle();
    expect(c.read(radiosProvider).single.nickname, 'Base camp');
  });

  test('the background notification names the active radio by its nickname', () {
    final up = LinkUp(
      't',
      pb.NodeInfo(nodeId: 0x11223344, name: 'N1'.codeUnits),
      LinkSession(FakeConnection(FakeNode())),
    );
    expect(backgroundNoticeFor(up)!.text, 'N1');
    expect(backgroundNoticeFor(up, radio: 'Truck')!.text, 'Truck');
    expect(backgroundNoticeFor(const LinkConnecting('ble:1|GhostWave-a11b', 1), radio: 'Truck')!.text, 'Truck');
  });
}

/// A fake radio with node ID [id] that answers what the app asks on connect.
FakeNode answering(int id) {
  final node = FakeNode(nodeId: id);
  node.onRequest.listen((e) {
    final (c, r) = e;
    final req = r.reqId;
    switch (r.whichRequest()) {
      case pb.ToRadio_Request.listContacts:
        c.send(pb.FromRadio(reqId: req, contactsEnd: pb.ContactsEnd()));
      case pb.ToRadio_Request.getPosition:
        c.send(pb.FromRadio(reqId: req, position: pb.OwnPosition()));
      case pb.ToRadio_Request.getStatus:
        c.send(pb.FromRadio(reqId: req, status: pb.Status()));
      case pb.ToRadio_Request.sendText:
        c.send(
          pb.FromRadio(
            reqId: req,
            sendQueued: pb.SendQueued(dest: r.sendText.dest, msgId: 7, clientMsgId: r.sendText.clientMsgId),
          ),
        );
      default:
        break;
    }
  });
  return node;
}

class FakeFiles implements BackupFiles {
  Uint8List? saved;

  @override
  bool get supported => true;

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    saved = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => saved;
}
