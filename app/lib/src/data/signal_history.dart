/// A node's signal over time, gathered from readings the app already keeps:
/// messages it sent us, the timeline's signal changes and its latest beacon.
/// Nothing is interpolated or guessed: each point is one frame the connected
/// node measured.
library;

import 'models.dart';
import 'timeline.dart';

/// Where a reading came from.
enum SignalSource {
  /// Its beacon (one hop: always the node itself).
  beacon('beacon'),

  /// A direct or channel message from it (the last hop: may be a relay).
  message('message'),

  /// A logged change of 10 dB or more (the new reading).
  change('signal change');

  const SignalSource(this.label);

  /// A word for the UI.
  final String label;
}

/// One measured reading.
class SignalReading {
  /// Creates a reading.
  const SignalReading({required this.at, required this.dbm, required this.source});

  /// When the frame was heard.
  final DateTime at;

  /// Its signal, whole dBm.
  final int dbm;

  /// What kind of frame it was.
  final SignalSource source;

  @override
  bool operator ==(Object other) =>
      other is SignalReading && other.at == at && other.dbm == dbm && other.source == source;

  @override
  int get hashCode => Object.hash(at, dbm, source);
}

/// Most readings kept for the graph (the newest).
const int kSignalHistoryMax = 200;

/// [nodeId]'s readings, oldest first, at most [kSignalHistoryMax].
///
/// Replayed messages are left out: their time is when the app got them, not
/// when the node heard them. Two readings at the same moment with the same
/// value count once.
List<SignalReading> signalHistory({
  required int nodeId,
  List<ChatMessage> messages = const [],
  Iterable<List<ChannelMessage>> channelMessages = const [],
  List<SignalShift> signalLog = const [],
  Neighbor? neighbor,
}) {
  final out = <SignalReading>[
    for (final m in messages)
      if (!m.outgoing && !m.replayed && m.peer == nodeId && m.rssiDbm != null)
        SignalReading(at: m.at, dbm: m.rssiDbm!, source: SignalSource.message),
    for (final list in channelMessages)
      for (final m in list)
        if (!m.outgoing && !m.replayed && m.src == nodeId && m.rssiDbm != null)
          SignalReading(at: m.at, dbm: m.rssiDbm!, source: SignalSource.message),
    for (final s in signalLog)
      if (s.nodeId == nodeId) SignalReading(at: s.at, dbm: s.toDbm, source: SignalSource.change),
    if (neighbor?.rssiDbm case final d?) SignalReading(at: neighbor!.lastSeen, dbm: d, source: SignalSource.beacon),
  ]..sort((a, b) => a.at.compareTo(b.at));
  final unique = <SignalReading>[];
  for (final r in out) {
    final dup = unique.isNotEmpty && unique.last.at == r.at && unique.last.dbm == r.dbm;
    if (!dup) unique.add(r);
  }
  return unique.length <= kSignalHistoryMax ? unique : unique.sublist(unique.length - kSignalHistoryMax);
}

/// "3 d 4 h", "5 h 12 min", "12 min", "40 s": how long a node has been up.
String formatUptime(Duration d) {
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    return h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
  }
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}
