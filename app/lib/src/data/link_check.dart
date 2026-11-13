/// A link check result as a path: the nodes in order and the signal measured
/// on each hop. One-hop link pings fill it today; a multi-hop route result
/// fits the same shape (more nodes, more hops), so the share card needs no
/// change for it.
library;

import '../link/geo.dart';

/// One node on the checked path.
class LinkCheckNode {
  /// Creates an entry.
  const LinkCheckNode({required this.nodeId, required this.name, this.pos});

  /// Node ID.
  final int nodeId;

  /// Display name (may be the hex ID).
  final String name;

  /// Last known position, if any. Positions are what the app last heard,
  /// not measured during the check.
  final LatLon? pos;
}

/// The signal on the hop between `nodes[i]` and `nodes[i + 1]`.
class LinkCheckHop {
  /// Creates a hop.
  const LinkCheckHop({this.forwardDbm, this.reverseDbm});

  /// How strongly the far end heard the near end, whole dBm (null: not measured).
  final int? forwardDbm;

  /// How strongly the near end heard the far end, whole dBm (null: not measured).
  final int? reverseDbm;
}

/// One finished check, ready to show or share.
class LinkCheck {
  /// Creates a result. [hops] has one entry fewer than [nodes].
  LinkCheck({
    required this.kind,
    required this.nodes,
    required this.hops,
    required this.at,
    required this.answered,
    this.elapsed,
  }) : assert(nodes.length >= 2, 'a path has two ends'),
       assert(hops.length == nodes.length - 1, 'one hop between each pair of nodes');

  /// A one-hop link ping from [origin] to [target].
  factory LinkCheck.linkPing({
    required LinkCheckNode origin,
    required LinkCheckNode target,
    required DateTime at,
    required bool answered,
    int? forwardDbm,
    int? reverseDbm,
    Duration? elapsed,
  }) => LinkCheck(
    kind: 'Link ping',
    nodes: [origin, target],
    hops: [if (answered) LinkCheckHop(forwardDbm: forwardDbm, reverseDbm: reverseDbm) else const LinkCheckHop()],
    at: at,
    answered: answered,
    elapsed: answered ? elapsed : null,
  );

  /// What kind of check, in words ("Link ping").
  final String kind;

  /// The path, from the node that ran the check to the one it reached.
  final List<LinkCheckNode> nodes;

  /// Signal per hop, in path order.
  final List<LinkCheckHop> hops;

  /// When the result arrived.
  final DateTime at;

  /// Whether the far end answered.
  final bool answered;

  /// Time from asking our node to getting the answer (includes the phone's
  /// link to its node). Null when there was no answer.
  final Duration? elapsed;

  /// The node that ran the check (the sender).
  LinkCheckNode get origin => nodes.first;

  /// The node checked.
  LinkCheckNode get target => nodes.last;

  /// Straight-line length of hop [i] in metres, when both ends have a position.
  double? hopDistanceM(int i) {
    final a = nodes[i].pos;
    final b = nodes[i + 1].pos;
    return a == null || b == null ? null : a.distanceTo(b);
  }

  /// Sum of all hop lengths in metres, when every node has a position.
  double? get totalDistanceM {
    var sum = 0.0;
    for (var i = 0; i < hops.length; i++) {
      final d = hopDistanceM(i);
      if (d == null) return null;
      sum += d;
    }
    return sum;
  }

  /// The nodes that have a position, in path order.
  List<LinkCheckNode> get placed => [
    for (final n in nodes)
      if (n.pos != null) n,
  ];
}
