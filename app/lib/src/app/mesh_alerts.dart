/// Local notifications for incoming DMs and SOS alerts while the app is in the
/// background but still connected. No push service: the link only outlives the
/// UI with the optional background connection (see `background_link.dart`).
library;

import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows notifications. The default does nothing; `main` installs [LocalMeshAlerts].
abstract interface class MeshAlerts {
  /// Asks the user for permission to notify (Android 13+, iOS). True if allowed.
  Future<bool> requestPermission();

  /// A DM from [from] (display name) arrived.
  Future<void> textReceived({required int peer, required String from, required String text});

  /// An SOS from [from] (display name) arrived.
  Future<void> sosReceived({required int src, required String from, required String text});

  /// The background connection ended and needs the user. [reason] says why.
  Future<void> backgroundLinkStopped(String reason);
}

/// [MeshAlerts] that shows nothing (tests, unsupported platforms).
class NoMeshAlerts implements MeshAlerts {
  /// Creates the no-op.
  const NoMeshAlerts();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> textReceived({required int peer, required String from, required String text}) async {}

  @override
  Future<void> sosReceived({required int src, required String from, required String text}) async {}

  @override
  Future<void> backgroundLinkStopped(String reason) async {}
}

/// The notifier the mesh controller calls; overridden in `main`.
final meshAlertsProvider = Provider<MeshAlerts>((ref) => const NoMeshAlerts());

/// [MeshAlerts] backed by `flutter_local_notifications`.
class LocalMeshAlerts implements MeshAlerts {
  LocalMeshAlerts._(this._plugin);

  static final StreamController<int> _sosTaps = StreamController<int>.broadcast();

  /// Node IDs of SOS notifications the user tapped.
  static Stream<int> get sosTaps => _sosTaps.stream;

  final FlutterLocalNotificationsPlugin _plugin;

  static const _messages = AndroidNotificationDetails(
    'messages',
    'Messages',
    channelDescription: 'Direct messages from the mesh',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  static const _sos = AndroidNotificationDetails(
    'sos',
    'SOS alerts',
    channelDescription: 'Emergency alerts from the mesh',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    color: Color(0xFFC62828),
  );

  /// Initializes the plugin. Does not ask for permission yet.
  static Future<LocalMeshAlerts> create() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_ghostwave'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        final src = p != null && p.startsWith('sos:') ? int.tryParse(p.substring(4)) : null;
        if (src != null) _sosTaps.add(src);
      },
    );
    return LocalMeshAlerts._(plugin);
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<void> textReceived({required int peer, required String from, required String text}) => _plugin.show(
    // one notification per peer, replaced by the newest message (bit 30 clear)
    id: peer & 0x3FFFFFFF,
    title: from,
    body: text,
    notificationDetails: const NotificationDetails(android: _messages, iOS: DarwinNotificationDetails()),
  );

  @override
  Future<void> sosReceived({required int src, required String from, required String text}) => _plugin.show(
    // bit 30 set: SOS ids never collide with DM ids
    id: (src & 0x3FFFFFFF) | 0x40000000,
    title: 'SOS from $from',
    body: text.isEmpty ? 'Open GhostWave to see the alert and ack it.' : text,
    payload: 'sos:$src',
    notificationDetails: const NotificationDetails(
      android: _sos,
      iOS: DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
    ),
  );

  /// DM IDs have bit 30 clear; SOS IDs use the low 30 bits, so this could only
  /// match the SOS of a node numbered 0x3FFFFFFF.
  static const _linkStoppedId = 0x7FFFFFFF;

  @override
  Future<void> backgroundLinkStopped(String reason) => _plugin.show(
    id: _linkStoppedId,
    title: 'GhostWave disconnected',
    body: '$reason Open the app to reconnect. Messages and SOS alerts will not reach this phone until then.',
    notificationDetails: const NotificationDetails(android: _messages, iOS: DarwinNotificationDetails()),
  );
}
