/// Local notifications for incoming DMs and SOS alerts while the app is in the
/// background but still connected. No push service: the link only outlives the
/// UI with the optional background connection (see `background_link.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show Color, DartPluginRegistrant, IsolateNameServer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows notifications. The default does nothing; `main` installs [LocalMeshAlerts].
abstract interface class MeshAlerts {
  /// Asks the user for permission to notify (Android 13+, iOS). True if allowed.
  Future<bool> requestPermission();

  /// A DM from [from] (display name) arrived. With [thread], the notification
  /// offers Reply and Mark read (Android).
  Future<void> textReceived({
    required int peer,
    required String from,
    required String text,
    NotificationThread? thread,
  });

  /// An SOS from [from] (display name) arrived.
  Future<void> sosReceived({required int src, required String from, required String text});

  /// The background connection ended and needs the user. [reason] says why.
  Future<void> backgroundLinkStopped(String reason);

  /// A trip reminder or overdue warning. The same [id] replaces the last one.
  Future<void> tripAlert({required int id, required String title, required String body});

  /// About your own radio or who it hears (battery, a new node). The same
  /// [id] replaces the last one.
  Future<void> radioAlert({required int id, required String title, required String body});
}

/// A conversation a message notification belongs to.
sealed class ChatTarget {
  const ChatTarget();
}

/// The DM thread with [peer].
final class DmThread extends ChatTarget {
  /// Creates the target.
  const DmThread(this.peer);

  /// The other node.
  final int peer;

  @override
  bool operator ==(Object other) => other is DmThread && other.peer == peer;

  @override
  int get hashCode => peer.hashCode;
}

/// The group channel [name].
final class ChannelThread extends ChatTarget {
  /// Creates the target.
  const ChannelThread(this.name);

  /// Channel name.
  final String name;

  @override
  bool operator ==(Object other) => other is ChannelThread && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Where a notification's Reply and Mark read actions go.
class NotificationThread {
  /// Creates the address.
  const NotificationThread({required this.node, required this.target, this.inlineReply = true});

  /// Parses [payload]; null if it is not one of ours.
  static NotificationThread? parse(String? payload) {
    if (payload == null) return null;
    final m = RegExp(r'^msg:([0-9a-f]{8}):(dm|ch):(.+)$').firstMatch(payload);
    if (m == null) return null;
    final node = int.parse(m.group(1)!, radix: 16);
    final rest = m.group(3)!;
    if (m.group(2) == 'dm') {
      if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(rest)) return null;
      return NotificationThread(node: node, target: DmThread(int.parse(rest, radix: 16)));
    }
    final String name;
    try {
      name = Uri.decodeComponent(rest);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (name.isEmpty || name.length > 64) return null;
    return NotificationThread(node: node, target: ChannelThread(name));
  }

  /// The node whose history holds the thread.
  final int node;

  /// The conversation.
  final ChatTarget target;

  /// Whether the notification may take a reply in place (false while the app
  /// is locked: the action then opens the app).
  final bool inlineReply;

  /// The notification payload: `msg:<node>:dm:<peer>` or `msg:<node>:ch:<name>`.
  String get payload {
    String hex(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return switch (target) {
      DmThread(:final peer) => 'msg:${hex(node)}:dm:${hex(peer)}',
      ChannelThread(:final name) => 'msg:${hex(node)}:ch:${Uri.encodeComponent(name)}',
    };
  }
}

/// A tap on a message notification's Reply or Mark read.
class NotificationActionEvent {
  /// Creates the event.
  const NotificationActionEvent({required this.action, required this.thread, this.input});

  /// From the map [toMap] made (it crosses isolates as plain values).
  static NotificationActionEvent? fromMap(Object? m) {
    if (m is! Map) return null;
    final action = m['a'], payload = m['p'], input = m['i'];
    if (action is! String || (action != kReplyAction && action != kMarkReadAction)) return null;
    final thread = NotificationThread.parse(payload is String ? payload : null);
    if (thread == null) return null;
    return NotificationActionEvent(action: action, thread: thread, input: input is String ? input : null);
  }

  /// [kReplyAction] or [kMarkReadAction].
  final String action;

  /// Where it applies.
  final NotificationThread thread;

  /// The typed reply.
  final String? input;

  /// Plain values for an isolate port or saved preferences.
  Map<String, Object?> toMap() => {'a': action, 'p': thread.payload, 'i': input};
}

/// Action ID of the inline Reply.
const String kReplyAction = 'reply';

/// Action ID of Mark read.
const String kMarkReadAction = 'read';

/// Action ID of "Open to reply" (the app is locked).
const String kOpenAction = 'open';

/// [MeshAlerts] that shows nothing (tests, unsupported platforms).
class NoMeshAlerts implements MeshAlerts {
  /// Creates the no-op.
  const NoMeshAlerts();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> textReceived({
    required int peer,
    required String from,
    required String text,
    NotificationThread? thread,
  }) async {}

  @override
  Future<void> sosReceived({required int src, required String from, required String text}) async {}

  @override
  Future<void> backgroundLinkStopped(String reason) async {}

  @override
  Future<void> tripAlert({required int id, required String title, required String body}) async {}

  @override
  Future<void> radioAlert({required int id, required String title, required String body}) async {}
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
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'GhostWave',
          appUserModelId: 'org.ghostwave.GhostWave',
          guid: '7f3a9c1e-4b62-4d8a-9e15-2c6d8f0a7b31',
        ),
      ),
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
      onDidReceiveNotificationResponse: (r) {
        final action = NotificationActionEvent.fromMap({'a': r.actionId, 'p': r.payload, 'i': r.input});
        if (action != null) {
          _actions.add(action);
          return;
        }
        final p = r.payload;
        final src = p != null && p.startsWith('sos:') ? int.tryParse(p.substring(4)) : null;
        if (src != null) _sosTaps.add(src);
      },
    );
    _listenForBackgroundActions();
    return LocalMeshAlerts._(plugin);
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    final macos = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) return await macos.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<void> textReceived({
    required int peer,
    required String from,
    required String text,
    NotificationThread? thread,
  }) => _plugin.show(
    // one notification per peer, replaced by the newest message (bit 30 clear)
    id: peer & 0x3FFFFFFF,
    title: from,
    body: text,
    payload: thread?.payload,
    notificationDetails: NotificationDetails(
      android: thread == null ? _messages : _messagesWithActions(inline: thread.inlineReply),
      iOS: const DarwinNotificationDetails(),
    ),
  );

  /// [_messages] with Reply (typed in the notification, sent without opening
  /// the app) and Mark read; while the app is locked, Reply opens the app.
  static AndroidNotificationDetails _messagesWithActions({required bool inline}) => AndroidNotificationDetails(
    _messages.channelId,
    _messages.channelName,
    channelDescription: _messages.channelDescription,
    importance: _messages.importance,
    priority: _messages.priority,
    category: _messages.category,
    actions: [
      if (inline)
        const AndroidNotificationAction(
          kReplyAction,
          'Reply',
          inputs: [AndroidNotificationActionInput(label: 'Reply')],
          semanticAction: SemanticAction.reply,
        )
      else
        const AndroidNotificationAction(kOpenAction, 'Open to reply', showsUserInterface: true),
      const AndroidNotificationAction(kMarkReadAction, 'Mark read', semanticAction: SemanticAction.markAsRead),
    ],
  );

  static final StreamController<NotificationActionEvent> _actions =
      StreamController<NotificationActionEvent>.broadcast();

  /// Reply and Mark read taps, from this isolate or the plugin's background one.
  static Stream<NotificationActionEvent> get actions => _actions.stream;

  static ReceivePort? _actionPort;

  /// Takes action taps that arrive in the plugin's background isolate (see
  /// [onBackgroundNotificationAction]) while this app is running.
  static void _listenForBackgroundActions() {
    if (_actionPort != null) return;
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(kNotificationActionPort);
    if (!IsolateNameServer.registerPortWithName(port.sendPort, kNotificationActionPort)) {
      port.close();
      return;
    }
    _actionPort = port;
    port.listen((m) {
      final e = NotificationActionEvent.fromMap(m);
      if (e != null) _actions.add(e);
    });
  }

  static const _trip = AndroidNotificationDetails(
    'trip',
    'Trip check-ins',
    channelDescription: 'Check-in reminders and overdue trip contacts',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  static const _radio = AndroidNotificationDetails(
    'radio',
    'Radio alerts',
    channelDescription: 'Your radio battery and nodes heard for the first time',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    category: AndroidNotificationCategory.status,
  );

  @override
  Future<void> radioAlert({required int id, required String title, required String body}) => _plugin.show(
    // negative like trip alerts, in their own half: bit 30 set
    id: -1 - ((id & 0x3FFFFFFF) | 0x40000000),
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: _radio, iOS: DarwinNotificationDetails()),
  );

  @override
  Future<void> tripAlert({required int id, required String title, required String body}) => _plugin.show(
    // negative: DM, channel and SOS notifications all use ids >= 0
    id: -1 - (id & 0x3FFFFFFF),
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: _trip, iOS: DarwinNotificationDetails()),
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

/// Name of the port the running app takes notification actions on.
const String kNotificationActionPort = 'ghostwave.notification-actions';

/// Preferences key of replies typed while the app was not running.
const String kQueuedRepliesKey = 'notifications.queuedReplies';

/// Most replies kept for a later start; older ones are dropped.
const int kMaxQueuedReplies = 20;

/// Runs in the notification plugin's background isolate when Reply or Mark
/// read is tapped. The link lives in the app's main isolate, so the tap is
/// handed over there. If the app is not running, a reply is saved and sent
/// the next time this node connects; Mark read has nothing left to clear.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse r) async {
  final map = {'a': r.actionId, 'p': r.payload, 'i': r.input};
  final e = NotificationActionEvent.fromMap(map);
  if (e == null) return;
  final port = IsolateNameServer.lookupPortByName(kNotificationActionPort);
  if (port != null) {
    port.send(e.toMap());
    return;
  }
  if (e.action != kReplyAction || (e.input ?? '').trim().isEmpty) return;
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await queueReply(prefs, e);
}

/// Saves [e] for [takeQueuedReplies], keeping the newest [kMaxQueuedReplies].
Future<void> queueReply(SharedPreferences prefs, NotificationActionEvent e) async {
  final list = [...?prefs.getStringList(kQueuedRepliesKey), jsonEncode(e.toMap())];
  await prefs.setStringList(
    kQueuedRepliesKey,
    list.length > kMaxQueuedReplies ? list.sublist(list.length - kMaxQueuedReplies) : list,
  );
}

/// Removes and returns the saved replies for [node], oldest first. Replies
/// for other nodes stay; unreadable entries are dropped.
Future<List<NotificationActionEvent>> takeQueuedReplies(SharedPreferences prefs, int node) async {
  await prefs.reload();
  final keep = <String>[], take = <NotificationActionEvent>[];
  for (final s in prefs.getStringList(kQueuedRepliesKey) ?? const <String>[]) {
    NotificationActionEvent? e;
    try {
      e = NotificationActionEvent.fromMap(jsonDecode(s));
    } on FormatException {
      e = null;
    }
    if (e == null) continue;
    if (e.thread.node == node) {
      take.add(e);
    } else {
      keep.add(s);
    }
  }
  if (take.isNotEmpty || keep.length != (prefs.getStringList(kQueuedRepliesKey)?.length ?? 0)) {
    await prefs.setStringList(kQueuedRepliesKey, keep);
  }
  return take;
}
