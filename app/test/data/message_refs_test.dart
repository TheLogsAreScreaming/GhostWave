import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/message_refs.dart';

void main() {
  group('messageRef', () {
    test('is 4 URL-safe characters, stable, and depends on sender and ID', () {
      final r = messageRef(0x0B0B0B0B, 0x12345678)!;
      expect(r, matches(RegExp(r'^[A-Za-z0-9_-]{4}$')));
      expect(messageRef(0x0B0B0B0B, 0x12345678), r);
      expect(messageRef(0x0B0B0B0C, 0x12345678), isNot(r));
      expect(messageRef(0x0B0B0B0B, 0x12345679), isNot(r));
      // golden value: both ends of the mesh must compute the same reference
      expect(messageRef(1, 1), 'V3_K'); // checked with Python's hashlib
    });

    test('no reference before the node gave the message an ID', () {
      expect(messageRef(5, 0), isNull);
    });

    test('rarely collides inside one conversation', () {
      final seen = <String>{};
      for (var id = 1; id <= 2000; id++) {
        seen.add(messageRef(0xA1B2C3D4, id * 7919)!);
      }
      expect(seen.length, greaterThan(1995));
    });
  });

  group('round trips', () {
    test('replies', () {
      for (final body in ['ok', 'meet at the saddle at 5', 'ünïcödé 🏔️ text', '  padded  ']) {
        final m = parseMeshText(encodeReply('Ab3_', body));
        expect(m, isA<ReplyText>());
        expect((m as ReplyText).ref, 'Ab3_');
        expect(m.body, body.trim());
      }
    });

    test('every reaction, and taking one back', () {
      for (final e in kReactions) {
        final text = encodeReaction('x-9Z', e);
        expect(utf8.encode(text).length, lessThanOrEqualTo(14), reason: e);
        final m = parseMeshText(text);
        expect(m, isA<ReactionText>());
        expect((m as ReactionText).emoji, e);
        expect(m.ref, 'x-9Z');
      }
      final off = parseMeshText(encodeReaction('x-9Z', null));
      expect(off, isA<ReactionText>());
      expect((off as ReactionText).emoji, isNull);
      expect(utf8.encode(encodeReaction('x-9Z', null)).length, 8);
    });

    test('a bare heart (no variation selector) counts as the heart reaction', () {
      final m = parseMeshText('+❤↩abcd') as ReactionText;
      expect(m.emoji, '❤️');
    });

    test('reply overhead is what the composer counts', () {
      expect(utf8.encode(encodeReply('abcd', 'x')).length, kReplyOverheadBytes + 1);
    });

    test('encoders refuse bad input', () {
      expect(() => encodeReply('abc', 'x'), throwsArgumentError);
      expect(() => encodeReply('ab cd', 'x'), throwsArgumentError);
      expect(() => encodeReply('abcd', '   '), throwsArgumentError);
      expect(() => encodeReaction('abcd', '🔥'), throwsArgumentError);
      expect(() => encodeReaction('a/cd', '👍'), throwsArgumentError);
    });
  });

  group('hostile and ordinary text stays plain', () {
    final cases = <String>[
      '',
      'hello',
      '↩',
      '↩abcd',
      '↩abcd ',
      '↩abcd    ',
      '↩abc', // short reference
      '↩ab/d text', // bad character
      '↩abcdtext', // no space
      '↩abcde text', // reference too long: still has no space at 5
      '+🔥↩abcd', // not an offered reaction
      '+👍👍↩abcd',
      '+👍↩abc',
      '+👍↩abcde',
      '+👍 ↩abcd',
      '👍↩abcd', // no plus
      '--↩abcd',
      '+↩abcd',
      ' +👍↩abcd',
      '+👍↩abcd ',
      'I said +👍↩abcd',
      '(1/2#a7) +👍↩abcd',
      'see ↩ above',
      '\u0000↩abcd x',
      '↩\u0000bcd x',
      '+👍↩ab\u0000d',
      '���',
      '↩abcd\u202Etext', // no space after the reference
    ];
    for (final c in cases) {
      test(jsonEncode(c), () => expect(parseMeshText(c), isA<PlainText>()));
    }

    test('random bytes, decoded leniently, never throw', () {
      final rng = Random(42);
      for (var i = 0; i < 5000; i++) {
        final bytes = List<int>.generate(rng.nextInt(40), (_) => rng.nextInt(256));
        if (rng.nextBool()) bytes.insertAll(0, utf8.encode(rng.nextBool() ? '↩' : '+👍↩'));
        final text = utf8.decode(bytes, allowMalformed: true);
        expect(() => parseMeshText(text), returnsNormally);
        expect(() => friendlyText(text), returnsNormally);
      }
    });

    test('a huge reply still parses, and only once', () {
      final body = 'x' * 100000;
      final m = parseMeshText('↩abcd $body') as ReplyText;
      expect(m.body.length, 100000);
      // a reply whose body looks like a reaction is still a reply
      final inner = parseMeshText('↩abcd +👍↩wxyz') as ReplyText;
      expect(inner.body, '+👍↩wxyz');
    });
  });

  group('friendlyText', () {
    test('for previews and notifications', () {
      expect(friendlyText('hi'), 'hi');
      expect(friendlyText(encodeReply('abcd', 'on my way')), '↩ on my way');
      expect(friendlyText(encodeReaction('abcd', '✅')), 'Reacted ✅');
      expect(friendlyText(encodeReaction('abcd', null)), 'Removed a reaction');
    });
  });

  group('ThreadRefs', () {
    const me = 0x11111111, bob = 0x22222222, cat = 0x33333333;
    final a = messageRef(bob, 100)!;

    test('folds reactions into counts; latest per person wins; removal clears', () {
      final t = ThreadRefs.of([
        const RefEntry(sender: bob, msgId: 100, text: 'camp at 5?'),
        RefEntry(sender: me, msgId: 200, text: encodeReaction(a, '👍')),
        RefEntry(sender: cat, msgId: 300, text: encodeReaction(a, '👍')),
        RefEntry(sender: cat, msgId: 301, text: encodeReaction(a, '❤️')), // cat changes its mind
        RefEntry(sender: bob, msgId: 101, text: encodeReaction(a, '😂')),
        RefEntry(sender: bob, msgId: 102, text: encodeReaction(a, null)), // bob takes it back
        RefEntry(sender: me, msgId: 201, text: encodeReply(a, 'yes')),
      ]);
      expect(t.countsFor(a), [('👍', 1), ('❤️', 1)]);
      expect(t.reactions[a], {me: '👍', cat: '❤️'});
      expect([for (var i = 0; i < 7; i++) t.folded(i)], [false, true, true, true, true, true, false]);
      expect(t.indexOf[a], 0);
      // the reply's own reference points at the reply, not at a reaction
      expect(t.indexOf[messageRef(me, 201)], 6);
      expect(t.indexOf.containsKey(messageRef(me, 200)), isFalse);
    });

    test('a reaction to a message not here stays visible', () {
      final t = ThreadRefs.of([RefEntry(sender: bob, msgId: 1, text: encodeReaction('zzzz', '👍'))]);
      expect(t.folded(0), isFalse);
      expect(t.countsFor('zzzz'), [('👍', 1)]);
    });

    test('a failed reaction of ours does not count', () {
      final t = ThreadRefs.of([
        const RefEntry(sender: bob, msgId: 100, text: 'x'),
        RefEntry(sender: me, msgId: 0, text: encodeReaction(a, '👍'), countable: false),
      ]);
      expect(t.countsFor(a), isEmpty);
    });

    test('many reactions from many senders: one each', () {
      final t = ThreadRefs.of([
        const RefEntry(sender: bob, msgId: 100, text: 'x'),
        for (var s = 0; s < 500; s++)
          for (final e in kReactions) RefEntry(sender: 0x1000 + s, msgId: s * 10 + 1, text: encodeReaction(a, e)),
      ]);
      expect(t.countsFor(a), [('❗', 500)]);
    });
  });
}
