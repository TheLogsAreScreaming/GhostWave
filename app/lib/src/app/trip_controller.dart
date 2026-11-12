/// The trip plan, check-ins we sent, and the reminder / overdue checks.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/trip.dart';
import 'mesh_alerts.dart';
import 'mesh_controller.dart';
import 'providers.dart';

/// The plan and the check-ins we sent, newest first.
class TripState {
  /// Creates the state.
  const TripState({this.plan = const TripPlan(), this.sent = const []});

  /// The plan.
  final TripPlan plan;

  /// Check-ins we sent, newest first, at most [kMaxSentCheckIns].
  final List<SentCheckIn> sent;

  /// The latest check-in we sent, if any.
  SentCheckIn? get lastSent => sent.isEmpty ? null : sent.first;
}

/// Keeps the trip in the app's preferences and runs a minute timer for
/// reminders and overdue warnings while the app is alive (with the background
/// connection on Android, that is also with the screen off).
class TripController extends Notifier<TripState> {
  static const _planKey = 'trip_plan_v1';
  static const _sentKey = 'trip_sent_v1';

  Timer? _timer;
  final Set<int> _warnedOverdue = <int>{};
  DateTime? _remindedFor;

  @override
  TripState build() {
    final prefs = ref.watch(sharedPrefsProvider);
    TripPlan plan = const TripPlan();
    var sent = const <SentCheckIn>[];
    try {
      final p = prefs.getString(_planKey);
      if (p != null) plan = TripPlan.fromJson((jsonDecode(p) as Map<Object?, Object?>).cast<String, Object?>());
      final s = prefs.getString(_sentKey);
      if (s != null) {
        sent = [
          for (final x in jsonDecode(s) as List<Object?>)
            SentCheckIn.fromJson((x! as Map<Object?, Object?>).cast<String, Object?>()),
        ];
      }
    } on Object catch (e) {
      // a damaged entry costs the trip setup, never the app
      debugPrint('trip data unreadable: $e');
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => check());
    ref.onDispose(() => _timer?.cancel());
    return TripState(plan: plan, sent: sent);
  }

  DateTime _now() => ref.read(clockProvider)();

  void _set(TripState s) {
    state = s;
    final prefs = ref.read(sharedPrefsProvider);
    unawaited(prefs.setString(_planKey, jsonEncode(s.plan.toJson())));
    unawaited(prefs.setString(_sentKey, jsonEncode([for (final c in s.sent) c.toJson()])));
  }

  /// Replaces the plan.
  void setPlan(TripPlan plan) => _set(TripState(plan: plan, sent: state.sent));

  /// Adds or removes a trip contact. False if the list is full.
  bool toggleContact(int peer) {
    final list = [...state.plan.contacts];
    if (list.remove(peer)) {
      setPlan(state.plan.copyWith(contacts: list));
      return true;
    }
    if (list.length >= kMaxTripContacts) return false;
    setPlan(state.plan.copyWith(contacts: [...list, peer]));
    return true;
  }

  /// Starts the trip now.
  void start() {
    _warnedOverdue.clear();
    _remindedFor = null;
    setPlan(state.plan.copyWith(startedAt: _now()));
  }

  /// Ends the trip. Reminders and overdue warnings stop.
  void end() => setPlan(state.plan.copyWith(clearStart: true));

  /// Sends [kind] to every trip contact as a DM, with our position if known.
  /// Returns how many were queued.
  Future<int> checkIn(CheckInKind kind) async {
    final peers = state.plan.contacts;
    if (peers.isEmpty) return 0;
    final mesh = ref.read(meshProvider.notifier);
    final text = checkInText(kind, ref.read(meshProvider).ownPos);
    final ids = <int, int>{};
    for (final p in peers) {
      ids[p] = await mesh.sendText(p, text);
    }
    final record = SentCheckIn(kind: kind, at: _now(), messages: ids);
    _remindedFor = null;
    _set(TripState(plan: state.plan, sent: [record, ...state.sent].take(kMaxSentCheckIns).toList()));
    return ids.length;
  }

  /// Sends check-in [c] again to [peer] (it failed or never arrived).
  Future<void> resend(SentCheckIn c, int peer) async {
    final text = checkInText(c.kind, ref.read(meshProvider).ownPos);
    final cmid = await ref.read(meshProvider.notifier).sendText(peer, text);
    _set(
      TripState(plan: state.plan, sent: [for (final x in state.sent) identical(x, c) ? x.withMessage(peer, cmid) : x]),
    );
  }

  /// Reminds us to check in when it's due, and warns once per contact that goes
  /// overdue. Runs every minute; tests call it directly.
  void check() {
    final plan = state.plan;
    final start = plan.startedAt;
    if (start == null) return;
    final now = _now();
    final alerts = ref.read(meshAlertsProvider);
    final mesh = ref.read(meshProvider);
    if (plan.reminderMinutes > 0) {
      final since = state.lastSent?.at ?? start;
      final due = since.add(Duration(minutes: plan.reminderMinutes));
      if (!now.isBefore(due) && _remindedFor != due) {
        _remindedFor = due;
        unawaited(
          alerts
              .tripAlert(
                id: 0,
                title: 'Time to check in',
                body: 'Open GhostWave and tap a check-in for your trip contacts.',
              )
              .catchError((Object _) {}),
        );
      }
    }
    for (final peer in plan.contacts) {
      final overdue = isOverdue(plan, peer, mesh.messages, now);
      if (!overdue) {
        _warnedOverdue.remove(peer);
        continue;
      }
      if (_warnedOverdue.add(peer)) {
        final last = lastCheckInFrom(peer, mesh.messages);
        unawaited(
          alerts
              .tripAlert(
                id: peer,
                title: '${mesh.nameOf(peer)} is overdue',
                body: last == null
                    ? 'No check-in since your trip started.'
                    : 'Last check-in: ${last.$1.kind.label}. Try messaging them.',
              )
              .catchError((Object _) {}),
        );
      }
    }
  }
}

/// The trip.
final tripProvider = NotifierProvider<TripController, TripState>(TripController.new);

/// Delivery of [c] to each contact, from message history.
Map<int, MsgState?> deliveryMap(SentCheckIn c, MeshState mesh) => {
  for (final peer in c.messages.keys) peer: deliveryOf(c, peer, mesh.messages),
};
