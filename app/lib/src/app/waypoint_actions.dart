/// What the user can do with waypoints: drop one, share it with a contact or a
/// channel, edit or delete their own, and hide others'. The pins live in the
/// node's encrypted history ([MeshState.waypoints]); sharing sends one
/// ordinary message (see data/waypoints.dart).
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/waypoints.dart';
import '../link/geo.dart';
import 'mesh_controller.dart';
import 'providers.dart';

/// DM byte limit when the node does not say (a 1.0 node).
const int kWaypointDefaultDmBytes = 73;

/// Channel byte limit when the node does not say.
const int kWaypointDefaultChannelBytes = 86;

/// Where a waypoint goes: a contact, a channel, or nowhere (this phone only).
sealed class WaypointTarget {
  const WaypointTarget();
}

/// Kept on this phone only.
final class KeepLocal extends WaypointTarget {
  /// Creates it.
  const KeepLocal();

  @override
  bool operator ==(Object other) => other is KeepLocal;

  @override
  int get hashCode => 0;
}

/// Sent as a DM to [peer].
final class ToContact extends WaypointTarget {
  /// Creates it.
  const ToContact(this.peer);

  /// The contact's node ID.
  final int peer;

  @override
  bool operator ==(Object other) => other is ToContact && other.peer == peer;

  @override
  int get hashCode => peer.hashCode;
}

/// Posted in [channel].
final class ToChannel extends WaypointTarget {
  /// Creates it.
  const ToChannel(this.channel);

  /// The channel name.
  final String channel;

  @override
  bool operator ==(Object other) => other is ToChannel && other.channel == channel;

  @override
  int get hashCode => channel.hashCode;
}

/// Where our waypoint [w] was shared.
WaypointTarget targetOf(Waypoint w) => switch ((w.peer, w.channel)) {
  (_, final String ch) => ToChannel(ch),
  (final int p, null) => ToContact(p),
  _ => const KeepLocal(),
};

/// Why a waypoint could not be sent.
class WaypointTooLong implements Exception {
  /// Creates it.
  const WaypointTooLong(this.maxBytes);

  /// The limit it did not fit.
  final int maxBytes;

  @override
  String toString() => 'The waypoint does not fit one $maxBytes-byte radio message';
}

/// The actions.
class WaypointActions {
  /// Creates them over [ref].
  WaypointActions(this.ref);

  /// Where the mesh state lives.
  final Ref ref;

  final Random _rng = Random.secure();

  MeshController get _mesh => ref.read(meshProvider.notifier);

  DateTime _now() => ref.read(clockProvider)();

  /// The byte limit of one message to [t].
  int maxBytesFor(WaypointTarget t) {
    final info = ref.read(nodeInfoProvider);
    return switch (t) {
      ToChannel() => (info?.maxChannelTextBytes ?? 0) == 0 ? kWaypointDefaultChannelBytes : info!.maxChannelTextBytes,
      _ => (info?.maxTextBytes ?? 0) == 0 ? kWaypointDefaultDmBytes : info!.maxTextBytes,
    };
  }

  /// [w] as it will look after a trip over the air to [t]: name and note
  /// cleaned and cut to fit. Throws [WaypointTooLong] if it cannot fit.
  Waypoint fitted(Waypoint w, WaypointTarget t) {
    final max = t is KeepLocal ? 1 << 20 : maxBytesFor(t);
    final text = waypointText(w.toWire(), max);
    final back = text == null ? null : parseWaypoint(text);
    if (back is! WaypointPut) throw WaypointTooLong(max);
    return w.copyWith(name: back.name, note: back.note);
  }

  Future<void> _send(WaypointTarget t, String text) async {
    switch (t) {
      case ToContact(:final peer):
        await _mesh.sendText(peer, text);
      case ToChannel(:final channel):
        await _mesh.sendChannelText(channel, text);
      case KeepLocal():
        break;
    }
  }

  Waypoint _withTarget(Waypoint w, WaypointTarget t) => switch (t) {
    ToContact(:final peer) => w.copyWith(clearPlace: true, peer: peer),
    ToChannel(:final channel) => w.copyWith(clearPlace: true, channel: channel),
    KeepLocal() => w.copyWith(clearPlace: true),
  };

  /// Drops a new waypoint of ours at [pos] and sends it to [to]. Returns it.
  Future<Waypoint> create({
    required WaypointKind kind,
    required String name,
    required LatLon pos,
    String note = '',
    WaypointTarget to = const KeepLocal(),
  }) async {
    final draft = Waypoint(
      id: newWaypointId(_rng, ref.read(meshProvider).waypoints.ownIds),
      kind: kind,
      name: cleanWaypointText(name, kWaypointNameMax),
      pos: pos,
      at: _now(),
      note: cleanWaypointText(note, kWaypointNoteMax),
    );
    final w = _withTarget(fitted(draft, to), to);
    _mesh.updateWaypoints((b) => b.put(w));
    if (to is! KeepLocal) await _send(to, waypointText(w.toWire(), maxBytesFor(to))!);
    return w;
  }

  /// Changes our waypoint [key]; if it was shared, the change is sent to the
  /// same place so it updates on others' maps too.
  Future<Waypoint?> edit(String key, {WaypointKind? kind, String? name, String? note, LatLon? pos}) async {
    final old = ref.read(meshProvider).waypoints.byKey[key];
    if (old == null || !old.mine) return null;
    final to = targetOf(old);
    final w = fitted(
      old.copyWith(
        kind: kind,
        name: name == null ? null : cleanWaypointText(name, kWaypointNameMax),
        note: note == null ? null : cleanWaypointText(note, kWaypointNoteMax),
        pos: pos,
        at: _now(),
      ),
      to,
    );
    _mesh.updateWaypoints((b) => b.put(w));
    if (to is! KeepLocal) await _send(to, waypointText(w.toWire(), maxBytesFor(to))!);
    return w;
  }

  /// Sends our waypoint [key] to [to] (it was kept local, or goes somewhere
  /// new). Later edits and the delete go there.
  Future<void> share(String key, WaypointTarget to) async {
    final old = ref.read(meshProvider).waypoints.byKey[key];
    if (old == null || !old.mine || to is KeepLocal) return;
    final w = _withTarget(fitted(old, to), to);
    _mesh.updateWaypoints((b) => b.put(w));
    await _send(to, waypointText(w.toWire(), maxBytesFor(to))!);
  }

  /// Deletes our waypoint [key]. If it was shared, a short removal message
  /// takes it off others' maps too.
  Future<void> delete(String key) async {
    final old = ref.read(meshProvider).waypoints.byKey[key];
    if (old == null || !old.mine) return;
    _mesh.updateWaypoints((b) => b.remove(key));
    final to = targetOf(old);
    if (to is! KeepLocal) await _send(to, waypointRemovalText(old.id, old.name, maxBytesFor(to)));
  }

  /// Hides (or shows again) someone else's waypoint on this phone only.
  void setHidden(String key, bool hidden) => _mesh.updateWaypoints((b) => b.setHidden(key, hidden));

  /// Forgets someone else's waypoint on this phone (it comes back if they
  /// send it again).
  void forget(String key) {
    final w = ref.read(meshProvider).waypoints.byKey[key];
    if (w == null || w.mine) return;
    _mesh.updateWaypoints((b) => b.remove(key));
  }
}

/// The waypoint actions.
final waypointActionsProvider = Provider<WaypointActions>(WaypointActions.new);
