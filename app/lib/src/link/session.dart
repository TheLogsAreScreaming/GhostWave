/// One client-link session over one [TransportConnection]: request/reply
/// correlation by `req_id`, and an event stream for `req_id == 0`.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'dart:async';

import 'package:protobuf/protobuf.dart' show InvalidProtocolBufferException;

import '../gen/ghostwave.pb.dart' as pb;
import 'frame_codec.dart';
import 'transport.dart';

/// A request the node answered with `Error`.
class NodeError implements Exception {
  /// Creates the error.
  const NodeError(this.code, this.detail);

  /// The error code. Unknown codes from a newer node have a generic value.
  final pb.Error_Code code;

  /// Free-text detail from the node.
  final String detail;

  /// Short user-facing text.
  String get message => switch (code.value) {
    1 => 'Bad frame',
    2 => 'Protocol version mismatch: update the app or the node',
    3 => 'The node does not know this request (update the node)',
    4 => 'Handshake missing',
    5 => 'Bad argument',
    6 => 'Text too long',
    7 => 'Rate limited: wait a minute',
    8 => 'Not found',
    9 => 'Key rejected: it does not match the node ID',
    10 => 'The node could not send it',
    11 => 'Too many apps connected to the node',
    12 => 'The node has no identity key',
    _ => 'Error ${code.value}',
  };

  @override
  String toString() => 'NodeError(${code.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// The link closed (or failed) before a reply arrived.
class LinkClosedException implements Exception {
  /// Creates the exception.
  const LinkClosedException([this.reason = 'link closed']);

  /// Why.
  final String reason;

  @override
  String toString() => 'LinkClosedException: $reason';
}

/// The node wants a PIN and none is known for it.
class PinRequiredException implements Exception {
  /// Creates the exception.
  const PinRequiredException();

  @override
  String toString() => 'PinRequiredException';
}

/// The `Hello` proof for [pin] (`docs/CLIENT_PROTOCOL.md` §7): the first 32
/// bytes of HMAC-SHA-512(pin, "ghostwave-pin-v1" || serverNonce || clientNonce).
List<int> pinProof(String pin, List<int> serverNonce, List<int> clientNonce) => Hmac(
  sha512,
  utf8.encode(pin),
).convert([...utf8.encode('ghostwave-pin-v1'), ...serverNonce, ...clientNonce]).bytes.sublist(0, 32);

/// No reply within the timeout.
class ReplyTimeoutException implements Exception {
  /// Creates the exception.
  const ReplyTimeoutException();

  @override
  String toString() => 'ReplyTimeoutException';
}

class _Pending {
  _Pending({required this.multi});

  final bool multi;
  final Completer<List<pb.FromRadio>> completer = Completer<List<pb.FromRadio>>();
  final List<pb.FromRadio> replies = <pb.FromRadio>[];
}

/// A live session. Create it, listen to [events], then call [hello].
class LinkSession {
  /// Wraps [connection]. Starts reading at once.
  LinkSession(this._conn, {this.replyTimeout = const Duration(seconds: 8)}) {
    _sub = _conn.input.listen(
      _onBytes,
      onError: (Object e) => _shutdown('link error: $e'),
      onDone: () => _shutdown('the node closed the link'),
      cancelOnError: true,
    );
  }

  final TransportConnection _conn;

  /// Default time to wait for a reply.
  final Duration replyTimeout;

  final FrameReader _reader = FrameReader();
  final Map<int, _Pending> _pending = <int, _Pending>{};
  final StreamController<pb.FromRadio> _events = StreamController<pb.FromRadio>.broadcast(sync: true);
  final Completer<String> _done = Completer<String>();
  late final StreamSubscription<List<int>> _sub;
  int _nextReq = 1;

  /// Unsolicited events (`req_id == 0`), including replayed ones, and stream
  /// errors the node reported without a request.
  Stream<pb.FromRadio> get events => _events.stream;

  /// Completes with the reason when the session ends.
  Future<String> get done => _done.future;

  /// Whether the session has ended.
  bool get isClosed => _done.isCompleted;

  /// Sends `Hello` and returns the node's `NodeInfo`.
  ///
  /// A node that wants a PIN answers with a challenge; [pinFor] then supplies
  /// the PIN. Throws [PinRequiredException] if there is none, and [NodeError]
  /// `BAD_PIN` if it is wrong.
  Future<pb.NodeInfo> hello(String clientName, {Future<String?> Function()? pinFor}) async {
    var r = await request(
      pb.ToRadio(
        hello: pb.Hello(protocolVersion: kProtocolVersion, clientName: clientName),
      ),
    );
    if (r.hasPinChallenge()) {
      final pin = await pinFor?.call();
      if (pin == null) throw const PinRequiredException();
      final rng = Random.secure();
      final nonce = List<int>.generate(16, (_) => rng.nextInt(256));
      r = await request(
        pb.ToRadio(
          hello: pb.Hello(
            protocolVersion: kProtocolVersion,
            clientName: clientName,
            clientNonce: nonce,
            pinProof: pinProof(pin, r.pinChallenge.nonce, nonce),
          ),
        ),
      );
    }
    if (!r.hasNodeInfo()) throw const LinkClosedException('unexpected reply to Hello');
    return r.nodeInfo;
  }

  /// Sends [msg] with a fresh `req_id` and returns the single reply. Throws
  /// [NodeError] if the reply is `Error`.
  Future<pb.FromRadio> request(pb.ToRadio msg, {Duration? timeout}) async {
    final replies = await _send(msg, multi: false, timeout: timeout);
    final r = replies.single;
    if (r.hasError()) throw NodeError(r.error.code, r.error.detail);
    return r;
  }

  /// `ListContacts`: every `Contact`, collected until `ContactsEnd`.
  Future<List<pb.Contact>> listContacts() async {
    final replies = await _send(pb.ToRadio(listContacts: pb.ListContacts()), multi: true);
    final last = replies.last;
    if (last.hasError()) throw NodeError(last.error.code, last.error.detail);
    return [
      for (final r in replies)
        if (r.hasContact()) r.contact,
    ];
  }

  /// `ListChannels` (protocol 1.1): every `Channel`, collected until `ChannelsEnd`.
  Future<List<pb.Channel>> listChannels() async {
    final replies = await _send(pb.ToRadio(listChannels: pb.ListChannels()), multi: true);
    final last = replies.last;
    if (last.hasError()) throw NodeError(last.error.code, last.error.detail);
    return [
      for (final r in replies)
        if (r.hasChannel()) r.channel,
    ];
  }

  Future<List<pb.FromRadio>> _send(pb.ToRadio msg, {required bool multi, Duration? timeout}) {
    if (isClosed) return Future.error(const LinkClosedException());
    final id = _nextReq;
    _nextReq = _nextReq >= 0x7FFFFFFF ? 1 : _nextReq + 1;
    final req = msg.deepCopy()..reqId = id;
    final frame = encodeFrame(req.writeToBuffer());
    final p = _Pending(multi: multi);
    _pending[id] = p;
    _conn.write(frame);
    return p.completer.future.timeout(
      timeout ?? replyTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw const ReplyTimeoutException();
      },
    );
  }

  void _onBytes(List<int> data) {
    _reader.push(data);
    for (final ev in _reader.drain()) {
      switch (ev) {
        case BadLength():
          break; // resynced; nothing to report to the app
        case Frame(:final version, :final body):
          if (version != kProtocolVersion) {
            _shutdown('the node speaks protocol version $version');
            return;
          }
          final pb.FromRadio m;
          try {
            m = pb.FromRadio.fromBuffer(body);
          } on InvalidProtocolBufferException {
            continue;
          }
          _route(m);
      }
    }
  }

  void _route(pb.FromRadio m) {
    final p = m.reqId == 0 ? null : _pending[m.reqId];
    if (p == null) {
      // an event kind from a newer node: nothing this app can show
      if (m.whichEvent() == pb.FromRadio_Event.notSet) return;
      if (!_events.isClosed) _events.add(m);
      if (m.hasError() && m.error.code == pb.Error_Code.BAD_VERSION) {
        _shutdown('protocol version mismatch: update the app or the node');
      }
      return;
    }
    p.replies.add(m);
    final finished = !p.multi || m.hasContactsEnd() || m.hasChannelsEnd() || m.hasError();
    if (finished) {
      _pending.remove(m.reqId);
      p.completer.complete(p.replies);
    }
  }

  void _shutdown(String reason) {
    if (_done.isCompleted) return;
    _done.complete(reason);
    for (final p in _pending.values) {
      if (!p.completer.isCompleted) p.completer.completeError(LinkClosedException(reason));
    }
    _pending.clear();
    unawaited(_sub.cancel());
    unawaited(_conn.close());
    unawaited(_events.close());
  }

  /// Closes the session; [reason] becomes the result of [done].
  Future<void> close({String reason = 'closed by the app'}) async => _shutdown(reason);
}
