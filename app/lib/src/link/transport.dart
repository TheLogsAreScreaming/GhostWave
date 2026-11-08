/// Byte transports for the client link. TCP today; BLE (a Nordic-UART-style
/// service carrying the same frames) plugs in behind the same interface later.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// One open byte stream to a node.
abstract interface class TransportConnection {
  /// Bytes from the node. Completes (done) when the link closes.
  Stream<Uint8List> get input;

  /// Sends bytes to the node. Errors surface on [input] or as a closed link.
  void write(List<int> bytes);

  /// Closes the link. Safe to call more than once.
  Future<void> close();
}

/// Opens [TransportConnection]s to one node. Each reconnect calls [open] again.
abstract interface class Transport {
  /// Human-readable target, e.g. `192.168.1.20:47800`.
  String get label;

  /// Opens a new connection, or throws.
  Future<TransportConnection> open();
}

/// A node address entered as `host:port`, `[v6]:port` or a bare port.
class TcpAddress {
  /// Creates an address.
  const TcpAddress(this.host, this.port);

  /// Host name or IP literal (no brackets).
  final String host;

  /// TCP port.
  final int port;

  /// Parses `host:port`, `[v6]:port` or `port` (meaning 127.0.0.1). Returns
  /// null if it is not valid.
  static TcpAddress? tryParse(String text) {
    final s = text.trim();
    if (s.isEmpty) return null;
    String host;
    String portText;
    if (s.startsWith('[')) {
      final end = s.indexOf(']');
      if (end < 0 || end + 1 >= s.length || s[end + 1] != ':') return null;
      host = s.substring(1, end);
      portText = s.substring(end + 2);
    } else {
      final colon = s.lastIndexOf(':');
      if (colon < 0) {
        host = '127.0.0.1';
        portText = s;
      } else {
        if (s.indexOf(':') != colon) return null; // bare IPv6 needs brackets
        host = s.substring(0, colon);
        portText = s.substring(colon + 1);
      }
    }
    final port = int.tryParse(portText);
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    if (host.contains(RegExp(r'\s'))) return null;
    return TcpAddress(host, port);
  }

  @override
  String toString() => host.contains(':') ? '[$host]:$port' : '$host:$port';
}

/// TCP transport (`ghostwaved --client-tcp`).
class TcpTransport implements Transport {
  /// Creates a transport for [address].
  TcpTransport(this.address, {this.connectTimeout = const Duration(seconds: 6)});

  /// Where the node listens.
  final TcpAddress address;

  /// How long [open] waits for the TCP handshake.
  final Duration connectTimeout;

  @override
  String get label => address.toString();

  @override
  Future<TransportConnection> open() async {
    final socket = await Socket.connect(address.host, address.port, timeout: connectTimeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return _TcpConnection(socket);
  }
}

class _TcpConnection implements TransportConnection {
  _TcpConnection(this._socket);

  final Socket _socket;
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _socket;

  @override
  void write(List<int> bytes) {
    if (_closed) return;
    _socket.add(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.close();
    } on SocketException {
      // already gone
    }
    _socket.destroy();
  }
}
