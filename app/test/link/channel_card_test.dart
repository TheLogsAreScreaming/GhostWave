// Channel cards: the versioned share format a channel QR code carries.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/link/contact_card.dart';

ChannelCardProblem? _problem(String text) => switch (ChannelCard.parse(text)) {
  ChannelCardOk() => null,
  ChannelCardRejected(:final problem) => problem,
};

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => 255 - i * 7));
  final keyHex = hexEncode(key);

  test('round-trips names with spaces, colons, percent signs and non-ASCII', () {
    for (final name in ['trail crew', 'a:b', '100%', 'é?v=2', 'ü#&/', 'x' * 16]) {
      final text = ChannelCard(name: name, psk: key).encode();
      final back = ChannelCard.tryParse(text)!;
      expect(back.name, name);
      expect(back.psk, key);
    }
  });

  test('writes format 1 without a marker, so older apps and gwclient read it', () {
    expect(ChannelCard(name: 'trail crew', psk: key).encode(), 'ghostwave-ch:trail%20crew:$keyHex');
  });

  test('reads an explicit ?v=1, upper-case hex and surrounding whitespace', () {
    final c = ChannelCard.tryParse('  GHOSTWAVE-CH:base:${keyHex.toUpperCase()}?v=1\n')!;
    expect(c.name, 'base');
    expect(c.psk, key);
  });

  test('refuses a card from a newer format and says to update', () {
    expect(_problem('ghostwave-ch:base:$keyHex?v=2'), ChannelCardProblem.newerFormat);
    expect(_problem('ghostwave-ch:base:$keyHex?v=99'), ChannelCardProblem.newerFormat);
    expect(ChannelCardProblem.newerFormat.message, contains('Update'));
  });

  test('refuses old or malformed version markers', () {
    for (final q in ['?v=0', '?v=', '?v=one', '?v=1&x=2', '?x=1', '?', '?v=1.0', '?v=-1', '?v=1234567']) {
      expect(_problem('ghostwave-ch:base:$keyHex$q'), ChannelCardProblem.badVersion, reason: q);
    }
  });

  test('refuses damaged keys', () {
    for (final bad in [
      'ghostwave-ch:base',
      'ghostwave-ch:base:',
      'ghostwave-ch:base:${keyHex.substring(2)}',
      'ghostwave-ch:base:${keyHex}00',
      'ghostwave-ch:base:${keyHex.substring(0, 62)}zz',
      // an early 16-byte key
      'ghostwave-ch:base:${keyHex.substring(0, 32)}',
    ]) {
      expect(_problem(bad), ChannelCardProblem.badKey, reason: bad);
    }
  });

  test('refuses bad names', () {
    for (final bad in [
      'ghostwave-ch::$keyHex',
      'ghostwave-ch:%E0%A4:$keyHex',
      'ghostwave-ch:${'x' * 17}:$keyHex',
      'ghostwave-ch:a%0Ab:$keyHex',
      'ghostwave-ch:a%7Fb:$keyHex',
    ]) {
      expect(_problem(bad), ChannelCardProblem.badName, reason: bad);
    }
  });

  test('a contact card with broken percent-encoding keeps the raw name instead of throwing', () {
    expect(ContactCard.tryParse('ghostwave:0a1b2c3d:$keyHex:%E0%A4')!.name, '%E0%A4');
  });

  test('other text is not a channel card', () {
    for (final other in ['', 'ghostwave-c', 'ghostwave:0a1b2c3d:$keyHex', 'https://example.com']) {
      expect(_problem(other), ChannelCardProblem.notAChannelCard, reason: other);
    }
  });
}
