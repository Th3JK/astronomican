import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter/material.dart';

import '../demo_data.dart';
import '../demo_markers.dart';
import '../support/demo_location.dart';
import '../support/demo_scope.dart';
import '../support/stop_card.dart';

/// Use case 3: a normal map with a picture pinned over it.
///
/// Here the picture is a floor plan stretched over the town square — the
/// point is the mechanism: any drawing given where its edges fall, or three
/// points on it and where they are, lands in place, and the stops stay on
/// their streets on top of it.
class OverlayPage extends StatefulWidget {
  /// The page.
  const OverlayPage({super.key});

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> with DemoLocation {
  static const Size _pictureSize = Size(2851, 2048);
  static final ImageGeoreference _reference = ImageGeoreference.fromBounds(
    north: 49.2627,
    south: 49.2597,
    west: 13.9002,
    east: 13.9062,
    imageSize: _pictureSize,
  );

  bool _streets = true;
  bool _corners = false;
  double _opacity = 0.8;
  TownStop? _selected;

  @override
  Widget build(BuildContext context) {
    final packs = DemoScope.packsOf(context);
    final quad = _reference.quad(_pictureSize);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image overlay'),
        actions: [
          IconButton(
            tooltip: 'Show the corners',
            isSelected: _corners,
            icon: const Icon(Icons.crop_free),
            onPressed: () => setState(() => _corners = !_corners),
          ),
        ],
      ),
      body: Stack(
        children: [
          GeoMap<TownStop>(
            source: _streets
                ? GeoMapSource.bundledPack(packs, strakonicePack)
                // Just the picture: the historic-map mode strakonice planned.
                : const GeoMapSource.blank(),
            initialBounds: quad.bounds,
            myLocation: myLocation,
            overlays: [
              GeoImageOverlay(
                id: 'plan',
                image: const MapImage.asset('assets/floors/hedva_0.webp'),
                georeference: _reference,
                imageSize: _pictureSize,
                opacity: _opacity,
              ),
            ],
            markers: [
              for (final stop in strakoniceStops)
                MapMarker(
                  id: '${stop.number}',
                  position: stop.position,
                  icon: numberedPin(stop.number, selected: stop == _selected),
                  data: stop,
                ),
              // The corners, computed from the same reference that placed the
              // picture: they should sit exactly on its corners.
              if (_corners)
                for (final (i, corner) in quad.corners.indexed)
                  MapMarker(
                    id: 'corner-$i',
                    position: corner,
                    icon: cornerMark('$i'),
                    tappable: false,
                  ),
            ],
            onMarkerTap: (marker) => setState(() => _selected = marker.data),
            unsupportedBuilder: unsupportedMap,
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Streets')),
                        ButtonSegment(value: false, label: Text('Blank')),
                      ],
                      selected: {_streets},
                      onSelectionChanged: (s) =>
                          setState(() => _streets = s.single),
                    ),
                    // A slider fills whatever height it is allowed, and the
                    // row allows the whole screen.
                    SizedBox(
                      width: 140,
                      height: 48,
                      child: Slider(
                        value: _opacity,
                        onChanged: (v) => setState(() => _opacity = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
      floatingActionButton: _selected == null ? locationButton() : null,
    );
  }
}
