import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/mesh_controller.dart';
import '../app/providers.dart';
import '../link/contact_card.dart';
import '../link/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// Longest node name an IDENT carries, in UTF-8 bytes.
const int kMaxNodeNameBytes = 9;

/// App version, read once from the platform.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// Registers the bundled fonts' SIL OFL licenses with the license page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, folder) in const [
      ('Space Grotesk', 'space_grotesk'),
      ('Inter', 'inter'),
      ('JetBrains Mono', 'jetbrains_mono'),
    ]) {
      final text = await rootBundle.loadString('assets/fonts/$folder/OFL.txt');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });
}

/// Node name, app data, about and licenses.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(nodeInfoProvider);
    final pkg = ref.watch(packageInfoProvider).value;
    final version = pkg == null ? '' : '${pkg.version} (build ${pkg.buildNumber})';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Node'),
          if (info == null)
            const ListTile(leading: Icon(Icons.link_off), title: Text('Connect to a node to change its settings.'))
          else ...[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Node name'),
              subtitle: Text(decodeLenient(info.name).isEmpty ? '(none)' : decodeLenient(info.name)),
              trailing: const Icon(Icons.edit_outlined),
              enabled: info.protocolMinor >= 1 && !info.legacy,
              onTap: () => unawaited(_rename(context, ref, decodeLenient(info.name))),
            ),
            if (info.protocolMinor < 1)
              const ListTile(
                dense: true,
                title: Text('This node runs an older ghostwaved: update it to rename from the app.'),
              ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Node firmware'),
              subtitle: Text(
                '${info.firmware} · client protocol ${info.protocolVersion}.${info.protocolMinor}',
                style: GwText.mono,
              ),
            ),
          ],
          const _Header('This phone'),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: const Text('Reset app data'),
            subtitle: const Text('Deletes chats, contacts, channels list and settings on this phone'),
            onTap: () => unawaited(_reset(context, ref)),
          ),
          const _Header('About'),
          ListTile(
            leading: Image.asset('assets/brand/logo.png', width: 32, height: 32, excludeFromSemantics: true),
            title: const Text('GhostWave'),
            subtitle: Text(version.isEmpty ? 'Phone app for the GhostWave mesh' : 'Version $version'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licenses'),
            subtitle: const Text('Open-source software and fonts used by the app'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'GhostWave',
              applicationVersion: version,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset('assets/brand/logo.png', width: 64, height: 64),
              ),
              applicationLegalese: 'MIT License. Fonts: SIL Open Font License 1.1.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, String current) async {
    final ctl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) {
          final t = ctl.text.trim();
          final ok = utf8Length(t) <= kMaxNodeNameBytes && !t.codeUnits.any((c) => c < 0x20 || c == 0x7F);
          return AlertDialog(
            title: const Text('Node name'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctl,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    counterText: '${utf8Length(t)} / $kMaxNodeNameBytes bytes',
                    errorText: ok ? null : 'At most $kMaxNodeNameBytes bytes',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                const Text('Others see it in their contacts after your node announces it (IDENT).'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
              FilledButton(onPressed: ok ? () => Navigator.pop(dialog, t) : null, child: const Text('Save')),
            ],
          );
        },
      ),
    );
    ctl.dispose();
    if (name == null || name == current || !context.mounted) return;
    try {
      await ref.read(meshProvider.notifier).setNodeName(name);
      if (context.mounted) showSnack(context, 'Node renamed to "$name"');
    } on NodeError catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset app data?'),
        content: const Text(
          'Deletes every chat, contact, the saved node address and other settings on this phone. '
          'Your node keeps its own contacts and channels. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GwColors.alert, foregroundColor: GwColors.onAlert),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    ref.read(nodeAddressProvider.notifier).disconnect();
    await ref.read(meshProvider.notifier).resetLocalData();
    await ref.read(sharedPrefsProvider).clear();
    ref
      ..invalidate(nodeAddressProvider)
      ..invalidate(recentNodesProvider);
    // back to the first screen: with no saved address, the app shows Connect
    navigator.popUntil((r) => r.isFirst);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: GwColors.spectralCyan)),
  );
}
