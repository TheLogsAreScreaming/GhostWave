import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../app/coverage.dart';
import '../app/mesh_controller.dart';
import '../app/preferences.dart';
import '../link/geo.dart';
import '../map/offline_maps.dart';
import '../data/coverage_sample.dart';
import 'coverage_screen.dart' show coverageLook;
import 'format.dart';
import 'offline_maps_screen.dart';
import 'tile_provider.dart';
import 'widgets.dart';
import 'theme.dart';

/// Own position, contacts, nodes heard nearby and SOS alerts on an
/// base map: OpenStreetMap online, or saved regions from a configured source.
class MapScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

enum _Kind { me, contact, nearby, sos }

class _Pin {
  const _Pin(this.kind, this.pos, this.title, this.detail);

  final _Kind kind;
  final LatLon pos;
  final String title;
  final String detail;
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _map = MapController();
  bool _fitted = false;
  bool _showTrails = true;
  bool _showCoverage = true;

  /// Colour-blind-safe line colours (Okabe-Ito), one per trip contact.
  static const _trailColors = [
    Color(0xFFE69F00),
    Color(0xFF56B4E9),
    Color(0xFF009E73),
    Color(0xFFF0E442),
    Color(0xFFD55E00),
    Color(0xFFCC79A7),
  ];
  MapFocus? _focus;
  OfflineFirstTileProvider? _tiles;
  Object? _tilesKey;

  OfflineFirstTileProvider _tileProvider(OfflineStore? store, String url, List<OfflineRegion> regions) {
    final usable = [
      for (final r in regions)
        if (r.urlTemplate == url) r,
    ];
    final key = Object.hashAll([url, for (final r in usable) r.id]);
    if (_tiles == null || key != _tilesKey) {
      _tilesKey = key;
      _tiles = OfflineFirstTileProvider(store: store, regions: usable);
    }
    return _tiles!;
  }

  void _showFocus(MapFocus f) {
    _focus = f;
    _fitted = true; // do not jump away from it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.move(ll.LatLng(f.pos.lat, f.pos.lon), 15);
    });
  }

  Future<void> _saveArea() async {
    final b = _map.camera.visibleBounds;
    await showDownloadRegionDialog(
      context,
      ref,
      south: b.south,
      west: b.west,
      north: b.north,
      east: b.east,
      zoom: _map.camera.zoom.floor(),
    );
  }

  List<_Pin> _pins(MeshState m) {
    final pins = <_Pin>[];
    if (m.ownPos case final p?) pins.add(_Pin(_Kind.me, p, 'My node', p.toString()));
    final ids = <int>{};
    for (final c in m.contacts.values) {
      final p = c.pos ?? m.neighbors[c.nodeId]?.pos;
      if (p == null) continue;
      ids.add(c.nodeId);
      final seen = c.lastSeen ?? m.neighbors[c.nodeId]?.lastSeen;
      pins.add(_Pin(_Kind.contact, p, m.nameOf(c.nodeId), seen == null ? p.toString() : 'seen ${timeAgo(seen)}'));
    }
    for (final n in m.neighbors.values) {
      if (n.pos == null || ids.contains(n.nodeId)) continue;
      pins.add(_Pin(_Kind.nearby, n.pos!, m.nameOf(n.nodeId), 'heard ${timeAgo(n.lastSeen)}'));
    }
    for (final a in m.alerts) {
      if (a.pos == null) continue;
      pins.add(
        _Pin(
          _Kind.sos,
          a.pos!,
          'SOS ${m.nameOf(a.src)}',
          [
            if (a.text.isNotEmpty) a.text,
            timeAgo(a.receivedAt),
            if (a.accuracyM != null) '±${a.accuracyM} m',
          ].join(' · '),
        ),
      );
    }
    return pins;
  }

  void _fit(List<_Pin> pins) {
    if (pins.isEmpty) return;
    final pts = [for (final p in pins) ll.LatLng(p.pos.lat, p.pos.lon)];
    if (pts.length == 1) {
      _map.move(pts.first, 14);
    } else {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48), maxZoom: 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final pins = _pins(mesh);
    final units = ref.watch(unitsProvider);
    final source = ref.watch(tileSourceProvider);
    final off = ref.watch(offlineMapsProvider);
    ref.listen(mapFocusProvider, (_, f) {
      if (f != null) setState(() => _showFocus(f));
    });
    final focus = _focus;
    final own = mesh.ownPos;
    final covState = ref.watch(coverageProvider);
    final walk = covState.running ?? covState.walks.firstOrNull;
    final covNow = DateTime.now().toUtc();
    final coverage = walk == null
        ? const <CoverageSample>[]
        : [for (final p in walk.pings) sampleOf(walk, p, mesh.messages, covNow)];
    final trails = [
      for (final (i, e) in mesh.trails.entries.where((e) => e.value.length > 1).indexed)
        (
          id: e.key,
          name: e.key == mesh.nodeId ? 'You' : mesh.nameOf(e.key),
          color: e.key == mesh.nodeId ? GwColors.mapMe : _trailColors[i % _trailColors.length],
          points: [for (final p in e.value) ll.LatLng(p.latitude, p.longitude)],
        ),
    ];
    if (!_fitted && pins.isNotEmpty) {
      _fitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit(pins);
      });
    }
    Color colorOf(_Kind k) => switch (k) {
      _Kind.me => GwColors.mapMe,
      _Kind.contact => GwColors.mapContact,
      _Kind.nearby => GwColors.mapNearby,
      _Kind.sos => GwColors.alert,
    };
    IconData iconOf(_Kind k) => switch (k) {
      _Kind.me => Icons.my_location,
      _Kind.contact => Icons.person_pin_circle,
      _Kind.nearby => Icons.cell_tower,
      _Kind.sos => Icons.sos,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            tooltip: 'Save this area for offline use',
            onPressed: isForbiddenBulkSource(source.urlTemplate)
                ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OfflineMapsScreen()))
                : _saveArea,
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
          if (trails.isNotEmpty)
            IconButton(
              tooltip: _showTrails ? 'Hide trails' : 'Show trails',
              isSelected: _showTrails,
              onPressed: () => setState(() => _showTrails = !_showTrails),
              icon: const Icon(Icons.route_outlined),
              selectedIcon: const Icon(Icons.route),
            ),
          if (coverage.isNotEmpty)
            IconButton(
              tooltip: _showCoverage ? 'Hide coverage' : 'Show coverage',
              isSelected: _showCoverage,
              onPressed: () => setState(() => _showCoverage = !_showCoverage),
              icon: const Icon(Icons.radar_outlined),
              selectedIcon: const Icon(Icons.radar),
            ),
          IconButton(tooltip: 'Show all', onPressed: () => _fit(pins), icon: const Icon(Icons.fit_screen)),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(initialCenter: ll.LatLng(46.87, -113.99), initialZoom: 11),
            children: [
              TileLayer(
                urlTemplate: source.urlTemplate,
                userAgentPackageName: 'org.ghostwave.ghostwave_app',
                tileProvider: _tileProvider(ref.read(offlineStoreProvider), source.urlTemplate, off.regions),
                maxZoom: 19,
              ),
              if (_showTrails && trails.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final t in trails)
                      Polyline(
                        points: t.points,
                        color: t.color,
                        strokeWidth: 4,
                        borderColor: Colors.black54,
                        borderStrokeWidth: 1,
                      ),
                  ],
                ),
              if (_showCoverage && coverage.isNotEmpty)
                CircleLayer(
                  circles: [
                    for (final s in coverage)
                      CircleMarker(
                        point: ll.LatLng(s.latitude, s.longitude),
                        radius: 7,
                        color: coverageLook(s).$2,
                        borderColor: Colors.black87,
                        borderStrokeWidth: 1,
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final p in pins)
                    Marker(
                      point: ll.LatLng(p.pos.lat, p.pos.lon),
                      width: 44,
                      height: 44,
                      child: Semantics(
                        button: true,
                        label: '${p.title}. ${p.detail}',
                        child: GestureDetector(
                          onTap: () => showSnack(context, '${p.title}: ${p.detail}'),
                          child: ExcludeSemantics(
                            child: Icon(iconOf(p.kind), color: colorOf(p.kind), size: p.kind == _Kind.sos ? 44 : 36),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // always visible: the OSM policy does not allow it behind a toggle
              SimpleAttributionWidget(source: Text(source.attributionText)),
            ],
          ),
          if (_showTrails && trails.isNotEmpty)
            Positioned(
              left: 12,
              bottom: 28,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trails, last 24 h', style: Theme.of(context).textTheme.labelSmall),
                      for (final t in trails)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 16, height: 4, color: t.color),
                            const SizedBox(width: 6),
                            Text(t.name, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showCoverage && coverage.isNotEmpty)
            Positioned(
              right: 12,
              bottom: 28,
              child: Semantics(
                container: true,
                label: 'Coverage legend',
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Coverage: ${coverage.length} pings', style: Theme.of(context).textTheme.labelSmall),
                        for (final (label, color) in const [
                          ('strong', Color(0xFF009E73)),
                          ('fair', Color(0xFFF0E442)),
                          ('weak', Color(0xFFE69F00)),
                          ('no reading', Color(0xFF56B4E9)),
                          ('failed', Color(0xFFD55E00)),
                          ('waiting', Color(0xFF9AA5B8)),
                        ])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 10, color: color),
                              const SizedBox(width: 6),
                              Text(label, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (pins.isEmpty && focus == null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No positions yet. Your node\'s fix and its neighbors\' beacons appear here.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          if (focus != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.location_searching),
                  title: Text(focus.title),
                  subtitle: Text(
                    own == null
                        ? 'Your position is not known yet, so no distance.'
                        : '${formatDistance(own.distanceTo(focus.pos), units)} '
                              '${compassPoint(own.bearingTo(focus.pos))} of you '
                              '(bearing ${own.bearingTo(focus.pos).round()}°)',
                  ),
                  trailing: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _focus = null),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final k in _Kind.values)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(iconOf(k), color: colorOf(k), size: 16),
                          const SizedBox(width: 4),
                          Text(switch (k) {
                            _Kind.me => 'My node',
                            _Kind.contact => 'Contact',
                            _Kind.nearby => 'Nearby',
                            _Kind.sos => 'SOS',
                          }, style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
