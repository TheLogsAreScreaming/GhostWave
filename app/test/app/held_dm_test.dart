// SendQueued.held (protocol 1.14): a DM the node keeps in its store until the
// other node is heard reads as waiting, not as sent, and the flag survives a
// restart of the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/message_groups.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/ui/message_bubble.dart';
import 'package:ghostwave_app/src/ui/theme.dart';

void main() {
  final at = DateTime(2026, 11, 20, 23, 42);

  Future<void> bubble(WidgetTester tester, MessageBubble b) => tester.pumpWidget(
    MaterialApp(
      theme: buildGhostWaveTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 380, child: b)),
      ),
    ),
  );

  testWidgets('a held DM says it is waiting; once delivered it says delivered', (tester) async {
    await bubble(
      tester,
      MessageBubble(outgoing: true, text: 'hi', at: at, state: MsgState.sent, held: true, onDelete: () {}),
    );
    expect(find.text('waiting to hear them'), findsOneWidget);
    expect(find.text('accepted by radio'), findsNothing);

    await bubble(tester, MessageBubble(outgoing: true, text: 'hi', at: at, state: MsgState.sent, onDelete: () {}));
    expect(find.text('accepted by radio'), findsOneWidget);

    // the receipt wins over a stale held flag
    await bubble(
      tester,
      MessageBubble(outgoing: true, text: 'hi', at: at, state: MsgState.delivered, held: true, onDelete: () {}),
    );
    expect(find.text('delivered'), findsOneWidget);
    expect(find.text('waiting to hear them'), findsNothing);
  });

  test('held round-trips through JSON and is left out when false', () {
    final m = ChatMessage(peer: 0xc8cc34e1, outgoing: true, text: 'hi', at: at, state: MsgState.sent, held: true);
    expect(ChatMessage.fromJson(m.toJson()).held, isTrue);
    final plain = m.copyWith(held: false);
    expect(plain.toJson().containsKey('held'), isFalse);
    expect(ChatMessage.fromJson(plain.toJson()).held, isFalse);
    // messages saved by older app versions have no key
    expect(ChatMessage.fromJson({'peer': 1, 'out': true, 'text': 'x', 'at': 0, 'state': 'sent'}).held, isFalse);
  });

  test('a long message is waiting while any sent part is held', () {
    ChatMessage part(int i, MsgState s, {bool held = false}) =>
        ChatMessage(peer: 1, outgoing: true, text: 'p$i', at: at, state: s, held: held);
    expect(
      LongMessageItem(total: 2, parts: {1: part(1, MsgState.delivered), 2: part(2, MsgState.sent, held: true)}).held,
      isTrue,
    );
    expect(LongMessageItem(total: 2, parts: {1: part(1, MsgState.sent), 2: part(2, MsgState.sent)}).held, isFalse);
    expect(LongMessageItem(total: 1, parts: {1: part(1, MsgState.delivered, held: true)}).held, isFalse);
  });
}
