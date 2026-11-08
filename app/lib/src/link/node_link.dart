/// Keeps one node connected: opens the transport, runs the `Hello` handshake,
/// and reconnects with backoff when the link drops.
library;

import 'dart:async';

import '../gen/ghostwave.pb.dart' as pb;
import 'session.dart';
import 'transport.dart';

/// Where the link is.
sealed class LinkState {
  const LinkState();
}

/// No target set, or the user disconnected.
final class LinkIdle extends LinkState {
  /// Creates the state.
  const LinkIdle();
}

/// Opening the transport or waiting for `NodeInfo`.
final class LinkConnecting extends LinkState {
  /// Creates the state.
  const LinkConnecting(this.target, this.attempt);

  /// Transport label.
  final String target;

  /// 1 for the first try after a (re)start.
  final int attempt;
}

/// Handshake done.
final class LinkUp extends LinkState {
  /// Creates the state.
  const LinkUp(this.target, this.info, this.session);

  /// Transport label.
  final String target;

  /// The node's identity.
  final pb.NodeInfo info;

  /// The live session; use it for requests.
  final LinkSession session;
}

/// The link dropped or could not open; another try is scheduled.
final class LinkWaiting extends LinkState {
  /// Creates the state.
  const LinkWaiting(this.target, this.reason, this.retryIn);

  /// Transport label.
  final String target;

  /// Why the last attempt failed.
  final String reason;

  /// Delay before the next attempt.
  final Duration retryIn;
}

/// Stopped for good until the user acts (e.g. protocol version mismatch).
final class LinkFailed extends LinkState {
  /// Creates the state.
  const LinkFailed(this.target, this.reason);

  /// Transport label.
  final String target;

  /// Why.
  final String reason;
}

/// Delays between reconnect attempts, by attempt number (the last repeats).
const List<Duration> kReconnectBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
];

/// The connection manager. Plain Dart; one per app.
class NodeLink {
  /// Creates the manager. [clientName] goes into `Hello`.
  NodeLink({this.clientName = 'GhostWave app', this.backoff = kReconnectBackoff});

  /// Sent in `Hello` (node logs only).
  final String clientName;

  /// Reconnect delays.
  final List<Duration> backoff;

  final StreamController<LinkState> _states = StreamController<LinkState>.broadcast(sync: true);
  final StreamController<pb.FromRadio> _events = StreamController<pb.FromRadio>.broadcast(sync: true);
  LinkState _state = const LinkIdle();
  Transport? _transport;
  int _generation = 0;
  Timer? _retry;

  /// Current state.
  LinkState get state => _state;

  /// State changes.
  Stream<LinkState> get states => _states.stream;

  /// Unsolicited node events from whichever session is live.
  Stream<pb.FromRadio> get events => _events.stream;

  /// The live session, or null.
  LinkSession? get session => switch (_state) {
    LinkUp(:final session) => session,
    _ => null,
  };

  /// Connects to [transport] (dropping any current link) and keeps it up.
  void connect(Transport transport) {
    _stopCurrent();
    _transport = transport;
    unawaited(_attempt(++_generation, 1));
  }

  /// Retries now if waiting or failed.
  void retryNow() {
    final t = _transport;
    if (t == null || _state is LinkUp || _state is LinkConnecting) return;
    _stopCurrent();
    unawaited(_attempt(++_generation, 1));
  }

  /// Drops the link and stops reconnecting.
  void disconnect() {
    _stopCurrent();
    _transport = null;
    _generation++;
    _set(const LinkIdle());
  }

  void _stopCurrent() {
    _retry?.cancel();
    _retry = null;
    final s = session;
    _generation++;
    if (s != null) unawaited(s.close());
  }

  Future<void> _attempt(int gen, int attempt) async {
    final t = _transport;
    if (t == null || gen != _generation) return;
    _set(LinkConnecting(t.label, attempt));
    LinkSession? s;
    try {
      final conn = await t.open();
      if (gen != _generation) {
        await conn.close();
        return;
      }
      s = LinkSession(conn);
      final sub = s.events.listen((e) {
        if (gen == _generation && !_events.isClosed) _events.add(e);
      });
      final info = await s.hello(clientName);
      if (gen != _generation) {
        await s.close();
        return;
      }
      _set(LinkUp(t.label, info, s));
      final reason = await s.done;
      unawaited(sub.cancel());
      if (gen != _generation) return;
      _scheduleRetry(gen, 1, reason);
    } on NodeError catch (e) {
      await s?.close();
      if (gen != _generation) return;
      if (e.code == pb.Error_Code.BAD_VERSION) {
        _set(LinkFailed(t.label, e.message));
      } else {
        _scheduleRetry(gen, attempt + 1, e.message);
      }
    } on Object catch (e) {
      await s?.close();
      if (gen != _generation) return;
      final reason = s != null && s.isClosed ? await s.done : _describe(e);
      if (reason.contains('protocol version')) {
        _set(LinkFailed(t.label, reason));
      } else {
        _scheduleRetry(gen, attempt + 1, reason);
      }
    }
  }

  void _scheduleRetry(int gen, int attempt, String reason) {
    final t = _transport;
    if (t == null) return;
    final delay = backoff[(attempt - 1).clamp(0, backoff.length - 1)];
    _set(LinkWaiting(t.label, reason, delay));
    _retry = Timer(delay, () => unawaited(_attempt(gen, attempt)));
  }

  static String _describe(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  void _set(LinkState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// Releases everything.
  Future<void> dispose() async {
    disconnect();
    await _states.close();
    await _events.close();
  }
}
