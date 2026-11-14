/// Chat export: one DM conversation or one group channel as plain text or CSV,
/// for the user to keep or hand on through the share sheet.
///
/// An export is a human report, not a backup: it can't be read back in. It
/// holds message text, times, senders and delivery states, and never a key
/// (no channel key, no node key): only names and node IDs.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../link/contact_card.dart';
import 'models.dart';

/// Which way a message went.
enum ExportDirection {
  /// Written on this phone.
  sent,

  /// Heard from the mesh.
  received,
}

/// One message as it is exported.
class ExportRow {
  /// Creates a row.
  const ExportRow({
    required this.at,
    required this.senderId,
    required this.senderName,
    required this.direction,
    required this.state,
    required this.text,
  });

  /// When it was written (sent) or received.
  final DateTime at;

  /// Sender's node ID; 0 if not known (an outgoing message before the first connect).
  final int senderId;

  /// Sender's display name.
  final String senderName;

  /// Sent or received.
  final ExportDirection direction;

  /// Delivery state, as a fixed lowercase word: `pending`, `sent`, `delivered`,
  /// `failed` (sent messages) or `received`.
  final String state;

  /// The message text, as written.
  final String text;
}

/// A conversation ready to export.
class ChatExport {
  /// Creates an export.
  const ChatExport({required this.title, required this.slug, required this.rows});

  /// One DM conversation, oldest first. [ownId] is this phone's node (null
  /// before the first connect); [nameOf] gives display names.
  factory ChatExport.dm({
    required int peer,
    required List<ChatMessage> messages,
    required int? ownId,
    required String Function(int id) nameOf,
  }) {
    final peerName = nameOf(peer);
    return ChatExport(
      title: 'Conversation with $peerName (${nodeIdHex(peer)})',
      slug: 'dm-${nodeIdHex(peer)}',
      rows: [
        for (final m in messages)
          ExportRow(
            at: m.at,
            senderId: m.outgoing ? (ownId ?? 0) : peer,
            senderName: m.outgoing ? 'You' : peerName,
            direction: m.outgoing ? ExportDirection.sent : ExportDirection.received,
            state: m.outgoing ? m.state.name : 'received',
            text: m.text,
          ),
      ],
    );
  }

  /// One group channel, oldest first. The channel key is not an input, so it
  /// can't end up in the file.
  factory ChatExport.channel({
    required String channel,
    required List<ChannelMessage> messages,
    required int? ownId,
    required String Function(int id) nameOf,
  }) => ChatExport(
    title: 'Group channel #$channel',
    slug: 'channel-$channel',
    rows: [
      for (final m in messages)
        ExportRow(
          at: m.at,
          senderId: m.outgoing ? (ownId ?? 0) : m.src,
          senderName: m.outgoing ? 'You' : nameOf(m.src),
          direction: m.outgoing ? ExportDirection.sent : ExportDirection.received,
          // channels have no receipts: an outgoing message ends at "sent"
          state: m.outgoing ? m.state.name : 'received',
          text: m.text,
        ),
    ],
  );

  /// Heading, e.g. "Group channel #trail crew".
  final String title;

  /// File name stem before sanitizing.
  final String slug;

  /// Messages, oldest first.
  final List<ExportRow> rows;

  /// A file name: `ghostwave-<slug>-<UTC yyyymmdd-hhmm>.<ext>`, ASCII letters,
  /// digits and dashes only.
  String fileName(String ext, DateTime now) {
    final safe = slug.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final u = now.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${u.year}${two(u.month)}${two(u.day)}-${two(u.hour)}${two(u.minute)}';
    return 'ghostwave-${safe.isEmpty ? 'chat' : safe}-$stamp.$ext';
  }

  /// Plain text, one block per message; times in UTC.
  String toText(DateTime now) {
    final out = StringBuffer()
      ..writeln('GhostWave chat export')
      ..writeln(title)
      ..writeln('Exported ${utcIso(now)}. Times are UTC. ${rows.length} message${rows.length == 1 ? '' : 's'}.')
      ..writeln();
    for (final r in rows) {
      final who = r.senderId == 0 ? r.senderName : '${r.senderName} (${nodeIdHex(r.senderId)})';
      final arrow = r.direction == ExportDirection.sent ? 'sent' : 'received';
      out.writeln('[${utcIso(r.at)}] $who, $arrow${r.direction == ExportDirection.sent ? ', ${r.state}' : ''}');
      for (final line in const LineSplitter().convert(r.text)) {
        out.writeln('  $line');
      }
      out.writeln();
    }
    return out.toString();
  }

  /// CSV per RFC 4180 (CRLF line ends, quoted where needed), with a header.
  /// Text cells that a spreadsheet would run as a formula are made inert.
  String toCsv() {
    final out = StringBuffer()..write('${kCsvHeader.join(',')}\r\n');
    for (final r in rows) {
      final cells = [
        utcIso(r.at),
        r.senderId == 0 ? '' : nodeIdHex(r.senderId),
        r.senderName,
        r.direction.name,
        r.state,
        r.text,
      ];
      out.write('${cells.map(csvCell).join(',')}\r\n');
    }
    return out.toString();
  }

  /// [toCsv] as UTF-8 with a byte-order mark, so spreadsheet apps pick the
  /// right encoding for names and text outside ASCII.
  Uint8List csvBytes() => Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv())]);

  /// [toText] as UTF-8.
  Uint8List textBytes(DateTime now) => Uint8List.fromList(utf8.encode(toText(now)));
}

/// CSV column names.
const List<String> kCsvHeader = ['time_utc', 'sender_id', 'sender_name', 'direction', 'state', 'text'];

/// [t] in UTC as ISO-8601 to the second, e.g. `2026-11-13T14:05:09Z`.
String utcIso(DateTime t) {
  final s = t.toUtc().toIso8601String();
  final dot = s.indexOf('.');
  return dot < 0 ? s : '${s.substring(0, dot)}Z';
}

/// One CSV cell: formula-guarded, then quoted per RFC 4180 if it holds a
/// comma, quote, CR or LF (or starts or ends with a space).
///
/// A cell starting with `=`, `+`, `-`, `@`, tab or CR is prefixed with `'`
/// so a spreadsheet shows it as text instead of running it.
String csvCell(String value) {
  var v = value;
  if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
  final needsQuotes = v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r') || v != v.trim();
  return needsQuotes ? '"${v.replaceAll('"', '""')}"' : v;
}
