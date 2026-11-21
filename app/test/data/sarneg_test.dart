import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/sarneg.dart';

void main() {
  group('code word', () {
    test('accepts 10 different letters after normalizing', () {
      expect(normalizeSarnegWord(' black horse '), 'BLACKHORSE');
      expect(checkSarnegWord('BLACKHORSE'), isNull);
      expect(checkSarnegWord('CUMBERLAND'), isNull);
    });

    test('names what is wrong', () {
      expect(checkSarnegWord('BLACK'), SarnegWordProblem.length);
      expect(checkSarnegWord('BLACKHORS3'), SarnegWordProblem.letters);
      expect(checkSarnegWord('BLACKHORSB'), SarnegWordProblem.repeats);
      expect(() => SarnegCodec('BLACKHORSB'), throwsArgumentError);
    });
  });

  group('codec', () {
    final c = SarnegCodec('BLACKHORSE');

    test('maps each digit to its letter', () {
      expect(c.encode('0123456789'), 'BLACKHORSE');
      expect(c.decode('BLACKHORSE'), '0123456789');
    });

    test('keeps plain letters apart from code letters', () {
      // the zone letter S is also a code letter: lower case keeps it plain
      expect(c.encode('17S 4823'), 'LRs KSAC');
      expect(c.decode('LRs KSAC'), '17s 4823');
      expect(c.encode('Grid 4823'), 'grid KSAC');
    });

    test('round-trips coordinates and frequencies', () {
      for (final plain in ['35.22710, -80.84310', '906.875', '12:45', '']) {
        expect(c.decode(c.encode(plain)), plain);
      }
    });

    test('wraps and unwraps whole messages', () {
      final msg = c.encodeMessage(' 906.875 ');
      expect(msg, '[SARNEG] EBO.SRH');
      expect(isSarnegMessage(msg), isTrue);
      expect(c.decodeMessage(msg), '906.875');
      expect(c.decodeMessage('plain 123'), isNull);
      expect(isSarnegMessage('see [SARNEG] later'), isFalse);
    });

    test('another word gives another text', () {
      expect(SarnegCodec('CUMBERLAND').encode('17'), 'UA');
    });
  });

  group('key set', () {
    final set = SarnegKeySet(word: 'BLACKHORSE', daily: {'2026-11-22': 'DUMBWAITER', '2026-11-21': 'CUMBERLAND'});

    test('picks the word for the local day', () {
      expect(set.wordFor(DateTime(2026, 11, 20, 23, 59)), 'BLACKHORSE');
      expect(set.wordFor(DateTime(2026, 11, 21, 0, 1)), 'CUMBERLAND');
      expect(set.codecFor(DateTime(2026, 11, 22, 12)).word, 'DUMBWAITER');
    });

    test('shares as text and reads it back', () {
      final text = set.toShareText();
      expect(text, 'SARNEG1:BLACKHORSE;2026-11-21=CUMBERLAND;2026-11-22=DUMBWAITER');
      expect(SarnegKeySet.parseShareText(text), set);
      expect(SarnegKeySet.parseShareText('sarneg1:black horse').word, 'BLACKHORSE');
    });

    test('refuses bad share text', () {
      for (final bad in [
        'hello',
        'SARNEG1:BLACK',
        'SARNEG1:BLACKHORSE;2026-11-21',
        'SARNEG1:BLACKHORSE;2026-13-40=CUMBERLAND',
        'SARNEG1:BLACKHORSE;2026-11-21=BLACKHORSB',
      ]) {
        expect(() => SarnegKeySet.parseShareText(bad), throwsFormatException, reason: bad);
      }
    });

    test('saves and loads; damaged data gives null', () {
      expect(SarnegKeySet.fromJson(set.toJson()), set);
      expect(SarnegKeySet.fromJson({'word': 'NOPE'}), isNull);
      expect(SarnegKeySet.fromJson('x'), isNull);
    });

    test('edits dated words and drops old ones', () {
      final more = set.withDay('2026-11-23', 'PLAYGROUND');
      expect(more.daily.keys, ['2026-11-21', '2026-11-22', '2026-11-23']);
      expect(more.withDay('2026-11-21', null).daily.keys, ['2026-11-22', '2026-11-23']);
      expect(more.withoutDaysBefore('2026-11-22').daily.keys, ['2026-11-22', '2026-11-23']);
    });
  });
}
