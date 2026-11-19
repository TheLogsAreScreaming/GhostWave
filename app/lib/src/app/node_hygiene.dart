/// Keeping the node lists tidy: when a node counts as stale, and nodes the
/// user chose to ignore. Both live only on this phone.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The choices offered for "stale after"; [Duration.zero] turns it off.
const staleChoices = <Duration>[
  Duration.zero,
  Duration(hours: 1),
  Duration(hours: 6),
  Duration(hours: 24),
  Duration(days: 3),
  Duration(days: 7),
];

/// The default: a node not heard for a day is stale.
const defaultStaleAfter = Duration(hours: 24);

/// Whether [t] is a believable "last heard" time at [now]: set, not before
/// 2020 (a radio whose clock was never set reports 1970), and not more than a
/// day ahead. Anything else is treated as unknown, never as very old.
bool plausibleHeard(DateTime? t, DateTime now) =>
    t != null && !t.isBefore(DateTime.utc(2020)) && !t.isAfter(now.add(const Duration(days: 1)));

/// Whether a node last heard at [lastHeard] is stale at [now].
///
/// Never stale when [after] is zero (off) or the time is not
/// [plausibleHeard]: a node with no believable time is shown as it is, not
/// guessed at.
bool isStale(DateTime? lastHeard, DateTime now, Duration after) {
  if (after == Duration.zero || !plausibleHeard(lastHeard, now)) return false;
  return now.difference(lastHeard!) >= after;
}

/// A short label for a [staleChoices] entry, e.g. "6 h", "3 days", "Off".
String staleChoiceLabel(Duration d) {
  if (d == Duration.zero) return 'Off';
  if (d.inHours < 24) return '${d.inHours} h';
  final days = d.inDays;
  return days == 1 ? '1 day' : '$days days';
}

/// How long without hearing a node before it is marked stale (saved).
class StaleAfterNotifier extends Notifier<Duration> {
  static const _key = 'stale_after_minutes';

  @override
  Duration build() {
    final m = ref.watch(sharedPrefsProvider).getInt(_key);
    if (m == null) return defaultStaleAfter;
    final d = Duration(minutes: m);
    return staleChoices.contains(d) ? d : defaultStaleAfter;
  }

  /// Chooses [d] (one of [staleChoices]).
  void set(Duration d) {
    state = d;
    unawaited(ref.read(sharedPrefsProvider).setInt(_key, d.inMinutes));
  }
}

/// When a node counts as stale.
final staleAfterProvider = NotifierProvider<StaleAfterNotifier, Duration>(StaleAfterNotifier.new);

/// Nodes the user chose to ignore (saved). An ignored node is hidden from the
/// chat list and the map and never notifies; its messages are still kept and
/// it still relays for the mesh. Reversible from Settings.
class IgnoredNodesNotifier extends Notifier<Set<int>> {
  static const _key = 'ignored_nodes';

  @override
  Set<int> build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    if (raw == null) return const {};
    try {
      return {for (final v in jsonDecode(raw) as List<Object?>) v! as int};
    } on Object {
      return const {};
    }
  }

  /// Ignores [nodeId].
  void ignore(int nodeId) => _save({...state, nodeId});

  /// Stops ignoring [nodeId].
  void unignore(int nodeId) => _save({...state}..remove(nodeId));

  void _save(Set<int> next) {
    state = Set.unmodifiable(next);
    final list = next.toList()..sort();
    unawaited(ref.read(sharedPrefsProvider).setString(_key, jsonEncode(list)));
  }
}

/// The ignored nodes.
final ignoredNodesProvider = NotifierProvider<IgnoredNodesNotifier, Set<int>>(IgnoredNodesNotifier.new);

/// Whether the map shows range rings around you (saved).
class RangeRingsNotifier extends Notifier<bool> {
  static const _key = 'map_range_rings';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  /// Turns the rings on or off.
  void set(bool on) {
    state = on;
    unawaited(ref.read(sharedPrefsProvider).setBool(_key, on));
  }
}

/// Whether range rings are on.
final rangeRingsProvider = NotifierProvider<RangeRingsNotifier, bool>(RangeRingsNotifier.new);
