import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/background_link.dart';
import '../app/mesh_alerts.dart';

/// Explains the background connection before anything is switched on.
class BackgroundSetupScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BackgroundSetupScreen({super.key});

  @override
  ConsumerState<BackgroundSetupScreen> createState() => _BackgroundSetupScreenState();
}

class _BackgroundSetupScreenState extends ConsumerState<BackgroundSetupScreen> {
  bool _busy = false;

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final alerts = ref.read(meshAlertsProvider);
    final platform = ref.read(backgroundPlatformProvider);
    final enabled = ref.read(backgroundEnabledProvider.notifier);
    try {
      await alerts.requestPermission();
      if (!await platform.batteryExempt()) await platform.requestBatteryExemption();
    } on Object catch (e) {
      // still worth turning on: the connection works, Android may just stop it sooner
      debugPrint('background setup: $e');
    }
    enabled.set(enabled: true);
    if (mounted) navigator.pop();
  }

  void _notNow() {
    ref.read(backgroundEnabledProvider.notifier).set(enabled: false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Background connection')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Stay connected when the app is closed?', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Android stops apps in the background, usually within minutes. If it stops GhostWave, you won\'t '
                  'hear about a DM or an SOS until you open the app again.',
                ),
                const SizedBox(height: 16),
                const _Point(
                  icon: Icons.sos_outlined,
                  title: 'SOS alerts and DMs reach you',
                  text: 'GhostWave keeps its link to your node with the screen off or the app swiped away.',
                ),
                const _Point(
                  icon: Icons.notifications_outlined,
                  title: 'A notification stays visible',
                  text: 'It says "GhostWave connected" and has a Disconnect button. Disconnecting ends it.',
                ),
                const _Point(
                  icon: Icons.battery_charging_full_outlined,
                  title: 'It uses more battery',
                  text:
                      'The phone can\'t fully sleep while connected. Next, Android asks whether GhostWave may '
                      'ignore battery optimization. Without that, Android may still stop the connection.',
                ),
                const _Point(
                  icon: Icons.location_off_outlined,
                  title: 'Your location stays foreground only',
                  text: 'Location sharing still pauses when the app is in the background.',
                ),
                const SizedBox(height: 8),
                const Text('You can change this at any time in Settings.'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => unawaited(_turnOn()),
                  child: const Text('Keep me connected'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : _notNow, child: const Text('Not now')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) =>
      ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(title), subtitle: Text(text));
}
