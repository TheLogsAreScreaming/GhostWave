import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/message_groups.dart';
import 'package:ghostwave_app/src/data/message_split.dart';
import 'package:ghostwave_app/src/data/models.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 11, 12);
  ChatMessage msg(String text, {int s = 0, bool out = false, MsgState state = MsgState.delivered}) => ChatMessage(
    peer: 7,
    outgoing: out,
    text: text,
    at: t0.add(Duration(seconds: s)),
    state: state,
  );
  final long = List.generate(30, (i) => 'word$i').join(' ');

  test('the parts of one message become one bubble with the whole text', () {
    final parts = splitMessage(long, 73, group: 0xa7);
    expect(parts.length, greaterThan(1));
    final items = groupThread([for (var i = 0; i < parts.length; i++) msg(parts[i], s: i)]);
    expect(items, hasLength(1));
    final g = items.single as LongMessageItem;
    expect(g.text, long);
    expect(g.missing, isEmpty);
  });

  test('shuffled parts are put back in order, where the first part arrived', () {
    final parts = splitMessage(long, 73, group: 1);
    final shuffled = [parts.last, ...parts.sublist(0, parts.length - 1)];
    final items = groupThread([
      msg('before', s: 0),
      for (var i = 0; i < shuffled.length; i++) msg(shuffled[i], s: i + 1),
    ]);
    expect(items, hasLength(2));
    expect((items[0] as SingleItem).message.text, 'before');
    expect((items[1] as LongMessageItem).text, long);
  });

  test('a missing part is shown as missing', () {
    final parts = splitMessage(long, 73, group: 2);
    final items = groupThread([msg(parts.first), msg(parts.last, s: 1)]);
    final g = items.single as LongMessageItem;
    expect(g.missing, [for (var i = 2; i < parts.length; i++) i]);
    expect(g.text, contains('not received yet'));
  });

  test('a duplicate part is shown once', () {
    final parts = splitMessage(long, 73, group: 3);
    final items = groupThread([for (final p in parts) msg(p), msg(parts.first, s: 5)]);
    expect((items.single as LongMessageItem).text, long);
  });

  test('two long messages interleaved stay apart', () {
    final a = splitMessage(long, 73, group: 4), b = splitMessage('$long again', 73, group: 5);
    final thread = <ChatMessage>[];
    for (var i = 0; i < a.length || i < b.length; i++) {
      if (i < a.length) thread.add(msg(a[i], s: thread.length));
      if (i < b.length) thread.add(msg(b[i], s: thread.length));
    }
    final items = groupThread(thread);
    expect(items, hasLength(2));
    expect((items[0] as LongMessageItem).text, long);
    expect((items[1] as LongMessageItem).text, '$long again');
  });

  test('a reused tag with different text starts a new message', () {
    final a = splitMessage(long, 73, group: 6), b = splitMessage('other $long', 73, group: 6);
    final items = groupThread([for (final p in a) msg(p), for (final p in b) msg(p, s: 60)]);
    expect(items, hasLength(2));
  });

  test('parts more than an hour apart are not joined', () {
    final parts = splitMessage(long, 73, group: 7);
    final items = groupThread([msg(parts[0]), msg(parts[1], s: 7200)]);
    expect(items, hasLength(2));
  });

  test('sent and received parts with the same tag are not mixed', () {
    final parts = splitMessage(long, 73, group: 8);
    final items = groupThread([msg(parts[0]), msg(parts[1], out: true, s: 1)]);
    expect(items, hasLength(2));
  });

  test('old untagged parts stay as they are', () {
    final items = groupThread([msg('(1/2) hello'), msg('(2/2) world', s: 1)]);
    expect(items.every((i) => i is SingleItem), isTrue);
  });

  test('a long message shows its weakest delivery state', () {
    final parts = splitMessage(long, 73, group: 9);
    final g =
        groupThread([
              msg(parts[0], out: true, state: MsgState.delivered),
              for (var i = 1; i < parts.length; i++)
                msg(parts[i], out: true, s: i, state: i == 1 ? MsgState.failed : MsgState.sent),
            ]).single
            as LongMessageItem;
    expect(g.state, MsgState.failed);
  });

  test('bad labels are not parts', () {
    expect(parsePart('(3/2#aa) x'), isNull);
    expect(parsePart('(1/1#aa) x'), isNull);
    expect(parsePart('(1/9#aa) x'), isNull);
    expect(parsePart('(1/2#zz) x'), isNull);
    expect(parsePart('(1/2#0a) x')!.group, 10);
  });
}
