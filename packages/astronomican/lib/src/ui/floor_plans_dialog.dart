import 'package:flutter/material.dart';

import '../core/building/map_building.dart';
import '../core/cluster/marker_clustering.dart';
import '../core/marker/map_marker.dart';
import '../image/image_map.dart';
import '../image/image_map_controller.dart';
import '../image/image_map_options.dart';
import '../location/my_location_controller.dart';
import '../location/my_location_style.dart';
import 'level_selector.dart';
import 'my_location_button.dart';

/// Opens [building]'s floors as floor plans over the whole screen, and
/// completes when the visitor closes them.
///
/// What a tap on a building on the street map can do instead of laying the
/// floors over the streets: the plans come up on their own, at a size meant
/// for reading them, with a level selector and the [markers] on each floor.
///
/// Give it the street map's [myLocation] and the plans show the visitor too,
/// read from the same feed — the GPS is not started twice — with following
/// of their own, so following on the plans leaves the street map alone.
Future<void> showFloorPlans<T>(
  BuildContext context, {
  required MapBuilding building,
  List<MapMarker<T>> markers = const [],
  void Function(MapMarker<T> marker)? onMarkerTap,
  MyLocationController? myLocation,
  MyLocationStyle myLocationStyle = const MyLocationStyle(),
  MarkerClustering? clustering,
  ImageMapOptions options = const ImageMapOptions(),
  String? initialLevelId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => BuildingFloorPlans<T>(
      building: building,
      markers: markers,
      onMarkerTap: onMarkerTap,
      myLocation: myLocation,
      myLocationStyle: myLocationStyle,
      clustering: clustering,
      options: options,
      initialLevelId: initialLevelId,
    ),
  ),
);

/// A building's floors as a page of its own: the plans, a level selector,
/// and the visitor's position.
///
/// What [showFloorPlans] shows; push it yourself for a route of your own.
class BuildingFloorPlans<T> extends StatefulWidget {
  /// The floors of [building].
  const BuildingFloorPlans({
    super.key,
    required this.building,
    this.markers = const [],
    this.onMarkerTap,
    this.myLocation,
    this.myLocationStyle = const MyLocationStyle(),
    this.clustering,
    this.options = const ImageMapOptions(),
    this.initialLevelId,
  });

  /// The building.
  final MapBuilding building;

  /// Markers on its floors.
  final List<MapMarker<T>> markers;

  /// Called with a tapped marker.
  final void Function(MapMarker<T> marker)? onMarkerTap;

  /// The street map's position controller, whose feed the plans read.
  final MyLocationController? myLocation;

  /// How the position is drawn.
  final MyLocationStyle myLocationStyle;

  /// How crowded markers merge.
  final MarkerClustering? clustering;

  /// The plans' zoom limits and transitions.
  final ImageMapOptions options;

  /// The floor to open on; the building's own choice otherwise.
  final String? initialLevelId;

  @override
  State<BuildingFloorPlans<T>> createState() => _BuildingFloorPlansState<T>();
}

class _BuildingFloorPlansState<T> extends State<BuildingFloorPlans<T>> {
  late final ImageMapController _controller = ImageMapController(
    levels: widget.building.levels,
    initialLevelId: widget.initialLevelId ?? widget.building.initialLevelId,
  );
  MyLocationController? _myLocation;

  @override
  void initState() {
    super.initState();
    final outside = widget.myLocation;
    if (outside != null) {
      final own = MyLocationController(
        feed: outside.feed,
        headingInterval: outside.headingInterval,
        headingDeadband: outside.headingDeadband,
        pauseWhenHidden: outside.pauseWhenHidden,
      );
      _myLocation = own;
      // Already running outside: carry on here without a tap.
      if (outside.status == MyLocationStatus.active ||
          outside.status == MyLocationStatus.searching) {
        own.start();
      }
    }
  }

  @override
  void dispose() {
    _myLocation?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myLocation = _myLocation;
    return Scaffold(
      appBar: AppBar(title: Text(widget.building.name)),
      body: Stack(
        children: [
          ImageMap<T>(
            controller: _controller,
            markers: widget.markers,
            onMarkerTap: widget.onMarkerTap,
            myLocation: myLocation,
            myLocationStyle: widget.myLocationStyle,
            clustering: widget.clustering,
            options: widget.options,
          ),
          Positioned(
            top: 12,
            right: 12,
            child: LevelSelector(controller: _controller),
          ),
          if (myLocation != null)
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: MyLocationButton(controller: myLocation),
            ),
        ],
      ),
    );
  }
}
