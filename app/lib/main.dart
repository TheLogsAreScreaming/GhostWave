import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app/mesh_controller.dart';
import 'src/app/providers.dart';
import 'src/data/mesh_store.dart';
import 'src/ui/connect_screen.dart';
import 'src/ui/home_shell.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationSupportDirectory();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), meshStoreProvider.overrideWithValue(MeshStore(dir))],
      child: const GhostWaveApp(),
    ),
  );
}

/// The app root.
class GhostWaveApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const GhostWaveApp({super.key});

  @override
  ConsumerState<GhostWaveApp> createState() => _GhostWaveAppState();
}

class _GhostWaveAppState extends ConsumerState<GhostWaveApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // reconnect to the remembered node on launch
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(nodeAddressProvider.notifier).connectSaved());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // save chat history before the OS may kill a backgrounded app
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(meshProvider.notifier).flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    // start the mesh controller with the app so no event is missed
    ref.watch(meshProvider.select((_) => 0));
    final hasAddress = ref.watch(nodeAddressProvider) != null;
    return MaterialApp(
      title: 'GhostWave',
      debugShowCheckedModeBanner: false,
      theme: buildGhostWaveTheme(),
      themeMode: ThemeMode.dark,
      home: hasAddress ? const HomeShell() : const _FirstRun(),
    );
  }
}

/// First launch: no node yet, so start on Connect.
class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) => const ConnectScreen();
}
