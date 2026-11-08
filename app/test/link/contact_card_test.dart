import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/link/contact_card.dart';
import 'package:ghostwave_app/src/link/transport.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i * 8 + 1));
  final keyHex = hexEncode(key);

  group('ContactCard', () {
    test('encodes and parses back', () {
      final card = ContactCard(nodeId: 0x0a1b2c3d, ed25519Pub: key, name: 'Bob: base camp');
      final text = card.encode();
      expect(text, 'ghostwave:0a1b2c3d:$keyHex:Bob%3A%20base%20camp');
      final back = ContactCard.tryParse(text)!;
      expect(back.nodeId, 0x0a1b2c3d);
      expect(back.ed25519Pub, key);
      expect(back.name, 'Bob: base camp');
    });

    test('name is optional; case and whitespace are forgiven', () {
      final c = ContactCard.tryParse('  GHOSTWAVE:0A1B2C3D:${keyHex.toUpperCase()}\n')!;
      expect(c.nodeId, 0x0a1b2c3d);
      expect(c.name, '');
      expect(ContactCard(nodeId: 1, ed25519Pub: key).encode(), 'ghostwave:00000001:$keyHex');
    });

    test('a raw colon in the name is kept', () {
      expect(ContactCard.tryParse('ghostwave:0a1b2c3d:$keyHex:a:b')!.name, 'a:b');
    });

    test('long names are cut to 32 UTF-8 bytes on a character boundary', () {
      final c = ContactCard.tryParse('ghostwave:0a1b2c3d:$keyHex:${'é' * 20}')!;
      expect(utf8Length(c.name), 32);
    });

    for (final bad in [
      '',
      'ghostwave:',
      'meshtastic:0a1b2c3d:$keyHex',
      'ghostwave:0a1b2c3:$keyHex',
      'ghostwave:0a1b2c3d:${keyHex.substring(2)}',
      'ghostwave:0a1b2c3g:$keyHex',
      'ghostwave:00000000:$keyHex',
      'ghostwave:0a1b2c3d:${keyHex.replaceRange(0, 1, 'x')}',
    ]) {
      test('rejects "${bad.length > 30 ? '${bad.substring(0, 30)}…' : bad}"', () {
        expect(ContactCard.tryParse(bad), isNull);
      });
    }
  });

  group('text helpers', () {
    test('utf8Length counts bytes, not characters', () {
      expect(utf8Length('abc'), 3);
      expect(utf8Length('é'), 2);
      expect(utf8Length('\u{1F3D4}'), 4);
    });

    test('truncateUtf8 never splits a character', () {
      expect(truncateUtf8('ab\u{1F3D4}', 5), 'ab');
      expect(truncateUtf8('ab\u{1F3D4}', 6), 'ab\u{1F3D4}');
    });

    test('decodeLenient tolerates bad UTF-8', () {
      expect(decodeLenient([0x68, 0x69, 0xFF]), 'hi�');
    });

    test('nodeIdHex pads to 8', () {
      expect(nodeIdHex(0xBEEF), '0000beef');
    });
  });

  group('TcpAddress', () {
    test('parses host:port, [v6]:port and a bare port', () {
      expect(TcpAddress.tryParse('192.168.1.20:47800').toString(), '192.168.1.20:47800');
      expect(TcpAddress.tryParse(' mesh.local:4403 ')!.host, 'mesh.local');
      expect(TcpAddress.tryParse('[fe80::1]:4403')!.host, 'fe80::1');
      expect(TcpAddress.tryParse('[fe80::1]:4403').toString(), '[fe80::1]:4403');
      expect(TcpAddress.tryParse('47800').toString(), '127.0.0.1:47800');
    });

    for (final bad in ['', 'host', 'host:', 'host:0', 'host:70000', 'fe80::1:4403', '[fe80::1]', 'a b:1']) {
      test('rejects "$bad"', () => expect(TcpAddress.tryParse(bad), isNull));
    }
  });
}
