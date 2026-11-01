import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter/material.dart';

import '../demo_data.dart';
import '../demo_markers.dart';
import '../support/demo_location.dart';
import '../support/stop_card.dart';

/// Use case 1: a normal map from an online provider.
class OnlineMapPage extends StatefulWidget {
  /// The page.
  const OnlineMapPage({super.key});

  /// A MapTiler key, passed with `--dart-define=MAPTILER_KEY=...`.
  static const String mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

  @override
  State<OnlineMapPage> createState() => _OnlineMapPageState();
}

enum _Provider { openFreeMap, osm, mapTiler }

class _OnlineMapPageState extends State<OnlineMapPage> with DemoLocation {
  final GeoMapController _controller = GeoMapController();
  _Provider _provider = _Provider.openFreeMap;
  TownStop? _selected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  GeoMapSource get _source => switch (_provider) {
    // A full vector style, free and without a key.
    _Provider.openFreeMap => const GeoMapSource.styleUrl(
      'https://tiles.openfreemap.org/styles/liberty',
    ),
    // Plain raster tiles, wrapped in a generated style. Fine to browse; the
    // OpenStreetMap tile policy forbids downloading them for offline use.
    _Provider.osm => const GeoMapSource.rasterTiles(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors',
    ),
    _Provider.mapTiler => const GeoMapSource.styleUrl(
      'https://api.maptiler.com/maps/streets-v2/style.json'
      '?key=${OnlineMapPage.mapTilerKey}',
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online map'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<_Provider>(
              segments: [
                const ButtonSegment(
                  value: _Provider.openFreeMap,
                  label: Text('OpenFreeMap'),
                ),
                const ButtonSegment(
                  value: _Provider.osm,
                  label: Text('OSM raster'),
                ),
                if (OnlineMapPage.mapTilerKey.isNotEmpty)
                  const ButtonSegment(
                    value: _Provider.mapTiler,
                    label: Text('MapTiler'),
                  ),
              ],
              selected: {_provider},
              onSelectionChanged: (s) => setState(() => _provider = s.single),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          GeoMap<TownStop>(
            source: _source,
            controller: _controller,
            myLocation: myLocation,
            clustering: const MarkerClustering(),
            markers: [
              for (final stop in strakoniceStops)
                MapMarker(
                  id: '${stop.number}',
                  position: stop.position,
                  icon: numberedPin(stop.number, selected: stop == _selected),
                  zIndex: stop == _selected ? 1 : 0,
                  data: stop,
                ),
            ],
            onMarkerTap: (marker) => setState(() => _selected = marker.data),
            onMapTap: (_) => setState(() => _selected = null),
            unsupportedBuilder: unsupportedMap,
          ),
          if (_selected case final stop?)
            Align(
              alignment: Alignment.bottomCenter,
              child: StopCard(
                title: '${stop.number}. ${stop.name}',
                onClose: () => setState(() => _selected = null),
              ),
            ),
        ],
      ),
      floatingActionButton: _selected == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                locationButton(),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  tooltip: 'Show the whole walk',
                  onPressed: () => _controller.fitPositions([
                    for (final stop in strakoniceStops) stop.position,
                  ]),
                  child: const Icon(Icons.fit_screen),
                ),
              ],
            )
          : null,
    );
  }
}
