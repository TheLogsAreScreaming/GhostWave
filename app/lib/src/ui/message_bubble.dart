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
    this.rssiDbm,
    this.progress,
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

  /// Signal of the last hop: the message (incoming) or its receipt (outgoing).
  final int? rssiDbm;

  /// Replaces the badge's word when only part is done, e.g. "2 of 3 delivered".
  final String? progress;

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
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () => Navigator.pop(sheet, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Copy timestamp'),
              onTap: () => Navigator.pop(sheet, 'timestamp'),
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
      case 'timestamp':
        await Clipboard.setData(ClipboardData(text: at.toUtc().toIso8601String()));
        if (context.mounted) showSnack(context, 'Timestamp copied');
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
                    if (rssiDbm case final d?)
                      Tooltip(
                        message: outgoing ? 'Receipt heard at ${signalText(d)}' : 'Heard at ${signalText(d)}',
                        child: Text(' · $d dBm', style: meta, semanticsLabel: 'signal ${signalText(d)}'),
                      ),
                    if (outgoing) ...[
                      const SizedBox(width: 6),
                      _DeliveryBadge(
                        icon: icon,
                        label: progress ?? label,
                        color: switch (state) {
                          MsgState.failed => scheme.error,
                          MsgState.delivered => GwColors.success,
                          MsgState.sent => GwColors.spectralCyan,
                          MsgState.pending => GwColors.mutedText,
                        },
                        style: meta,
                      ),
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

/// The delivery state as a small pill: icon, word and tint together, so it
/// reads without colour.
class _DeliveryBadge extends StatelessWidget {
  const _DeliveryBadge({required this.icon, required this.label, required this.color, required this.style});

  final IconData icon;
  final String label;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(GwRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(label, style: style?.copyWith(color: color)),
            ),
          ],
        ),
      ),
    ),
  );
}
