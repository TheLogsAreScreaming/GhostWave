/// Replies and reactions in a chat view, shared by DMs and channels: what each
/// row shows, the reply being written, and scrolling to a quoted original.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/message_refs.dart';
import 'message_bubble.dart';
import 'theme.dart';

/// Characters of the original shown in a quote.
const int kQuoteChars = 80;

/// A thread's rows read for replies and reactions.
class ThreadView {
  /// Folds [entries] (oldest first, one per chat row); [names] gives each
  /// row's sender as shown ("You" for ours); [own] is our node ID.
  ThreadView(this.entries, this.names, this.own) : refs = ThreadRefs.of(entries);

  /// The rows.
  final List<RefEntry> entries;

  /// Sender name per row.
  final List<String> names;

  /// Our node ID (0 before the first connect).
  final int own;

  /// The folding.
  final ThreadRefs refs;

  /// Rows shown as bubbles: everything but reactions whose message is here.
  late final List<int> visible = [
    for (var i = 0; i < entries.length; i++)
      if (!refs.folded(i)) i,
  ];

  /// Row [i]'s own reference (null while it has no mesh ID).
  String? refOf(int i) => switch (refs.meaning[i]) {
    // a reaction cannot be replied or reacted to
    ReactionText() => null,
    _ => messageRef(entries[i].sender, entries[i].msgId),
  };

  /// The text row [i]'s bubble shows.
  String textOf(int i) => switch (refs.meaning[i]) {
    PlainText(:final text) => text,
    ReplyText(:final body) => body,
    ReactionText(emoji: final e?) => 'Reacted $e to a message not on this phone',
    ReactionText() => 'Took back a reaction to a message not on this phone',
  };

  /// The quote above row [i] if it is a reply; [onTap] gets the original's row.
  BubbleQuote? quoteOf(int i, void Function(int row) onTap) {
    final m = refs.meaning[i];
    if (m is! ReplyText) return null;
    final j = refs.indexOf[m.ref];
    if (j == null) return const BubbleQuote(sender: 'Reply', snippet: null);
    return BubbleQuote(sender: names[j], snippet: snippet(textOf(j)), onTap: () => onTap(j));
  }

  /// Reactions under row [i].
  List<BubbleReaction> reactionsOf(int i) {
    final ref = refOf(i);
    final mine = ref == null ? null : refs.reactions[ref]?[own];
    return [for (final (e, n) in refs.countsFor(ref)) BubbleReaction(e, n, mine: e == mine)];
  }

  /// Our reaction to row [i], if any.
  String? myReactionTo(int i) {
    final ref = refOf(i);
    return ref == null ? null : refs.reactions[ref]?[own];
  }
}

/// The start of [text] on one line, for a quote.
String snippet(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = flat.runes.toList();
  return runes.length <= kQuoteChars ? flat : '${String.fromCharCodes(runes.take(kQuoteChars))}…';
}

/// The reply being written: what it answers.
class ReplyDraft {
  /// Creates a draft for the row with reference [ref].
  const ReplyDraft({required this.ref, required this.sender, required this.snippet});

  /// The original's reference.
  final String ref;

  /// Who wrote it.
  final String sender;

  /// The start of its text.
  final String snippet;
}

/// The bar above the message box while replying, with a cancel button.
class ReplyBar extends StatelessWidget {
  /// Creates the bar.
  const ReplyBar({required this.draft, required this.onCancel, super.key});

  /// What is being answered.
  final ReplyDraft draft;

  /// Stops replying (the typed text stays).
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final meta = Theme.of(context).textTheme.labelSmall;
    return Container(
      margin: const EdgeInsets.fromLTRB(GwSpace.md, GwSpace.xs, GwSpace.md, 0),
      padding: const EdgeInsetsDirectional.fromSTEB(GwSpace.sm, GwSpace.xs, 0, GwSpace.xs),
      decoration: BoxDecoration(
        color: GwColors.surface2,
        border: const BorderDirectional(start: BorderSide(color: GwColors.spectralCyan, width: 3)),
        borderRadius: BorderRadius.circular(GwSpace.xs),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18, color: GwColors.spectralCyan),
          const SizedBox(width: GwSpace.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: 'Replying to ${draft.sender}: ${draft.snippet}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Replying to ${draft.sender}', style: meta?.copyWith(fontWeight: FontWeight.w600)),
                  Text(draft.snippet, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: meta),
                ],
              ),
            ),
          ),
          IconButton(tooltip: 'Cancel reply', onPressed: onCancel, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

/// Scrolling a reversed chat list to a row that may not be built yet, and
/// marking it briefly. Rows wrap their bubble in [keyFor].
mixin ThreadJumper<T extends StatefulWidget> on State<T> {
  /// The chat list's controller.
  final ScrollController jumpScroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  Timer? _flashTimer;

  /// The row marked after a jump.
  int? flashed;

  /// The key of row [row].
  GlobalKey keyFor(int row) => _keys.putIfAbsent(row, GlobalKey.new);

  /// Scrolls until [row] is built, centres it and marks it. Returns false if
  /// it could not be reached (not in the list being shown).
  Future<bool> jumpTo(int row) async {
    final reduce = MediaQuery.disableAnimationsOf(context);
    // older rows sit further up (higher offsets) in a reversed list; try that
    // way first, then the other
    for (final up in const [true, false]) {
      for (var step = 0; step < 400; step++) {
        final ctx = _keys[row]?.currentContext;
        if (ctx != null) {
          if (!ctx.mounted) return false;
          await Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
          );
          if (!mounted) return false;
          _flash(row);
          return true;
        }
        if (!jumpScroll.hasClients) return false;
        final p = jumpScroll.position;
        final next = up
            ? (p.pixels + p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent)
            : (p.pixels - p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent);
        if (next == p.pixels) break;
        jumpScroll.jumpTo(next);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return false;
      }
    }
    return false;
  }

  void _flash(int row) {
    _flashTimer?.cancel();
    setState(() => flashed = row);
    _flashTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => flashed = null);
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    jumpScroll.dispose();
    super.dispose();
  }
}
