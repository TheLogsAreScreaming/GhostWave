/// One client-link session over one [TransportConnection]: request/reply
/// correlation by `req_id`, and an event stream for `req_id == 0`.
library;

import 'dart:async';

import 'package:protobuf/protobuf.dart' show InvalidProtocolBufferException;

import '../gen/ghostwave.pb.dart' as pb;
import 'frame_codec.dart';
import 'link_crypto.dart';
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
  LinkCipher? _tx;
  LinkCipher? _rx;
  bool _rxConfirmed = false;
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

  /// Whether the node has proved it holds the session keys, so this link is
  /// encrypted and authenticated.
  bool get isEncrypted => _rxConfirmed;

  /// Whether the session has ended.
  bool get isClosed => _done.isCompleted;

  /// Sends `Hello` and returns the node's `NodeInfo`.
  ///
  /// A node that wants a PIN answers with a challenge; [pinFor] then supplies
  /// the PIN and the link is encrypted from that point. Throws
  /// [PinRequiredException] if there is none, and [NodeError] `BAD_PIN` if it
  /// is wrong. With [requireEncrypted], a node that doesn't encrypt is refused
  /// with [TransportFatalException]: someone on the network could be posing
  /// as a node with no PIN.
  Future<pb.NodeInfo> hello(
    String clientName, {
    Future<String?> Function()? pinFor,
    bool requireEncrypted = false,
  }) async {
    var r = await request(
      pb.ToRadio(
        hello: pb.Hello(protocolVersion: kProtocolVersion, clientName: clientName),
      ),
    );
    if (r.hasPinChallenge()) {
      final pin = await pinFor?.call();
      if (pin == null) throw const PinRequiredException();
      final challenge = r.pinChallenge;
      if (challenge.nonce.length != 16 || challenge.serverShare.length != 32) {
        throw const TransportFatalException(_updateNode);
      }
      final secret = newLinkSecret();
      final share = await linkShare(pin, challenge.nonce, secret);
      final keys = await linkKeys(
        secret: secret,
        theirShare: challenge.serverShare,
        nonce: challenge.nonce,
        serverShare: challenge.serverShare,
        clientShare: share,
      );
      if (keys == null) throw const TransportFatalException(_badHandshake);
      final reply = request(
        pb.ToRadio(
          hello: pb.Hello(
            protocolVersion: kProtocolVersion,
            clientName: clientName,
            clientShare: share,
            pinProof: keys.confirm,
          ),
        ),
      );
      // The proof above went out in clear, as it must. Everything after it is
      // sealed, starting with the node's reply.
      _tx = LinkCipher(keys.clientToNode);
      _rx = LinkCipher(keys.nodeToClient);
      r = await reply;
    }
    if (!r.hasNodeInfo()) throw const LinkClosedException('unexpected reply to Hello');
    if (requireEncrypted && !isEncrypted) throw const TransportFatalException(_updateNode);
    return r.nodeInfo;
  }

  static const _updateNode =
      'This node did not offer an encrypted connection, so GhostWave did not connect. Update the node, and check you are on the right network.';
  static const _badHandshake = 'The node sent an invalid handshake, so GhostWave did not connect.';

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
    final tx = _tx;
    final bytes = req.writeToBuffer();
    final frame = tx == null ? encodeFrame(bytes) : encodeFrame(tx.seal(bytes), version: kSecureVersion);
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
          final List<int> plain;
          final rx = _rx;
          if (rx != null && version == kSecureVersion) {
            final opened = rx.open(body);
            if (opened == null) {
              _shutdown('the encrypted link failed its check');
              return;
            }
            _rxConfirmed = true;
            plain = opened;
          } else if (version != kProtocolVersion || rx != null && _rxConfirmed) {
            _shutdown(
              rx != null && _rxConfirmed
                  ? 'an unencrypted frame arrived on the encrypted link'
                  : 'the node speaks protocol version $version',
            );
            return;
          } else {
            plain = body;
          }
          final pb.FromRadio m;
          try {
            m = pb.FromRadio.fromBuffer(plain);
          } on InvalidProtocolBufferException {
            continue;
          }
          // until the node proves it has the keys, the only thing it may say
          // in clear is an error such as BAD_PIN
          if (rx != null && !_rxConfirmed && !m.hasError()) {
            _shutdown('the node did not encrypt the link');
            return;
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
