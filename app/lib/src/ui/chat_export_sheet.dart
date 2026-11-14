import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/share_gateway.dart';
import '../data/chat_export.dart';
import 'widgets.dart';

/// Asks plain text or CSV, then hands the file to the share sheet. [now] is
/// for tests; it defaults to the clock.
Future<void> showChatExportSheet(BuildContext context, ChatExport export, {DateTime Function()? now}) async {
  if (export.rows.isEmpty) {
    showSnack(context, 'No messages to export');
    return;
  }
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
  final share = ProviderScope.containerOf(context, listen: false).read(shareGatewayProvider);
  final format = await showModalBottomSheet<_Format>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => ChatExportSheet(export: export),
  );
  if (format == null) return;
  final at = (now ?? DateTime.now)();
  try {
    switch (format) {
      case _Format.text:
        await share.shareFile(
          export.textBytes(at),
          export.fileName('txt', at),
          'text/plain',
          subject: export.title,
          origin: origin,
        );
      case _Format.csv:
        await share.shareFile(
          export.csvBytes(),
          export.fileName('csv', at),
          'text/csv',
          subject: export.title,
          origin: origin,
        );
    }
  } on Object catch (e) {
    if (context.mounted) showSnack(context, 'Could not export: $e');
  }
}

enum _Format { text, csv }

/// The format picker. Pops `_Format` (private): open it with [showChatExportSheet].
class ChatExportSheet extends StatelessWidget {
  /// Creates the sheet for [export].
  const ChatExportSheet({required this.export, super.key});

  /// What would be exported.
  final ChatExport export;

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    final n = export.rows.length;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export chat', style: styles.titleLarge),
            const SizedBox(height: 4),
            Text('${export.title}: $n message${n == 1 ? '' : 's'}', style: styles.bodyMedium),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notes),
              title: const Text('Plain text'),
              subtitle: const Text('Easy to read or print'),
              onTap: () => Navigator.of(context).pop(_Format.text),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV (spreadsheet)'),
              subtitle: const Text('Time (UTC), sender, direction, delivery state, text'),
              onTap: () => Navigator.of(context).pop(_Format.csv),
            ),
            const SizedBox(height: 8),
            Text(
              'The file holds the messages unencrypted. Where it goes next is up to you. '
              'No keys are included.',
              style: styles.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
