import 'package:flutter/material.dart';

import 'theme.dart';

class _Page {
  const _Page(this.icon, this.title, this.body);

  final IconData? icon;
  final String title;
  final String body;
}

const List<_Page> _pages = [
  _Page(
    null,
    'Welcome to GhostWave',
    'GhostWave sends messages over LoRa radio, with no cell service or internet. Each message hops from '
        'node to node. If no path exists yet, nodes carry it until one appears, so delivery can take time.',
  ),
  _Page(
    Icons.lan_outlined,
    'Connect to your node',
    'This app controls one GhostWave node. Enter its address on the next screen. No radio yet? Run the '
        'virtual mesh on a computer on the same Wi-Fi. A node on a network asks for a PIN. Use a Wi-Fi network '
        'you trust: the link is not encrypted.',
  ),
  _Page(
    Icons.qr_code_2,
    'Your QR card',
    'The Me tab shows your contact card. When someone scans it, they get your key, and messages between you '
        'are encrypted end to end. Nodes in radio range also appear in Chats by themselves, marked unverified.',
  ),
  _Page(
    Icons.sos,
    'How SOS works',
    'Press and hold the SOS button for 3 seconds. Your node broadcasts your position and message, and repeats '
        'it until you stop it. Nearby nodes carry it to anyone they meet. An ack means someone received it, '
        'not that help has arrived. GhostWave is experimental: do not rely on it as your only emergency device.',
  ),
];

/// Four short pages on first launch.
class WalkthroughScreen extends StatefulWidget {
  /// Creates the screen; [onDone] runs when it is finished or skipped.
  const WalkthroughScreen({required this.onDone, super.key});

  /// Finished or skipped.
  final VoidCallback onDone;

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  final PageController _pager = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: widget.onDone, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    child: Column(
                      children: [
                        if (p.icon == null)
                          Image.asset('assets/brand/logo.png', width: 120, height: 120, excludeFromSemantics: true)
                        else
                          Icon(
                            p.icon,
                            size: 96,
                            color: p.icon == Icons.sos ? GwColors.errorText : GwColors.spectralCyan,
                          ),
                        const SizedBox(height: 24),
                        Semantics(
                          header: true,
                          child: Text(p.title, style: text.headlineSmall, textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 16),
                        Text(p.body, style: text.bodyLarge, textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Semantics(
              label: 'Page ${_page + 1} of ${_pages.length}',
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      Container(
                        width: i == _page ? 22 : 8,
                        height: 8,
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: i == _page ? GwColors.spectralCyan : GwColors.outline,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? widget.onDone
                      : () => _pager.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
