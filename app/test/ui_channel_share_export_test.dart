// Channel share dialog and chat export sheet, at normal and large text.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwave_app/src/app/share_gateway.dart';
import 'package:ghostwave_app/src/data/chat_export.dart';
import 'package:ghostwave_app/src/data/models.dart';
import 'package:ghostwave_app/src/link/contact_card.dart';
import 'package:ghostwave_app/src/ui/channel_screens.dart';
import 'package:ghostwave_app/src/ui/chat_export_sheet.dart';
import 'package:ghostwave_app/src/ui/theme.dart';

class FakeShare implements ShareGateway {
  final List<(Uint8List, String, String)> files = [];

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {}

  @override
  Future<void> shareImage(Uint8List png, String fileName, {String? text, String? subject, Rect? origin}) async {}

  @override
  Future<void> shareFile(Uint8List data, String fileName, String mimeType, {String? subject, Rect? origin}) async =>
      files.add((data, fileName, mimeType));
}

final Uint8List key = Uint8List.fromList(List.generate(32, (i) => i * 3));

Future<FakeShare> _pump(WidgetTester tester, Widget Function(BuildContext) open, {double text = 1}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final share = FakeShare();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [shareGatewayProvider.overrideWithValue(share)],
      child: MaterialApp(
        theme: buildGhostWaveTheme(),
        home: Scaffold(
          body: Builder(builder: (context) => Center(child: open(context))),
        ),
      ),
    ),
  );
  return share;
}

ChatExport _export() => ChatExport.channel(
  channel: 'trail crew',
  messages: [
    ChannelMessage(
      channel: 'trail crew',
      outgoing: false,
      text: '=evil()',
      at: DateTime.utc(2026, 11, 13, 9),
      src: 0x1A2B3C4D,
    ),
    ChannelMessage(channel: 'trail crew', outgoing: true, text: 'hello, all', at: DateTime.utc(2026, 11, 13, 9, 1)),
  ],
  ownId: 0x11111111,
  nameOf: (_) => 'Ridge',
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('share dialog shows the warning, QR and copyable card at text x$scale', (tester) async {
      final card = ChannelCard(name: 'trail crew', psk: key);
      await _pump(
        tester,
        (context) => TextButton(onPressed: () => showChannelShare(context, card), child: const Text('open')),
        text: scale,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Anyone who sees it'), findsOneWidget);
      expect(find.bySemanticsLabel('QR code for channel trail crew'), findsOneWidget);
      final shown = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(ChannelCard.tryParse(shown)!.psk, key, reason: 'the shown text joins the same channel');

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.ensureVisible(find.text('Copy as text'));
      await tester.tap(find.text('Copy as text'));
      await tester.pump();
      expect(copied, shown);
      expect(find.textContaining('Anyone with this text can read the channel'), findsOneWidget);
    });

    testWidgets('export sheet hands a CSV to the share sheet at text x$scale', (tester) async {
      final share = await _pump(
        tester,
        (context) => TextButton(
          onPressed: () => showChatExportSheet(context, _export(), now: () => DateTime.utc(2026, 11, 14, 8, 30)),
          child: const Text('export'),
        ),
        text: scale,
      );
      await tester.tap(find.text('export'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('No keys are included'), findsOneWidget);
      await tester.tap(find.text('CSV (spreadsheet)'));
      await tester.pumpAndSettle();
      expect(share.files, hasLength(1));
      final (data, name, mime) = share.files.single;
      expect(name, 'ghostwave-channel-trail-crew-20261114-0830.csv');
      expect(mime, 'text/csv');
      final csv = utf8.decode(data.skip(3).toList());
      expect(csv, startsWith('time_utc,sender_id,sender_name,direction,state,text\r\n'));
      expect(csv, contains("'=evil()"));
      expect(csv, contains('"hello, all"'));
    });
  }

  testWidgets('plain text export and the empty case', (tester) async {
    final share = await _pump(
      tester,
      (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () => showChatExportSheet(context, _export()), child: const Text('export')),
          TextButton(
            onPressed: () => showChatExportSheet(context, const ChatExport(title: 't', slug: 's', rows: [])),
            child: const Text('empty'),
          ),
        ],
      ),
    );
    await tester.tap(find.text('empty'));
    await tester.pump();
    expect(find.text('No messages to export'), findsOneWidget);
    expect(share.files, isEmpty);
    await tester.tap(find.text('export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain text'));
    await tester.pumpAndSettle();
    final (data, name, mime) = share.files.single;
    expect(mime, 'text/plain');
    expect(name, endsWith('.txt'));
    expect(utf8.decode(data), contains('Group channel #trail crew'));
  });
}
