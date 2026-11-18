import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/traffic.dart';
import '../gen/ghostwave.pb.dart' as pb;
import 'mesh_controller.dart';
import 'providers.dart';

/// Turns a node event into the packet it stands for, or null when it is not
/// a packet heard over the air (answers to requests, status, replays).
/// [own] is our node's ID, the last stop of every route, when known.
TrafficPacket? packetFromEvent(pb.FromRadio e, {required int? own, required DateTime now}) {
  // replayed events were heard while no app was connected: not live traffic
  if (e.replayed) return null;
  bool real(int id) => id != 0 && id != 0xFFFFFFFF && id != own;
  List<int> toUs(int from) => [from, ?own];
  TrafficPacket simple(TrafficKind kind, int from, {int? rssi, int? hops, int? lastHop}) =>
      TrafficPacket(kind: kind, path: toUs(from), at: now, rssiDbm: rssi, hops: hops, lastHop: lastHop);

  switch (e.whichEvent()) {
    case pb.FromRadio_Event.neighbor:
      final n = e.neighbor;
      if (!real(n.nodeId)) return null;
      // a beacon is heard straight from the node that sent it
      return simple(TrafficKind.advert, n.nodeId, rssi: n.hasRssiDbm() ? n.rssiDbm : null, hops: 1, lastHop: n.nodeId);
    case pb.FromRadio_Event.peerIdent:
      final p = e.peerIdent;
      return real(p.nodeId) ? simple(TrafficKind.advert, p.nodeId) : null;
    case pb.FromRadio_Event.text:
      final t = e.text;
      return real(t.src) ? simple(TrafficKind.direct, t.src, rssi: t.hasRssiDbm() ? t.rssiDbm : null) : null;
    case pb.FromRadio_Event.channelMessage:
      final c = e.channelMessage;
      return real(c.src) ? simple(TrafficKind.channel, c.src, rssi: c.hasRssiDbm() ? c.rssiDbm : null) : null;
    case pb.FromRadio_Event.delivered:
      final d = e.delivered;
      return real(d.dest) ? simple(TrafficKind.ack, d.dest, rssi: d.hasRssiDbm() ? d.rssiDbm : null) : null;
    case pb.FromRadio_Event.sosAck:
      final a = e.sosAck;
      return real(a.responder) ? simple(TrafficKind.ack, a.responder) : null;
    case pb.FromRadio_Event.linkPingResult:
      final r = e.linkPingResult;
      if (!r.answered || !real(r.nodeId)) return null;
      // a link check only reaches nodes heard directly
      return simple(
        TrafficKind.ack,
        r.nodeId,
        rssi: r.hasReverseRssiDbm() ? r.reverseRssiDbm : null,
        hops: 1,
        lastHop: r.nodeId,
      );
    case pb.FromRadio_Event.traceResult:
      final r = e.traceResult;
      if (!r.answered || !real(r.nodeId)) return null;
      // back: the relays from the target in order, then our node
      final back = r.backNodes;
      if (back.isEmpty) return simple(TrafficKind.trace, r.nodeId);
      final path = [r.nodeId, ...back];
      final relays = back.length - 1;
      return TrafficPacket(
        kind: TrafficKind.trace,
        path: path,
        pathKnown: true,
        at: now,
        hops: back.length,
        lastHop: relays > 0 ? back[relays - 1] : r.nodeId,
        rssiDbm: r.backRssiDbm.length == back.length ? r.backRssiDbm.last : null,
      );
    case pb.FromRadio_Event.sos:
      final a = e.sos;
      return real(a.src) ? simple(TrafficKind.other, a.src) : null;
    case pb.FromRadio_Event.sosCancelled:
      final c = e.sosCancelled;
      return real(c.src) ? simple(TrafficKind.other, c.src) : null;
    default:
      return null;
  }
}

/// The traffic view's state: what it shows and the packets heard lately.
class TrafficState {
  /// Creates the state.
  const TrafficState({
    this.on = false,
    this.kinds = const {...TrafficKind.values},
    this.hopLabels = true,
    this.recent = const [],
    this.serial = 0,
  });

  /// Whether the map shows traffic.
  final bool on;

  /// The packet kinds shown.
  final Set<TrafficKind> kinds;

  /// Whether hop names show beside each hop while a route is on screen.
  final bool hopLabels;

  /// The latest packets of the shown kinds, newest first.
  final List<TrafficPacket> recent;

  /// Counts every packet added, so a listener can tell a new one apart from
  /// an equal-looking older one.
  final int serial;

  /// The newest packet, if any.
  TrafficPacket? get latest => recent.firstOrNull;

  /// A copy with the given fields changed.
  TrafficState copyWith({
    bool? on,
    Set<TrafficKind>? kinds,
    bool? hopLabels,
    List<TrafficPacket>? recent,
    int? serial,
  }) => TrafficState(
    on: on ?? this.on,
    kinds: kinds ?? this.kinds,
    hopLabels: hopLabels ?? this.hopLabels,
    recent: recent ?? this.recent,
    serial: serial ?? this.serial,
  );
}

/// How many packets the traffic view remembers.
const int kTrafficKeep = 50;

/// The traffic view.
final trafficProvider = NotifierProvider<TrafficController, TrafficState>(TrafficController.new);

/// Listens to the node's live events while the traffic view is on.
class TrafficController extends Notifier<TrafficState> {
  @override
  TrafficState build() {
    final link = ref.watch(nodeLinkProvider);
    final sub = link.events.listen(_onEvent);
    ref.onDispose(() => unawaited(sub.cancel()));
    return const TrafficState();
  }

  void _onEvent(pb.FromRadio e) {
    if (!state.on) return;
    final p = packetFromEvent(e, own: ref.read(meshProvider).nodeId, now: ref.read(clockProvider)());
    if (p != null) add(p);
  }

  /// Adds a heard packet, if its kind is shown.
  void add(TrafficPacket p) {
    if (!state.kinds.contains(p.kind)) return;
    state = state.copyWith(recent: [p, ...state.recent.take(kTrafficKeep - 1)], serial: state.serial + 1);
  }

  /// Turns the traffic view on or off. Off forgets what was heard.
  void setOn(bool on) => state = on ? state.copyWith(on: true) : state.copyWith(on: false, recent: const []);

  /// Shows or hides packets of [kind].
  void setKind(TrafficKind kind, bool shown) {
    final kinds = {...state.kinds};
    shown ? kinds.add(kind) : kinds.remove(kind);
    state = state.copyWith(
      kinds: kinds,
      recent: [
        for (final p in state.recent)
          if (kinds.contains(p.kind)) p,
      ],
    );
  }

  /// Shows or hides hop names on routes.
  void setHopLabels(bool on) => state = state.copyWith(hopLabels: on);

  /// Forgets the packets heard so far.
  void clear() => state = state.copyWith(recent: const []);
}
