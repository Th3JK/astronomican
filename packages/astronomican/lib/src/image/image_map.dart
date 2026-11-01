import 'package:flutter/widgets.dart';

import '../core/cluster/marker_clustering.dart';
import '../core/map_level.dart';
import '../core/map_position.dart';
import '../core/marker/map_marker.dart';
import '../location/location_fix.dart';
import '../location/my_location_controller.dart';
import '../location/my_location_style.dart';
import 'image_map_controller.dart';
import 'image_map_options.dart';
import 'level_viewport.dart';

/// A picture used as the map: an illustrated site map, or the floors of a
/// building, with markers placed by their position on the picture.
///
/// Pure Flutter — no platform view, no network — so it runs everywhere
/// Flutter does, tests included.
///
/// * Pinch, pan and double tap to zoom, kept inside the picture's bounds.
/// * Opens framed on the level's focus rather than the whole sheet.
/// * Markers stay the same size on screen at every zoom.
/// * Several levels switch with a slide up or down; replacing the levels
///   (another building) dissolves instead.
/// * With [clustering], markers that crowd each other merge into a count,
///   and split again as the visitor zooms in.
/// * With [myLocation], the visitor's position is drawn — a GPS fix through
///   the level's georeference, or a position on a floor from the app — and
///   the map can follow it and turn to face the way the visitor does.
///
/// ```dart
/// final controller = ImageMapController(levels: [
///   MapLevel(
///     id: 'ground',
///     label: '1',
///     image: MapImage.asset('assets/floors/ground.webp'),
///     size: Size(2664, 2048),
///   ),
/// ]);
///
/// ImageMap<Stop>(
///   controller: controller,
///   markers: [
///     for (final stop in stops)
///       MapMarker(
///         id: '${stop.id}',
///         position: ImagePosition(stop.x, stop.y),
///         levelId: stop.floor,
///         data: stop,
///       ),
///   ],
///   onMarkerTap: (marker) => open(marker.data!),
/// );
/// ```
class ImageMap<T> extends StatefulWidget {
  /// A map driven by [controller].
  const ImageMap({
    super.key,
    required ImageMapController this.controller,
    this.markers = const [],
    this.options = const ImageMapOptions(),
    this.fitPadding = EdgeInsets.zero,
    this.onMarkerTap,
    this.onBackgroundTap,
    this.markerBuilder,
    this.errorBuilder,
    this.bundle,
    this.myLocation,
    this.myLocationStyle = const MyLocationStyle(),
    this.clustering,
    this.onClusterTap,
    this.clusterBuilder,
  }) : level = null;

  /// A map of the one picture [level], for when there is nothing to switch
  /// between and no camera to drive from outside.
  const ImageMap.single({
    super.key,
    required MapLevel this.level,
    this.markers = const [],
    this.options = const ImageMapOptions(),
    this.fitPadding = EdgeInsets.zero,
    this.onMarkerTap,
    this.onBackgroundTap,
    this.markerBuilder,
    this.errorBuilder,
    this.bundle,
    this.myLocation,
    this.myLocationStyle = const MyLocationStyle(),
    this.clustering,
    this.onClusterTap,
    this.clusterBuilder,
  }) : controller = null;

  /// Which level is shown, and where the camera looks.
  final ImageMapController? controller;

  /// The one level of [ImageMap.single].
  final MapLevel? level;

  /// Everything drawn on the map. Each shows on its own level, or on all of
  /// them when it names none.
  final List<MapMarker<T>> markers;

  /// Zoom limits, transitions and the like.
  final ImageMapOptions options;

  /// Room left around the level when it is fitted to the screen — under a
  /// toolbar or a bottom sheet, say.
  final EdgeInsets fitPadding;

  /// Called when a tappable marker is tapped.
  final void Function(MapMarker<T> marker)? onMarkerTap;

  /// Called when the picture is tapped away from any marker, with the point
  /// tapped in the level's frame. Handy for authoring: tap a room, log the
  /// coordinate.
  final void Function(ImagePosition position)? onBackgroundTap;

  /// Builds a marker as any widget, in place of its icon.
  ///
  /// The widget must size itself; the icon's anchor is applied to whatever
  /// size it lays out at. Taps and semantics are added around it by the map.
  final ImageMarkerBuilder<T>? markerBuilder;

  /// Shown in place of a picture that fails to load. The markers still stand
  /// in their places on it.
  final ImageErrorWidgetBuilder? errorBuilder;

  /// The bundle asset pictures load from, when not the default one.
  final AssetBundle? bundle;

  /// The visitor's position, drawn on the level and followed when asked.
  ///
  /// While following, a fix on another floor switches to that floor.
  final MyLocationController? myLocation;

  /// How the position is drawn.
  final MyLocationStyle myLocationStyle;

  /// How crowded markers merge, or null to draw every marker on its own.
  final MarkerClustering? clustering;

  /// Called with a tapped cluster. Without it, a tap zooms in until the
  /// cluster splits.
  final void Function(MarkerCluster<T> cluster)? onClusterTap;

  /// Builds a cluster as any widget, in place of its badge.
  final ImageClusterBuilder<T>? clusterBuilder;

  @override
  State<ImageMap<T>> createState() => _ImageMapState<T>();
}

class _ImageMapState<T> extends State<ImageMap<T>> {
  ImageMapController? _own;

  ImageMapController get _controller => widget.controller ?? _own!;

  @override
  void initState() {
    super.initState();
    _syncOwnController();
    _controller.addListener(_onControllerChanged);
    widget.myLocation?.addListener(_onLocation);
  }

  @override
  void didUpdateWidget(ImageMap<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.controller ?? _own!;
    _syncOwnController();
    if (!identical(old, _controller)) {
      old.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
    }
    if (!identical(oldWidget.myLocation, widget.myLocation)) {
      oldWidget.myLocation?.removeListener(_onLocation);
      widget.myLocation?.addListener(_onLocation);
    }
  }

  void _syncOwnController() {
    final level = widget.level;
    if (widget.controller != null || level == null) {
      _own?.dispose();
      _own = null;
      return;
    }
    final own = _own;
    if (own == null) {
      _own = ImageMapController(levels: [level]);
    } else if (own.levels.single != level) {
      own.replaceLevels([level]);
    }
  }

  @override
  void dispose() {
    widget.myLocation?.removeListener(_onLocation);
    _controller.removeListener(_onControllerChanged);
    _own?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// While following, goes to the floor a fix is on.
  void _onLocation() {
    final location = widget.myLocation;
    final fix = location?.fix;
    if (location == null ||
        fix == null ||
        location.mode == MyLocationMode.none ||
        fix.position is! ImagePosition) {
      return;
    }
    final LocationFix(:levelId) = fix;
    if (levelId == null || levelId == _controller.activeLevelId) return;
    if (_controller.levels.any((level) => level.id == levelId)) {
      _controller.showLevel(levelId);
    }
  }

  List<PlacedMarker<T>> _placed(MapLevel level) {
    final placed = <PlacedMarker<T>>[];
    for (final marker in widget.markers) {
      if (marker.levelId != null && marker.levelId != level.id) continue;
      final point = level.locate(marker.position);
      if (point == null) continue;
      placed.add(PlacedMarker(marker, point.toOffset()));
    }
    // Stable, so markers of equal index keep the order the app gave them.
    return _stableSorted(placed);
  }

  static List<PlacedMarker<T>> _stableSorted<T>(List<PlacedMarker<T>> items) {
    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final byZ = a.$2.marker.zIndex.compareTo(b.$2.marker.zIndex);
      return byZ != 0 ? byZ : a.$1.compareTo(b.$1);
    });
    return [for (final (_, item) in indexed) item];
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final level = controller.activeLevel;
    final options = widget.options;
    final background = options.backgroundColor;

    Widget map = LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (level == null || !viewport.isFinite || viewport.isEmpty) {
          return const SizedBox.expand();
        }
        return AnimatedSwitcher(
          duration: options.levelTransition,
          switchInCurve: options.transitionCurve,
          switchOutCurve: options.transitionCurve,
          transitionBuilder: (child, animation) => _LevelTransition(
            animation: animation,
            direction: () => controller.direction,
            child: child,
          ),
          // Both levels laid over each other at the screen's size, so neither
          // is squeezed while they change places.
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: LevelViewport<T>(
            key: ValueKey('${controller.generation}/${level.id}'),
            controller: controller,
            level: level,
            viewport: viewport,
            markers: _placed(level),
            options: options,
            fitPadding: widget.fitPadding,
            onMarkerTap: widget.onMarkerTap,
            onBackgroundTap: widget.onBackgroundTap,
            markerBuilder: widget.markerBuilder,
            errorBuilder: widget.errorBuilder,
            bundle: widget.bundle,
            myLocation: widget.myLocation,
            myLocationStyle: widget.myLocationStyle,
            clustering: widget.clustering,
            onClusterTap: widget.onClusterTap,
            clusterBuilder: widget.clusterBuilder,
          ),
        );
      },
    );

    if (background != null) map = ColoredBox(color: background, child: map);
    return ClipRect(child: map);
  }
}

/// How one level gives way to the next.
///
/// A floor slides, because up and down are real directions in a building and
/// saying which way the visitor moved is worth something. Levels are listed
/// from the lowest up, so going up the list the new floor comes down from
/// above and the one left behind runs out of the bottom. Another building
/// dissolves, since sliding it in would claim the two stand side by side.
///
/// The direction is read live rather than captured: the level sliding out was
/// built when it slid in, and must leave the way the current change goes.
class _LevelTransition extends StatelessWidget {
  const _LevelTransition({
    required this.animation,
    required this.direction,
    required this.child,
  });

  final Animation<double> animation;
  final int Function() direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final dir = direction();
        if (dir == 0) return Opacity(opacity: animation.value, child: child);
        final leaving = animation.status == AnimationStatus.reverse;
        final remaining = 1 - animation.value;
        return FractionalTranslation(
          translation: Offset(0, (leaving ? dir : -dir) * remaining),
          child: child,
        );
      },
    );
  }
}
