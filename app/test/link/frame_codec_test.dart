// Frame codec tests. Golden frames are the byte-exact vectors from
// firmware/tests/test_client_proto.cpp and docs/CLIENT_PROTOCOL.md §6 in this
// repo: the node, the Python reference client and this app must agree.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/gen/ghostwave.pb.dart' as pb;
import 'package:ghostwave_app/src/link/frame_codec.dart';
import 'package:ghostwave_app/src/link/geo.dart';

Uint8List hex(String s) {
  final t = s.replaceAll(' ', '');
  return Uint8List.fromList([for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16)]);
}

Uint8List key(int seed) => Uint8List.fromList([for (var i = 0; i < 32; i++) (seed + i * 7) & 0xFF]);

Frame onlyFrame(List<int> bytes) {
  final r = FrameReader()..push(bytes);
  final e = r.next();
  expect(e, isA<Frame>());
  expect(r.next(), isNull);
  return e! as Frame;
}

void main() {
  group('golden frames (GhostWave test_client_proto.cpp)', () {
    test('ToRadio{req_id 1, Hello{1, "app"}}', () {
      final m = pb.ToRadio(reqId: 1, hello: pb.Hello(protocolVersion: 1, clientName: 'app'));
      expect(encodeFrame(m.writeToBuffer()), hex('94c30c0001 0801 5207 0801 1203 617070'));
    });

    test('ToRadio{req_id 2, SendText{a1b2c3d4, "hi", 42}}', () {
      final m = pb.ToRadio(reqId: 2, sendText: pb.SendText(dest: 0xA1B2C3D4, text: 'hi'.codeUnits, clientMsgId: 42));
      expect(encodeFrame(m.writeToBuffer()), hex('94c3100001 0802 5a0b 0dd4c3b2a1 12026869 182a'));
    });

    test('FromRadio{Delivered{a1b2c3d4, 01020304, 42}} encodes and decodes', () {
      final golden = hex('94c30f0001 620c 0dd4c3b2a1 1504030201 182a');
      final m = pb.FromRadio(delivered: pb.Delivered(dest: 0xA1B2C3D4, msgId: 0x01020304, clientMsgId: 42));
      expect(encodeFrame(m.writeToBuffer()), golden);

      final f = onlyFrame(golden);
      expect(f.version, kProtocolVersion);
      final back = pb.FromRadio.fromBuffer(f.body);
      expect(back.whichEvent(), pb.FromRadio_Event.delivered);
      expect(back.reqId, 0);
      expect(back.delivered.dest, 0xA1B2C3D4);
      expect(back.delivered.msgId, 0x01020304);
      expect(back.delivered.clientMsgId, 42);
    });

    test('negative coordinates are zigzag varints (sint32)', () {
      final m = pb.FromRadio(position: pb.OwnPosition(pos: pb.Position(latE7: -1, lonE7: 1)));
      expect(m.writeToBuffer(), hex('8a01 06 0a04 0801 1002'));
      final back = pb.FromRadio.fromBuffer(hex('8a01 06 0a04 0801 1002'));
      expect(back.position.pos.latE7, -1);
      expect(back.position.pos.lonE7, 1);
    });
  });

  group('protobuf round trips', () {
    test('every request kind survives a frame', () {
      final samples = <pb.ToRadio>[
        pb.ToRadio(reqId: 1, hello: pb.Hello(protocolVersion: 1, clientName: 'GhostWave iOS')),
        pb.ToRadio(
          reqId: 2,
          sendText: pb.SendText(dest: 0xA1B2C3D4, text: utf8.encode('hello \u{1F3D4}'), clientMsgId: 0xFFFFFFFF),
        ),
        pb.ToRadio(
          reqId: 300,
          addContact: pb.AddContact(nodeId: 0xBEEF, ed25519Pub: key(1), name: 'bob'),
        ),
        pb.ToRadio(addContact: pb.AddContact(nodeId: 0x12345678, x25519Pub: key(9))),
        pb.ToRadio(reqId: 4, listContacts: pb.ListContacts()),
        pb.ToRadio(
          reqId: 5,
          setKnownPosition: pb.SetKnownPosition(nodeId: 0xFFFFFFFE, pos: const LatLon(-45.5, 170.25).toProto()),
        ),
        pb.ToRadio(reqId: 6, sosStart: pb.SosStart(text: 'twisted ankle'.codeUnits, batteryPct: 0, accuracyM: 12)),
        pb.ToRadio(reqId: 7, sosStart: pb.SosStart()),
        pb.ToRadio(reqId: 8, sosStop: pb.SosStop()),
        pb.ToRadio(reqId: 9, sosAck: pb.SosAck(nodeId: 0x01020304)),
        pb.ToRadio(reqId: 10, getStatus: pb.GetStatus()),
        pb.ToRadio(reqId: 11, getPosition: pb.GetPosition()),
        pb.ToRadio(reqId: 12, setOwnPosition: pb.SetOwnPosition(pos: pb.Position())),
        pb.ToRadio(reqId: 13, setOwnPosition: pb.SetOwnPosition()),
      ];
      for (final m in samples) {
        final fr = encodeFrame(m.writeToBuffer());
        expect(fr.length, lessThanOrEqualTo(kMaxFrame));
        final back = pb.ToRadio.fromBuffer(onlyFrame(fr).body);
        expect(back, m, reason: m.toString());
      }
      // optional fields: 0 is present, unset is absent
      final sos = pb.ToRadio.fromBuffer(samples[6].writeToBuffer()).sosStart;
      expect(sos.hasBatteryPct(), isTrue);
      expect(sos.batteryPct, 0);
      expect(pb.ToRadio.fromBuffer(samples[7].writeToBuffer()).sosStart.hasBatteryPct(), isFalse);
      // a fix at 0,0 is a present, empty Position
      expect(pb.ToRadio.fromBuffer(samples[12].writeToBuffer()).setOwnPosition.hasPos(), isTrue);
      expect(pb.ToRadio.fromBuffer(samples[13].writeToBuffer()).setOwnPosition.hasPos(), isFalse);
    });

    test('every event kind survives a frame', () {
      final samples = <pb.FromRadio>[
        pb.FromRadio(
          reqId: 1,
          nodeInfo: pb.NodeInfo(
            protocolVersion: 1,
            nodeId: 0x9ABCDEF0,
            name: 'A'.codeUnits,
            ed25519Pub: key(3),
            x25519Pub: key(4),
            firmware: 'ghostwaved 0.1',
            maxTextBytes: 79,
          ),
        ),
        pb.FromRadio(replayed: true, text: pb.TextMessage(src: 7, msgId: 0xDEADBEEF, text: [0x68, 0x69, 0, 0xFF])),
        pb.FromRadio(
          sos: pb.SosAlert(
            src: 5,
            seq: 65535,
            pos: const LatLon(46.9, -114).toProto(),
            accuracyM: 8,
            text: 'help'.codeUnits,
          ),
        ),
        pb.FromRadio(sos: pb.SosAlert(src: 5, seq: 1)),
        pb.FromRadio(sosAck: pb.SosAckReceived(responder: 6, seq: 3)),
        pb.FromRadio(neighbor: pb.Neighbor(nodeId: 8, pos: const LatLon(1, 2).toProto(), isNew: true)),
        pb.FromRadio(
          reqId: 77,
          status: pb.Status(
            tx: 1,
            rx: 2,
            rxBad: 3,
            rxAuthFail: 4,
            delivered: 5,
            forwarded: 6,
            stored: 7,
            airMs: Int64(0x1FFFFFFFF),
            storeSize: 9,
            neighbors: 10,
            sosHeld: 11,
            sosActive: true,
            uptimeS: 13,
            clients: 14,
            queued: 15,
          ),
        ),
        pb.FromRadio(reqId: 78, position: pb.OwnPosition()),
        pb.FromRadio(reqId: 79, position: pb.OwnPosition(pos: const LatLon(-89.9999999, -179.9999999).toProto())),
        pb.FromRadio(
          reqId: 80,
          error: pb.Error(code: pb.Error_Code.TOO_LONG, detail: 'text over 79 bytes'),
        ),
        pb.FromRadio(
          reqId: 81,
          contact: pb.Contact(nodeId: 3, name: 'c'.codeUnits, x25519Pub: key(5), ed25519Pub: key(6), pinned: true),
        ),
        pb.FromRadio(reqId: 81, contactsEnd: pb.ContactsEnd(count: 1)),
        pb.FromRadio(reqId: 82, sendQueued: pb.SendQueued(dest: 1, msgId: 2, clientMsgId: 3)),
        pb.FromRadio(reqId: 83, ok: pb.Ok()),
        pb.FromRadio(peerIdent: pb.PeerIdent(nodeId: 4, name: 'dave'.codeUnits, isNew: true)),
        pb.FromRadio(
          keyChange: pb.KeyChange(nodeId: 4, ed25519Pub: key(8), name: 'dave'.codeUnits),
        ),
      ];
      for (final m in samples) {
        final fr = encodeFrame(m.writeToBuffer());
        expect(fr.length, lessThanOrEqualTo(kMaxFrame));
        expect(pb.FromRadio.fromBuffer(onlyFrame(fr).body), m, reason: m.toString());
      }
      expect(const LatLon(46.8700001, -113.9912345).toProto(), pb.Position(latE7: 468700001, lonE7: -1139912345));
    });

    test('unknown request and event fields from a newer protocol are skipped', () {
      // req_id 5, then field 99 (length-delimited): no request this app knows
      final t = pb.ToRadio.fromBuffer(hex('0805 9a06 02 0801'));
      expect(t.reqId, 5);
      expect(t.whichRequest(), pb.ToRadio_Request.notSet);
      // replayed, then field 101
      final f = pb.FromRadio.fromBuffer(hex('1001 aa06 00'));
      expect(f.replayed, isTrue);
      expect(f.whichEvent(), pb.FromRadio_Event.notSet);
      // an unknown error code still decodes as an error
      final e = pb.FromRadio.fromBuffer(hex('9201 02 0863'));
      expect(e.hasError(), isTrue);
    });
  });

  group('framing', () {
    test('a message that does not fit is refused, not cut', () {
      final big = pb.ToRadio(sendText: pb.SendText(dest: 1, text: List.filled(kMaxBody, 0x78)));
      expect(() => encodeFrame(big.writeToBuffer()), throwsA(isA<FrameTooLargeException>()));
      // version 1, request tag 1 + len 2, dest 5, text tag 1 + len 2
      final fits = pb.ToRadio(sendText: pb.SendText(dest: 1, text: List.filled(kMaxBody - 12, 0x78)));
      expect(encodeFrame(fits.writeToBuffer()).length, kMaxFrame);
    });

    final a = pb.ToRadio(reqId: 1, getStatus: pb.GetStatus());
    final b = pb.ToRadio(reqId: 2, sendText: pb.SendText(dest: 3, text: 'yo'.codeUnits, clientMsgId: 4));
    final stream = <int>[
      0x00,
      0x94,
      0x00,
      0xC3,
      0x94,
      ...encodeFrame(a.writeToBuffer()),
      ...encodeFrame(b.writeToBuffer()),
    ];

    test('two frames in one push, after garbage incl. a lone first magic byte', () {
      final r = FrameReader()..push(stream);
      final f1 = r.next()! as Frame;
      final f2 = r.next()! as Frame;
      expect(f1.version, kProtocolVersion);
      expect(pb.ToRadio.fromBuffer(f1.body), a);
      expect(pb.ToRadio.fromBuffer(f2.body), b);
      expect(r.next(), isNull);
      expect(r.buffered, 0);
      expect(r.skipped, 5);
    });

    test('byte by byte', () {
      final r = FrameReader();
      var frames = 0;
      for (final c in stream) {
        r.push([c]);
        frames += r.drain().whereType<Frame>().length;
      }
      expect(frames, 2);
      expect(r.buffered, 0);
    });

    test('a truncated frame waits for the rest', () {
      final one = encodeFrame(b.writeToBuffer());
      final r = FrameReader()..push(one.sublist(0, one.length - 1));
      expect(r.next(), isNull);
      expect(r.buffered, one.length - 1);
      r.push([one.last]);
      expect(r.next(), isA<Frame>());
    });

    for (final badLen in [kMaxBody + 1, 0xFFFF, 0]) {
      test('length $badLen is reported, then the reader resyncs', () {
        final r = FrameReader()
          ..push([kMagic0, kMagic1, badLen & 0xFF, badLen >> 8, 1, 2, 3, ...encodeFrame(a.writeToBuffer())]);
        final e = r.next();
        expect(e, isA<BadLength>());
        expect((e! as BadLength).length, badLen);
        final f = r.next()! as Frame;
        expect(pb.ToRadio.fromBuffer(f.body).whichRequest(), pb.ToRadio_Request.getStatus);
      });
    }

    test('the version byte is passed through for the caller to judge', () {
      final f = onlyFrame(encodeFrame([0x08, 0x01], version: 2));
      expect(f.version, 2);
      expect(f.body, [0x08, 0x01]);
    });

    test('junk never piles up in the buffer', () {
      final r = FrameReader()..push(List.filled(10000, 0x55));
      expect(r.next(), isNull);
      expect(r.buffered, 0);
    });

    test('FrameDecoder handles arbitrary chunking', () async {
      final chunks = <List<int>>[
        for (var i = 0; i < stream.length; i += 3) stream.sublist(i, (i + 3).clamp(0, stream.length)),
      ];
      final out = await Stream<List<int>>.fromIterable(chunks).transform(const FrameDecoder()).toList();
      expect(out.whereType<Frame>().length, 2);
    });
  });
}
