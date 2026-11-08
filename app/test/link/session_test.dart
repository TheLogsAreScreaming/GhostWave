import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/frame_codec.dart';
import 'package:ghostwave_app/src/link/link_crypto.dart';
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';
import 'package:ghostwave_app/src/link/transport.dart';

import 'fake_node.dart';

void main() {
  group('LinkSession', () {
    test('Hello returns NodeInfo; req_ids count up and are echoed', () async {
      final node = FakeNode();
      final s = LinkSession(await node.open() as FakeConnection);
      final info = await s.hello('test');
      expect(info.nodeId, 0x11223344);
      expect(node.requests.single.hello.protocolVersion, 1);
      expect(node.requests.single.hello.clientName, 'test');

      node.onRequest.listen((e) {
        final (c, r) = e;
        if (r.hasGetStatus()) c.send(pb.FromRadio(reqId: r.reqId, status: pb.Status(tx: 5)));
      });
      final st = await s.request(pb.ToRadio(getStatus: pb.GetStatus()));
      expect(st.status.tx, 5);
      expect(node.requests.map((r) => r.reqId), [1, 2]);
      await s.close();
    });

    test('an Error reply throws NodeError', () async {
      final node = FakeNode();
      final s = LinkSession(await node.open() as FakeConnection);
      node.onRequest.listen((e) {
        final (c, r) = e;
        if (r.hasSendText()) {
          c.send(
            pb.FromRadio(
              reqId: r.reqId,
              error: pb.Error(code: pb.Error_Code.TOO_LONG),
            ),
          );
        }
      });
      await expectLater(
        s.request(pb.ToRadio(sendText: pb.SendText(dest: 1, text: List.filled(74, 1)))),
        throwsA(isA<NodeError>().having((e) => e.code, 'code', pb.Error_Code.TOO_LONG)),
      );
    });

    test('ListContacts collects Contact... until ContactsEnd', () async {
      final node = FakeNode();
      final s = LinkSession(await node.open() as FakeConnection);
      node.onRequest.listen((e) {
        final (c, r) = e;
        if (!r.hasListContacts()) return;
        c.send(pb.FromRadio(reqId: r.reqId, contact: pb.Contact(nodeId: 1)));
        c.send(pb.FromRadio(text: pb.TextMessage(src: 9))); // an event in between
        c.send(pb.FromRadio(reqId: r.reqId, contact: pb.Contact(nodeId: 2)));
        c.send(pb.FromRadio(reqId: r.reqId, contactsEnd: pb.ContactsEnd(count: 2)));
      });
      final events = <pb.FromRadio>[];
      s.events.listen(events.add);
      final list = await s.listContacts();
      expect(list.map((c) => c.nodeId), [1, 2]);
      expect(events.single.text.src, 9);
    });

    test('req_id 0 goes to events; replies to unknown req_ids too', () async {
      final node = FakeNode();
      final c = await node.open() as FakeConnection;
      final s = LinkSession(c);
      final events = <pb.FromRadio>[];
      s.events.listen(events.add);
      c.send(pb.FromRadio(replayed: true, text: pb.TextMessage(src: 1, msgId: 2)));
      c.send(pb.FromRadio(reqId: 999, ok: pb.Ok()));
      await pumpEventQueue();
      expect(events.length, 2);
      expect(events.first.replayed, isTrue);
    });

    test('garbage and undecodable bodies do not break the stream', () async {
      final node = FakeNode();
      final c = await node.open() as FakeConnection;
      final s = LinkSession(c);
      final events = <pb.FromRadio>[];
      s.events.listen(events.add);
      c.sendRaw([0, 1, 2, 0x94, 0xC3, 0xFF, 0xFF]); // garbage, bad length
      c.sendRaw([0x94, 0xC3, 0x03, 0x00, 0x01, 0x08, 0xFF]); // truncated varint: bad protobuf
      c.send(pb.FromRadio(neighbor: pb.Neighbor(nodeId: 4)));
      await pumpEventQueue();
      expect(events.single.neighbor.nodeId, 4);
      expect(s.isClosed, isFalse);
    });

    test('a frame with another version ends the session', () async {
      final node = FakeNode();
      final c = await node.open() as FakeConnection;
      final s = LinkSession(c);
      c.send(pb.FromRadio(ok: pb.Ok()), version: 2);
      expect(await s.done, contains('protocol version 2'));
    });

    test('pending requests fail when the link drops', () async {
      final node = FakeNode(autoHello: false);
      final c = await node.open() as FakeConnection;
      final s = LinkSession(c);
      final f = s.request(pb.ToRadio(getStatus: pb.GetStatus()));
      await c.drop();
      await expectLater(f, throwsA(isA<LinkClosedException>()));
      expect(s.isClosed, isTrue);
    });

    test('no reply times out', () {
      fakeAsync((fa) {
        late final LinkSession s;
        FakeNode(autoHello: false).open().then((c) => s = LinkSession(c));
        fa.flushMicrotasks();
        Object? err;
        s.request(pb.ToRadio(getStatus: pb.GetStatus())).catchError((Object e) {
          err = e;
          return pb.FromRadio();
        });
        fa.elapse(const Duration(seconds: 9));
        expect(err, isA<ReplyTimeoutException>());
      });
    });
  });

  group('PIN', () {
    String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

    test('handshake and sealing match the C++ golden vector', () async {
      final nonce = List<int>.generate(16, (i) => i);
      final a = List<int>.generate(32, (i) => 0x20 + i);
      final b = List<int>.generate(32, (i) => 0x40 + i);
      final ya = await linkShare('424242', nonce, a);
      final yb = await linkShare('424242', nonce, b);
      expect(hex(ya), '38bf4429b49432f20f593d21ee96447c298460e41229b556954b9ed5fd9c607f');
      expect(hex(yb), '2a9bc7b16628c651f031472d94e225e28c6588bcb734af4098518b4019159274');
      final keys = (await linkKeys(secret: b, theirShare: ya, nonce: nonce, serverShare: ya, clientShare: yb))!;
      expect(hex(keys.clientToNode), 'a0e4a8cb23d66cd1af1bd5994bed4459d222f81cca23aa512599386ef826fb72');
      expect(hex(keys.nodeToClient), '3bca5414128da4100632f07dbbdfba67910e4f9c5c9f6dcea0f7ab830a8abc3e');
      expect(hex(keys.confirm), '686c345c320e4de70c9fa8789b5735c6b5119ad7f68c23aa334074997e0b89b7');
      final tx = LinkCipher(keys.clientToNode)..seal(const [1]); // counter 0 used
      expect(hex(tx.seal('hello'.codeUnits)), 'cf671d1055de9274ad90eb49f9ef026827366b7a89');
    });

    test('a low-order share gives no keys', () async {
      final nonce = List<int>.filled(16, 1);
      final keys = await linkKeys(
        secret: List<int>.filled(32, 9),
        theirShare: List<int>.filled(32, 0),
        nonce: nonce,
        serverShare: List<int>.filled(32, 0),
        clientShare: List<int>.filled(32, 2),
      );
      expect(keys, isNull);
    });

    Future<(FakeNode, LinkSession)> pinSession() async {
      final node = FakeNode()..pin = '424242';
      final conn = await node.open() as FakeConnection;
      final s = LinkSession(conn);
      await s.hello('t', pinFor: () async => '424242');
      return (node, s);
    }

    test('after the PIN every frame is sealed, both ways', () async {
      final (node, s) = await pinSession();
      addTearDown(s.close);
      expect(s.isEncrypted, isTrue);
      final reply = s.request(pb.ToRadio(getStatus: pb.GetStatus()));
      await pumpEventQueue();
      expect(node.last.plainAfterKeys, 0);
      expect(node.last.badFrames, 0);
      expect(node.requests.last.hasGetStatus(), isTrue);
      node.last.send(pb.FromRadio(reqId: node.requests.last.reqId, status: pb.Status()));
      await reply;
    });

    test('a wrong PIN is refused and the link stays unencrypted', () async {
      final node = FakeNode()..pin = '424242';
      final s = LinkSession(await node.open());
      addTearDown(s.close);
      await expectLater(s.hello('t', pinFor: () async => '000000'), throwsA(isA<NodeError>()));
      expect(s.isEncrypted, isFalse);
    });

    test('an unencrypted frame on an encrypted link ends it', () async {
      final (node, s) = await pinSession();
      node.last.sendRaw(encodeFrame(pb.FromRadio(status: pb.Status()).writeToBuffer()));
      expect(await s.done, contains('unencrypted'));
    });

    test('a changed frame on an encrypted link ends it', () async {
      final (node, s) = await pinSession();
      final sealed = node.last.tx!.seal(pb.FromRadio(status: pb.Status()).writeToBuffer())..[0] ^= 1;
      node.last.sendRaw(encodeFrame(sealed, version: kSecureVersion));
      expect(await s.done, contains('check'));
    });

    test('a replayed frame on an encrypted link ends it', () async {
      final (node, s) = await pinSession();
      final frame = encodeFrame(
        node.last.tx!.seal(pb.FromRadio(status: pb.Status()).writeToBuffer()),
        version: kSecureVersion,
      );
      node.last.sendRaw(frame);
      node.last.sendRaw(frame);
      expect(await s.done, contains('check'));
    });

    test('a node that answers the proof in clear is refused', () async {
      final node = FakeNode(autoHello: false);
      final sub = node.onRequest.listen((e) async {
        final (c, r) = e;
        if (r.hello.pinProof.isEmpty) {
          final nonce = List<int>.filled(16, 1);
          c.send(
            pb.FromRadio(
              reqId: r.reqId,
              pinChallenge: pb.PinChallenge(nonce: nonce, serverShare: await linkShare('1', nonce, List.filled(32, 7))),
            ),
          );
        } else {
          c.send(pb.FromRadio(reqId: r.reqId, nodeInfo: node.info));
        }
      });
      addTearDown(sub.cancel);
      final s = LinkSession(await node.open());
      await expectLater(s.hello('t', pinFor: () async => '1'), throwsA(isA<LinkClosedException>()));
      expect(await s.done, contains('did not encrypt'));
    });

    test('a challenge with no share (older node) is refused, no proof is sent', () async {
      final node = FakeNode()
        ..pin = '424242'
        ..oldChallenge = true;
      final s = LinkSession(await node.open());
      addTearDown(s.close);
      await expectLater(s.hello('t', pinFor: () async => '424242'), throwsA(isA<TransportFatalException>()));
      expect(node.requests.where((r) => r.hello.pinProof.isNotEmpty), isEmpty);
    });

    test('where encryption is required, a plain node is refused', () async {
      final s = LinkSession(await FakeNode().open());
      addTearDown(s.close);
      await expectLater(s.hello('t', requireEncrypted: true), throwsA(isA<TransportFatalException>()));
    });

    test('TCP needs encryption except on loopback', () {
      expect(TcpTransport(const TcpAddress('192.168.1.20', 47800)).needsEncryption, isTrue);
      expect(TcpTransport(const TcpAddress('node.lan', 47800)).needsEncryption, isTrue);
      expect(TcpTransport(const TcpAddress('127.0.0.1', 47800)).needsEncryption, isFalse);
      expect(TcpTransport(const TcpAddress('::1', 47800)).needsEncryption, isFalse);
      expect(TcpTransport(const TcpAddress('localhost', 47800)).needsEncryption, isFalse);
    });

    test('a PIN node with no saved PIN waits for the user, without retrying', () {
      fakeAsync((fa) {
        final node = FakeNode()..pin = '424242';
        final link = NodeLink();
        link.connect(node);
        fa.flushMicrotasks();
        expect(link.state, isA<LinkNeedsPin>());
        expect((link.state as LinkNeedsPin).wrong, isFalse);
        fa.elapse(const Duration(minutes: 2));
        expect(node.opens, 1, reason: 'no guessing loop');
        link.dispose();
      });
    });

    test('the saved PIN is used; a wrong one is dropped and reported', () {
      fakeAsync((fa) {
        final saved = <String, String>{};
        final node = FakeNode()..pin = '424242';
        final link = NodeLink()
          ..pinFor = ((t) async => saved[t])
          ..onBadPin = ((t) async => saved.remove(t));
        saved[node.label] = '111111';
        link.connect(node);
        fa.flushMicrotasks();
        expect((link.state as LinkNeedsPin).wrong, isTrue);
        expect(saved, isEmpty);
        fa.elapse(const Duration(minutes: 1));
        expect(node.opens, 1);

        saved[node.label] = '424242';
        link.retryNow();
        fa.flushMicrotasks();
        expect(link.state, isA<LinkUp>());
        link.dispose();
      });
    });
  });

  group('NodeLink', () {
    test('a link that stops answering is detected and reconnected, no user action', () {
      fakeAsync((fa) {
        var silent = true; // the first connection goes quiet (half-open TCP)
        final node = FakeNode();
        node.onRequest.listen((e) {
          final (c, r) = e;
          if (r.hasGetStatus() && !(silent && node.connections.length == 1)) {
            c.send(pb.FromRadio(reqId: r.reqId, status: pb.Status()));
          }
        });
        final link = NodeLink();
        final states = <LinkState>[];
        link.states.listen(states.add);
        link.connect(node);
        fa.flushMicrotasks();
        expect(link.state, isA<LinkUp>());

        // first ping at 15 s, no reply by 25 s: link timed out
        fa.elapse(const Duration(seconds: 26));
        final waiting = states.whereType<LinkWaiting>().single;
        expect(waiting.reason, contains('link timed out'));
        expect(node.connections.first.closed, isTrue, reason: 'the dead socket is closed');

        fa.elapse(const Duration(seconds: 1));
        expect(link.state, isA<LinkUp>());
        expect(node.opens, 2);

        // the new connection answers pings: it stays up
        silent = false;
        fa.elapse(const Duration(minutes: 2));
        expect(link.state, isA<LinkUp>());
        expect(node.opens, 2);
        link.dispose();
      });
    });

    test('checkNow reconnects at once while waiting, with the backoff reset', () {
      fakeAsync((fa) {
        final node = FakeNode()..failOpens = 4;
        final link = NodeLink();
        link.connect(node);
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 2 + 5));
        expect((link.state as LinkWaiting).retryIn, const Duration(seconds: 10));
        node.failOpens = 0;
        link.checkNow(); // app resumed: no 10 s wait
        fa.flushMicrotasks();
        expect(link.state, isA<LinkUp>());
        link.dispose();
      });
    });

    test('checkNow pings a live link, and a dead one is dropped', () {
      fakeAsync((fa) {
        final node = FakeNode(); // never answers GetStatus
        final link = NodeLink();
        final states = <LinkState>[];
        link.states.listen(states.add);
        link.connect(node);
        fa.flushMicrotasks();
        link.checkNow(); // well before the first periodic ping at 15 s
        fa.elapse(const Duration(seconds: 11));
        expect(states.whereType<LinkWaiting>().single.reason, contains('link timed out'));
        expect(node.opens, 2, reason: 'reconnected after the 1 s backoff');
        link.dispose();
      });
    });

    test('connects, then reconnects and says Hello again after a drop', () {
      fakeAsync((fa) {
        final node = FakeNode();
        final link = NodeLink(clientName: 'app');
        final states = <LinkState>[];
        link.states.listen(states.add);
        link.connect(node);
        fa.flushMicrotasks();
        expect(link.state, isA<LinkUp>());
        expect((link.state as LinkUp).info.nodeId, 0x11223344);

        node.last.drop();
        fa.elapse(const Duration(milliseconds: 10));
        expect(link.state, isA<LinkWaiting>());
        fa.elapse(const Duration(seconds: 1));
        expect(link.state, isA<LinkUp>());
        expect(node.requests.where((r) => r.hasHello()).length, 2);
        expect(states.whereType<LinkUp>().length, 2);
        link.dispose();
      });
    });

    test('backs off while the node is unreachable', () {
      fakeAsync((fa) {
        final node = FakeNode()..failOpens = 3;
        final link = NodeLink();
        link.connect(node);
        fa.flushMicrotasks();
        expect(link.state, isA<LinkWaiting>());
        expect((link.state as LinkWaiting).retryIn, const Duration(seconds: 2));
        fa.elapse(const Duration(seconds: 2));
        expect((link.state as LinkWaiting).retryIn, const Duration(seconds: 5));
        fa.elapse(const Duration(seconds: 5));
        expect((link.state as LinkWaiting).retryIn, const Duration(seconds: 10));
        fa.elapse(const Duration(seconds: 10));
        expect(link.state, isA<LinkUp>());
        expect(node.opens, 4);
        link.dispose();
      });
    });

    test('events from the live session are forwarded', () {
      fakeAsync((fa) {
        final node = FakeNode();
        final link = NodeLink();
        final events = <pb.FromRadio>[];
        link.events.listen(events.add);
        link.connect(node);
        fa.flushMicrotasks();
        node.last.send(pb.FromRadio(delivered: pb.Delivered(dest: 1, msgId: 2, clientMsgId: 3)));
        fa.flushMicrotasks();
        expect(events.single.delivered.clientMsgId, 3);
        link.dispose();
      });
    });

    test('BAD_VERSION on Hello stops reconnecting', () {
      fakeAsync((fa) {
        final node = FakeNode(autoHello: false);
        node.onRequest.listen((e) {
          final (c, r) = e;
          c.send(
            pb.FromRadio(
              reqId: r.reqId,
              error: pb.Error(code: pb.Error_Code.BAD_VERSION),
            ),
          );
        });
        final link = NodeLink();
        link.connect(node);
        fa.flushMicrotasks();
        expect(link.state, isA<LinkFailed>());
        fa.elapse(const Duration(minutes: 1));
        expect(node.opens, 1);
        link.dispose();
      });
    });

    test('disconnect stops reconnecting', () {
      fakeAsync((fa) {
        final node = FakeNode();
        final link = NodeLink();
        link.connect(node);
        fa.flushMicrotasks();
        link.disconnect();
        fa.flushMicrotasks();
        expect(link.state, isA<LinkIdle>());
        fa.elapse(const Duration(minutes: 1));
        expect(node.opens, 1);
        expect(node.last.closed, isTrue);
        link.dispose();
      });
    });
  });
}
