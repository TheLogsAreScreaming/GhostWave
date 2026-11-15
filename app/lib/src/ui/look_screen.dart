/// Settings → Look: the colour theme and the page background.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/look.dart';
import 'node_mark.dart';
import 'theme.dart';
import 'widgets.dart';

/// One-line summary for the settings list.
String lookSummary(LookSettings look, DateTime now) {
  final theme = look.theme == LookTheme.seasonal ? 'Season (${Season.of(now).label})' : look.theme.label;
  return '$theme · ${look.effectiveBackdrop.label} background';
}

/// The Look page.
class LookScreen extends ConsumerWidget {
  /// Creates the page.
  const LookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(lookProvider);
    final now = ref.watch(lookClockProvider)();
    final notifier = ref.read(lookProvider.notifier);
    final text = Theme.of(context).textTheme;
    final night = look.theme == LookTheme.night;
    final highContrast = MediaQuery.highContrastOf(context);

    String describe(LookTheme t) => switch (t) {
      LookTheme.stock => 'GhostWave cyan and violet',
      LookTheme.seasonal => 'Now ${Season.of(now).label.toLowerCase()}. Changes by itself through the year.',
      LookTheme.colorBlind => 'Yellow, blue and orange that stay apart with common colour-vision differences',
      LookTheme.night => 'Dim red only, to keep your eyes used to the dark. Maps and photos turn red too.',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Look')),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: GwSpace.xl),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: GwSpace.lg),
              child: SectionLabel('Colour theme'),
            ),
            RadioGroup<LookTheme>(
              groupValue: look.theme,
              onChanged: (t) {
                if (t != null) notifier.setTheme(t);
              },
              child: Column(
                children: [
                  for (final t in LookTheme.values)
                    RadioListTile<LookTheme>(
                      value: t,
                      title: Text(t.label),
                      subtitle: Text(describe(t)),
                      secondary: _Swatches(GwPalette.forTheme(t, now)),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: GwSpace.lg),
              child: SectionLabel('Background'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg),
              child: SegmentedButton<LookBackdrop>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: LookBackdrop.solid, label: Text('Solid'), icon: Icon(Icons.square_rounded)),
                  ButtonSegment(value: LookBackdrop.gradient, label: Text('Gradient'), icon: Icon(Icons.gradient)),
                  ButtonSegment(value: LookBackdrop.photo, label: Text('Photo'), icon: Icon(Icons.image_outlined)),
                ],
                selected: {look.backdrop},
                onSelectionChanged: night
                    ? null
                    : (s) {
                        final b = s.first;
                        if (b == LookBackdrop.photo && look.photoPath == null) {
                          unawaited(_pick(context, ref));
                        } else {
                          notifier.setBackdrop(b);
                        }
                      },
              ),
            ),
            const SizedBox(height: GwSpace.sm),
            if (!night) ...[
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: Text(look.photoPath == null ? 'Choose a photo' : 'Choose a different photo'),
                subtitle: const Text('Darkened behind the pages so text stays easy to read. Kept on this phone.'),
                onTap: () => unawaited(_pick(context, ref)),
              ),
              if (look.photoPath != null)
                ListTile(
                  leading: const Icon(Icons.hide_image_outlined),
                  title: const Text('Remove the photo'),
                  onTap: notifier.removePhoto,
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(GwSpace.lg, GwSpace.sm, GwSpace.lg, 0),
              child: Text(
                night
                    ? 'Night vision always uses a black background.'
                    : highContrast
                    ? 'High contrast is on in your phone settings, so cards stay solid.'
                    : 'With a gradient or photo, cards turn to frosted glass.',
                style: text.bodySmall?.copyWith(color: GwColors.mutedText),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: GwSpace.lg),
              child: SectionLabel('Preview'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg),
              // a picture of the theme, not controls
              child: IgnorePointer(
                child: Semantics(
                  label: 'Preview of the chosen look',
                  excludeSemantics: true,
                  child: const _PreviewCard(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(lookProvider.notifier).pickPhoto();
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'Could not use that photo: $e');
    }
  }
}

/// Three dots showing a palette's accent, second colour and success colour.
class _Swatches extends StatelessWidget {
  const _Swatches(this.p);

  final GwPalette p;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.all(GwSpace.xs + 2),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(GwRadius.pill),
        border: Border.all(color: p.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in [p.accent, p.secondary, p.success])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: DecoratedBox(
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 14),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A sample card with the colours that matter: text, muted text, accent,
/// success and alert.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GwSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ridge camp', style: text.titleMedium),
            Text('Heard 2 min ago · 1 hop', style: text.bodyMedium?.copyWith(color: GwColors.mutedText)),
            const SizedBox(height: GwSpace.md),
            Wrap(
              spacing: GwSpace.sm,
              runSpacing: GwSpace.sm,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Message')),
                Chip(
                  avatar: Icon(Icons.check_circle, color: GwColors.success, size: 18),
                  label: const Text('Delivered'),
                ),
                Chip(
                  backgroundColor: GwColors.alert,
                  side: BorderSide.none,
                  avatar: Icon(Icons.sos, color: GwColors.onAlert, size: 18),
                  label: Text('SOS', style: TextStyle(color: GwColors.onAlert)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user give [nodeId] a photo or colour on this phone, or go back to
/// its generated mark.
Future<void> showNodeLookSheet(BuildContext context, int nodeId) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _NodeLookSheet(nodeId),
);

class _NodeLookSheet extends ConsumerWidget {
  const _NodeLookSheet(this.nodeId);

  final int nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(nodeLooksProvider.select((m) => m[nodeId]));
    final looks = ref.read(nodeLooksProvider.notifier);
    final text = Theme.of(context).textTheme;
    final spec = NodeMarkSpec.forNode(nodeId);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(GwSpace.lg, 0, GwSpace.lg, GwSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NodeMark(nodeId: nodeId, size: 56),
                const SizedBox(width: GwSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text('Node picture', style: text.titleLarge)),
                      Text(
                        'Only on this phone. Never sent over the mesh.',
                        style: text.bodySmall?.copyWith(color: GwColors.mutedText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: GwSpace.lg),
            Text('Colour', style: text.titleSmall),
            const SizedBox(height: GwSpace.sm),
            Wrap(
              spacing: GwSpace.sm,
              runSpacing: GwSpace.sm,
              children: [
                for (final hue in kNodeHues)
                  _HueButton(
                    color: spec.withHue(hue).color,
                    hue: hue,
                    selected: look?.photoPath == null && look?.hue == hue,
                    onTap: () => looks.setHue(nodeId, hue),
                  ),
              ],
            ),
            const SizedBox(height: GwSpace.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text(look?.photoPath == null ? 'Choose a photo' : 'Choose a different photo'),
              onTap: () async {
                try {
                  await looks.pickPhoto(nodeId);
                } on Object catch (e) {
                  if (context.mounted) showSnack(context, 'Could not use that photo: $e');
                }
              },
            ),
            if (look != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Use the generated mark'),
                onTap: () => looks.reset(nodeId),
              ),
          ],
        ),
      ),
    );
  }
}

/// A round colour choice, 48 px, with a tick when chosen.
class _HueButton extends StatelessWidget {
  const _HueButton({required this.color, required this.hue, required this.selected, required this.onTap});

  final Color color;
  final int hue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Colour, hue $hue degrees',
    excludeSemantics: true,
    child: InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? GwColors.text : Colors.transparent, width: 3),
        ),
        child: selected ? Icon(Icons.check, color: GwColors.background) : null,
      ),
    ),
  );
}
