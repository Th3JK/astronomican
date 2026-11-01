import 'dart:async';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter/material.dart';

import '../demo_data.dart';
import '../demo_markers.dart';
import '../support/demo_location.dart';
import '../support/demo_scope.dart';
import '../support/stop_card.dart';

/// Use case 2: a normal map from an offline `.mbtiles` pack with its own
/// style.
///
/// The pack is installed through the app's [MapPackManager]: copied out of the
/// bundle on first launch, and from then on only when a higher version ships —
/// or when a newer one is downloaded, which this page picks up by itself.
class OfflinePackPage extends StatefulWidget {
  /// The page.
  const OfflinePackPage({super.key});

  @override
  State<OfflinePackPage> createState() => _OfflinePackPageState();
}

class _OfflinePackPageState extends State<OfflinePackPage> with DemoLocation {
  Future<InstalledPack>? _pack;
  bool _cluster = true;
  PackProgress? _progress;
  StreamSubscription<InstalledPack>? _changes;
  TownStop? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pack != null) return;
    final packs = DemoScope.packsOf(context);
    _install(packs);
    // A download finishing while the map is open swaps the new version in.
    _changes = packs.changes.listen((_) => _install(packs));
  }

  void _install(MapPackManager packs) {
    setState(() {
      _pack = packs.ensureBundled(
        strakonicePack,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline pack'),
        actions: [
          IconButton(
            tooltip: _cluster ? 'Show every stop' : 'Group close stops',
            isSelected: _cluster,
            icon: const Icon(Icons.bubble_chart_outlined),
            selectedIcon: const Icon(Icons.bubble_chart),
            onPressed: () => setState(() => _cluster = !_cluster),
          ),
        ],
      ),
      body: FutureBuilder<InstalledPack>(
        future: _pack,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final pack = snapshot.data;
          if (pack == null) {
            // Only ever seen on the first launch, while the pack is copied.
            return Center(
              child: SizedBox(
                width: 240,
                child: LinearProgressIndicator(value: _progress?.fraction),
              ),
            );
          }
          return Stack(
            children: [
              GeoMap<TownStop>(
                source: GeoMapSource.pack(pack),
                // The tileset stops at the town's edge; keep the camera there.
                cameraBounds: pack.bounds,
                minZoom: 13,
                maxZoom: 19,
                // The credit is drawn by the page instead, below.
                attribution: MapAttribution.hidden,
                myLocation: myLocation,
                clustering: _cluster ? const MarkerClustering() : null,
                markers: [
                  for (final stop in strakoniceStops)
                    MapMarker(
                      id: '${stop.number}',
                      position: stop.position,
                      icon: numberedPin(
                        stop.number,
                        selected: stop == _selected,
                      ),
                      zIndex: stop == _selected ? 1 : 0,
                      // The open stop stays on its own, clustered or not.
                      clusterable: stop != _selected,
                      data: stop,
                    ),
                ],
                onMarkerTap: (marker) =>
                    setState(() => _selected = marker.data),
                onMapTap: (_) => setState(() => _selected = null),
                unsupportedBuilder: unsupportedMap,
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(
                    '${pack.id} v${pack.version} · ${pack.origin.name}',
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 4,
                child: Text(
                  pack.manifest.attribution ?? '',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Positioned(
                right: 16,
                bottom: _selected == null ? 28 : 104,
                child: locationButton(),
              ),
              if (_selected case final stop?)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: StopCard(
                    title: '${stop.number}. ${stop.name}',
                    subtitle:
                        'Drawn from ${pack.file('strakonice.mbtiles').path}',
                    onClose: () => setState(() => _selected = null),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
