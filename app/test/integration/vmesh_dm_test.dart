// Integration test against real GhostWave daemons on the UDP virtual radio,
// like GhostWave's vmesh_lan.sh / clientlink_e2e.sh: two nodes 1.5 km apart,
// each with --client-tcp on loopback, driven only through this app's link
// code. A's client DMs B's client and gets Delivered.
//
// Runs only where ghostwaved is available: set GHOSTWAVED=/path/to/ghostwaved,
// or build it in this repo (../firmware/build/ghostwaved, from app/), or have
// `ghostwaved` on PATH. Skipped otherwise. Optional env:
//   GW_MCAST_PORT  multicast port (default 47760)
//   GW_TCP_PORT    first client port (default 47830; uses 2)
//   VMESH_IF       multicast interface address, e.g. 127.0.0.1
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
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
import 'package:ghostwave_app/src/link/geo.dart';
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/link/transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/history_keys.dart';

String? findGhostwaved() {
  final env = Platform.environment['GHOSTWAVED'];
  if (env != null && env.isNotEmpty) return File(env).existsSync() ? env : null;
  // The daemon from this repo's own firmware tree (tests run with cwd = app/).
  final inTree = File('../firmware/build/ghostwaved');
  if (inTree.existsSync()) return inTree.absolute.path;
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    final f = File('$dir/ghostwaved');
    if (dir.isNotEmpty && f.existsSync()) return f.path;
  }
  return null;
}

class Daemon {
  Daemon._(this.name, this.process, this.port);

  final String name;
  final Process process;
  final int port;
  final StringBuffer log = StringBuffer();
  final Completer<void> ready = Completer<void>();

  static Future<Daemon> start(
    String bin,
    Directory work,
    String name,
    double km,
    int mcast,
    int port, {
    String? pin,
  }) async {
    final lat = (46.87 + km * 0.0089932).toStringAsFixed(7);
    final args = [
      '--radio', 'udp', '--mcast', '239.77.0.1:$mcast', '--key', '${work.path}/$name.key', //
      '--name', name, '--lat', lat, '--lon', '-113.99', '--client-tcp', '127.0.0.1:$port',
      if (pin != null) ...['--client-pin', pin],
      if (Platform.environment['VMESH_IF'] case final vif?) ...['--vif', vif],
    ];
    final p = await Process.start(bin, args, workingDirectory: work.path);
    final d = Daemon._(name, p, port);
    void onLine(String line) {
      d.log.writeln(line);
      if (line.startsWith('client link on tcp') && !d.ready.isCompleted) d.ready.complete();
    }

    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
    // stdin stays open (the daemon reads commands from it), like the FIFO in vmesh_lan.sh
    return d;
  }

  void stop() => process.kill();
}

Future<T> firstWhere<T>(
  Stream<pb.FromRadio> s,
  bool Function(pb.FromRadio) test,
  T Function(pb.FromRadio) pick,
  Duration timeout,
) => s.firstWhere(test).then(pick).timeout(timeout);

void main() {
  final bin = findGhostwaved();

  test(
    'the app and a real node agree keys from the PIN and talk over the encrypted link',
    () async {
      final mcast = (int.tryParse(Platform.environment['GW_MCAST_PORT'] ?? '') ?? 47760) + 20;
      final tcp = (int.tryParse(Platform.environment['GW_TCP_PORT'] ?? '') ?? 47830) + 20;
      final work = await Directory.systemTemp.createTemp('gwapp-pin.');
      final d = await Daemon.start(bin!, work, 'P', 0, mcast, tcp, pin: '424242');
      addTearDown(() async {
        d.stop();
        await work.delete(recursive: true);
      });
      await d.ready.future.timeout(const Duration(seconds: 10));
      final transport = TcpTransport(TcpAddress('127.0.0.1', tcp));

      final wrong = LinkSession(await transport.open());
      await expectLater(wrong.hello('wrong', pinFor: () async => '000000'), throwsA(isA<NodeError>()));
      expect(wrong.isEncrypted, isFalse);
      await wrong.close();

      final s = LinkSession(await transport.open());
      addTearDown(s.close);
      final info = await s.hello('right', pinFor: () async => '424242', requireEncrypted: true);
      expect(s.isEncrypted, isTrue);
      expect(info.protocolMinor, 3);
      final status = await s.request(pb.ToRadio(getStatus: pb.GetStatus()));
      expect(status.hasStatus(), isTrue);
      expect(s.isClosed, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
    skip: bin == null ? 'ghostwaved not found: set GHOSTWAVED to run this test' : false,
  );

  test(
    'two app clients exchange a DM over the virtual mesh and get Delivered',
    () async {
      final mcast = int.tryParse(Platform.environment['GW_MCAST_PORT'] ?? '') ?? 47760;
      final tcp = int.tryParse(Platform.environment['GW_TCP_PORT'] ?? '') ?? 47830;
      final work = await Directory.systemTemp.createTemp('gwapp-vmesh.');
      final daemons = <Daemon>[];
      final links = <NodeLink>[];
      addTearDown(() async {
        for (final l in links) {
          await l.dispose();
        }
        for (final d in daemons) {
          d.stop();
        }
        await work.delete(recursive: true);
      });
      try {
        daemons.add(await Daemon.start(bin!, work, 'A', 0, mcast, tcp));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        daemons.add(await Daemon.start(bin, work, 'B', 1.5, mcast, tcp + 1));
        for (final d in daemons) {
          await d.ready.future.timeout(const Duration(seconds: 10));
        }

        Future<(NodeLink, LinkUp)> up(int port, String name) async {
          final link = NodeLink(clientName: name);
          links.add(link);
          final first = link.states.firstWhere((s) => s is LinkUp);
          link.connect(TcpTransport(TcpAddress('127.0.0.1', port)));
          return (link, await first.timeout(const Duration(seconds: 10)) as LinkUp);
        }

        final (linkA, upA) = await up(tcp, 'app test A');
        final (linkB, upB) = await up(tcp + 1, 'app test B');
        final a = upA.session;
        final b = upB.session;
        expect(upA.info.protocolVersion, 1);
        expect(upA.info.name, utf8.encode('A'));
        expect(upA.info.ed25519Pub, hasLength(32));
        expect(upA.info.maxTextBytes, 73);

        // what a QR scan does, both ways
        await a.request(
          pb.ToRadio(
            addContact: pb.AddContact(nodeId: upB.info.nodeId, ed25519Pub: upB.info.ed25519Pub, name: 'Bee'),
          ),
        );
        await b.request(
          pb.ToRadio(
            addContact: pb.AddContact(nodeId: upA.info.nodeId, ed25519Pub: upA.info.ed25519Pub, name: 'Ay'),
          ),
        );
        final contacts = await a.listContacts();
        expect(contacts.any((c) => c.nodeId == upB.info.nodeId && c.pinned), isTrue);
        await a.request(
          pb.ToRadio(
            setKnownPosition: pb.SetKnownPosition(
              nodeId: upB.info.nodeId,
              pos: const LatLon(46.87 + 1.5 * 0.0089932, -113.99).toProto(),
            ),
          ),
        );

        // a key that does not hash to the ID is refused
        await expectLater(
          a.request(
            pb.ToRadio(
              addContact: pb.AddContact(nodeId: upB.info.nodeId, ed25519Pub: upA.info.ed25519Pub),
            ),
          ),
          throwsA(isA<NodeError>().having((e) => e.code, 'code', pb.Error_Code.KEY_REJECTED)),
        );

        await Future<void>.delayed(const Duration(seconds: 3)); // start-up beacons
        const cmid = 4242;
        final gotText = firstWhere(
          linkB.events,
          (e) => e.hasText() && e.text.src == upA.info.nodeId,
          (e) => e.text,
          const Duration(seconds: 60),
        );
        final gotDelivered = firstWhere(
          linkA.events,
          (e) => e.hasDelivered() && e.delivered.clientMsgId == cmid,
          (e) => e.delivered,
          const Duration(seconds: 60),
        );
        final q = await a.request(
          pb.ToRadio(
            sendText: pb.SendText(dest: upB.info.nodeId, text: utf8.encode('hello B, from the app'), clientMsgId: cmid),
          ),
        );
        expect(q.sendQueued.clientMsgId, cmid);
        expect(q.sendQueued.msgId, isNot(0));

        final text = await gotText;
        expect(utf8.decode(text.text), 'hello B, from the app');
        expect(text.msgId, q.sendQueued.msgId);
        final delivered = await gotDelivered;
        expect(delivered.dest, upB.info.nodeId);
        expect(delivered.msgId, q.sendQueued.msgId);

        final st = await a.request(pb.ToRadio(getStatus: pb.GetStatus()));
        expect(st.status.clients, 1);
        expect(st.status.tx, greaterThan(0));
      } on Object {
        for (final d in daemons) {
          // ignore: avoid_print
          print('--- ${d.name} log\n${d.log}');
        }
        rethrow;
      }
    },
    skip: bin == null ? 'ghostwaved not found: set GHOSTWAVED to run this test' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'full app stack: two MeshControllers add each other by card, DM shows sent then delivered',
    () async {
      final mcast = (int.tryParse(Platform.environment['GW_MCAST_PORT'] ?? '') ?? 47760) + 1;
      final tcp = (int.tryParse(Platform.environment['GW_TCP_PORT'] ?? '') ?? 47830) + 2;
      final work = await Directory.systemTemp.createTemp('gwapp-vmesh2.');
      final daemons = <Daemon>[];
      final containers = <ProviderContainer>[];
      addTearDown(() async {
        for (final c in containers) {
          c.dispose();
        }
        for (final d in daemons) {
          d.stop();
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await work.delete(recursive: true);
      });
      try {
        daemons.add(await Daemon.start(bin!, work, 'A', 0, mcast, tcp));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        daemons.add(await Daemon.start(bin, work, 'B', 1.5, mcast, tcp + 1));
        for (final d in daemons) {
          await d.ready.future.timeout(const Duration(seconds: 10));
        }
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        Future<ProviderContainer> app(String name, int port) async {
          final store = Directory('${work.path}/app_$name')..createSync();
          final c = ProviderContainer(
            overrides: [
              sharedPrefsProvider.overrideWithValue(prefs),
              meshStoreProvider.overrideWithValue(MeshStore(store, testHistoryKeys)),
            ],
          );
          containers.add(c);
          c.listen(meshProvider, (_, _) {});
          c.listen(nodeInfoProvider, (_, _) {}); // unlistened providers pause
          c.read(nodeLinkProvider).connect(TcpTransport(TcpAddress('127.0.0.1', port)));
          for (var i = 0; i < 100 && c.read(nodeInfoProvider) == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return c;
        }

        final a = await app('A', tcp);
        final b = await app('B', tcp + 1);
        final infoA = a.read(nodeInfoProvider)!;
        final infoB = b.read(nodeInfoProvider)!;

        // the QR exchange: each app parses the other's encoded card
        ContactCard cardOf(pb.NodeInfo i, String name) => ContactCard.tryParse(
          ContactCard(nodeId: i.nodeId, ed25519Pub: Uint8List.fromList(i.ed25519Pub), name: name).encode(),
        )!;
        await a.read(meshProvider.notifier).addContact(cardOf(infoB, 'Bee'));
        await b.read(meshProvider.notifier).addContact(cardOf(infoA, 'Ay'));
        expect(a.read(meshProvider).contacts[infoB.nodeId]!.pinned, isTrue);

        await Future<void>.delayed(const Duration(seconds: 3));
        await a.read(meshProvider.notifier).sendText(infoB.nodeId, 'from the app UI layer');
        expect(a.read(meshProvider).messages[infoB.nodeId]!.single.state, MsgState.sent);

        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (DateTime.now().isBefore(deadline) &&
            (a.read(meshProvider).messages[infoB.nodeId]!.single.state != MsgState.delivered ||
                (b.read(meshProvider).messages[infoA.nodeId] ?? const []).isEmpty)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(a.read(meshProvider).messages[infoB.nodeId]!.single.state, MsgState.delivered);
        final got = b.read(meshProvider).messages[infoA.nodeId]!.single;
        expect(got.text, 'from the app UI layer');
        expect(got.outgoing, isFalse);
        expect(b.read(meshProvider).unread[infoA.nodeId], 1);
      } on Object {
        for (final d in daemons) {
          // ignore: avoid_print
          print('--- ${d.name} log\n${d.log}');
        }
        rethrow;
      }
    },
    skip: bin == null ? 'ghostwaved not found: set GHOSTWAVED to run this test' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
