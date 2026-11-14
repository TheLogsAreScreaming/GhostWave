// The node details graph: readings the app already keeps, merged in time
// order, with nothing replayed, outgoing or invented.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/data/signal_history.dart';
import 'package:ghostwave_app/src/data/timeline.dart';

const int ridge = 0x9F219DBB;
final DateTime t0 = DateTime(2026, 11, 14, 9);
DateTime at(int min) => t0.add(Duration(minutes: min));

void main() {
  test('merges messages, signal changes and the latest beacon, oldest first', () {
    final h = signalHistory(
      nodeId: ridge,
      messages: [
        ChatMessage(peer: ridge, outgoing: false, text: 'a', at: at(10), rssiDbm: -101),
        ChatMessage(peer: ridge, outgoing: true, text: 'mine', at: at(11), rssiDbm: -80), // receipt: not its signal
        ChatMessage(peer: ridge, outgoing: false, text: 'old', at: at(12), rssiDbm: -90, replayed: true),
        ChatMessage(peer: ridge, outgoing: false, text: 'no reading', at: at(13)),
      ],
      channelMessages: [
        [
          ChannelMessage(channel: 'crew', outgoing: false, text: 'x', at: at(5), src: ridge, rssiDbm: -110),
          ChannelMessage(channel: 'crew', outgoing: false, text: 'y', at: at(6), src: 7, rssiDbm: -60),
        ],
      ],
      signalLog: [
        SignalShift(nodeId: ridge, fromDbm: -110, toDbm: -95, at: at(20)),
        SignalShift(nodeId: 7, fromDbm: -110, toDbm: -95, at: at(21)),
      ],
      neighbor: Neighbor(nodeId: ridge, lastSeen: at(30), rssiDbm: -96),
    );
    expect(
      [for (final r in h) (r.dbm, r.source)],
      [
        (-110, SignalSource.message),
        (-101, SignalSource.message),
        (-95, SignalSource.change),
        (-96, SignalSource.beacon),
      ],
    );
    expect(h.first.at, at(5));
  });

  test('a beacon logged as a change is not counted twice', () {
    final h = signalHistory(
      nodeId: ridge,
      signalLog: [SignalShift(nodeId: ridge, fromDbm: -110, toDbm: -96, at: at(30))],
      neighbor: Neighbor(nodeId: ridge, lastSeen: at(30), rssiDbm: -96),
    );
    expect(h, hasLength(1));
  });

  test('nothing recorded: empty, never a guess', () {
    expect(
      signalHistory(
        nodeId: ridge,
        neighbor: Neighbor(nodeId: ridge, lastSeen: at(1)),
      ),
      isEmpty,
    );
  });

  test('keeps the newest readings only', () {
    final log = [
      for (var i = 0; i < kSignalHistoryMax + 50; i++)
        SignalShift(nodeId: ridge, fromDbm: -120, toDbm: -100 - i % 9, at: at(i)),
    ];
    final h = signalHistory(nodeId: ridge, signalLog: log);
    expect(h, hasLength(kSignalHistoryMax));
    expect(h.last.at, at(kSignalHistoryMax + 49));
  });

  test('uptime in words', () {
    expect(formatUptime(const Duration(seconds: 40)), '40 s');
    expect(formatUptime(const Duration(minutes: 12, seconds: 5)), '12 min');
    expect(formatUptime(const Duration(hours: 5, minutes: 12)), '5 h 12 min');
    expect(formatUptime(const Duration(hours: 2)), '2 h');
    expect(formatUptime(const Duration(days: 3, hours: 4, minutes: 9)), '3 d 4 h');
  });
}
