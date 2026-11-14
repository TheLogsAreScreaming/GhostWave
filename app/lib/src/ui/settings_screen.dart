import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/local_alerts.dart';
import '../app/trip_controller.dart';
import '../app/field_reports_controller.dart';
import '../app/background_link.dart';
import '../app/location_share.dart';
import '../app/backup.dart';
import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/providers.dart';
import '../app/radios.dart';
import '../link/contact_card.dart';
import '../link/session.dart';
import 'background_setup_screen.dart';
import 'backup_screen.dart';
import 'my_radios_screen.dart';
import 'offline_maps_screen.dart';
import 'privacy_screen.dart';
import 'transmit.dart';
import 'theme.dart';
import 'walkthrough_screen.dart';
import 'widgets.dart';

/// Longest node name an IDENT carries, in UTF-8 bytes.
const int kMaxNodeNameBytes = 9;

/// App version, read once from the platform.
/// The commit this build came from, set by CI with --dart-define (empty in local builds).
const String kBuildCommit = String.fromEnvironment('GW_COMMIT');

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
    final version = pkg == null
        ? ''
        : '${pkg.version} (build ${pkg.buildNumber}${kBuildCommit.isEmpty ? '' : ', $kBuildCommit'})';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ReadableWidth(
        child: ListView(
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
              if (info.protocolMinor < 1 || info.legacy)
                ListTile(
                  dense: true,
                  title: Text(
                    info.legacy
                        ? 'Not available on this node: its firmware has no name that other nodes can see.'
                        : 'This node runs an older ghostwaved: update it to rename from the app.',
                  ),
                ),
              if (ref.read(meshProvider.notifier).nodeCanSetTx)
                SwitchListTile(
                  secondary: const Icon(Icons.cell_tower),
                  title: const Text('Transmit'),
                  subtitle: Text(
                    ref.watch(meshProvider.select((m) => m.txOff))
                        ? 'Off: the node only listens'
                        : 'On: the node sends and relays',
                  ),
                  value: !ref.watch(meshProvider.select((m) => m.txOff)),
                  onChanged: (on) => unawaited(confirmSetTransmit(context, ref, on: on)),
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
            const _Header('Alerts'),
            Consumer(
              builder: (context, ref, _) {
                final a = ref.watch(localAlertSettingsProvider);
                final set = ref.read(localAlertSettingsProvider.notifier).set;
                return Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.battery_alert_outlined),
                      title: const Text('Radio battery low'),
                      subtitle: const Text('At 20 % and again at 10 %, if your radio reports its battery'),
                      value: a.battery,
                      onChanged: (v) => set(a.copyWith(battery: v)),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.person_pin_circle_outlined),
                      title: const Text('Trip contact gone quiet'),
                      subtitle: const Text('Your radio has not heard them for 30 minutes, while a trip is on'),
                      value: a.quiet,
                      onChanged: (v) => set(a.copyWith(quiet: v)),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.cell_tower),
                      title: const Text('New node heard'),
                      subtitle: const Text('Each node your radio hears for the first time while connected'),
                      value: a.newNode,
                      onChanged: (v) => set(a.copyWith(newNode: v)),
                    ),
                  ],
                );
              },
            ),
            const _Header('This phone'),
            ListTile(
              leading: const Icon(Icons.settings_input_antenna),
              title: const Text('My radios'),
              subtitle: Text(_radiosSummary(ref.watch(radiosProvider).length, ref.watch(activeRadioProvider))),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyRadiosScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.straighten),
              title: const Text('Distance units'),
              trailing: SegmentedButton<Units>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Units.metric, label: Text('km')),
                  ButtonSegment(value: Units.imperial, label: Text('mi')),
                ],
                selected: {ref.watch(unitsProvider)},
                onSelectionChanged: (s) => ref.read(unitsProvider.notifier).set(s.first),
              ),
            ),
            if (ref.watch(backgroundLinkProvider).supported) const _BackgroundTiles(),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Offline maps'),
              subtitle: const Text('Tile source and saved regions'),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OfflineMapsScreen())),
            ),
            if (ref.watch(backupFilesProvider).supported)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Backup and restore'),
                subtitle: const Text('Encrypted file of your chats, contacts and channels'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackupScreen())),
              ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Show the introduction'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (page) => WalkthroughScreen(onDone: () => Navigator.of(page).pop())),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy & data'),
              subtitle: const Text('What is kept, what is sent, and deleting it'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen())),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
              title: const Text('Reset app data'),
              subtitle: const Text('Deletes chats, contacts, offline maps and settings on this phone'),
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
    // not disposed here: the dialog's closing animation still uses it
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

  Future<void> _reset(BuildContext context, WidgetRef ref) => confirmAndResetAppData(context, ref);
}

/// Asks, then deletes everything GhostWave keeps on this phone: chats,
/// contacts, field tests, the trip, offline maps, PINs and settings. The node
/// keeps its own data. Returns to the first screen.
Future<void> confirmAndResetAppData(BuildContext context, WidgetRef ref) async {
  {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset app data?'),
        content: const Text(
          'Deletes every chat, contact, saved field test, your trip plan, offline maps, saved PINs, the saved '
          'node address and other settings on this phone. Your node keeps its own contacts and channels. '
          'This cannot be undone.',
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
    await ref.read(offlineMapsProvider.notifier).reset();
    ref.read(fieldReportsProvider.notifier).deleteAll();
    await ref.read(fieldReportStoreProvider)?.idle;
    await ref.read(pinStoreProvider).clear();
    await ref.read(sharedPrefsProvider).clear();
    ref
      ..invalidate(tripProvider)
      ..invalidate(fieldReportsProvider)
      ..invalidate(nodeAddressProvider)
      ..invalidate(recentNodesProvider)
      ..invalidate(radiosProvider)
      ..invalidate(unitsProvider)
      ..invalidate(backgroundEnabledProvider)
      ..invalidate(locationShareProvider)
      ..invalidate(tileSourceProvider)
      ..invalidate(walkthroughDoneProvider);
    // back to the first screen: with no saved address, the app shows Connect
    navigator.popUntil((r) => r.isFirst);
  }
}

/// The background connection switch, and a warning if Android may still stop it.
class _BackgroundTiles extends ConsumerWidget {
  const _BackgroundTiles();

  void _openSetup(BuildContext context) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackgroundSetupScreen())));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(backgroundEnabledProvider) ?? false;
    final exempt = ref.watch(batteryExemptProvider).value ?? true;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.sync_alt),
          title: const Text('Stay connected in the background'),
          subtitle: const Text('Keeps the link up with the screen off, so DMs and SOS alerts reach you'),
          value: on,
          onChanged: (v) {
            if (v) {
              _openSetup(context);
            } else {
              ref.read(backgroundEnabledProvider.notifier).set(enabled: false);
            }
          },
        ),
        if (on && !exempt)
          ListTile(
            leading: Icon(Icons.battery_alert_outlined, color: Theme.of(context).colorScheme.error),
            title: const Text('Android may still stop the connection'),
            subtitle: const Text('Battery optimization is on for GhostWave. Tap to review.'),
            onTap: () => _openSetup(context),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: GwSpace.md),
    child: SectionLabel(text),
  );
}

/// "2 radios · using Trail base", for the My radios entry.
String _radiosSummary(int count, SavedRadio? active) {
  final saved = switch (count) {
    0 => 'No radios saved yet',
    1 => '1 radio',
    _ => '$count radios',
  };
  return active == null ? saved : '$saved · using ${active.displayName}';
}
