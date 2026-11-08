import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/node_link.dart';
import 'package:ghostwave_app/src/link/session.dart';

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

  group('NodeLink', () {
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
