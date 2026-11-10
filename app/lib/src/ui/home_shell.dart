import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(nodeLinkProvider).state case final LinkNeedsPin s) unawaited(askForPin(context, ref, s));
    });
  }

  @override
  void dispose() {
    unawaited(_sosTaps?.cancel());
    super.dispose();
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
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: select,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(icon: d.icon, selectedIcon: d.selected, label: d.label),
              ],
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

/// Says why messages are not going out while the node's transmitter is off.
class _TxOffBanner extends StatelessWidget {
  const _TxOffBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                'Radio transmit is off. Messages wait here until you type tx on on the node\'s serial console.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
