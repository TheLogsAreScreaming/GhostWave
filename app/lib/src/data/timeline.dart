/// The timeline: one feed of what happened on the mesh, newest first. Built
/// from history the app already keeps (messages, the node journal, SOS state)
/// plus a short log of signal changes; nothing here talks to the node.
library;

import '../link/contact_card.dart';
import '../link/geo.dart';
import 'message_refs.dart';
import 'models.dart';
import 'node_journal.dart';
import 'trip.dart';

/// What a timeline entry is about. Each kind is one filter.
enum TimelineKind {
  /// A direct or channel message, either way.
  message('Messages'),

  /// A node heard for the first time.
  node('New nodes'),

  /// A node's signal moved by [kSignalShiftDb] or more.
  signal('Signal'),

  /// SOS alerts, acks and our own SOS.
  alert('Alerts'),

  /// A position someone shared (check-ins with a position).
  position('Positions');

  const TimelineKind(this.label);

  /// Filter label.
  final String label;
}

/// A change this large (whole dB) between two readings of one node is logged.
const int kSignalShiftDb = 10;

/// Most signal changes kept per node history (oldest go first).
const int kSignalLogMax = 300;

/// One logged signal change: [nodeId] was heard at [fromDbm], now at [toDbm].
class SignalShift {
  /// Creates an entry.
  const SignalShift({required this.nodeId, required this.fromDbm, required this.toDbm, required this.at});

  /// From [toJson]; null when malformed.
  static SignalShift? tryFromJson(Object? j) {
    if (j case [final int id, final int from, final int to, final int ms]) {
      return SignalShift(nodeId: id, fromDbm: from, toDbm: to, at: DateTime.fromMillisecondsSinceEpoch(ms));
    }
    return null;
  }

  /// The node.
  final int nodeId;

  /// The reading before, whole dBm.
  final int fromDbm;

  /// The new reading, whole dBm.
  final int toDbm;

  /// When the new reading arrived.
  final DateTime at;

  /// Change in dB: positive is stronger.
  int get deltaDb => toDbm - fromDbm;

  /// Compact JSON form: `[id, from, to, ms]`.
  List<int> toJson() => [nodeId, fromDbm, toDbm, at.millisecondsSinceEpoch];

  @override
  bool operator ==(Object other) =>
      other is SignalShift &&
      other.nodeId == nodeId &&
      other.fromDbm == fromDbm &&
      other.toDbm == toDbm &&
      other.at == at;

  @override
  int get hashCode => Object.hash(nodeId, fromDbm, toDbm, at);
}

/// [log] with a shift added when [previous] and [current] differ by at least
/// [kSignalShiftDb]; otherwise [log] itself. Keeps the newest [kSignalLogMax].
List<SignalShift> recordSignal(List<SignalShift> log, int nodeId, int? previous, int current, DateTime at) {
  if (previous == null || (current - previous).abs() < kSignalShiftDb) return log;
  final next = [...log, SignalShift(nodeId: nodeId, fromDbm: previous, toDbm: current, at: at)];
  return next.length <= kSignalLogMax ? next : next.sublist(next.length - kSignalLogMax);
}

/// Reads a saved signal log, skipping malformed entries.
List<SignalShift> signalLogFromJson(Object? j) => [
  if (j is List)
    for (final x in j) ?SignalShift.tryFromJson(x),
];

/// One line in the feed.
class TimelineEvent {
  /// Creates an entry.
  const TimelineEvent({
    required this.kind,
    required this.at,
    required this.title,
    this.detail = '',
    this.nodeId,
    this.channel,
    this.pos,
  });

  /// What it is about.
  final TimelineKind kind;

  /// When it happened (as this phone saw it).
  final DateTime at;

  /// One line, plain words.
  final String title;

  /// More, if there is any.
  final String detail;

  /// The node it is about, if one.
  final int? nodeId;

  /// The channel, for channel messages.
  final String? channel;

  /// A position, if it carried one.
  final LatLon? pos;
}

String _preview(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 120 ? flat : '${flat.substring(0, 119)}…';
}

String _posText(LatLon p) => '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';

String _dbm(int? v) => v == null ? '' : ' · $v dBm';

/// Builds the whole feed, newest first. [nameOf] names a node for display.
List<TimelineEvent> buildTimeline({
  required String Function(int id) nameOf,
  Map<int, List<ChatMessage>> messages = const {},
  Map<String, List<ChannelMessage>> channelMessages = const {},
  NodeJournal journal = const NodeJournal(),
  List<SignalShift> signalLog = const [],
  List<SosAlertEntry> alerts = const [],
  OwnSos ownSos = const OwnSos(),
}) {
  final out = <TimelineEvent>[];

  for (final thread in messages.values) {
    for (final m in thread) {
      // coverage-walk probes are quiet by design: keep them out of the feed
      if (m.text.startsWith('[Coverage] ')) continue;
      // reactions show on their message, not as events of their own
      if (parseMeshText(m.text) is ReactionText) continue;
      final who = nameOf(m.peer);
      final checkIn = parseCheckIn(m.text);
      if (checkIn?.pos case final p?) {
        out.add(
          TimelineEvent(
            kind: TimelineKind.position,
            at: m.at,
            title: m.outgoing ? 'You shared your position with $who' : '$who shared a position',
            detail: '${checkIn!.kind.label} · ${_posText(p)}',
            nodeId: m.peer,
            pos: p,
          ),
        );
        continue;
      }
      out.add(
        TimelineEvent(
          kind: TimelineKind.message,
          at: m.at,
          title: m.outgoing ? 'You to $who' : '$who to you',
          detail: '${_preview(friendlyText(m.text))}${m.outgoing ? '' : _dbm(m.rssiDbm)}',
          nodeId: m.peer,
        ),
      );
    }
  }

  for (final e in channelMessages.entries) {
    for (final m in e.value) {
      if (parseMeshText(m.text) is ReactionText) continue;
      final who = m.outgoing ? 'You' : nameOf(m.src);
      final checkIn = parseCheckIn(m.text);
      if (checkIn?.pos case final p?) {
        out.add(
          TimelineEvent(
            kind: TimelineKind.position,
            at: m.at,
            title: m.outgoing ? 'You shared your position in #${e.key}' : '$who shared a position in #${e.key}',
            detail: '${checkIn!.kind.label} · ${_posText(p)}',
            nodeId: m.outgoing ? null : m.src,
            channel: e.key,
            pos: p,
          ),
        );
        continue;
      }
      out.add(
        TimelineEvent(
          kind: TimelineKind.message,
          at: m.at,
          title: '$who in #${e.key}',
          detail: '${_preview(friendlyText(m.text))}${m.outgoing ? '' : _dbm(m.rssiDbm)}',
          nodeId: m.outgoing ? null : m.src,
          channel: e.key,
        ),
      );
    }
  }

  for (final e in journal.entries.values) {
    final via = e.via.keys.isEmpty ? '' : ' (${e.via.keys.first.name})';
    out.add(
      TimelineEvent(
        kind: TimelineKind.node,
        at: e.firstHeard,
        title: 'First heard ${nameOf(e.nodeId)}',
        detail: 'New node ${nodeIdHex(e.nodeId)}$via',
        nodeId: e.nodeId,
        pos: e.fixes.isEmpty ? null : e.fixes.first,
      ),
    );
  }

  for (final s in signalLog) {
    final stronger = s.deltaDb > 0;
    out.add(
      TimelineEvent(
        kind: TimelineKind.signal,
        at: s.at,
        title: '${nameOf(s.nodeId)} ${stronger ? 'stronger' : 'weaker'} by ${s.deltaDb.abs()} dB',
        detail: '${s.fromDbm} dBm to ${s.toDbm} dBm',
        nodeId: s.nodeId,
      ),
    );
  }

  for (final a in alerts) {
    final who = nameOf(a.src);
    final bits = [
      if (a.text.isNotEmpty) _preview(a.text),
      if (a.pos case final p?) _posText(p),
      if (a.batteryPct case final b?) 'battery $b%',
      if (a.cancelled) a.cancelVerified ? 'ended by sender (signature checked)' : 'ended by sender (not checked)',
      if (a.acked) 'you answered',
    ];
    out.add(
      TimelineEvent(
        kind: TimelineKind.alert,
        at: a.receivedAt,
        title: 'SOS from $who',
        detail: bits.join(' · '),
        nodeId: a.src,
        pos: a.pos,
      ),
    );
  }

  if (ownSos.startedAt case final t?) {
    out.add(
      TimelineEvent(
        kind: TimelineKind.alert,
        at: t,
        title: ownSos.active ? 'You raised an SOS (still on)' : 'You raised an SOS',
        detail: ownSos.text.isEmpty ? '' : _preview(ownSos.text),
      ),
    );
  }
  for (final ack in ownSos.acks) {
    out.add(
      TimelineEvent(
        kind: TimelineKind.alert,
        at: ack.at,
        title: '${nameOf(ack.responder)} answered your SOS',
        nodeId: ack.responder,
      ),
    );
  }

  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// The entries of [events] whose kind is in [kinds] and whose words match
/// [query] (case-insensitive; empty matches everything).
List<TimelineEvent> filterTimeline(List<TimelineEvent> events, Set<TimelineKind> kinds, String query) {
  final q = query.trim().toLowerCase();
  return [
    for (final e in events)
      if (kinds.contains(e.kind) &&
          (q.isEmpty ||
              e.title.toLowerCase().contains(q) ||
              e.detail.toLowerCase().contains(q) ||
              (e.nodeId != null && nodeIdHex(e.nodeId!).contains(q)) ||
              (e.channel?.toLowerCase().contains(q) ?? false)))
        e,
  ];
}
