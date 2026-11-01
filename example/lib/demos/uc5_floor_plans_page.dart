import 'package:astronomican/astronomican.dart';
import 'package:flutter/material.dart';

import '../demo_data.dart';
import '../demo_markers.dart';
import '../support/demo_location.dart';
import '../support/simulated_walk.dart';

/// Use case 5: several floor plans, and two buildings.
///
/// Switching floors slides the plans; switching buildings dissolves. Picking a
/// stop from the list goes to its floor first and then flies to it.
class FloorPlansPage extends StatefulWidget {
  /// The page.
  const FloorPlansPage({super.key});

  @override
  State<FloorPlansPage> createState() => _FloorPlansPageState();
}

class _FloorPlansPageState extends State<FloorPlansPage> {
  Building _building = rymarovMuseum;
  late final ImageMapController _controller = ImageMapController(
    levels: _building.floors,
  );
  final GlobalKey<LevelSelectorState> _selector = GlobalKey();
  RoomStop? _selected;
  bool _cluster = true;
  late SimulatedRoomWalk _walk = SimulatedRoomWalk(_building.stops);
  late MyLocationController _me = MyLocationController(feed: _walk);

  @override
  void dispose() {
    _me.dispose();
    _walk.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showBuilding(Building building) {
    final (oldWalk, oldMe) = (_walk, _me);
    setState(() {
      _building = building;
      _selected = null;
      // Each building has its own beacons.
      _walk = SimulatedRoomWalk(building.stops);
      _me = MyLocationController(feed: _walk);
    });
    _controller.replaceLevels(building.floors);
    oldMe.dispose();
    oldWalk.dispose();
  }

  void _showStop(RoomStop stop) {
    setState(() => _selected = stop);
    _controller.animateTo(stop.position, levelId: stop.floor, zoom: 2.2);
  }

  @override
  Widget build(BuildContext context) {
    final stops = _building.stops;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Floor plans'),
        actions: [
          IconButton(
            tooltip: _cluster ? 'Show every stop' : 'Group close stops',
            isSelected: _cluster,
            icon: const Icon(Icons.bubble_chart_outlined),
            selectedIcon: const Icon(Icons.bubble_chart),
            onPressed: () => setState(() => _cluster = !_cluster),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<Building>(
              segments: [
                ButtonSegment(
                  value: rymarovMuseum,
                  label: const Text('Museum'),
                ),
                ButtonSegment(value: hedvaWorks, label: const Text('Hedva')),
              ],
              selected: {_building},
              onSelectionChanged: (s) => _showBuilding(s.single),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ImageMap<RoomStop>(
                  controller: _controller,
                  myLocation: _me,
                  clustering: _cluster
                      ? const MarkerClustering(radius: 40)
                      : null,
                  options: const ImageMapOptions(
                    backgroundColor: Color(0xFFF3EBDD),
                  ),
                  markers: [
                    for (final (i, stop) in stops.indexed)
                      MapMarker(
                        id: '${stop.id}',
                        position: stop.position,
                        levelId: stop.floor,
                        icon: numberedPin(i + 1, selected: stop == _selected),
                        zIndex: stop == _selected ? 1 : 0,
                        clusterable: stop != _selected,
                        data: stop,
                        semanticLabel: stop.name,
                      ),
                  ],
                  onMarkerTap: (marker) =>
                      setState(() => _selected = marker.data),
                  onBackgroundTap: (_) {
                    _selector.currentState?.close();
                    setState(() => _selected = null);
                  },
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: MyLocationButton(
                    controller: _me,
                    onAccessProblem: (status) =>
                        explainLocation(context, status),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: LevelSelector(
                    key: _selector,
                    controller: _controller,
                    semanticLabel: 'Floor',
                    // The rymarov app's navy and gold.
                    theme: const LevelSelectorThemeData(
                      backgroundColor: DemoColors.navy,
                      activeColor: DemoColors.gold,
                      activeLabelColor: DemoColors.navy,
                      labelColor: DemoColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: stops.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final stop = stops[i];
                return ChoiceChip(
                  label: Text('${i + 1}. ${stop.name}'),
                  selected: stop == _selected,
                  onSelected: (_) => _showStop(stop),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
