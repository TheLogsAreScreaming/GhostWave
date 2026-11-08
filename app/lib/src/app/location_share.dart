/// Opt-in sharing of the phone's GPS position with the node (`SetOwnPosition`),
/// only while the app is in the foreground and the link is up.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../gen/ghostwave.pb.dart' as pb;
import '../link/geo.dart';
import 'mesh_controller.dart';
import 'providers.dart';

/// Whether the app may read the phone's position.
enum LocationAccess {
  /// Allowed (while in use or always).
  granted,

  /// Refused this time; asking again may work.
  denied,

  /// Refused for good; only the system settings can change it.
  deniedForever,

  /// Location services are switched off on the phone.
  serviceOff,
}

/// Where positions come from. Tests replace it with a fake.
abstract interface class PositionSource {
  /// Checks access, asking the user if it has not been decided yet.
  Future<LocationAccess> ensureAccess();

  /// Position fixes, at most one per [distanceFilterM] metres of movement.
  Stream<LatLon> watch({required int distanceFilterM});

  /// Opens the system page that can fix [why] (app or location settings).
  Future<void> openSettings(LocationAccess why);
}

/// [PositionSource] backed by the platform location service (`geolocator`).
class GeolocatorPositionSource implements PositionSource {
  /// Creates the source.
  const GeolocatorPositionSource();

  @override
  Future<LocationAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return switch (p) {
      LocationPermission.whileInUse || LocationPermission.always => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine => LocationAccess.denied,
    };
  }

  @override
  Stream<LatLon> watch({required int distanceFilterM}) =>
      Geolocator.getPositionStream(locationSettings: LocationSettings(distanceFilter: distanceFilterM))
          .map((p) => LatLon(p.latitude, p.longitude));

  @override
  Future<void> openSettings(LocationAccess why) async {
    if (why == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

/// The position source; overridden in tests.
final positionSourceProvider = Provider<PositionSource>((ref) => const GeolocatorPositionSource());

/// What [PositionThrottle.offer] decided.
sealed class ThrottleDecision {
  const ThrottleDecision();
}

/// Send this fix now.
final class SendNow extends ThrottleDecision {
  /// Creates the decision.
  const SendNow();
}

/// Moved far enough, but the last send was too recent: try again after [wait].
final class SendAfter extends ThrottleDecision {
  /// Creates the decision.
  const SendAfter(this.wait);

  /// Time until the next send is allowed.
  final Duration wait;
}

/// Not worth sending (has not moved far enough).
final class NoSend extends ThrottleDecision {
  /// Creates the decision.
  const NoSend();
}

/// Rate limit for position updates: a fix is sent when the phone has moved at
/// least [minDistanceM] from the last position sent, and never more often than
/// [minInterval]. The first fix (and the first after [reset]) goes out at once.
class PositionThrottle {
  /// Creates a throttle.
  PositionThrottle({this.minInterval = const Duration(seconds: 30), this.minDistanceM = 50});

  /// Shortest time between two sends.
  final Duration minInterval;

  /// Smallest movement worth a new send, metres.
  final double minDistanceM;

  LatLon? _lastSent;
  DateTime? _lastSentAt;

  /// Decides what to do with fix [p] at [now].
  ThrottleDecision offer(LatLon p, DateTime now) {
    final last = _lastSent;
    final at = _lastSentAt;
    if (last == null || at == null) return const SendNow();
    if (last.distanceTo(p) < minDistanceM) return const NoSend();
    final elapsed = now.difference(at);
    return elapsed >= minInterval ? const SendNow() : SendAfter(minInterval - elapsed);
  }

  /// Records that [p] was sent at [at].
  void sent(LatLon p, DateTime at) {
    _lastSent = p;
    _lastSentAt = at;
  }

  /// Forgets the last send, so the next fix goes out at once (new link).
  void reset() {
    _lastSent = null;
    _lastSentAt = null;
  }
}

/// Location sharing state for the UI.
class LocationShareState {
  /// Creates a state.
  const LocationShareState({
    required this.enabled,
    this.access,
    this.active = false,
    this.lastSent,
    this.lastSentAt,
    this.error,
  });

  /// The user's choice (saved).
  final bool enabled;

  /// Last access check, null before the first.
  final LocationAccess? access;

  /// Watching the GPS right now (enabled, allowed, foreground, link up).
  final bool active;

  /// Last position the node accepted.
  final LatLon? lastSent;

  /// When [lastSent] was sent.
  final DateTime? lastSentAt;

  /// Last error from the GPS or the node.
  final String? error;

  /// A copy with the given fields changed.
  LocationShareState copyWith({
    bool? enabled,
    LocationAccess? access,
    bool clearAccess = false,
    bool? active,
    LatLon? lastSent,
    DateTime? lastSentAt,
    String? error,
    bool clearError = false,
  }) => LocationShareState(
    enabled: enabled ?? this.enabled,
    access: clearAccess ? null : access ?? this.access,
    active: active ?? this.active,
    lastSent: lastSent ?? this.lastSent,
    lastSentAt: lastSentAt ?? this.lastSentAt,
    error: clearError ? null : error ?? this.error,
  );
}

/// Shares the phone's position with the node while enabled, in the
/// foreground, allowed and connected. See [PositionThrottle] for the rate.
class LocationShareController extends Notifier<LocationShareState> {
  static const _key = 'share_location';

  /// Fixes are requested at this movement granularity, metres.
  static const distanceFilterM = 50;

  final PositionThrottle _throttle = PositionThrottle();
  StreamSubscription<LatLon>? _sub;
  Timer? _pending;
  LatLon? _latest;
  bool _starting = false;

  @override
  LocationShareState build() {
    ref.onDispose(_stop);
    ref.listen(appForegroundProvider, (_, _) => _reconcile());
    ref.listen(sessionProvider, (prev, next) {
      if (next != null && prev == null) {
        // new link: the node may have restarted, so resend the latest fix
        _throttle.reset();
        final p = _latest;
        if (p != null && _sub != null) _offer(p);
      }
      _reconcile();
    });
    Future.microtask(_reconcile);
    return LocationShareState(enabled: ref.read(sharedPrefsProvider).getBool(_key) ?? false);
  }

  /// Turns sharing on or off (saved). Turning it on asks for permission.
  Future<void> setEnabled({required bool enabled}) async {
    state = state.copyWith(enabled: enabled, clearError: true, clearAccess: true);
    await ref.read(sharedPrefsProvider).setBool(_key, enabled);
    if (!ref.mounted) return;
    await _reconcile();
  }

  /// Opens the system settings page for the current access problem.
  Future<void> openSettings() => ref.read(positionSourceProvider).openSettings(state.access ?? LocationAccess.denied);

  bool get _wanted => state.enabled && ref.read(appForegroundProvider) && ref.read(sessionProvider) != null;

  Future<void> _reconcile() async {
    if (!ref.mounted) return;
    if (!_wanted) {
      _stop();
      if (state.active) state = state.copyWith(active: false);
      return;
    }
    if (_sub != null || _starting) return;
    _starting = true;
    try {
      final source = ref.read(positionSourceProvider);
      final access = await source.ensureAccess();
      if (!ref.mounted) return;
      state = state.copyWith(access: access);
      if (access != LocationAccess.granted || !_wanted || _sub != null) return;
      _sub = source
          .watch(distanceFilterM: distanceFilterM)
          .listen(_offer, onError: (Object e) => state = state.copyWith(error: 'GPS: $e'));
      state = state.copyWith(active: true, clearError: true);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: 'GPS: $e');
    } finally {
      _starting = false;
    }
  }

  void _offer(LatLon p) {
    _latest = p;
    switch (_throttle.offer(p, ref.read(clockProvider)())) {
      case SendNow():
        _pending?.cancel();
        _pending = null;
        unawaited(_send(p));
      case SendAfter(:final wait):
        _pending ??= Timer(wait, () {
          _pending = null;
          final latest = _latest;
          if (latest != null && ref.mounted) _offer(latest);
        });
      case NoSend():
        break;
    }
  }

  Future<void> _send(LatLon p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final now = ref.read(clockProvider)();
    _throttle.sent(p, now);
    try {
      await session.request(pb.ToRadio(setOwnPosition: pb.SetOwnPosition(pos: p.toProto())));
      if (!ref.mounted) return;
      state = state.copyWith(lastSent: p, lastSentAt: now, clearError: true);
      ref.read(meshProvider.notifier).noteOwnPosition(p);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: 'Node: $e');
    }
  }

  void _stop() {
    _pending?.cancel();
    _pending = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }
}

/// Phone-position sharing.
final locationShareProvider = NotifierProvider<LocationShareController, LocationShareState>(
  LocationShareController.new,
);
