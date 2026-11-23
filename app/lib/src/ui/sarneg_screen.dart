import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/location_share.dart';
import '../app/sarneg_controller.dart';
import '../data/sarneg.dart';
import 'theme.dart';
import 'widgets.dart';

/// What to say about a code word that cannot be used.
String sarnegProblemText(SarnegWordProblem p) => switch (p) {
  SarnegWordProblem.length => 'Use exactly 10 letters',
  SarnegWordProblem.letters => 'Use only the letters A to Z',
  SarnegWordProblem.repeats => 'No letter may appear twice',
};

const _notEncryption =
    'SARNEG hides numbers (grids, frequencies, times) from a casual listener. '
    'It is not encryption: someone who hears a few messages can work out the word. '
    'Keep using private channels for anything that matters.';

/// Sets the team's SARNEG code words, shares them, and encodes or decodes by hand.
class SarnegScreen extends ConsumerWidget {
  /// Creates the screen.
  const SarnegScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(sarnegProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('SARNEG code word')),
      body: ReadableWidth(
        child: switch (keys) {
          AsyncData(:final value) => _Body(keys: value),
          AsyncError() => const Center(child: Text('The saved code word could not be read.')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.keys});

  final SarnegKeySet? keys;

  Future<void> _setWord(BuildContext context, WidgetRef ref) async {
    final word = await showDialog<String>(
      context: context,
      builder: (_) => _WordDialog(title: keys == null ? 'Set the code word' : 'Change the code word'),
    );
    if (word == null) return;
    final k = keys;
    await ref.read(sarnegProvider.notifier).save(SarnegKeySet(word: word, daily: k?.daily ?? const {}));
  }

  Future<void> _addDay(BuildContext context, WidgetRef ref, SarnegKeySet k) async {
    final now = ref.read(sarnegClockProvider)();
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 366)),
      helpText: 'Day for this word',
    );
    if (day == null || !context.mounted) return;
    final word = await showDialog<String>(
      context: context,
      builder: (_) => _WordDialog(title: 'Word for ${sarnegDay(day)}'),
    );
    if (word == null) return;
    if (k.daily.length >= kSarnegMaxDailyWords && !k.daily.containsKey(sarnegDay(day))) {
      if (context.mounted) showSnack(context, 'At most $kSarnegMaxDailyWords dated words');
      return;
    }
    await ref.read(sarnegProvider.notifier).save(k.withDay(sarnegDay(day), word));
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final text = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const SarnegImportScreen()));
    if (text == null || !context.mounted) return;
    try {
      final k = SarnegKeySet.parseShareText(text);
      await ref.read(sarnegProvider.notifier).save(k);
      if (context.mounted) showSnack(context, 'Code word saved');
    } on FormatException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Forget the code words?'),
        content: const Text('Messages already received stay as they are, but this phone can no longer decode them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Forget')),
        ],
      ),
    );
    if (ok == true) await ref.read(sarnegProvider.notifier).save(null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = keys;
    final today = ref.watch(sarnegClockProvider)();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const Text(
          'Agree a 10-letter word with no repeated letter. Its first letter stands for 0, '
          'the next for 1, and so on, so the numbers in a message go out as letters.',
        ),
        const SizedBox(height: 8),
        const _Warning(_notEncryption),
        const SizedBox(height: 16),
        if (k == null) ...[
          const Text('No code word on this phone yet.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _setWord(context, ref),
                icon: const Icon(Icons.edit),
                label: const Text('Type a word'),
              ),
              OutlinedButton.icon(
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan or paste'),
              ),
            ],
          ),
        ] else ...[
          _WordCard(keys: k, today: today),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _setWord(context, ref),
                icon: const Icon(Icons.edit),
                label: const Text('Change'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ShareDialog(keys: k),
                ),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Share'),
              ),
              OutlinedButton.icon(
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan or paste'),
              ),
              TextButton.icon(
                onPressed: () => _forget(context, ref),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Forget'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Words for given days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('On these days the dated word replaces the main one. Old days are removed.'),
          for (final e in k.daily.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(e.key),
              subtitle: Text(e.value, style: GwText.mono),
              trailing: IconButton(
                tooltip: 'Remove ${e.key}',
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(sarnegProvider.notifier).save(k.withDay(e.key, null)),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addDay(context, ref, k),
              icon: const Icon(Icons.add),
              label: const Text('Add a day'),
            ),
          ),
          const SizedBox(height: 16),
          _TryIt(codec: k.codecFor(today)),
        ],
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: GwColors.surface2,
      border: Border.all(color: GwColors.outlineVariant),
      borderRadius: BorderRadius.circular(GwRadius.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// Today's word, hidden until asked for.
class _WordCard extends StatefulWidget {
  const _WordCard({required this.keys, required this.today});

  final SarnegKeySet keys;
  final DateTime today;

  @override
  State<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<_WordCard> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.keys.wordFor(widget.today);
    final dated = widget.keys.daily.containsKey(sarnegDay(widget.today));
    final digits = [for (var i = 0; i < 10; i++) '${word[i]}=$i'].join('  ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    dated ? 'Today’s word (dated)' : 'Today’s word',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: _shown ? 'Hide the word' : 'Show the word',
                  icon: Icon(_shown ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _shown = !_shown),
                ),
              ],
            ),
            Text(
              _shown ? word : '••••••••••',
              style: GwText.mono.copyWith(fontSize: 24, letterSpacing: 4),
              semanticsLabel: _shown ? word.split('').join(' ') : 'hidden',
            ),
            if (_shown) ...[const SizedBox(height: 6), Text(digits, style: GwText.mono)],
          ],
        ),
      ),
    );
  }
}

/// Encode and decode by hand with today's word.
class _TryIt extends StatefulWidget {
  const _TryIt({required this.codec});

  final SarnegCodec codec;

  @override
  State<_TryIt> createState() => _TryItState();
}

class _TryItState extends State<_TryIt> {
  final _plain = TextEditingController();
  final _coded = TextEditingController();

  @override
  void dispose() {
    _plain.dispose();
    _coded.dispose();
    super.dispose();
  }

  Widget _result(BuildContext context, String label, String value) => Row(
    children: [
      Expanded(
        child: SelectableText(value.isEmpty ? '–' : value, style: GwText.mono, semanticsLabel: '$label: $value'),
      ),
      IconButton(
        tooltip: 'Copy $label',
        icon: const Icon(Icons.copy),
        onPressed: value.isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) showSnack(context, 'Copied');
              },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.codec;
    final body = sarnegBody(_coded.text) ?? _coded.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Encode or decode by hand', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _plain,
          decoration: const InputDecoration(labelText: 'Numbers to encode', hintText: '17S 4823 or 906.875'),
          onChanged: (_) => setState(() {}),
        ),
        _result(context, 'encoded text', _plain.text.trim().isEmpty ? '' : c.encodeMessage(_plain.text)),
        const SizedBox(height: 8),
        TextField(
          controller: _coded,
          decoration: const InputDecoration(labelText: 'Letters to decode', hintText: 'LRs KSAC'),
          onChanged: (_) => setState(() {}),
        ),
        _result(context, 'decoded text', body.trim().isEmpty ? '' : c.decode(body)),
      ],
    );
  }
}

/// Types and checks one code word.
class _WordDialog extends StatefulWidget {
  const _WordDialog({required this.title});

  final String title;

  @override
  State<_WordDialog> createState() => _WordDialogState();
}

class _WordDialogState extends State<_WordDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    final w = normalizeSarnegWord(_text.text);
    final p = checkSarnegWord(w);
    if (p != null) {
      setState(() => _error = sarnegProblemText(p));
      return;
    }
    Navigator.pop(context, w);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    // Full dialog width, so a refusal like "No letter may appear twice" fits.
    content: SizedBox(
      width: double.maxFinite,
      child: TextField(
        controller: _text,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        maxLength: 12,
        style: GwText.mono,
        decoration: InputDecoration(
          hintText: 'BLACKHORSE',
          errorText: _error,
          errorMaxLines: 3,
          counterText: '', // the error needs the whole row
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _done(),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _done, child: const Text('Save')),
    ],
  );
}

/// The code words as a QR code and as text.
class _ShareDialog extends StatelessWidget {
  const _ShareDialog({required this.keys});

  final SarnegKeySet keys;

  @override
  Widget build(BuildContext context) {
    final text = keys.toShareText();
    return AlertDialog(
      title: const Text('Share the code word'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Show this to your team in person. Anyone who scans it can read your SARNEG messages.'),
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              height: 220,
              child: QrImageView(
                data: text,
                size: 220,
                backgroundColor: Colors.white,
                semanticsLabel: 'SARNEG code word QR code',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) showSnack(context, 'Copied. Paste it only somewhere private.');
          },
          child: const Text('Copy as text'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}

/// Scans or pastes a shared code word; pops with its text.
class SarnegImportScreen extends StatefulWidget {
  /// Creates the screen.
  const SarnegImportScreen({super.key});

  @override
  State<SarnegImportScreen> createState() => _SarnegImportScreenState();
}

class _SarnegImportScreenState extends State<SarnegImportScreen> {
  final _paste = TextEditingController();
  bool _scanning = false;
  String? _error;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _use(String text) {
    try {
      SarnegKeySet.parseShareText(text);
      Navigator.pop(context, text.trim());
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Get a code word')),
    body: ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_scanning)
            SizedBox(
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  onDetect: (capture) {
                    for (final b in capture.barcodes) {
                      final raw = b.rawValue ?? '';
                      if (raw.trim().toUpperCase().startsWith(kSarnegSharePrefix)) {
                        setState(() => _scanning = false);
                        _use(raw);
                        return;
                      }
                    }
                  },
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Camera unavailable: ${error.errorCode.name}. Paste the text below.'),
                    ),
                  ),
                ),
              ),
            )
          else if (!Platform.isWindows)
            FilledButton.icon(
              onPressed: () => setState(() => _scanning = true),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _paste,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 4,
            style: GwText.mono,
            decoration: InputDecoration(
              labelText: 'Or paste the text',
              hintText: 'SARNEG1:BLACKHORSE',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: () => _use(_paste.text), child: const Text('Use this word')),
          ),
        ],
      ),
    ),
  );
}

/// Asks for the numbers to send, encodes them with today's word, and
/// returns the whole message ([kSarnegMarker] and the code letters), or null.
Future<String?> showSarnegComposeSheet(BuildContext context, {String initial = ''}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ComposeSheet(initial: initial),
);

class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet({required this.initial});

  final String initial;

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);
  bool _locating = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _myPosition() async {
    setState(() => _locating = true);
    final source = ref.read(positionSourceProvider);
    try {
      final access = await source.ensureAccess();
      if (!mounted) return;
      if (access != LocationAccess.granted) {
        showSnack(context, 'Location is off for this app');
        return;
      }
      final p = await source.watch(distanceFilterM: 0).first.timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final pos = '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';
      final t = _text.text.trim();
      _text.text = t.isEmpty ? pos : '$t $pos';
    } on TimeoutException {
      if (mounted) showSnack(context, 'No position fix yet. Try again in the open.');
    } on Object catch (e) {
      if (mounted) showSnack(context, 'No position: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(sarnegProvider).value;
    final pad = EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom);
    if (keys == null) {
      return SafeArea(
        child: Padding(
          padding: pad,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SARNEG', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Set your team’s code word first. Everyone who should read the numbers needs the same word.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const SarnegScreen())));
                },
                child: const Text('Set the code word'),
              ),
            ],
          ),
        ),
      );
    }
    final codec = keys.codecFor(ref.watch(sarnegClockProvider)());
    final plain = _text.text.trim();
    final coded = plain.isEmpty ? '' : codec.encodeMessage(plain);
    return SafeArea(
      child: Padding(
        padding: pad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send numbers in SARNEG', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Digits go out as code letters. Other words are sent as they are.'),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: widget.initial.isEmpty,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Numbers to send', hintText: '17S 4823 or 906.875'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _locating ? null : _myPosition,
              icon: _locating
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: const Text('Add my position'),
            ),
            const SizedBox(height: 4),
            Text('Goes out as', style: Theme.of(context).textTheme.labelMedium),
            Text(coded.isEmpty ? '–' : coded, style: GwText.mono),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: coded.isEmpty ? null : () => Navigator.pop(context, coded),
                child: const Text('Put in message'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under a SARNEG message: tap to show its numbers, decoded with the word for
/// the day it was sent or received.
class SarnegDecodeLine extends ConsumerStatefulWidget {
  /// Creates the line for [text], sent or received at [at].
  const SarnegDecodeLine({required this.text, required this.at, this.style, super.key});

  /// The whole message, marker included.
  final String text;

  /// When it was sent or received.
  final DateTime at;

  /// Text style.
  final TextStyle? style;

  @override
  ConsumerState<SarnegDecodeLine> createState() => _SarnegDecodeLineState();
}

class _SarnegDecodeLineState extends ConsumerState<SarnegDecodeLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(sarnegProvider).value;
    final decoded = keys?.codecFor(widget.at).decodeMessage(widget.text);
    final label = !_open
        ? 'SARNEG · tap to decode'
        : decoded == null
        ? 'SARNEG · no code word set'
        : 'Decoded: $decoded';
    return Semantics(
      button: true,
      label: _open ? label : 'Decode SARNEG numbers',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          if (_open && decoded == null) {
            unawaited(Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const SarnegScreen())));
            return;
          }
          setState(() => _open = !_open);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_open ? Icons.lock_open : Icons.pin_outlined, size: 16, color: GwColors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: (widget.style ?? const TextStyle()).copyWith(
                    color: GwColors.accent,
                    fontFamily: _open && decoded != null ? GwText.mono.fontFamily : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The composer's SARNEG button: encodes the typed numbers (or new ones) and
/// puts the coded message in [controller].
class SarnegComposeButton extends StatelessWidget {
  /// Creates the button for [controller].
  const SarnegComposeButton({required this.controller, this.enabled = true, super.key});

  /// The composer's text.
  final TextEditingController controller;

  /// False while the composer is disabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: IconButton(
      style: IconButton.styleFrom(minimumSize: const Size(48, 52)),
      tooltip: 'Send numbers in SARNEG',
      icon: const Icon(Icons.pin_outlined),
      onPressed: !enabled
          ? null
          : () async {
              final current = controller.text.trim();
              final coded = await showSarnegComposeSheet(context, initial: isSarnegMessage(current) ? '' : current);
              if (coded == null) return;
              controller.text = coded;
              controller.selection = TextSelection.collapsed(offset: coded.length);
            },
    ),
  );
}
