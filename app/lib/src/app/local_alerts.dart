/// Phone notifications about your own radio and the people around it: low
/// radio battery, a node heard for the first time, and a trip contact your
/// radio has stopped hearing. Decided by [LocalAlertEngine]; this wires it to
/// the radio's status, its neighbor beacons and the trip, and to settings.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gen/ghostwave.pb.dart' as pb;
import '../link/node_link.dart';
import 'local_alert_engine.dart';
import 'mesh_alerts.dart';
import 'mesh_controller.dart';
import 'providers.dart';
import 'trip_controller.dart';

/// Which local alerts are on. Saved in preferences.
class LocalAlertSettings {
  /// Creates the settings.
  const LocalAlertSettings({this.battery = true, this.newNode = false, this.quiet = true});

  /// Radio battery at 20 % and again at 10 %.
  final bool battery;

  /// A node your radio hears for the first time this session. Off by default:
  /// busy areas would be noisy.
  final bool newNode;

  /// A trip contact your radio has not heard for 30 minutes, while a trip is on.
  final bool quiet;

  /// A copy with changes.
  LocalAlertSettings copyWith({bool? battery, bool? newNode, bool? quiet}) => LocalAlertSettings(
    battery: battery ?? this.battery,
    newNode: newNode ?? this.newNode,
    quiet: quiet ?? this.quiet,
  );
}

/// Reads and saves [LocalAlertSettings].
class LocalAlertSettingsNotifier extends Notifier<LocalAlertSettings> {
  static const _battery = 'alert_battery';
  static const _newNode = 'alert_new_node';
  static const _quiet = 'alert_quiet';

  @override
  LocalAlertSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    return LocalAlertSettings(
      battery: p.getBool(_battery) ?? true,
      newNode: p.getBool(_newNode) ?? false,
      quiet: p.getBool(_quiet) ?? true,
    );
  }

  /// Saves [s].
  void set(LocalAlertSettings s) {
    state = s;
    final p = ref.read(sharedPrefsProvider);
    unawaited(p.setBool(_battery, s.battery));
    unawaited(p.setBool(_newNode, s.newNode));
    unawaited(p.setBool(_quiet, s.quiet));
  }
}

/// Local alert settings.
final localAlertSettingsProvider = NotifierProvider<LocalAlertSettingsNotifier, LocalAlertSettings>(
  LocalAlertSettingsNotifier.new,
);

/// Nodes heard this soon after connecting are the baseline, not "new": the
/// radio already knew them, and the app is only catching up.
const Duration kNewNodeBaseline = Duration(minutes: 2);

/// Turns link, status, beacon and timer events into notifications. Plain
/// Dart over a [Ref], so tests drive it directly with a fake clock.
class LocalAlertsRunner {
  /// Creates the runner.
  LocalAlertsRunner(this._ref);

  final Ref _ref;
  final LocalAlertEngine _engine = LocalAlertEngine();
  DateTime? _sessionStart;

  DateTime _now() => _ref.read(clockProvider)();

  /// The link changed state.
  void onLinkState(LinkState s) {
    switch (s) {
      case LinkUp():
        _engine.resetSession(); // a new radio, or the same one after a gap: start over
        _sessionStart = _now();
      case LinkIdle() || LinkFailed() || LinkNeedsPin() || LinkWaiting():
        _sessionStart = null;
      case LinkConnecting():
        break;
    }
  }

  /// A heartbeat's status. A radio that cannot read its battery never counts as low.
  void onStatus(pb.Status status) {
    if (!status.hasBatteryPct()) return;
    final e = _engine.battery(status.batteryPct);
    if (e != null) _notify(e);
  }

  /// The neighbor list changed (a beacon arrived).
  void onNeighbors(MeshState mesh) {
    if (_sessionStart == null) return;
    final baseline = _now().difference(_sessionStart!) < kNewNodeBaseline;
    for (final n in mesh.neighbors.values) {
      final e = _engine.heard(n.nodeId, n.lastSeen, notifyFirst: !baseline);
      if (e != null) _notify(e);
    }
  }

  /// Once a minute: trip contacts the radio has stopped hearing.
  void tick() {
    final trip = _ref.read(tripProvider);
    if (!trip.plan.active) return;
    final up = _sessionStart != null;
    for (final e in _engine.checkQuiet(_now(), trip.plan.contacts.toSet(), connected: up)) {
      _notify(e);
    }
  }

  void _notify(LocalAlertEvent e) {
    final s = _ref.read(localAlertSettingsProvider);
    final mesh = _ref.read(meshProvider);
    final alerts = _ref.read(meshAlertsProvider);
    final name = e.nodeId == null ? '' : mesh.nameOf(e.nodeId!);
    final Future<void> shown;
    switch (e.kind) {
      case LocalAlertKind.batteryLow:
      case LocalAlertKind.batteryCritical:
        if (!s.battery) return;
        shown = alerts.radioAlert(
          id: 1,
          title: e.kind == LocalAlertKind.batteryCritical ? 'Radio battery very low' : 'Radio battery low',
          body: '${e.message}. Charge it or swap batteries soon.',
        );
      case LocalAlertKind.newNode:
        if (!s.newNode) return;
        shown = alerts.radioAlert(id: e.nodeId!, title: 'New node heard', body: '$name is in radio range.');
      case LocalAlertKind.contactQuiet:
        if (!s.quiet) return;
        shown = alerts.tripAlert(
          id: e.nodeId! ^ 0x55,
          title: '$name has gone quiet',
          body: 'Your radio has not heard them for over 30 minutes. They may be out of range.',
        );
    }
    unawaited(shown.catchError((Object _) {}));
  }
}

/// Runs the local alerts while the app is alive: battery from each heartbeat,
/// new nodes from beacons, quiet trip contacts every minute.
final localAlertsProvider = Provider<void>((ref) {
  final runner = LocalAlertsRunner(ref);
  final link = ref.watch(nodeLinkProvider);
  runner.onLinkState(link.state);
  final states = link.states.listen(runner.onLinkState);
  final beats = link.heartbeats.listen(runner.onStatus);
  ref.listen(meshProvider.select((m) => m.neighbors), (_, _) => runner.onNeighbors(ref.read(meshProvider)));
  final timer = Timer.periodic(const Duration(minutes: 1), (_) => runner.tick());
  ref.onDispose(() {
    timer.cancel();
    unawaited(states.cancel());
    unawaited(beats.cancel());
  });
});
