/// Opt-in sharing of the phone's GPS position with the node (`SetOwnPosition`)
/// while the link is up: in the foreground, and in the background only with a
/// second opt-in and the background connection running.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../gen/ghostwave.pb.dart' as pb;
import '../link/geo.dart';
import '../link/node_link.dart';
import '../link/session.dart';
import 'background_link.dart';
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
    this.background = false,
    this.access,
    this.active = false,
    this.lastSent,
    this.lastSentAt,
    this.error,
  });

  /// The user's choice (saved).
  final bool enabled;

  /// The user's second choice: keep sharing with the app in the background
  /// (saved, off by default).
  final bool background;

  /// Last access check, null before the first.
  final LocationAccess? access;

  /// Watching the GPS right now.
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
    bool? background,
    LocationAccess? access,
    bool clearAccess = false,
    bool? active,
    LatLon? lastSent,
    DateTime? lastSentAt,
    String? error,
    bool clearError = false,
  }) => LocationShareState(
    enabled: enabled ?? this.enabled,
    background: background ?? this.background,
    access: clearAccess ? null : access ?? this.access,
    active: active ?? this.active,
    lastSent: lastSent ?? this.lastSent,
    lastSentAt: lastSentAt ?? this.lastSentAt,
    error: clearError ? null : error ?? this.error,
  );
}

/// Shares the phone's position with the node while enabled, in the
/// allowed and connected, and either in the foreground or with background
/// sharing on and allowed by Android. See [PositionThrottle] for the rate.
class LocationShareController extends Notifier<LocationShareState> {
  static const _key = 'share_location';
  static const _backgroundKey = 'share_location_background';

  /// Fixes are requested at this movement granularity, metres.
  static const distanceFilterM = 50;

  final PositionThrottle _throttle = PositionThrottle();
  StreamSubscription<LatLon>? _sub;
  Timer? _pending;
  LatLon? _latest;
  bool _starting = false;
  Timer? _retry;

  @override
  LocationShareState build() {
    ref.onDispose(_stop);
    ref.listen(appForegroundProvider, (_, _) => _reconcile());
    // Straight from the link: with no UI there are no frames to rebuild providers.
    final link = ref.watch(nodeLinkProvider);
    var wasUp = link.state is LinkUp;
    final linkSub = link.states.listen((s) {
      final up = s is LinkUp;
      if (up && !wasUp) {
        // new link: the node may have restarted, so resend the latest fix
        _throttle.reset();
        final p = _latest;
        if (p != null && _sub != null) _offer(p);
      }
      wasUp = up;
      unawaited(_reconcile());
    });
    final grantSub = ref.watch(backgroundLinkProvider).locationGrantChanges.listen((_) => _reconcile());
    // the plugin silently stops updates when the activity goes, with no event on the stream
    final goneSub = ref.watch(backgroundPlatformProvider).activityGone.listen((_) {
      if (_sub != null) _restartSoon();
    });
    ref.onDispose(() {
      unawaited(linkSub.cancel());
      unawaited(grantSub.cancel());
      unawaited(goneSub.cancel());
    });
    Future.microtask(_reconcile);
    final prefs = ref.read(sharedPrefsProvider);
    return LocationShareState(
      enabled: prefs.getBool(_key) ?? false,
      background: prefs.getBool(_backgroundKey) ?? false,
    );
  }

  /// Turns sharing on or off (saved). Turning it on asks for permission.
  Future<void> setEnabled({required bool enabled}) async {
    state = state.copyWith(enabled: enabled, clearError: true, clearAccess: true);
    await ref.read(sharedPrefsProvider).setBool(_key, enabled);
    if (!ref.mounted) return;
    await _reconcile();
  }

  /// Turns background sharing on or off (saved). Turning it on needs the
  /// location permission first: Android refuses the service type without it.
  Future<void> setBackground({required bool enabled}) async {
    if (enabled) {
      final access = await ref.read(positionSourceProvider).ensureAccess();
      if (!ref.mounted) return;
      if (access != LocationAccess.granted) {
        state = state.copyWith(access: access);
        return;
      }
    }
    state = state.copyWith(background: enabled, clearError: true);
    await ref.read(sharedPrefsProvider).setBool(_backgroundKey, enabled);
    if (!ref.mounted) return;
    await _reconcile();
  }

  /// Opens the system settings page for the current access problem.
  Future<void> openSettings() => ref.read(positionSourceProvider).openSettings(state.access ?? LocationAccess.denied);

  LinkSession? get _session => ref.read(nodeLinkProvider).session;

  bool get _wanted {
    if (!state.enabled || _session == null) return false;
    return ref.read(appForegroundProvider) || (state.background && ref.read(backgroundLinkProvider).locationGranted);
  }

  Future<void> _reconcile() async {
    if (!ref.mounted) return;
    ref.read(backgroundLinkProvider).locationWanted = state.enabled && state.background;
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
          .listen(
            _offer,
            onError: (Object e) {
              if (ref.mounted) state = state.copyWith(error: 'GPS: $e');
              _restartSoon();
            },
            onDone: _restartSoon,
          );
      state = state.copyWith(active: true, clearError: true);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: 'GPS: $e');
    } finally {
      _starting = false;
    }
  }

  /// How long after the GPS stream stops to try another.
  static Duration restartDelay = const Duration(seconds: 2);

  /// The GPS stream stopped: start another if still wanted.
  void _restartSoon() {
    unawaited(_sub?.cancel());
    _sub = null;
    _retry?.cancel();
    _retry = Timer(restartDelay, () => unawaited(_reconcile()));
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
    final session = _session;
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
    _retry?.cancel();
    _retry = null;
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
