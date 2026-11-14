/// Reply and Mark read from a message notification (Android), handled in the
/// app's main isolate where the link lives. Works with the background
/// connection: the service keeps this isolate running, so a reply goes out
/// at once; with no link it waits in the outbox like any message.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/message_split.dart';
import 'mesh_alerts.dart';
import 'mesh_controller.dart';
import 'providers.dart';

/// Whether the app is locked. GhostWave has no app lock today, so this is
/// false; an app lock overrides it. While true, notifications offer "Open to
/// reply" instead of an inline reply, and a reply that still arrives is not
/// sent.
final appLockedProvider = Provider<bool>((ref) => false);

/// Taps on Reply / Mark read; `main` passes the notification plugin's.
final notificationActionSourceProvider = Provider<Stream<NotificationActionEvent>>((ref) => const Stream.empty());

/// DM limit used when the node has not reported one.
const int kFallbackMaxTextBytes = 73;

/// Channel limit used when the node has not reported one.
const int kFallbackMaxChannelTextBytes = 73;

/// Handles notification actions, and sends replies saved while the app was
/// not running once their node's history is loaded. Watched by the app root.
final notificationActionsProvider = Provider<NotificationActions>((ref) {
  final handler = NotificationActions(ref);
  final sub = ref.watch(notificationActionSourceProvider).listen((e) => unawaited(handler.handle(e)));
  ref.listen(meshProvider.select((m) => m.nodeId), (_, node) {
    if (node != null) unawaited(handler.sendQueued(node));
  }, fireImmediately: true);
  ref.onDispose(() => unawaited(sub.cancel()));
  return handler;
});

/// See [notificationActionsProvider].
class NotificationActions {
  /// Creates the handler.
  NotificationActions(this._ref);

  final Ref _ref;
  final Set<int> _drained = {};

  /// Applies one tap. A reply for a node that is not the connected one is
  /// saved for when that node connects.
  Future<void> handle(NotificationActionEvent e) async {
    final mesh = _ref.read(meshProvider);
    if (mesh.nodeId != e.thread.node) {
      if (e.action == kReplyAction) await _queue(e);
      return;
    }
    switch (e.action) {
      case kMarkReadAction:
        _markRead(e.thread.target);
      case kReplyAction:
        await _reply(e);
    }
  }

  /// Sends the replies saved for [node] (once per node per app run).
  Future<void> sendQueued(int node) async {
    if (!_drained.add(node)) return;
    final prefs = _ref.read(sharedPrefsProvider);
    for (final e in await takeQueuedReplies(prefs, node)) {
      if (!_ref.mounted) return;
      await _reply(e);
    }
  }

  void _markRead(ChatTarget t) {
    final ctl = _ref.read(meshProvider.notifier);
    switch (t) {
      case DmThread(:final peer):
        ctl.markRead(peer);
      case ChannelThread(:final name):
        ctl.markChannelRead(name);
    }
  }

  Future<void> _queue(NotificationActionEvent e) async {
    if ((e.input ?? '').trim().isEmpty) return;
    await queueReply(_ref.read(sharedPrefsProvider), e);
  }

  Future<void> _reply(NotificationActionEvent e) async {
    final text = (e.input ?? '').trim();
    if (text.isEmpty) return;
    final alerts = _ref.read(meshAlertsProvider);
    final mesh = _ref.read(meshProvider);
    final ctl = _ref.read(meshProvider.notifier);
    Future<void> tell(int id, String from, String body) =>
        alerts.textReceived(peer: id, from: from, text: body).catchError((Object _) {});
    if (_ref.read(appLockedProvider)) {
      // never send from a locked app: keep the words as a draft instead
      if (e.thread.target case DmThread(:final peer)) ctl.setDraft(peer, text);
      await tell(_idFor(e.thread.target), 'GhostWave is locked', 'Reply not sent. Open the app to send it.');
      return;
    }
    final info = _ref.read(nodeInfoProvider);
    switch (e.thread.target) {
      case DmThread(:final peer):
        final max = (info?.maxTextBytes ?? 0) == 0 ? kFallbackMaxTextBytes : info!.maxTextBytes;
        if (splitMessage(text, max).length > kMaxMessageParts) {
          ctl.setDraft(peer, text);
          await tell(peer, mesh.nameOf(peer), 'Reply too long to send. It is saved as a draft in the chat.');
          return;
        }
        await ctl.sendMessage(peer, text, max);
        ctl.markRead(peer);
      case ChannelThread(:final name):
        final max = (info?.maxChannelTextBytes ?? 0) == 0 ? kFallbackMaxChannelTextBytes : info!.maxChannelTextBytes;
        if (utf8.encode(text).length > max) {
          await tell(_idFor(e.thread.target), '#$name', 'Reply not sent: over $max bytes. Open the app to shorten it.');
          return;
        }
        await ctl.sendChannelText(name, text);
        ctl.markChannelRead(name);
    }
  }

  // the same notification IDs the incoming message used (see MeshController)
  static int _idFor(ChatTarget t) => switch (t) {
    DmThread(:final peer) => peer,
    ChannelThread(:final name) => name.hashCode | 0x20000000,
  };
}
