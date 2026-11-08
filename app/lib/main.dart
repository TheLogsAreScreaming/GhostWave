import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app/background_link.dart';
import 'src/app/location_share.dart';
import 'src/app/mesh_alerts.dart';
import 'src/app/mesh_controller.dart';
import 'src/app/preferences.dart';
import 'src/app/providers.dart';
import 'src/data/mesh_store.dart';
import 'src/map/offline_maps.dart';
import 'src/ui/connect_screen.dart';
import 'src/ui/home_shell.dart';
import 'src/ui/settings_screen.dart';
import 'src/ui/theme.dart';
import 'src/ui/walkthrough_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationSupportDirectory();
  MeshAlerts alerts = const NoMeshAlerts();
  try {
    alerts = await LocalMeshAlerts.create();
  } on Object catch (e) {
    // notifications are a convenience: the app works without them
    debugPrint('notifications unavailable: $e');
  }
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        meshStoreProvider.overrideWithValue(MeshStore(dir)),
        meshAlertsProvider.overrideWithValue(alerts),
        offlineStoreProvider.overrideWithValue(OfflineStore(dir)),
        pinStoreProvider.overrideWithValue(const SecurePinStore()),
        if (Platform.isAndroid) backgroundPlatformProvider.overrideWithValue(AndroidBackgroundPlatform()),
      ],
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
    // inactive (permission dialog, notification shade) still counts as foreground
    ref
        .read(appForegroundProvider.notifier)
        .set(foreground: state == AppLifecycleState.resumed || state == AppLifecycleState.inactive);
    // back in front: the link may have died while the screen was off
    if (state == AppLifecycleState.resumed) {
      ref.read(nodeLinkProvider).checkNow();
      // the user may be back from Android's battery screen
      ref.invalidate(batteryExemptProvider);
    }
    // save chat history before the OS may kill a backgrounded app
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(meshProvider.notifier).flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    // start the mesh controller with the app so no event is missed
    ref.watch(meshProvider.select((_) => 0));
    // and location sharing, which follows the link and the foreground state
    ref.watch(locationShareProvider.select((_) => 0));
    // and the background connection, which follows the link and the user's choice
    ref.watch(backgroundLinkProvider);
    final hasAddress = ref.watch(nodeAddressProvider) != null;
    return MaterialApp(
      title: 'GhostWave',
      debugShowCheckedModeBanner: false,
      theme: buildGhostWaveTheme(),
      themeMode: ThemeMode.dark,
      home: hasAddress
          ? const HomeShell()
          : ref.watch(walkthroughDoneProvider)
          ? const _FirstRun()
          : WalkthroughScreen(onDone: ref.read(walkthroughDoneProvider.notifier).finish),
    );
  }
}

/// First launch: no node yet, so start on Connect.
class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) => const ConnectScreen();
}
