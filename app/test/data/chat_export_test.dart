// Chat export: plain text and CSV, hostile text kept inert, no keys.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/data/chat_export.dart';
import 'package:ghostwave_app/src/data/models.dart';

const int me = 0x11111111;
const int ridge = 0x1A2B3C4D;
const String psk = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

String nameOf(int id) => id == ridge ? '=Ridge' : id.toRadixString(16);

/// A minimal RFC 4180 reader, to check what a spreadsheet would see.
List<List<String>> readCsv(String s) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var i = 0;
  var quoted = false;
  while (i < s.length) {
    final c = s[i];
    if (quoted) {
      if (c == '"' && i + 1 < s.length && s[i + 1] == '"') {
        cell.write('"');
        i += 2;
        continue;
      }
      if (c == '"') {
        quoted = false;
      } else {
        cell.write(c);
      }
      i++;
      continue;
    }
    if (c == '"') {
      expect(cell.isEmpty, isTrue, reason: 'a quote may only open a cell');
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\r') {
      expect(s[i + 1], '\n', reason: 'lines end with CRLF');
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
      i++;
    } else {
      cell.write(c);
    }
    i++;
  }
  expect(row, isEmpty, reason: 'the file ends with CRLF');
  return rows;
}

void main() {
  final t0 = DateTime.utc(2026, 11, 13, 14, 5, 9, 123);

  group('csvCell', () {
    test('plain text stays as it is', () => expect(csvCell('hello there'), 'hello there'));
    test('commas, quotes and line breaks are quoted', () {
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell('two\nlines'), '"two\nlines"');
      expect(csvCell('cr\rhere'), '"cr\rhere"');
      expect(csvCell(' padded '), '" padded "');
    });
    test('formula starters are made inert', () {
      expect(csvCell('=1+1'), "'=1+1");
      expect(csvCell('+1'), "'+1");
      expect(csvCell('-1'), "'-1");
      expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
      expect(csvCell('\t=1'), "'\t=1");
      expect(csvCell('=HYPERLINK("http://x","y")'), '"\'=HYPERLINK(""http://x"",""y"")"');
      expect(csvCell('a=1'), 'a=1');
    });
  });

  test('utcIso is UTC to the second', () {
    expect(utcIso(t0), '2026-11-13T14:05:09Z');
    expect(utcIso(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)), '1970-01-01T00:00:00Z');
    expect(utcIso(t0.toLocal()), '2026-11-13T14:05:09Z');
  });

  test('a DM exports every field, oldest first, hostile text kept as data', () {
    final hostile = [
      '=cmd|\' /C calc\'!A0',
      '+SUM(1,2)',
      '-2+3',
      '@import',
      'quote " and, comma',
      'multi\r\nline\nmessage',
      '',
      'émoji 🌲',
    ];
    final msgs = [
      for (var i = 0; i < hostile.length; i++)
        ChatMessage(
          peer: ridge,
          outgoing: i.isEven,
          text: hostile[i],
          at: t0.add(Duration(minutes: i)),
          state: i.isEven ? MsgState.values[(i ~/ 2) % 4] : MsgState.delivered,
        ),
    ];
    final export = ChatExport.dm(peer: ridge, messages: msgs, ownId: me, nameOf: nameOf);
    final rows = readCsv(export.toCsv());
    expect(rows.first, kCsvHeader);
    expect(rows, hasLength(hostile.length + 1));
    for (var i = 0; i < hostile.length; i++) {
      final r = rows[i + 1];
      expect(r[0], utcIso(t0.add(Duration(minutes: i))));
      expect(r[1], i.isEven ? '11111111' : '1a2b3c4d');
      expect(r[2], i.isEven ? 'You' : "'=Ridge", reason: 'names are escaped too');
      expect(r[3], i.isEven ? 'sent' : 'received');
      expect(r[4], i.isEven ? MsgState.values[(i ~/ 2) % 4].name : 'received');
      final t = hostile[i];
      expect(r[5], t.isNotEmpty && '=+-@'.contains(t[0]) ? "'$t" : t);
      for (final cell in r) {
        expect(cell.isEmpty || !'=+-@\t\r'.contains(cell[0]), isTrue, reason: 'cell "$cell" would run as a formula');
      }
    }
    expect(export.csvBytes().take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(export.csvBytes().skip(3).toList()), export.toCsv());
  });

  test('plain text: header, UTC times, multi-line messages indented', () {
    final export = ChatExport.dm(
      peer: ridge,
      messages: [
        ChatMessage(peer: ridge, outgoing: false, text: 'first\nsecond', at: t0),
        ChatMessage(
          peer: ridge,
          outgoing: true,
          text: 'ok',
          at: t0.add(const Duration(seconds: 1)),
          state: MsgState.failed,
        ),
      ],
      ownId: null,
      nameOf: (_) => 'Ridge',
    );
    final text = export.toText(DateTime.utc(2026, 11, 14, 8));
    expect(text, contains('Conversation with Ridge (1a2b3c4d)'));
    expect(text, contains('Exported 2026-11-14T08:00:00Z. Times are UTC. 2 messages.'));
    expect(text, contains('[2026-11-13T14:05:09Z] Ridge (1a2b3c4d), received\n  first\n  second\n'));
    expect(text, contains('[2026-11-13T14:05:10Z] You, sent, failed\n  ok\n'), reason: 'own ID unknown: no ID shown');
  });

  test('a channel export never holds the channel key', () {
    final export = ChatExport.channel(
      channel: 'trail crew',
      messages: [
        ChannelMessage(channel: 'trail crew', outgoing: false, text: 'hi', at: t0, src: ridge),
        ChannelMessage(channel: 'trail crew', outgoing: true, text: 'yo', at: t0, state: MsgState.sent),
      ],
      ownId: me,
      nameOf: (id) => 'Ridge',
    );
    final now = DateTime.utc(2026, 11, 14);
    for (final out in [export.toCsv(), export.toText(now)]) {
      expect(out.toLowerCase(), isNot(contains(psk)));
      expect(out, isNot(contains('ghostwave-ch:')));
    }
    final rows = readCsv(export.toCsv());
    expect(rows[1].sublist(1, 5), ['1a2b3c4d', 'Ridge', 'received', 'received']);
    expect(rows[2].sublist(1, 5), ['11111111', 'You', 'sent', 'sent']);
    expect(export.toText(now), contains('Group channel #trail crew'));
  });

  test('file names are plain ASCII with a UTC stamp', () {
    final export = ChatExport.channel(channel: '../Ünï crew!', messages: const [], ownId: null, nameOf: nameOf);
    expect(export.fileName('csv', DateTime.utc(2026, 1, 2, 3, 4)), 'ghostwave-channel-n-crew-20260102-0304.csv');
    const blank = ChatExport(title: 't', slug: '!!!', rows: []);
    expect(blank.fileName('txt', DateTime.utc(2026, 1, 2, 3, 4)), 'ghostwave-chat-20260102-0304.txt');
  });
}
