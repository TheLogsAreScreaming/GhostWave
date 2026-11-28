import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../app/coverage.dart';
import '../app/mesh_controller.dart';
import '../app/node_hygiene.dart';
import '../app/preferences.dart';
import '../app/traffic.dart';
import '../link/contact_card.dart' show nodeIdHex;
import '../link/geo.dart';
import '../map/offline_maps.dart';
import '../data/coverage_sample.dart';
import '../data/traffic.dart';
import 'coverage_screen.dart' show coverageLook;
import 'format.dart';
import 'node_details_screen.dart';
import 'offline_maps_screen.dart';
import 'range_rings_layer.dart';
import 'tile_provider.dart';
import 'traffic_map.dart';
import 'waypoint_screens.dart';
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
  const _Pin(this.kind, this.pos, this.title, this.detail, {this.nodeId, this.seen, this.stale = false});

  final _Kind kind;
  final LatLon pos;
  final String title;
  final String detail;

  /// The node it stands for; tapping opens its details. Null for an SOS spot.
  final int? nodeId;

  /// When it was last heard, if known.
  final DateTime? seen;

  /// Not heard for longer than the stale setting: drawn faded.
  final bool stale;
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _map = MapController();
  final _stackKey = GlobalKey();
  final _toolbarKey = GlobalKey();
  final _cardKey = GlobalKey();
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
  StreamSubscription<MapEvent>? _mapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapSub = _map.mapEventStream.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _mapSub?.cancel();
    super.dispose();
  }

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

  List<_Pin> _pins(MeshState m, {Set<int> ignored = const {}, Duration staleAfter = Duration.zero, DateTime? now}) {
    final pins = <_Pin>[];
    final at = now ?? DateTime.now();
    if (m.ownPos case final p?) pins.add(_Pin(_Kind.me, p, 'My node', p.toString(), nodeId: m.nodeId));
    final ids = <int>{};
    for (final c in m.contacts.values) {
      if (ignored.contains(c.nodeId)) continue;
      final p = c.pos ?? m.neighbors[c.nodeId]?.pos;
      if (p == null) continue;
      ids.add(c.nodeId);
      final seen = c.lastSeen ?? m.neighbors[c.nodeId]?.lastSeen;
      final stale = isStale(seen, at, staleAfter);
      pins.add(
        _Pin(
          _Kind.contact,
          p,
          m.nameOf(c.nodeId),
          seen == null ? p.toString() : 'seen ${timeAgo(seen)}${stale ? ' · stale' : ''}',
          nodeId: c.nodeId,
          seen: seen,
          stale: stale,
        ),
      );
    }
    for (final n in m.neighbors.values) {
      if (n.pos == null || ids.contains(n.nodeId) || ignored.contains(n.nodeId)) continue;
      final stale = isStale(n.lastSeen, at, staleAfter);
      pins.add(
        _Pin(
          _Kind.nearby,
          n.pos!,
          m.nameOf(n.nodeId),
          'heard ${timeAgo(n.lastSeen)}${stale ? ' · stale' : ''}',
          nodeId: n.nodeId,
          seen: n.lastSeen,
          stale: stale,
        ),
      );
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
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: _fitPadding(), maxZoom: 15));
    }
  }

  /// Room around the fitted pins, kept clear of the toolbar and the traffic
  /// card that float over the map.
  EdgeInsets _fitPadding() {
    Rect? rectOf(GlobalKey k) {
      final box = k.currentContext?.findRenderObject();
      final stack = _stackKey.currentContext?.findRenderObject();
      if (box is! RenderBox || stack is! RenderBox || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
    }

    final stack = _stackKey.currentContext?.size;
    if (stack == null) return const EdgeInsets.all(kMapFitMargin);
    return mapFitPadding(Offset.zero & stack, overlays: [?rectOf(_toolbarKey), ?rectOf(_cardKey)]);
  }

  void _locate(MeshState m) {
    final p = m.ownPos;
    if (p == null) {
      showSnack(context, 'Your position is not known yet.');
      return;
    }
    _map.move(ll.LatLng(p.lat, p.lon), math.max(_map.camera.zoom, 14));
  }

  Future<void> _filter() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final kinds = ref.watch(trafficProvider.select((s) => s.kinds));
        return ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg),
              child: Text('Packet types to show', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final k in TrafficKind.values)
              CheckboxListTile(
                value: kinds.contains(k),
                onChanged: (v) => ref.read(trafficProvider.notifier).setKind(k, v ?? false),
                secondary: Icon(Icons.circle, size: 14, color: trafficColor(k)),
                title: Text(k.label),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _search(List<_Pin> pins) async {
    final nodes = [
      for (final p in pins)
        if (p.nodeId != null) p,
    ];
    final picked = await showModalBottomSheet<_Pin>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _NodeSearchSheet(pins: nodes),
    );
    if (picked != null && mounted) _map.move(ll.LatLng(picked.pos.lat, picked.pos.lon), math.max(_map.camera.zoom, 14));
  }

  /// Collapses nearby pins into cluster groups based on pixel distance.
  List<({List<_Pin> members, LatLon center})> _clusterPins(List<_Pin> pins) {
    if (pins.isEmpty) return const [];
    MapCamera camera;
    try {
      camera = _map.camera;
    } on Object {
      return [
        for (final p in pins) (members: [p], center: p.pos),
      ];
    }
    const threshold = 40.0; // pixels
    final used = List.filled(pins.length, false);
    final clusters = <({List<_Pin> members, LatLon center})>[];
    for (var i = 0; i < pins.length; i++) {
      if (used[i]) continue;
      final pi = camera.latLngToScreenOffset(ll.LatLng(pins[i].pos.lat, pins[i].pos.lon));
      final group = [pins[i]];
      used[i] = true;
      for (var j = i + 1; j < pins.length; j++) {
        if (used[j]) continue;
        final pj = camera.latLngToScreenOffset(ll.LatLng(pins[j].pos.lat, pins[j].pos.lon));
        final dx = pi.dx - pj.dx, dy = pi.dy - pj.dy;
        if (dx * dx + dy * dy <= threshold * threshold) {
          group.add(pins[j]);
          used[j] = true;
        }
      }
      final lat = group.map((p) => p.pos.lat).reduce((a, b) => a + b) / group.length;
      final lon = group.map((p) => p.pos.lon).reduce((a, b) => a + b) / group.length;
      clusters.add((members: group, center: LatLon(lat, lon)));
    }
    return clusters;
  }

  _Kind _dominantKind(List<_Pin> pins) {
    if (pins.any((p) => p.kind == _Kind.sos)) return _Kind.sos;
    if (pins.any((p) => p.kind == _Kind.me)) return _Kind.me;
    if (pins.any((p) => p.kind == _Kind.contact)) return _Kind.contact;
    return _Kind.nearby;
  }

  void _tapCluster(List<_Pin> members) {
    // If all pins are physically close (< 100 m) or we're very zoomed in, list them.
    var maxDist = 0.0;
    for (var i = 0; i < members.length; i++) {
      for (var j = i + 1; j < members.length; j++) {
        final d = members[i].pos.distanceTo(members[j].pos);
        if (d > maxDist) maxDist = d;
      }
    }
    if (maxDist < 100 || _map.camera.zoom >= 17) {
      unawaited(
        showModalBottomSheet<_Pin>(
          context: context,
          showDragHandle: true,
          builder: (_) => _ClusterSheet(pins: members),
        ).then((p) {
          if (!mounted || p == null) return;
          if (p.nodeId != null) {
            unawaited(openNodeDetails(context, p.nodeId!));
          } else {
            showSnack(context, '${p.title}: ${p.detail}');
          }
        }),
      );
      return;
    }
    final pts = [for (final p in members) ll.LatLng(p.pos.lat, p.pos.lon)];
    _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(80), maxZoom: 18));
  }

  Future<void> _options() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final t = ref.watch(trafficProvider);
        final ctl = ref.read(trafficProvider.notifier);
        return ListView(
          shrinkWrap: true,
          children: [
            SwitchListTile(
              value: t.on,
              onChanged: ctl.setOn,
              title: const Text('Show traffic'),
              subtitle: const Text('Packets your node hears travel across the map.'),
            ),
            SwitchListTile(
              value: t.hopLabels,
              onChanged: t.on ? ctl.setHopLabels : null,
              title: const Text('Hop names'),
              subtitle: const Text('Name each hop while a route is on screen.'),
            ),
            ListTile(
              enabled: t.recent.isNotEmpty,
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Clear heard traffic'),
              onTap: ctl.clear,
            ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final traffic = ref.watch(trafficProvider);
    final trafficOn = traffic.on;
    final darkTiles = trafficOn && Theme.of(context).brightness == Brightness.dark;
    final now = ref.read(clockProvider);
    String nameOf(int id) => id == mesh.nodeId ? 'You' : mesh.nameOf(id);
    LatLon? posOf(int id) => id == mesh.nodeId
        ? mesh.ownPos
        : mesh.contacts[id]?.pos ?? mesh.neighbors[id]?.pos ?? mesh.journal.entries[id]?.lastPos;
    final pins = _pins(
      mesh,
      ignored: ref.watch(ignoredNodesProvider),
      staleAfter: ref.watch(staleAfterProvider),
      now: now(),
    );
    final clusters = _clusterPins(pins);
    final rings = ref.watch(rangeRingsProvider);
    final waypoints = [
      for (final w in mesh.waypoints.all.reversed)
        if (!w.hidden) w,
    ];
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
          IconButton(
            tooltip: rings ? 'Hide range rings' : 'Show range rings',
            isSelected: rings,
            onPressed: () {
              ref.read(rangeRingsProvider.notifier).set(!rings);
              if (!rings && mesh.ownPos == null) showSnack(context, 'Rings appear once your position is known.');
            },
            icon: const Icon(Icons.track_changes_outlined),
            selectedIcon: const Icon(Icons.track_changes),
          ),
          IconButton(
            tooltip: 'Waypoints',
            onPressed: () {
              final c = _map.camera.center;
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => WaypointsScreen(center: LatLon(c.latitude, c.longitude))),
                ),
              );
            },
            icon: const Icon(Icons.push_pin_outlined),
          ),
        ],
      ),
      body: Stack(
        key: _stackKey,
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: const ll.LatLng(46.87, -113.99),
              initialZoom: 11,
              // long-press drops a waypoint (the Waypoints list has a button too)
              onLongPress: (_, p) => unawaited(openNewWaypoint(context, pos: LatLon(p.latitude, p.longitude))),
            ),
            children: [
              ColorFiltered(
                // the traffic view on a dark theme darkens the tiles; otherwise
                // an identity filter keeps the tile layer's state across toggles
                colorFilter: darkTiles ? kDarkTiles : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: TileLayer(
                  urlTemplate: source.urlTemplate,
                  userAgentPackageName: 'org.ghostwave.ghostwave_app',
                  tileProvider: _tileProvider(ref.read(offlineStoreProvider), source.urlTemplate, off.regions),
                  maxZoom: 19,
                ),
              ),
              if (rings && own != null) RangeRingsLayer(centre: own, units: units, clear: _fitPadding()),
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
              if (waypoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final w in waypoints)
                      Marker(
                        point: ll.LatLng(w.pos.lat, w.pos.lon),
                        width: 44,
                        height: 44,
                        child: WaypointMarker(waypoint: w),
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final c in clusters)
                    if (c.members.length == 1)
                      Marker(
                        point: ll.LatLng(c.members.first.pos.lat, c.members.first.pos.lon),
                        width: 44,
                        height: 44,
                        child: Semantics(
                          button: true,
                          label: '${c.members.first.title}. ${c.members.first.detail}',
                          hint: c.members.first.nodeId == null ? null : 'Opens node details',
                          child: GestureDetector(
                            onTap: () => c.members.first.nodeId == null
                                ? showSnack(context, '${c.members.first.title}: ${c.members.first.detail}')
                                : unawaited(openNodeDetails(context, c.members.first.nodeId!)),
                            child: ExcludeSemantics(
                              child:
                                  trafficOn &&
                                      (c.members.first.kind == _Kind.nearby || c.members.first.kind == _Kind.contact)
                                  ? Center(
                                      child: TrafficNodePin(
                                        color: colorOf(c.members.first.kind),
                                        heardRecently: heardRecently(c.members.first.seen, now()),
                                        icon: c.members.first.kind == _Kind.contact ? Icons.person : Icons.cell_tower,
                                      ),
                                    )
                                  : Opacity(
                                      opacity: c.members.first.stale ? 0.45 : 1,
                                      child: Icon(
                                        iconOf(c.members.first.kind),
                                        color: colorOf(c.members.first.kind),
                                        size: c.members.first.kind == _Kind.sos ? 44 : 36,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      )
                    else
                      Marker(
                        point: ll.LatLng(c.center.lat, c.center.lon),
                        width: 48,
                        height: 48,
                        child: Semantics(
                          button: true,
                          label: '${c.members.length} nodes clustered. Tap to expand',
                          child: GestureDetector(
                            onTap: () => _tapCluster(c.members),
                            child: ExcludeSemantics(
                              child: _ClusterMarker(count: c.members.length, color: colorOf(_dominantKind(c.members))),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
              if (trafficOn) TrafficRoutesLayer(posOf: posOf, nameOf: nameOf),
              // always visible: the OSM policy does not allow it behind a toggle
              SimpleAttributionWidget(source: Text(source.attributionText)),
            ],
          ),
          if (_showTrails && trails.isNotEmpty && !trafficOn)
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
          if (_showCoverage && coverage.isNotEmpty && !trafficOn)
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
          if (pins.isEmpty && waypoints.isEmpty && focus == null)
            Positioned(
              top: 12,
              left: 12,
              right: 88, // clear of the toolbar
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No positions yet. Your node\'s fix and its neighbors\' beacons appear here. '
                    'Long-press the map to drop a waypoint.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          if (focus != null)
            Positioned(
              top: 12,
              left: 12,
              right: 88, // clear of the toolbar
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
          if (trafficOn)
            Positioned(
              left: 12,
              right: 12,
              bottom: 28, // above the attribution
              child: SafeArea(
                top: false,
                child: TrafficRouteCard(key: _cardKey, posOf: posOf, nameOf: nameOf, now: now),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: MapToolbar(
              key: _toolbarKey,
              children: [
                MapToolButton(
                  icon: Icons.near_me_outlined,
                  label: 'Locate',
                  tooltip: 'Go to my position',
                  onPressed: () => _locate(mesh),
                ),
                MapToolButton(
                  icon: Icons.filter_list,
                  label: 'Filter',
                  tooltip: 'Packet types to show',
                  onPressed: () => unawaited(_filter()),
                ),
                MapToolButton(
                  icon: Icons.route,
                  label: 'Traffic',
                  tooltip: trafficOn ? 'Hide live traffic' : 'Show live traffic',
                  selected: trafficOn,
                  onPressed: () => ref.read(trafficProvider.notifier).setOn(!trafficOn),
                ),
                MapToolButton(
                  icon: Icons.search,
                  label: 'Search',
                  tooltip: 'Find a node on the map',
                  onPressed: () => unawaited(_search(pins)),
                ),
                MapToolButton(
                  icon: Icons.open_in_full,
                  label: 'Fit all',
                  tooltip: 'Show all',
                  onPressed: () => _fit(pins),
                ),
                MapToolButton(
                  icon: Icons.more_horiz,
                  label: 'Options',
                  tooltip: 'Map options',
                  onPressed: () => unawaited(_options()),
                ),
              ],
            ),
          ),
          if (!trafficOn)
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

/// A circular badge showing how many nodes have collapsed into one cluster.
class _ClusterMarker extends StatelessWidget {
  const _ClusterMarker({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2.5),
        boxShadow: const [BoxShadow(blurRadius: 4, offset: Offset(0, 1), color: Colors.black38)],
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1),
        ),
      ),
    );
  }
}

/// Lists the individual nodes inside a cluster so the user can pick one.
class _ClusterSheet extends StatelessWidget {
  const _ClusterSheet({required this.pins});

  final List<_Pin> pins;

  @override
  Widget build(BuildContext context) {
    IconData iconOf(_Kind k) => switch (k) {
      _Kind.me => Icons.my_location,
      _Kind.contact => Icons.person_pin_circle,
      _Kind.nearby => Icons.cell_tower,
      _Kind.sos => Icons.sos,
    };
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(GwSpace.lg, 0, GwSpace.lg, GwSpace.sm),
          child: Text('${pins.length} nodes here', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final p in pins)
          ListTile(
            leading: Icon(iconOf(p.kind), size: 20),
            title: Text(p.title),
            subtitle: Text(p.detail),
            onTap: () => Navigator.pop(context, p),
          ),
        SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + GwSpace.sm),
      ],
    );
  }
}

/// Finds a node that has a position, by name or ID.
class _NodeSearchSheet extends StatefulWidget {
  const _NodeSearchSheet({required this.pins});

  final List<_Pin> pins;

  @override
  State<_NodeSearchSheet> createState() => _NodeSearchSheetState();
}

class _NodeSearchSheetState extends State<_NodeSearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final hits = [
      for (final p in widget.pins)
        if (q.isEmpty || p.title.toLowerCase().contains(q) || nodeIdHex(p.nodeId!).toLowerCase().contains(q)) p,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GwSpace.lg),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Node name or ID'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Flexible(
              child: hits.isEmpty
                  ? const Padding(padding: EdgeInsets.all(GwSpace.lg), child: Text('No node on the map matches.'))
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in hits)
                          ListTile(
                            title: Text(p.title),
                            subtitle: Text(p.detail),
                            onTap: () => Navigator.pop(context, p),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
