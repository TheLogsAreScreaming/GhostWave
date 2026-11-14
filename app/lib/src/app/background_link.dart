/// The optional background connection: decides when Android's foreground
/// service should run. The link itself stays in the app's one Dart isolate, so
/// chat history and acks need no second code path when no UI exists.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../link/ble.dart';
import '../link/contact_card.dart';
import '../link/node_link.dart';
import 'mesh_alerts.dart';
import 'providers.dart';
import 'radios.dart';

/// What the persistent notification says.
class BackgroundNotice {
  /// Creates the wording.
  const BackgroundNotice(this.title, this.text);

  /// First line.
  final String title;

  /// Second line.
  final String text;

  @override
  bool operator ==(Object other) => other is BackgroundNotice && other.title == title && other.text == text;

  @override
  int get hashCode => Object.hash(title, text);
}

/// The service's notification for link state [s]; null when it should not run.
/// [radio] is the active radio's name on this phone, when it has one.
///
/// [LinkFailed] and [LinkNeedsPin] are null too: they wait for the user, so
/// holding the phone awake for them would only waste battery.
BackgroundNotice? backgroundNoticeFor(LinkState s, {String? radio}) => switch (s) {
  LinkUp(:final info) => BackgroundNotice(
    'GhostWave connected',
    radio ?? (decodeLenient(info.name).isEmpty ? nodeIdHex(info.nodeId) : decodeLenient(info.name)),
  ),
  LinkConnecting(:final target) || LinkWaiting(:final target) => BackgroundNotice(
    'GhostWave reconnecting',
    radio ?? BleNodeRef.tryParse(target)?.name ?? target,
  ),
  LinkIdle() || LinkFailed() || LinkNeedsPin() => null,
};

/// The Android side. Tests use a fake.
abstract interface class BackgroundPlatform {
  /// Whether this phone can run the service.
  bool get supported;

  /// Starts the service, or re-promotes it if it is running. False if Android
  /// refused. With [withLocation] it also asks to read the GPS in the
  /// background; [locationGrants] reports whether that was allowed.
  Future<bool> start(BackgroundNotice notice, {bool withLocation = false});

  /// Fires each time the service enters the foreground: whether it may read the GPS.
  Stream<bool> get locationGrants;

  /// Fires when the activity is gone but the engine stays (app swiped away).
  Stream<void> get activityGone;

  /// Changes the notification of the running service.
  Future<void> update(BackgroundNotice notice);

  /// Stops the service.
  Future<void> stop();

  /// Whether the app is exempt from battery optimization.
  Future<bool> batteryExempt();

  /// Shows Android's dialog asking for the exemption.
  Future<void> requestBatteryExemption();

  /// Fires when the notification's Disconnect button is tapped.
  Stream<void> get disconnectRequests;
}

/// [BackgroundPlatform] for phones without the service (iPhone, tests).
class NoBackgroundPlatform implements BackgroundPlatform {
  /// Creates the no-op.
  const NoBackgroundPlatform();

  @override
  bool get supported => false;

  @override
  Future<bool> start(BackgroundNotice notice, {bool withLocation = false}) async => false;

  @override
  Stream<bool> get locationGrants => const Stream<bool>.empty();

  @override
  Stream<void> get activityGone => const Stream<void>.empty();

  @override
  Future<void> update(BackgroundNotice notice) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<bool> batteryExempt() async => true;

  @override
  Future<void> requestBatteryExemption() async {}

  @override
  Stream<void> get disconnectRequests => const Stream<void>.empty();
}

/// [BackgroundPlatform] over the method channel to `GhostWaveEngine.kt`.
class AndroidBackgroundPlatform implements BackgroundPlatform {
  /// Creates the channel; answers the Disconnect button.
  AndroidBackgroundPlatform() {
    assert(Platform.isAndroid, 'Android only');
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'disconnectRequested') _disconnects.add(null);
      if (call.method == 'locationGrant') _grants.add(call.arguments == true);
      if (call.method == 'activityGone') _activityGone.add(null);
    });
  }

  static const _channel = MethodChannel('org.ghostwave/background_link');
  final StreamController<void> _disconnects = StreamController<void>.broadcast();
  final StreamController<bool> _grants = StreamController<bool>.broadcast();
  final StreamController<void> _activityGone = StreamController<void>.broadcast();

  static Map<String, String> _args(BackgroundNotice n) => {'title': n.title, 'text': n.text};

  @override
  bool get supported => true;

  @override
  Future<bool> start(BackgroundNotice notice, {bool withLocation = false}) async =>
      await _channel.invokeMethod<bool>('start', {..._args(notice), 'location': withLocation}) ?? false;

  @override
  Stream<bool> get locationGrants => _grants.stream;

  @override
  Stream<void> get activityGone => _activityGone.stream;

  @override
  Future<void> update(BackgroundNotice notice) => _channel.invokeMethod<void>('update', _args(notice));

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<bool> batteryExempt() async => await _channel.invokeMethod<bool>('batteryExempt') ?? false;

  @override
  Future<void> requestBatteryExemption() => _channel.invokeMethod<void>('requestBatteryExemption');

  @override
  Stream<void> get disconnectRequests => _disconnects.stream;
}

/// The phone's background service; `main` installs the Android one.
final backgroundPlatformProvider = Provider<BackgroundPlatform>((ref) => const NoBackgroundPlatform());

/// The user's choice: null until they have been told about it and decided.
class BackgroundEnabledNotifier extends Notifier<bool?> {
  static const _key = 'background_link';

  @override
  bool? build() => ref.watch(sharedPrefsProvider).getBool(_key);

  /// Records the decision.
  void set({required bool enabled}) {
    state = enabled;
    unawaited(ref.read(sharedPrefsProvider).setBool(_key, enabled));
  }
}

/// Whether the background connection is on (null: not decided yet).
final backgroundEnabledProvider = NotifierProvider<BackgroundEnabledNotifier, bool?>(BackgroundEnabledNotifier.new);

/// Whether Android's battery optimization leaves the app alone.
final batteryExemptProvider = FutureProvider<bool>((ref) => ref.watch(backgroundPlatformProvider).batteryExempt());

/// Starts, updates and stops the service.
///
/// Subscribes to the link directly: with no UI there are no frames, and
/// Riverpod delays provider rebuilds to the next frame.
class BackgroundLinkManager {
  /// Creates the manager for [link].
  BackgroundLinkManager({required this.link, required this.platform, required this.alerts, this.radioName}) {
    _subs
      ..add(link.states.listen((_) => _apply()))
      ..add(platform.disconnectRequests.listen((_) => link.disconnect()))
      ..add(platform.locationGrants.listen(_setGrant));
  }

  /// The one link.
  final NodeLink link;

  /// The Android side.
  final BackgroundPlatform platform;

  /// Tells the user when the connection ended without them.
  final MeshAlerts alerts;

  /// The active radio's name on this phone (its nickname), if any.
  final String? Function()? radioName;

  final List<StreamSubscription<void>> _subs = [];
  Future<void> _queue = Future<void>.value();
  bool _enabled = false;
  bool _foreground = true;
  bool _running = false;
  BackgroundNotice? _shown;
  bool _locationWanted = false;
  bool _locationRequested = false;
  bool _locationGranted = false;
  final StreamController<void> _grantChanges = StreamController<void>.broadcast(sync: true);

  /// Whether the running service may read the GPS in the background.
  bool get locationGranted => _locationGranted;

  /// Fires when [locationGranted] changes.
  Stream<void> get locationGrantChanges => _grantChanges.stream;

  /// Asks for (or gives up) background GPS. Android only grants it while the
  /// app is on screen, so a change made in the background waits for the return.
  set locationWanted(bool value) {
    if (_locationWanted == value) return;
    _locationWanted = value;
    _apply();
  }

  void _setGrant(bool granted) {
    if (_locationGranted == granted) return;
    _locationGranted = granted;
    _apply(); // the notification says so
    if (!_grantChanges.isClosed) _grantChanges.add(null);
  }

  /// Whether this phone has the service at all.
  bool get supported => platform.supported;

  /// Applies the user's choice.
  set enabled(bool value) {
    _enabled = value;
    _apply();
  }

  /// Applies an app lifecycle change. Android only lets a foreground app start
  /// the service, so a refused start is tried again on return.
  set foreground(bool value) {
    _foreground = value;
    if (value) _apply();
  }

  // Serialized, so a quick connect and disconnect can't leave the service running.
  void _apply() {
    if (!supported) return;
    final state = link.state;
    _queue = _queue.then((_) => _step(state)).catchError((Object e) => debugPrint('background link: $e'));
  }

  Future<void> _step(LinkState state) async {
    final base = _enabled ? backgroundNoticeFor(state, radio: radioName?.call()) : null;
    final notice = base == null || !_locationGranted
        ? base
        : BackgroundNotice(base.title, '${base.text} · sharing your location');
    if (notice == null) {
      if (!_running) return;
      _running = false;
      _shown = null;
      _locationRequested = false;
      _setGrant(false);
      await platform.stop();
      if (_enabled && !_foreground) await _tellUser(state);
    } else if (!_running) {
      if (_foreground && await platform.start(notice, withLocation: _locationWanted)) {
        _running = true;
        _shown = notice;
        _locationRequested = _locationWanted;
      }
    } else if (_locationRequested != _locationWanted && _foreground) {
      _shown = notice;
      _locationRequested = _locationWanted;
      await platform.start(notice, withLocation: _locationWanted);
    } else if (notice != _shown) {
      _shown = notice;
      await platform.update(notice);
    }
  }

  Future<void> _tellUser(LinkState state) => switch (state) {
    LinkFailed(:final reason) => alerts.backgroundLinkStopped('$reason.'),
    LinkNeedsPin() => alerts.backgroundLinkStopped('The node wants its PIN.'),
    _ => Future<void>.value(),
  };

  /// Shows the notification again (the active radio was renamed).
  void refresh() => _apply();

  /// Waits for pending service calls (tests).
  Future<void> get idle => _queue;

  /// Stops listening. The process is ending, so the service goes with it.
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_grantChanges.close());
  }
}

/// The manager, kept in step with the user's choice and the app lifecycle.
final backgroundLinkProvider = Provider<BackgroundLinkManager>((ref) {
  final manager = BackgroundLinkManager(
    link: ref.watch(nodeLinkProvider),
    platform: ref.watch(backgroundPlatformProvider),
    alerts: ref.watch(meshAlertsProvider),
    radioName: () {
      final r = ref.read(activeRadioProvider);
      return r == null || r.nickname.isEmpty ? null : r.nickname;
    },
  );
  ref
    ..listen(backgroundEnabledProvider, (_, on) => manager.enabled = on ?? false, fireImmediately: true)
    ..listen(appForegroundProvider, (_, fg) => manager.foreground = fg, fireImmediately: true)
    ..listen(activeRadioProvider.select((r) => r?.nickname), (_, _) => manager.refresh())
    ..onDispose(manager.dispose);
  return manager;
});
