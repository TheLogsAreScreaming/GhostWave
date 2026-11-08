import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/preferences.dart';
import '../map/offline_maps.dart';
import 'theme.dart';
import 'widgets.dart';

String _size(int bytes) =>
    bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// The tile source and the regions saved for offline use.
class OfflineMapsScreen extends ConsumerWidget {
  /// Creates the screen.
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(tileSourceProvider);
    final off = ref.watch(offlineMapsProvider);
    final ctl = ref.read(offlineMapsProvider.notifier);
    final job = off.job;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline maps')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Map tiles'),
              subtitle: Text(source.isDefault ? 'OpenStreetMap (online only)' : source.urlTemplate, style: GwText.mono),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => unawaited(_editSource(context, ref, source)),
            ),
          ),
          if (source.isDefault || isForbiddenBulkSource(source.urlTemplate))
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'OpenStreetMap\'s tile servers do not allow downloading areas for offline use, so GhostWave '
                'will not do that with them. Places you have already viewed stay cached for a while. To save '
                'regions, set a tile URL from a provider whose terms allow offline use, or your own tile server.',
              ),
            ),
          if (job != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Downloading ${off.jobName}'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: job.total == 0 ? null : job.done / job.total,
                      semanticsLabel: 'Download progress',
                      semanticsValue: '${job.done} of ${job.total} tiles',
                    ),
                    const SizedBox(height: 4),
                    Text('${job.done} of ${job.total} tiles · ${_size(job.bytes)}. Keep the app open.'),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: ctl.cancel, child: const Text('Cancel')),
                    ),
                  ],
                ),
              ),
            ),
          if (off.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(off.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          Text(
            'Saved regions · ${_size(off.usedBytes)} of ${kMaxOfflineBytes ~/ (1024 * 1024)} MB',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (off.regions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('None yet. Move the Map to an area and tap its download button.'),
            ),
          for (final r in off.regions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.map_outlined),
              title: Text(r.name),
              subtitle: Text(
                '${r.tiles} tiles · ${_size(r.bytes)} · zoom ${r.bounds.minZoom}-${r.bounds.maxZoom}'
                '${r.failed > 0 ? ' · ${r.failed} missing' : ''}'
                '${r.urlTemplate != source.urlTemplate ? ' · from another tile source, not in use' : ''}',
              ),
              trailing: IconButton(
                tooltip: 'Delete ${r.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => unawaited(ctl.delete(r)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editSource(BuildContext context, WidgetRef ref, TileSource s) async {
    final url = TextEditingController(text: s.isDefault ? '' : s.urlTemplate);
    final attr = TextEditingController(text: s.attribution);
    final ctl = ref.read(tileSourceProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Map tiles'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Tile URL',
                  hintText: 'https://host/{z}/{x}/{y}.png',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: attr,
                decoration: const InputDecoration(
                  labelText: 'Attribution shown on the map',
                  hintText: '© the map\'s data and tile providers',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Check that the provider\'s terms allow offline use, and add any API key to the URL.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, 'reset'), child: const Text('Use OpenStreetMap')),
          FilledButton(onPressed: () => Navigator.pop(dialog, 'save'), child: const Text('Save')),
        ],
      ),
    );
    final u = url.text, a = attr.text;
    // not disposed here: the dialog's closing animation still uses it
    if (result == 'reset') ctl.reset();
    if (result == 'save' && !ctl.set(u, a)) {
      messenger.showSnackBar(const SnackBar(content: Text('Not a valid tile URL: it needs {z}, {x} and {y}.')));
    }
  }
}

/// Asks for a name and detail level, then downloads the map area [south]..[east].
Future<void> showDownloadRegionDialog(
  BuildContext context,
  WidgetRef ref, {
  required double south,
  required double west,
  required double north,
  required double east,
  required int zoom,
}) async {
  final name = TextEditingController();
  final minZoom = (zoom - 3).clamp(1, kMaxOfflineZoom);
  var maxZoom = (zoom + 2).clamp(minZoom, kMaxOfflineZoom);
  RegionBounds bounds() =>
      RegionBounds(south: south, west: west, north: north, east: east, minZoom: minZoom, maxZoom: maxZoom);
  final go = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        final b = bounds();
        final why = ref.read(offlineMapsProvider.notifier).refusal(b);
        return AlertDialog(
          title: const Text('Save this area'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Text('Most detail: zoom $maxZoom'),
                Slider(
                  value: maxZoom.toDouble(),
                  min: minZoom.toDouble(),
                  max: kMaxOfflineZoom.toDouble(),
                  divisions: kMaxOfflineZoom - minZoom == 0 ? 1 : kMaxOfflineZoom - minZoom,
                  label: '$maxZoom',
                  semanticFormatterCallback: (v) => 'zoom ${v.round()}',
                  onChanged: minZoom == kMaxOfflineZoom ? null : (v) => setState(() => maxZoom = v.round()),
                ),
                Text('About ${b.tileCount} tiles, around ${_size(b.estimatedBytes)}.'),
                if (why != null) ...[
                  const SizedBox(height: 8),
                  Text(why, style: TextStyle(color: Theme.of(dialog).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: why == null ? () => Navigator.pop(dialog, true) : null,
              child: const Text('Download'),
            ),
          ],
        );
      },
    ),
  );
  final n = name.text.trim();
  // not disposed here: the dialog's closing animation still uses it
  if (go != true || !context.mounted) return;
  showSnack(context, 'Downloading. Follow it under Offline maps.');
  unawaited(ref.read(offlineMapsProvider.notifier).download(n.isEmpty ? 'Region' : n, bounds()));
}
