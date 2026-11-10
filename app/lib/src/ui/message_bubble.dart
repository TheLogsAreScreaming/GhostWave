import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// One chat message (DM or channel). Long-press for Copy / Retry / Delete;
/// a tap on a failed message retries it.
class MessageBubble extends StatelessWidget {
  /// Creates a bubble.
  const MessageBubble({
    required this.outgoing,
    required this.text,
    required this.at,
    required this.state,
    required this.onDelete,
    this.onRetry,
    this.sender,
    this.replayed = false,
    this.error,
    this.receipts = true,
    super.key,
  });

  /// Sent by us.
  final bool outgoing;

  /// The text.
  final String text;

  /// When.
  final DateTime at;

  /// Delivery state (outgoing).
  final MsgState state;

  /// Sender name, shown above incoming channel messages.
  final String? sender;

  /// Held by the node while no app was connected.
  final bool replayed;

  /// Why it failed.
  final String? error;

  /// Whether this kind of message gets delivery receipts (DMs yes, channels no).
  final bool receipts;

  /// Retries a failed message.
  final VoidCallback? onRetry;

  /// Removes it from the history.
  final VoidCallback onDelete;

  Future<void> _menu(BuildContext context) async {
    final failed = state == MsgState.failed && onRetry != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () => Navigator.pop(sheet, 'copy'),
            ),
            if (failed)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Send again'),
                onTap: () => Navigator.pop(sheet, 'retry'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete from this phone'),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) showSnack(context, 'Copied');
      case 'retry':
        onRetry?.call();
      case 'delete':
        onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label) = switch (state) {
      MsgState.pending => (Icons.schedule, 'saved on phone'),
      MsgState.sent => (Icons.done, receipts ? 'accepted by radio' : 'sent to the mesh'),
      MsgState.delivered => (Icons.done_all, 'delivered'),
      MsgState.failed => (Icons.error_outline, 'failed'),
    };
    final meta = Theme.of(context).textTheme.labelSmall;
    return LayoutBuilder(builder: (context, box) => _bubble(context, box.maxWidth, scheme, meta, icon, label));
  }

  Widget _bubble(BuildContext context, double pane, ColorScheme scheme, TextStyle? meta, IconData icon, String label) {
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        container: true,
        onLongPressHint: 'Copy, delete or send again',
        child: GestureDetector(
          onTap: state == MsgState.failed && onRetry != null ? onRetry : null,
          onLongPress: () => unawaited(_menu(context)),
          child: Container(
            // a share of the pane it sits in (a side pane on wide windows), capped for reading
            constraints: BoxConstraints(maxWidth: (pane * 0.8).clamp(0, 560)),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.fromLTRB(GwSpace.md + 2, GwSpace.sm + 1, GwSpace.md + 2, GwSpace.sm - 2),
            decoration: BoxDecoration(
              color: outgoing ? GwColors.spectralCyan.withValues(alpha: 0.16) : GwColors.surface2,
              border: Border.all(
                color: outgoing ? GwColors.spectralCyan.withValues(alpha: 0.30) : GwColors.outlineVariant,
              ),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(GwRadius.lg),
                topEnd: const Radius.circular(GwRadius.lg),
                bottomStart: Radius.circular(outgoing ? GwRadius.lg : GwSpace.xs),
                bottomEnd: Radius.circular(outgoing ? GwSpace.xs : GwRadius.lg),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!outgoing && sender != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sender!,
                      style: meta?.copyWith(color: scheme.tertiary, fontWeight: FontWeight.w600),
                    ),
                  ),
                Align(alignment: Alignment.centerLeft, child: Text(text)),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 2,
                  children: [
                    if (replayed) Text('held · ', style: meta),
                    Text(clockTime(at), style: meta),
                    if (outgoing) ...[
                      const SizedBox(width: 6),
                      Icon(
                        icon,
                        size: 14,
                        color: state == MsgState.failed
                            ? scheme.error
                            : state == MsgState.delivered
                            ? GwColors.success
                            : null,
                        semanticLabel: label,
                      ),
                      const SizedBox(width: 2),
                      Text(label, style: meta),
                    ],
                  ],
                ),
                if (state == MsgState.failed)
                  Text(
                    '${error ?? 'Failed'}${onRetry != null ? ' · tap to retry' : ''}',
                    style: meta?.copyWith(color: scheme.error),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
