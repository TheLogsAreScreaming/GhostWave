import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/mesh_controller.dart';
import 'contacts_screen.dart';
import 'map_screen.dart';
import 'me_screen.dart';
import 'sos_screen.dart';
import 'status_screen.dart';

/// Bottom-navigation shell with the app's tabs and the SOS alert banner.
class HomeShell extends ConsumerStatefulWidget {
  /// Creates the shell.
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _sosTab = 2;
  static const _statusTab = 4;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final unread = mesh.unread.values.fold(0, (a, b) => a + b);
    final alerts = mesh.activeAlerts.length;
    return Scaffold(
      body: Column(
        children: [
          SosAlertBanner(onView: () => setState(() => _tab = _sosTab)),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: alerts > 0,
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
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.forum_outlined)),
            selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.forum)),
            label: 'Contacts',
          ),
          const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: alerts > 0 || mesh.ownSos.active,
              label: Text(mesh.ownSos.active ? 'ON' : '$alerts'),
              child: const Icon(Icons.sos_outlined),
            ),
            label: 'SOS',
          ),
          const NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'Me',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Status',
          ),
        ],
      ),
    );
  }
}
