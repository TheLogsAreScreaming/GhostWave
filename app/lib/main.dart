import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app/providers.dart';
import 'src/ui/connect_screen.dart';
import 'src/ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: const GhostWaveApp()));
}

/// The app root.
class GhostWaveApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const GhostWaveApp({super.key});

  @override
  ConsumerState<GhostWaveApp> createState() => _GhostWaveAppState();
}

class _GhostWaveAppState extends ConsumerState<GhostWaveApp> {
  @override
  void initState() {
    super.initState();
    // reconnect to the remembered node on launch
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(nodeAddressProvider.notifier).connectSaved());
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = ref.watch(nodeAddressProvider) != null;
    return MaterialApp(
      title: 'GhostWave',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: hasAddress ? const HomeShell() : const _FirstRun(),
    );
  }

  static ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6B5E), brightness: b),
    useMaterial3: true,
  );
}

/// First launch: no node yet, so start on Connect.
class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) => const ConnectScreen();
}
