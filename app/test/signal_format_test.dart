// Signal labels: a number and a word, never colour alone; long messages show
// their weakest part.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/message_groups.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/ui/format.dart';

void main() {
  test('signal words and text', () {
    expect(signalText(-58), '-58 dBm, strong');
    expect(signalWord(-90), 'strong');
    expect(signalWord(-91), 'good');
    expect(signalWord(-105), 'good');
    expect(signalWord(-115), 'fair');
    expect(signalWord(-116), 'weak');
    expect(secondsAgo(12), '12 s ago');
    expect(secondsAgo(600), '10 min ago');
    expect(secondsAgo(7200), '2 h ago');
  });

  test('a long message reports its weakest part', () {
    final at = DateTime(2026, 11, 12);
    ChatMessage part(int i, int total, int? dbm) =>
        ChatMessage(peer: 1, outgoing: false, text: '($i/$total#ab) p$i', at: at, msgId: i, rssiDbm: dbm);
    final item = groupThread([part(1, 3, -90), part(2, 3, null), part(3, 3, -112)]).single as LongMessageItem;
    expect(item.rssiDbm, -112);
    final none = groupThread([part(1, 2, null), part(2, 2, null)]).single as LongMessageItem;
    expect(none.rssiDbm, isNull);
  });
}
