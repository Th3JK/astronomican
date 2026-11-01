import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter/material.dart';

import '../demo_data.dart';
import '../demo_markers.dart';
import '../support/demo_location.dart';
import '../support/demo_scope.dart';
import '../support/stop_card.dart';

/// Use case 6: the offline map with a building on it whose floors can be
/// opened.
///
/// Outdoors the museum is one marker, set apart from the town walk's pins.
/// Tapping it offers both ways in: its floors laid over the streets, with the
/// stops on them carried from their x, y through the floors'
/// georeference — or its floor plans on their own, full screen. Zooming out
/// past the indoor zoom, or leaving, brings the marker back.
class IndoorPage extends StatefulWidget {
  /// The page.
  const IndoorPage({super.key});

  @override
  State<IndoorPage> createState() => _IndoorPageState();
}

class _IndoorPageState extends State<IndoorPage> with DemoLocation {
  final GeoMapController _controller = GeoMapController(
    // From across town a floor plan is noise; the floors show from here in,
    // and the museum's marker stands for them further out.
    indoorMinZoom: 16,
  );
  final MapBuilding _museum = MapBuilding(
    id: 'museum',
    name: rymarovMuseum.name,
    levels: georeferencedMuseumFloors,
  );
  String? _selected;

  List<MapMarker<String>> get _museumStops => [
    for (final (i, stop) in rymarovMuseum.stops.indexed)
      MapMarker(
        id: 'museum-${stop.id}',
        position: stop.position,
        levelId: stop.floor,
        icon: numberedPin(i + 1, selected: 'museum-${stop.id}' == _selected),
        clusterable: 'museum-${stop.id}' != _selected,
        data: stop.name,
      ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openBuilding(MapBuilding building) async {
    final choice = await showModalBottomSheet<_Way>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                building.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text('${building.levels.length} floors'),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Show the floors on the map'),
              subtitle: const Text('Laid over the streets, where they are'),
              onTap: () => Navigator.pop(context, _Way.onMap),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Open the floor plans'),
              subtitle: const Text('Full screen, one floor at a time'),
              onTap: () => Navigator.pop(context, _Way.plans),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Way.onMap:
        await _controller.enterBuilding(building);
      case _Way.plans:
        await showFloorPlans<String>(
          context,
          building: building,
          markers: _museumStops,
          myLocation: myLocation,
          clustering: const MarkerClustering(radius: 40),
          onMarkerTap: (marker) => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(marker.data!))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final packs = DemoScope.packsOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor on the map'),
        actions: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.activeBuilding == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Go outside',
                    icon: const Icon(Icons.park_outlined),
                    onPressed: _controller.leaveBuilding,
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GeoMap<String>(
            source: GeoMapSource.bundledPack(packs, strakonicePack),
            controller: _controller,
            initialCamera: GeoCamera(target: _museum.position!, zoom: 15.6),
            maxZoom: 21,
            myLocation: myLocation,
            clustering: const MarkerClustering(),
            // Floors are read at zoom 18 to 21, where the default of 16
            // would leave the museum's rooms overlapping.
            clusterMaxZoom: 20,
            buildings: [_museum],
            onBuildingTap: _openBuilding,
            markers: [
              ..._museumStops,
              for (final stop in strakoniceStops)
                MapMarker(
                  id: 'town-${stop.number}',
                  position: stop.position,
                  icon: MarkerIcon.pin(
                    color: 'town-${stop.number}' == _selected
                        ? DemoColors.red
                        : const Color(0xFF2E7D32),
                    height: 34,
                  ),
                  data: stop.name,
                ),
            ],
            onMarkerTap: (marker) => setState(() => _selected = marker.id),
            onMapTap: (_) => setState(() => _selected = null),
            unsupportedBuilder: unsupportedMap,
          ),
          // Floors to choose from only while inside.
          Positioned(
            top: 12,
            right: 12,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => _controller.activeBuilding == null
                  ? const SizedBox.shrink()
                  : LevelSelector(
                      controller: _controller,
                      semanticLabel: 'Floor',
                    ),
            ),
          ),
          if (_selected case final id?)
            Align(
              alignment: Alignment.bottomCenter,
              child: StopCard(
                title: _nameOf(id),
                subtitle: id.startsWith('museum')
                    ? 'Indoors, on its floor'
                    : 'Outdoors',
                onClose: () => setState(() => _selected = null),
              ),
            ),
        ],
      ),
      floatingActionButton: _selected == null ? locationButton() : null,
    );
  }

  String _nameOf(String id) {
    for (final stop in rymarovMuseum.stops) {
      if ('museum-${stop.id}' == id) return stop.name;
    }
    for (final stop in strakoniceStops) {
      if ('town-${stop.number}' == id) return stop.name;
    }
    return id;
  }
}

enum _Way { onMap, plans }
