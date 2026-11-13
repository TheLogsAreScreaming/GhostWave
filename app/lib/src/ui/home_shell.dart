import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/trails.dart';
import '../app/home_surfaces.dart';
import '../app/background_link.dart';
import '../app/mesh_alerts.dart';
import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../app/providers.dart';
import '../link/node_link.dart';
import 'background_setup_screen.dart';
import 'contacts_screen.dart';
import 'map_screen.dart';
import 'me_screen.dart';
import 'sos_screen.dart';
import 'status_screen.dart';
import 'trip_screen.dart';
import 'transmit.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bottom-navigation shell with the app's tabs and the SOS alert banner.
class HomeShell extends ConsumerStatefulWidget {
  /// Creates the shell.
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _mapTab = 1;
  static const _sosTab = 2;
  StreamSubscription<int>? _sosTaps;
  StreamSubscription<LaunchAction>? _launches;
  static const _chatsTab = 0;
  static const _statusTab = 4;
  int _tab = 0;
  bool _offeredBackground = false;

  static const _askedNotificationsKey = 'asked_notifications';

  @override
  void initState() {
    super.initState();
    // ask once for notification permission (Android 13+, iOS), after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _askNotificationsOnce());
    _sosTaps = LocalMeshAlerts.sosTaps.listen(_openSos);
    _launches = ref.read(homeSurfacesProvider).actions.listen(_openLaunch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(nodeLinkProvider).state case final LinkNeedsPin s) unawaited(askForPin(context, ref, s));
    });
  }

  @override
  void dispose() {
    unawaited(_sosTaps?.cancel());
    unawaited(_launches?.cancel());
    super.dispose();
  }

  /// An app-icon shortcut or the widget: open the place. Never sends anything;
  /// an SOS still needs the hold.
  void _openLaunch(LaunchAction a) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    switch (a) {
      case LaunchAction.sos:
        setState(() => _tab = _sosTab);
      case LaunchAction.chats:
        setState(() => _tab = _chatsTab);
      case LaunchAction.checkin:
        setState(() => _tab = _sosTab);
        unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TripScreen())));
    }
  }

  /// A tapped SOS notification: the sender on the map, or the SOS tab without a fix.
  void _openSos(int src) {
    if (!mounted) return;
    final mesh = ref.read(meshProvider);
    final pos = mesh.alerts.where((a) => a.src == src).firstOrNull?.pos;
    if (pos == null) {
      setState(() => _tab = _sosTab);
    } else {
      ref.read(mapFocusProvider.notifier).show(pos, 'SOS from ${mesh.nameOf(src)}');
    }
  }

  Future<void> _askNotificationsOnce() async {
    if (!mounted) return;
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.getBool(_askedNotificationsKey) ?? false) return;
    await prefs.setBool(_askedNotificationsKey, true);
    if (!mounted) return;
    try {
      await ref.read(meshAlertsProvider).requestPermission();
    } on Object catch (e) {
      debugPrint('notification permission: $e');
    }
  }

  /// After the first working link, explain the background connection and let the user decide.
  void _offerBackgroundOnce() {
    if (_offeredBackground || !ref.read(backgroundLinkProvider).supported) return;
    if (ref.read(backgroundEnabledProvider) != null) return;
    _offeredBackground = true;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackgroundSetupScreen())));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(widgetSyncProvider); // keeps the home-screen widget current while the app runs
    ref.watch(trailsRecorderProvider); // trip contacts' trails, only while a trip is on
    ref.listen(linkStateProvider, (_, next) {
      if (next.value case final LinkNeedsPin s) unawaited(askForPin(context, ref, s));
      if (next.value is LinkUp) _offerBackgroundOnce();
    });
    ref.listen(mapFocusProvider, (_, f) {
      if (f != null) setState(() => _tab = _mapTab);
    });
    final mesh = ref.watch(meshProvider);
    final unread = mesh.totalUnread;
    final alerts = mesh.activeAlerts.length;
    final sosBadge = alerts > 0 || mesh.ownSos.active;
    final sosLabel = mesh.ownSos.active ? 'ON' : '$alerts';
    Widget unreadBadge(Widget icon) => Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: icon);
    Widget sosIcon(IconData i) => Badge(
      isLabelVisible: sosBadge,
      backgroundColor: GwColors.alert,
      textColor: GwColors.onAlert,
      label: Text(sosLabel),
      child: Icon(i),
    );
    final destinations = <_Dest>[
      _Dest('Chats', unreadBadge(const Icon(Icons.forum_outlined)), unreadBadge(const Icon(Icons.forum))),
      const _Dest('Map', Icon(Icons.map_outlined), Icon(Icons.map)),
      _Dest('SOS', sosIcon(Icons.sos_outlined), sosIcon(Icons.sos)),
      const _Dest('Me', Icon(Icons.qr_code_2_outlined), Icon(Icons.qr_code_2)),
      const _Dest('Status', Icon(Icons.insights_outlined), Icon(Icons.insights)),
    ];
    final size = WindowSizeClass.of(MediaQuery.sizeOf(context).width);
    final tabs = MediaQuery.removePadding(
      context: context,
      // the bars above already cover the status bar
      removeTop: true,
      child: IndexedStack(
        index: _tab,
        children: [
          const ContactsScreen(),
          const MapScreen(),
          const SosScreen(),
          const MeScreen(),
          // built only while selected, so the status poll runs only when visible
          if (_tab == _statusTab) const StatusScreen() else const SizedBox.shrink(),
        ],
      ),
    );
    void select(int i) => setState(() => _tab = i);
    return Scaffold(
      body: Column(
        children: [
          SosAlertBanner(onView: () => setState(() => _tab = _sosTab)),
          ConnectionBar(safeTop: alerts == 0),
          if (mesh.txOff && ref.watch(linkStateProvider).value is LinkUp) const _TxOffBanner(),
          Expanded(
            child: size == WindowSizeClass.compact
                ? tabs
                : Row(
                    children: [
                      SafeArea(
                        top: false,
                        right: false,
                        child: NavigationRail(
                          selectedIndex: _tab,
                          onDestinationSelected: select,
                          extended: size == WindowSizeClass.large,
                          minExtendedWidth: 200,
                          labelType: size == WindowSizeClass.large
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          groupAlignment: -0.9,
                          destinations: [
                            for (final d in destinations)
                              NavigationRailDestination(icon: d.icon, selectedIcon: d.selected, label: Text(d.label)),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: tabs),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: size != WindowSizeClass.compact
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: GwColors.outlineVariant)),
              ),
              child: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: select,
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(icon: d.icon, selectedIcon: d.selected, label: d.label),
                ],
              ),
            ),
    );
  }
}

/// One tab: its label and icons (with any badge).
class _Dest {
  const _Dest(this.label, this.icon, this.selected);

  final String label;
  final Widget icon;
  final Widget selected;
}

/// Says why messages are not going out while the node's transmitter is off,
/// with a button to turn it on where the node allows it (protocol 1.8).
class _TxOffBanner extends ConsumerWidget {
  const _TxOffBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final canSet = ref.read(meshProvider.notifier).nodeCanSetTx;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.portable_wifi_off, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                canSet
                    ? 'Radio transmit is off: your node only listens. Messages wait here until it is on.'
                    : 'Radio transmit is off. Messages wait here until you type tx on on the node\'s serial console.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (canSet)
              TextButton(
                onPressed: () => unawaited(confirmSetTransmit(context, ref, on: true)),
                child: Text(
                  'Turn on',
                  style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
