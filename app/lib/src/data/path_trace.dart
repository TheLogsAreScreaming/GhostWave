// The result of a multi-hop traceroute (client protocol 1.10, docs/TRACEROUTE.md):
// the path a probe took out to a node and the path its answer took back, each
// hop with the signal the receiving radio measured. Plain data, no Flutter, so
// other screens (link checks, history, sharing) can use it.

/// One radio on a traced path.
class TraceStep {
  /// Creates a step.
  const TraceStep({required this.node, required this.rssiDbm});

  /// The node ID of the radio that received the frame.
  final int node;

  /// How strongly that radio heard the frame it received, in dBm. On the way
  /// out that is the probe from the hop before it; on the way back, the answer.
  final int rssiDbm;

  /// The JSON form, for saving.
  Map<String, Object> toJson() => {'node': node, 'rssi': rssiDbm};

  /// Reads [toJson]'s form; null when malformed.
  static TraceStep? fromJson(Object? j) {
    if (j is! Map) return null;
    final node = j['node'], rssi = j['rssi'];
    if (node is! int || rssi is! int) return null;
    return TraceStep(node: node, rssiDbm: rssi);
  }

  @override
  bool operator ==(Object other) => other is TraceStep && other.node == node && other.rssiDbm == rssiDbm;

  @override
  int get hashCode => Object.hash(node, rssiDbm);
}

/// A finished traceroute.
class PathTrace {
  /// Creates a trace result.
  const PathTrace({
    required this.target,
    required this.answered,
    required this.at,
    this.out = const [],
    this.back = const [],
  });

  /// An unanswered trace: nothing is known about the path.
  const PathTrace.unanswered({required this.target, required this.at})
    : answered = false,
      out = const [],
      back = const [];

  /// The node traced to.
  final int target;

  /// Whether its answer came back in time. When false, [out] and [back] are
  /// empty: a lost probe or answer tells nothing about where it was lost.
  final bool answered;

  /// When the result arrived.
  final DateTime at;

  /// The way out: the relays in order, then [target].
  final List<TraceStep> out;

  /// The way back: the relays from [target] in order, then our own radio.
  final List<TraceStep> back;

  /// Hops on the way out (the number of radio transmissions).
  int get hopsOut => out.length;

  /// Hops on the way back.
  int get hopsBack => back.length;

  /// The relays on the way out, without the target.
  List<int> get relaysOut => [for (final s in out.take(out.isEmpty ? 0 : out.length - 1)) s.node];

  /// The relays on the way back, without our own radio.
  List<int> get relaysBack => [for (final s in back.take(back.isEmpty ? 0 : back.length - 1)) s.node];

  /// Whether the answer came back through the same relays the probe took
  /// (in reverse). Routes here are not fixed, so this is often false.
  bool get sameWayBack => answered && _listEq(relaysOut.reversed.toList(), relaysBack);

  /// The weakest reading on either way, or null when unanswered.
  TraceStep? get weakest {
    TraceStep? w;
    for (final s in [...out, ...back]) {
      if (w == null || s.rssiDbm < w.rssiDbm) w = s;
    }
    return w;
  }

  /// The JSON form, for saving.
  Map<String, Object> toJson() => {
    'target': target,
    'answered': answered,
    'at': at.toUtc().toIso8601String(),
    'out': [for (final s in out) s.toJson()],
    'back': [for (final s in back) s.toJson()],
  };

  /// Reads [toJson]'s form; null when malformed.
  static PathTrace? fromJson(Object? j) {
    if (j is! Map) return null;
    final target = j['target'], answered = j['answered'], at = DateTime.tryParse('${j['at']}');
    if (target is! int || answered is! bool || at == null) return null;
    List<TraceStep>? steps(Object? v) {
      if (v is! List) return null;
      final r = <TraceStep>[];
      for (final e in v) {
        final s = TraceStep.fromJson(e);
        if (s == null) return null;
        r.add(s);
      }
      return r;
    }

    final out = steps(j['out']), back = steps(j['back']);
    if (out == null || back == null) return null;
    if (!answered) return PathTrace.unanswered(target: target, at: at.toLocal());
    return PathTrace(target: target, answered: true, at: at.toLocal(), out: out, back: back);
  }
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
