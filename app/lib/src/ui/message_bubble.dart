import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/message_refs.dart';
import '../data/models.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// The original a reply quotes, shown above the reply's text.
class BubbleQuote {
  /// Creates a quote. [snippet] null means the original is not on this phone.
  const BubbleQuote({required this.sender, required this.snippet, this.onTap});

  /// Who wrote the original.
  final String sender;

  /// The start of its text.
  final String? snippet;

  /// Scrolls to the original.
  final VoidCallback? onTap;
}

/// One reaction under a bubble.
class BubbleReaction {
  /// Creates a reaction count.
  const BubbleReaction(this.emoji, this.count, {this.mine = false});

  /// One of [kReactions].
  final String emoji;

  /// How many people chose it.
  final int count;

  /// Whether ours is among them.
  final bool mine;
}

/// One chat message (DM or channel). Long-press for React / Reply / Copy /
/// Retry / Delete, swipe right to reply; a tap on a failed message retries it.
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
    this.quote,
    this.reactions = const [],
    this.onReply,
    this.onReact,
    this.myReaction,
    this.highlighted = false,
    super.key,
  });

  /// The message this one replies to.
  final BubbleQuote? quote;

  /// Reactions to show under the bubble, in [kReactions] order.
  final List<BubbleReaction> reactions;

  /// Starts a reply to this message; null when it cannot be replied to yet.
  final VoidCallback? onReply;

  /// Sets our reaction (null takes it back); null when it cannot be reacted to.
  final void Function(String? emoji)? onReact;

  /// Our current reaction, if any.
  final String? myReaction;

  /// Briefly marked after a tap on a quote of it.
  final bool highlighted;

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
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (onReact != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: GwSpace.md),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final e in kReactions)
                      _ReactionPick(emoji: e, selected: e == myReaction, onTap: () => Navigator.pop(sheet, 'react:$e')),
                  ],
                ),
              ),
            if (onReact != null && myReaction != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text('Remove my $myReaction'),
                onTap: () => Navigator.pop(sheet, 'unreact'),
              ),
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () => Navigator.pop(sheet, 'reply'),
              ),
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
    if (choice != null && choice.startsWith('react:')) {
      onReact?.call(choice.substring(6));
      return;
    }
    switch (choice) {
      case 'unreact':
        onReact?.call(null);
      case 'reply':
        onReply?.call();
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
    final bubble = LayoutBuilder(builder: (context, box) => _bubble(context, box.maxWidth, scheme, meta, icon, label));
    final react = onReact;
    return Column(
      crossAxisAlignment: outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onReply == null) bubble else _SwipeToReply(onReply: onReply!, child: bubble),
        if (reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: GwSpace.xs),
            child: Wrap(
              alignment: outgoing ? WrapAlignment.end : WrapAlignment.start,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final r in reactions)
                  _ReactionChip(
                    reaction: r,
                    // a tap on a chip sets ours to it, or takes ours back
                    onTap: react == null ? null : () => react(r.mine ? null : r.emoji),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bubble(BuildContext context, double pane, ColorScheme scheme, TextStyle? meta, IconData icon, String label) {
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        container: true,
        onLongPressHint: onReact != null || onReply != null
            ? 'React, reply, copy or delete'
            : 'Copy, delete or send again',
        customSemanticsActions: {const CustomSemanticsAction(label: 'Reply'): ?onReply},
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
                color: highlighted
                    ? GwColors.spectralCyan
                    : outgoing
                    ? GwColors.spectralCyan.withValues(alpha: 0.30)
                    : GwColors.outlineVariant,
                width: highlighted ? 2 : 1,
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
                if (quote case final q?) _Quote(quote: q, meta: meta),
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

/// The quoted original above a reply: sender and the start of its text, in a
/// bar that scrolls to it when tapped.
class _Quote extends StatelessWidget {
  const _Quote({required this.quote, required this.meta});

  final BubbleQuote quote;
  final TextStyle? meta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final snippet = quote.snippet;
    final body = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: GwSpace.xs),
      padding: const EdgeInsets.fromLTRB(GwSpace.sm, 2, GwSpace.sm, 2),
      decoration: BoxDecoration(
        color: GwColors.spectralCyan.withValues(alpha: 0.08),
        border: const BorderDirectional(start: BorderSide(color: GwColors.spectralCyan, width: 3)),
        borderRadius: BorderRadius.circular(GwSpace.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quote.sender,
            style: meta?.copyWith(color: scheme.tertiary, fontWeight: FontWeight.w600),
          ),
          Text(
            snippet ?? 'Original message not on this phone',
            maxLines: 2,
            overflow: TextOverflow.fade,
            style: meta?.copyWith(fontStyle: snippet == null ? FontStyle.italic : null),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: quote.onTap != null,
      label: 'Reply to ${quote.sender}: ${snippet ?? 'original not on this phone'}',
      hint: quote.onTap != null ? 'Shows the original' : null,
      excludeSemantics: true,
      child: GestureDetector(onTap: quote.onTap, behavior: HitTestBehavior.opaque, child: body),
    );
  }
}

/// A reaction and its count under a bubble; ours is outlined.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, this.onTap});

  final BubbleReaction reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = kReactionNames[reaction.emoji] ?? reaction.emoji;
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$name, ${reaction.count}${reaction.mine ? ', including you' : ''}',
      hint: onTap == null ? null : (reaction.mine ? 'Takes your reaction back' : 'React with $name'),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GwRadius.lg),
        child: ConstrainedBox(
          // a comfortable touch target without making the chip look big
          constraints: const BoxConstraints(minHeight: 32, minWidth: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: GwColors.surface2,
              borderRadius: BorderRadius.circular(GwRadius.lg),
              border: Border.all(
                color: reaction.mine ? GwColors.spectralCyan : GwColors.outlineVariant,
                width: reaction.mine ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reaction.emoji),
                  const SizedBox(width: 4),
                  Text('${reaction.count}', style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One emoji in the long-press menu's reaction row.
class _ReactionPick extends StatelessWidget {
  const _ReactionPick({required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: 'React with ${kReactionNames[emoji] ?? emoji}',
    excludeSemantics: true,
    child: InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: selected
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: GwColors.spectralCyan.withValues(alpha: 0.16),
                border: Border.all(color: GwColors.spectralCyan),
              )
            : null,
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    ),
  );
}

/// Drag a bubble towards the reading end to reply: it follows the finger a
/// little, and past the threshold the reply starts on release.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.onReply, required this.child});

  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const double _max = 72;
  static const double _threshold = 48;
  double _dx = 0;
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        final along = rtl ? -d.delta.dx : d.delta.dx;
        setState(() => _dx = (_dx + along).clamp(0, _max));
        final armed = _dx >= _threshold;
        if (armed && !_armed) unawaited(HapticFeedback.selectionClick());
        _armed = armed;
      },
      onHorizontalDragEnd: (_) {
        if (_armed) widget.onReply();
        setState(() {
          _dx = 0;
          _armed = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _armed = false;
      }),
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          if (_dx > 8)
            PositionedDirectional(
              start: 0,
              child: Opacity(
                opacity: (_dx / _threshold).clamp(0, 1),
                child: const Icon(Icons.reply, color: GwColors.spectralCyan),
              ),
            ),
          Transform.translate(offset: Offset(rtl ? -_dx : _dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
