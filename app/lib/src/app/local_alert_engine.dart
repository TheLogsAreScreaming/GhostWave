/// Offline alert decision logic for GhostWave. No platform notification dependency.
/// The app supplies actual radio telemetry and heard-node events.
library;

enum LocalAlertKind { batteryLow, batteryCritical, newNode, contactQuiet }

class LocalAlertEvent {
  const LocalAlertEvent(this.kind, this.message, {this.nodeId});
  final LocalAlertKind kind;
  final String message;
  final int? nodeId;
}

/// Stateful, deterministic alert evaluator. One instance belongs to one radio.
/// A reconnect must call [resetSession] to avoid stale silence warnings.
class LocalAlertEngine {
  LocalAlertEngine({
    this.lowBatteryPercent = 20,
    this.criticalBatteryPercent = 10,
    this.quietAfter = const Duration(minutes: 30),
  }) : assert(criticalBatteryPercent < lowBatteryPercent),
       assert(criticalBatteryPercent >= 0),
       assert(lowBatteryPercent <= 100);

  final int lowBatteryPercent;
  final int criticalBatteryPercent;
  final Duration quietAfter;
  final Set<int> _seen = {};
  final Map<int, DateTime> _lastHeard = {};
  final Set<int> _quietNotified = {};
  int _batteryLevel = 0; // 0 normal, 1 low, 2 critical

  /// Do not interpret a missing or invalid battery reading as low battery.
  LocalAlertEvent? battery(int? percent) {
    if (percent == null || percent < 0 || percent > 100) return null;
    final level = percent <= criticalBatteryPercent
        ? 2
        : percent <= lowBatteryPercent
        ? 1
        : 0;
    if (level == 0) {
      _batteryLevel = 0;
      return null;
    }
    if (level <= _batteryLevel) return null;
    _batteryLevel = level;
    return LocalAlertEvent(
      level == 2 ? LocalAlertKind.batteryCritical : LocalAlertKind.batteryLow,
      'Radio battery at $percent%',
    );
  }

  /// The first observed node establishes the baseline, unless [notifyFirst]
  /// is true. Repeated beacons never generate duplicate new-node alerts.
  LocalAlertEvent? heard(int id, DateTime at, {bool notifyFirst = true}) {
    final fresh = _seen.add(id);
    final old = _lastHeard[id];
    if (old == null || at.isAfter(old)) _lastHeard[id] = at;
    _quietNotified.remove(id);
    if (!fresh || !notifyFirst) return null;
    return LocalAlertEvent(LocalAlertKind.newNode, 'New node heard: $id', nodeId: id);
  }

  /// Only explicitly monitored contacts can go quiet. This reports silence,
  /// not a verified offline state. Call only while the local link is up.
  List<LocalAlertEvent> checkQuiet(DateTime now, Set<int> monitored, {required bool connected}) {
    if (!connected) return const [];
    _quietNotified.removeWhere((id) => !monitored.contains(id));
    final events = <LocalAlertEvent>[];
    for (final id in monitored) {
      final last = _lastHeard[id];
      if (last == null || now.isBefore(last) || now.difference(last) < quietAfter) continue;
      if (_quietNotified.add(id)) {
        events.add(
          LocalAlertEvent(
            LocalAlertKind.contactQuiet,
            'Trip contact $id has not been heard for ${now.difference(last).inMinutes} minutes',
            nodeId: id,
          ),
        );
      }
    }
    return events;
  }

  /// Clear session observations when switching radios; do not carry old
  /// neighbors, battery state, or silence timers to the new connection.
  void resetSession() {
    _seen.clear();
    _lastHeard.clear();
    _quietNotified.clear();
    _batteryLevel = 0;
  }
}
