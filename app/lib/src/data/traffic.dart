// Live traffic: packets the node reports hearing, and the route each one took
// across the map. Plain data, no Flutter, so the map, tests and anything else
// can build routes the same way.
//
// GhostWave's client protocol reports who sent a frame and how strongly the
// last hop was heard. Only a traceroute names every relay, so most routes are
// sender → us; a trace draws every hop of its way back. Nothing is guessed:
// unknown hop counts stay unknown.

import '../link/geo.dart';

/// What kind of packet was heard. Each kind has one colour on the map.
enum TrafficKind {
  /// A node announcing itself: a beacon or a signed identity.
  advert('Advert'),

  /// A direct (end-to-end encrypted) message to us.
  direct('Direct message'),

  /// A message on a group channel.
  channel('Channel message'),

  /// A receipt or answer: delivery receipt, SOS acknowledgement, link check.
  ack('Acknowledgement'),

  /// A traceroute answer, with every relay of its way back.
  trace('Trace'),

  /// Anything else: SOS alerts and their cancels.
  other('Other');

  const TrafficKind(this.label);

  /// The name shown in the legend and on the type pill.
  final String label;
}

/// One packet heard live.
class TrafficPacket {
  /// Creates a packet.
  const TrafficPacket({
    required this.kind,
    required this.path,
    required this.at,
    this.pathKnown = false,
    this.hops,
    this.lastHop,
    this.rssiDbm,
  });

  /// What it was.
  final TrafficKind kind;

  /// The nodes it passed, in order: the sender first, our own node last (when
  /// our node ID is known). Without [pathKnown] the relays between are not
  /// listed, so a two-node path means "sender, then us", not "one hop".
  final List<int> path;

  /// Whether [path] lists every relay (a traceroute's way back).
  final bool pathKnown;

  /// How many radio transmissions it took to reach us, when known.
  final int? hops;

  /// The node our radio heard it from, when known.
  final int? lastHop;

  /// How strongly our node heard the last hop, in dBm, when reported.
  final int? rssiDbm;

  /// When it was heard.
  final DateTime at;

  /// The sender.
  int get origin => path.first;
}

/// A node on a route that has a position.
class RoutePoint {
  /// Creates a point.
  const RoutePoint(this.node, this.pos);

  /// The node.
  final int node;

  /// Where it is.
  final LatLon pos;

  @override
  bool operator ==(Object other) => other is RoutePoint && other.node == node && other.pos == pos;

  @override
  int get hashCode => Object.hash(node, pos);

  @override
  String toString() => 'RoutePoint($node, $pos)';
}

/// A packet's route as it can be drawn: the hops with a position, in order.
class TrafficRoute {
  /// Creates a route.
  const TrafficRoute({required this.packet, required this.points, required this.offMap});

  /// The packet.
  final TrafficPacket packet;

  /// The hops that have a position, in order. Hops without one are skipped,
  /// so the line jumps from one known hop to the next.
  final List<RoutePoint> points;

  /// The hops that have no position, in order, each once.
  final List<int> offMap;

  /// The lines to draw: one between each pair of [points].
  int get legs => points.length < 2 ? 0 : points.length - 1;

  /// Whether there is at least one line to draw.
  bool get drawable => legs > 0;
}

/// Builds the drawable route of [p]. [posOf] gives a node's position, or null
/// when it has none. A node listed twice in a row (a radio hearing its own
/// repeat) is drawn once.
TrafficRoute buildRoute(TrafficPacket p, LatLon? Function(int node) posOf) {
  final points = <RoutePoint>[];
  final offMap = <int>[];
  int? prev;
  for (final node in p.path) {
    if (node == prev) continue;
    prev = node;
    final pos = posOf(node);
    if (pos == null) {
      if (!offMap.contains(node)) offMap.add(node);
      continue;
    }
    // two hops at the same spot would draw a zero-length leg
    if (points.isNotEmpty && points.last.pos == pos) continue;
    points.add(RoutePoint(node, pos));
  }
  return TrafficRoute(packet: p, points: points, offMap: offMap);
}

/// The route in words: `Sender → relay → … → You`, using [nameOf].
String routeText(TrafficPacket p, String Function(int node) nameOf) {
  final names = <String>[];
  int? prev;
  for (final n in p.path) {
    if (n == prev) continue;
    prev = n;
    names.add(nameOf(n));
  }
  return names.join(' → ');
}

/// "Heard from …" and the signal, as known.
String heardText(TrafficPacket p, String Function(int node) nameOf) {
  final from = p.lastHop;
  final dbm = p.rssiDbm;
  return [if (from != null) 'Heard from ${nameOf(from)}' else 'Heard', if (dbm != null) '$dbm dBm'].join(' · ');
}

/// Hop count, signal, hops off the map and age, as known.
String detailText(TrafficRoute r, DateTime now) {
  final p = r.packet;
  final age = now.difference(p.at).inSeconds;
  final hops = p.hops;
  return [
    switch (hops) {
      null => 'Hops unknown',
      1 => 'Direct · 1 hop',
      _ => '$hops hops',
    },
    if (p.rssiDbm != null) '${p.rssiDbm} dBm',
    '${r.offMap.length} not on map',
    '${age < 0 ? 0 : age}s ago',
  ].join(' · ');
}

/// Holds the packets waiting to be animated, at most [maxActive] at once.
/// Pure bookkeeping: the caller's clock decides when one is finished.
class TrafficQueue {
  /// Creates a queue.
  TrafficQueue({this.maxActive = 3, this.maxWaiting = 12});

  /// How many routes may animate at the same time.
  final int maxActive;

  /// How many may wait; the oldest waiting one is dropped past that.
  final int maxWaiting;

  final List<TrafficRoute> _active = [];
  final List<TrafficRoute> _waiting = [];

  /// The routes animating now, oldest first.
  List<TrafficRoute> get active => List.unmodifiable(_active);

  /// The routes waiting their turn, oldest first.
  List<TrafficRoute> get waiting => List.unmodifiable(_waiting);

  /// Adds [r]: it starts at once when a slot is free, otherwise waits.
  /// Returns whether it started.
  bool add(TrafficRoute r) {
    if (_active.length < maxActive) {
      _active.add(r);
      return true;
    }
    _waiting.add(r);
    if (_waiting.length > maxWaiting) _waiting.removeAt(0);
    return false;
  }

  /// Ends [r] and starts the next waiting route, which it returns (or null).
  TrafficRoute? finish(TrafficRoute r) {
    if (!_active.remove(r)) return null;
    if (_waiting.isEmpty) return null;
    final next = _waiting.removeAt(0);
    _active.add(next);
    return next;
  }

  /// Drops everything.
  void clear() {
    _active.clear();
    _waiting.clear();
  }
}
