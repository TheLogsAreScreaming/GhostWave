/// Stream framing for the GhostWave client link (GhostWave
/// `docs/CLIENT_PROTOCOL.md` §2).
///
/// ```
/// 0x94 0xC3 len_lo len_hi | version | protobuf ToRadio / FromRadio
/// ```
/// `len` counts the version byte plus the protobuf bytes and is 1..176, so a
/// whole frame is at most 180 bytes. Plain Dart: no Flutter imports.
library;

import 'dart:async';
import 'dart:typed_data';

/// First magic byte.
const int kMagic0 = 0x94;

/// Second magic byte.
const int kMagic1 = 0xC3;

/// Magic (2) + length (2).
const int kFrameHeader = 4;

/// Largest whole frame, in bytes (fits one BLE write at ATT MTU 185).
const int kMaxFrame = 180;

/// Largest `len`: version byte + protobuf bytes.
const int kMaxBody = kMaxFrame - kFrameHeader;

/// The protocol version this app speaks.
const int kProtocolVersion = 1;

/// Thrown by [encodeFrame] when a message does not fit one frame. Messages are
/// never cut.
class FrameTooLargeException implements Exception {
  /// Creates the exception for a body of [bodyLength] bytes.
  const FrameTooLargeException(this.bodyLength);

  /// Version byte + protobuf bytes that were asked for.
  final int bodyLength;

  @override
  String toString() => 'FrameTooLargeException: body of $bodyLength bytes, max $kMaxBody';
}

/// Wraps protobuf bytes [pb] in a frame.
Uint8List encodeFrame(List<int> pb, {int version = kProtocolVersion}) {
  final len = 1 + pb.length;
  if (len > kMaxBody) throw FrameTooLargeException(len);
  final out = Uint8List(kFrameHeader + len);
  out[0] = kMagic0;
  out[1] = kMagic1;
  out[2] = len & 0xFF;
  out[3] = len >> 8;
  out[4] = version & 0xFF;
  out.setRange(5, out.length, pb);
  return out;
}

/// What a [FrameReader] produces.
sealed class FrameEvent {
  const FrameEvent();
}

/// A complete frame. The caller judges [version].
final class Frame extends FrameEvent {
  /// Creates a frame event.
  const Frame(this.version, this.body);

  /// The version byte.
  final int version;

  /// The protobuf bytes.
  final Uint8List body;
}

/// A header with a length of 0 or over [kMaxBody]. The reader dropped the
/// magic and searches for the next one.
final class BadLength extends FrameEvent {
  /// Creates a bad-length event.
  const BadLength(this.length);

  /// The length field that was read.
  final int length;
}

/// Incremental frame parser: push bytes in any split, pull frames out.
///
/// Garbage before a magic is skipped; the buffer never holds more than one
/// partial frame (plus a lone first magic byte).
class FrameReader {
  final List<int> _buf = <int>[];
  int _skipped = 0;

  /// Bytes waiting for the rest of a frame.
  int get buffered => _buf.length;

  /// Garbage bytes skipped so far.
  int get skipped => _skipped;

  /// Adds received bytes.
  void push(List<int> data) => _buf.addAll(data);

  /// The next complete frame or bad length, or null if more bytes are needed.
  FrameEvent? next() {
    var i = 0;
    while (i < _buf.length) {
      if (_buf[i] == kMagic0 && (i + 1 == _buf.length || _buf[i + 1] == kMagic1)) {
        break;
      }
      i++;
    }
    if (i > 0) {
      _skipped += i;
      _buf.removeRange(0, i);
    }
    if (_buf.length < kFrameHeader) return null;
    final len = _buf[2] | (_buf[3] << 8);
    if (len == 0 || len > kMaxBody) {
      _buf.removeRange(0, 2);
      return BadLength(len);
    }
    if (_buf.length < kFrameHeader + len) return null;
    final version = _buf[4];
    final body = Uint8List.fromList(_buf.sublist(kFrameHeader + 1, kFrameHeader + len));
    _buf.removeRange(0, kFrameHeader + len);
    return Frame(version, body);
  }

  /// Every complete frame or bad length currently buffered.
  Iterable<FrameEvent> drain() sync* {
    for (var e = next(); e != null; e = next()) {
      yield e;
    }
  }
}

/// Byte stream -> [FrameEvent]s, as a [StreamTransformer].
class FrameDecoder extends StreamTransformerBase<List<int>, FrameEvent> {
  /// Creates the transformer.
  const FrameDecoder();

  @override
  Stream<FrameEvent> bind(Stream<List<int>> stream) async* {
    final reader = FrameReader();
    await for (final chunk in stream) {
      reader.push(chunk);
      yield* Stream.fromIterable(reader.drain());
    }
  }
}
