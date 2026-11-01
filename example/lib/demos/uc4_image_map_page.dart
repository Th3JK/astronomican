import 'dart:math' as math;

import 'package:astronomican/astronomican.dart';
import 'package:flutter/material.dart';

import '../demo_data.dart';
import '../demo_markers.dart';
import '../support/demo_location.dart';
import '../support/simulated_walk.dart';
import '../support/stop_card.dart';

/// Use case 4: a picture as the whole map, with stops placed by x, y on it.
///
/// The Hedva ground floor from the rymarov app, with its own shield artwork:
/// plain, done once visited, and popped while selected. Tapping the plan away
/// from a stop reports the point tapped — the quickest way to author
/// positions.
class ImageMapPage extends StatefulWidget {
  /// The page.
  const ImageMapPage({super.key});

  @override
  State<ImageMapPage> createState() => _ImageMapPageState();
}

class _ImageMapPageState extends State<ImageMapPage> {
  late final ImageMapController _controller = ImageMapController(
    levels: [hedvaWorks.floors.first],
  );
  final Set<int> _done = {};
  RoomStop? _selected;
  final math.Random _random = math.Random();
  // Where a beacon on each door would say the visitor is.
  late final SimulatedRoomWalk _walk = SimulatedRoomWalk(_stops);
  late final MyLocationController _me = MyLocationController(feed: _walk);

  List<RoomStop> get _stops => [
    for (final stop in hedvaWorks.stops)
      if (stop.floor == '1') stop,
  ];

  @override
  void dispose() {
    _me.dispose();
    _walk.dispose();
    _controller.dispose();
    super.dispose();
  }

  ShieldState _stateOf(RoomStop stop) {
    if (stop == _selected) return ShieldState.selected;
    return _done.contains(stop.id) ? ShieldState.done : ShieldState.plain;
  }

  void _select(RoomStop? stop) {
    setState(() {
      // Leaving a stop marks it visited.
      if (_selected case final previous?) _done.add(previous.id);
      _selected = stop;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image as the map')),
      body: Stack(
        children: [
          ImageMap<RoomStop>(
            controller: _controller,
            myLocation: _me,
            options: const ImageMapOptions(
              maxZoom: 5,
              backgroundColor: Color(0xFFF3EBDD),
            ),
            markers: [
              for (final stop in _stops)
                MapMarker(
                  id: '${stop.id}',
                  position: stop.position,
                  icon: shield(_stateOf(stop)),
                  data: stop,
                  semanticLabel: stop.name,
                  zIndex: stop == _selected ? 1 : 0,
                ),
            ],
            // The icon's picture, with a pop when selected: anything a widget
            // can do, which is the image map's advantage over MapLibre.
            markerBuilder: (context, marker) => AnimatedScale(
              scale: marker.data == _selected ? 1.2 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: MarkerIconView(marker.icon),
            ),
            onMarkerTap: (marker) => _select(marker.data),
            onBackgroundTap: (p) {
              _select(null);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('Tapped x ${p.x.round()}, y ${p.y.round()}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
            },
          ),
          if (_selected case final stop?)
            Align(
              alignment: Alignment.bottomCenter,
              child: StopCard(
                title: stop.name,
                subtitle: 'x ${stop.x.round()}, y ${stop.y.round()}',
                onClose: () => _select(null),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MyLocationButton(
            controller: _me,
            onAccessProblem: (status) => explainLocation(context, status),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'random',
            tooltip: 'Fly to a stop',
            onPressed: () {
              final stop = _stops[_random.nextInt(_stops.length)];
              _select(stop);
              _controller.animateTo(stop.position, zoom: 2.5);
            },
            child: const Icon(Icons.flight_takeoff),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'fit',
            tooltip: 'Whole plan',
            onPressed: _controller.fitLevel,
            child: const Icon(Icons.fit_screen),
          ),
          if (_selected != null) const SizedBox(height: 72),
        ],
      ),
    );
  }
}
