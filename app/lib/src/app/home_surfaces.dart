/// App-icon shortcuts and the Android home-screen widget.
///
/// Both only open the app at a place: nothing is sent from the home screen, and
/// an SOS still needs the hold on the SOS screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip.dart';
import '../link/contact_card.dart';
import '../link/node_link.dart';
import 'mesh_controller.dart';
import 'providers.dart';
import 'trip_controller.dart';

/// Where a shortcut or the widget asked to open the app.
enum LaunchAction {
  /// The SOS tab.
  sos,

  /// The trip screen, to check in.
  checkin,

  /// The Chats tab.
  chats,
}

/// [name] as a [LaunchAction], or null for anything else.
LaunchAction? launchActionNamed(String? name) => switch (name) {
  'sos' => LaunchAction.sos,
  'checkin' => LaunchAction.checkin,
  'chats' => LaunchAction.chats,
  _ => null,
};

/// What the widget shows.
class WidgetText {
  /// Creates the text.
  const WidgetText(this.status, this.detail, {this.alert = false});

  /// The link, in words.
  final String status;

  /// What needs attention, or empty.
  final String detail;

  /// Something urgent: SOS, or an overdue trip contact.
  final bool alert;

  @override
  bool operator ==(Object other) =>
      other is WidgetText && other.status == status && other.detail == detail && other.alert == alert;

  @override
  int get hashCode => Object.hash(status, detail, alert);
}

/// The widget's text from the link, the mesh and the trip. Pure, for tests.
WidgetText widgetTextFor(LinkState? link, MeshState mesh, TripState trip, DateTime now) {
  final status = switch (link) {
    LinkUp(:final info) => 'Connected to ${nodeName(info.name, info.nodeId)}',
    LinkConnecting() => 'Connecting to your radio…',
    LinkWaiting() => 'Radio link dropped, reconnecting',
    LinkNeedsPin() => 'Your radio needs its PIN',
    LinkFailed() => 'Not connected: open GhostWave',
    LinkIdle() || null => 'Not connected',
  };
  final overdue = [
    for (final p in trip.plan.contacts)
      if (isOverdue(trip.plan, p, mesh.messages, now)) mesh.nameOf(p),
  ];
  final sos = mesh.activeAlerts.length;
  final unread = mesh.totalUnread;
  final parts = <String>[
    if (mesh.ownSos.active) 'Your SOS is on',
    if (sos > 0) '$sos SOS ${sos == 1 ? 'alert' : 'alerts'}',
    if (overdue.isNotEmpty) '${overdue.join(', ')} overdue',
    if (unread > 0) '$unread unread',
    if (trip.plan.active && overdue.isEmpty)
      trip.lastSent == null ? 'Trip on, no check-in yet' : 'Checked in ${_ago(now.difference(trip.lastSent!.at))}',
  ];
  return WidgetText(
    status,
    parts.isEmpty ? 'All quiet' : parts.join(' · '),
    alert: mesh.ownSos.active || sos > 0 || overdue.isNotEmpty,
  );
}

/// The node's name for the widget: its IDENT name, or its node ID.
String nodeName(List<int> name, int id) {
  final s = decodeLenient(name).trim();
  return s.isNotEmpty ? s : nodeIdHex(id);
}

String _ago(Duration d) => d.inMinutes < 1
    ? 'just now'
    : d.inMinutes < 60
    ? '${d.inMinutes} min ago'
    : '${d.inHours} h ago';

/// The platform side: launch actions in, widget text out.
abstract interface class HomeSurfacesPlatform {
  /// Launch actions from shortcuts and the widget, each once.
  Stream<LaunchAction> get actions;

  /// Shows [text] on the home-screen widget.
  Future<void> showOnWidget(WidgetText text);
}

/// No shortcuts or widget (tests, other platforms).
class NoHomeSurfaces implements HomeSurfacesPlatform {
  /// Creates the no-op.
  const NoHomeSurfaces();

  @override
  Stream<LaunchAction> get actions => const Stream.empty();

  @override
  Future<void> showOnWidget(WidgetText text) async {}
}

/// Android: `HomeSurfaces.kt`.
class AndroidHomeSurfaces implements HomeSurfacesPlatform {
  /// Listens for the native side's ping and takes any action waiting now.
  AndroidHomeSurfaces() {
    _launch.setMethodCallHandler((call) async {
      if (call.method == 'ping') unawaited(_take());
    });
    unawaited(_take());
  }

  static const _launch = MethodChannel('org.ghostwave/launch');
  static const _widget = MethodChannel('org.ghostwave/home_widget');
  final StreamController<LaunchAction> _actions = StreamController<LaunchAction>.broadcast();
  LaunchAction? _early;

  Future<void> _take() async {
    try {
      final a = launchActionNamed(await _launch.invokeMethod<String>('takePending'));
      if (a == null) return;
      if (_actions.hasListener) {
        _actions.add(a);
      } else {
        _early = a; // the app opened from a shortcut before the UI was listening
      }
    } on PlatformException catch (e) {
      debugPrint('launch action: $e');
    } on MissingPluginException {
      // no native side (an engine without the activity's channels)
    }
  }

  @override
  Stream<LaunchAction> get actions async* {
    if (_early case final a?) {
      _early = null;
      yield a;
    }
    yield* _actions.stream;
  }

  @override
  Future<void> showOnWidget(WidgetText text) async {
    try {
      await _widget.invokeMethod<void>('update', {'status': text.status, 'detail': text.detail, 'alert': text.alert});
    } on PlatformException catch (e) {
      debugPrint('widget: $e');
    } on MissingPluginException {
      // no native side
    }
  }
}

/// The platform side; `main` installs the Android one.
final homeSurfacesProvider = Provider<HomeSurfacesPlatform>((ref) => const NoHomeSurfaces());

/// Keeps the widget's text current: pushes when it changes, and once a minute
/// so "checked in 5 min ago" and overdue states stay true.
final widgetSyncProvider = Provider<void>((ref) {
  final platform = ref.watch(homeSurfacesProvider);
  WidgetText? last;
  void push() {
    final t = widgetTextFor(
      ref.read(linkStateProvider).value,
      ref.read(meshProvider),
      ref.read(tripProvider),
      ref.read(clockProvider)(),
    );
    if (t == last) return;
    last = t;
    unawaited(platform.showOnWidget(t));
  }

  ref
    ..listen(linkStateProvider, (_, _) => push())
    ..listen(meshProvider, (_, _) => push())
    ..listen(tripProvider, (_, _) => push());
  final timer = Timer.periodic(const Duration(minutes: 1), (_) => push());
  ref.onDispose(timer.cancel);
  push();
});
