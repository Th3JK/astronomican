import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/cluster/marker_clustering.dart';
import '../core/map_level.dart';
import '../core/map_position.dart';
import '../core/marker/map_marker.dart';
import '../location/level_location.dart';
import '../location/my_location_controller.dart';
import '../location/my_location_style.dart';
import '../ui/marker_icon_view.dart';
import 'image_follow.dart';
import 'image_map_controller.dart';
import 'image_map_options.dart';
import 'location_layer.dart';
import 'marker_flow_delegate.dart';
import 'viewport_math.dart';

/// Builds the widget an image map draws for [marker], in place of its icon.
typedef ImageMarkerBuilder<T> =
    Widget Function(BuildContext context, MapMarker<T> marker);

/// Builds the widget an image map draws for [cluster], in place of its badge.
typedef ImageClusterBuilder<T> =
    Widget Function(BuildContext context, MarkerCluster<T> cluster);

/// A marker with the point it stands on, resolved for one level.
@internal
@immutable
class PlacedMarker<T> {
  /// [marker] standing at [position] in the level's frame.
  const PlacedMarker(this.marker, this.position);

  /// The marker.
  final MapMarker<T> marker;

  /// Where it stands.
  final Offset position;

  @override
  bool operator ==(Object other) =>
      other is PlacedMarker<T> &&
      other.marker == marker &&
      other.position == position;

  @override
  int get hashCode => Object.hash(marker, position);
}

/// One level of an image map, with its own camera.
///
/// Each level gets its own viewer rather than sharing one, so a level can be
/// created already framed — no first frame at the wrong zoom — and so the
/// level sliding out keeps its camera while the one sliding in has its own.
@internal
class LevelViewport<T> extends StatefulWidget {
  /// A viewport showing [level] in a box [viewport] across.
  const LevelViewport({
    super.key,
    required this.controller,
    required this.level,
    required this.viewport,
    required this.markers,
    required this.options,
    required this.fitPadding,
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
  });

  /// The controller this viewport answers to.
  final ImageMapController controller;

  /// The level shown.
  final MapLevel level;

  /// The size of the map's box.
  final Size viewport;

  /// The markers on this level, in paint order.
  final List<PlacedMarker<T>> markers;

  /// The map's options.
  final ImageMapOptions options;

  /// Padding the level is fitted within.
  final EdgeInsets fitPadding;

  /// Called with a tapped marker.
  final void Function(MapMarker<T> marker)? onMarkerTap;

  /// Called with the point of the level tapped outside any marker.
  final void Function(ImagePosition position)? onBackgroundTap;

  /// Builds markers in place of their icons.
  final ImageMarkerBuilder<T>? markerBuilder;

  /// Shown in place of a picture that fails to load.
  final ImageErrorWidgetBuilder? errorBuilder;

  /// The bundle asset pictures load from.
  final AssetBundle? bundle;

  /// The visitor's position, drawn and followed.
  final MyLocationController? myLocation;

  /// How the position is drawn.
  final MyLocationStyle myLocationStyle;

  /// How crowded markers merge, or null to draw each one.
  final MarkerClustering? clustering;

  /// Called with a tapped cluster; without it a tap zooms in until it splits.
  final void Function(MarkerCluster<T> cluster)? onClusterTap;

  /// Builds clusters in place of their badges.
  final ImageClusterBuilder<T>? clusterBuilder;

  @override
  State<LevelViewport<T>> createState() => _LevelViewportState<T>();
}

class _LevelViewportState<T> extends State<LevelViewport<T>>
    with TickerProviderStateMixin
    implements ImageViewportHandle {
  late final TransformationController _transform;
  late final AnimationController _animation;
  late final ImageFollower _follower;
  (CameraPose, CameraPose)? _tween;
  Matrix4? _tweenEnd;
  Curve _curve = Curves.easeOutCubic;

  /// Set while the clamp writes to the controller, so its own notification
  /// does not send it round again.
  bool _clamping = false;

  /// Set while a camera move runs. Its end point is already in bounds, and
  /// clamping the frames on the way would make it stutter.
  bool _animating = false;

  /// Set while a finger is on the map. Following waits for it to lift:
  /// moving the camera under a finger fights the finger.
  bool _interacting = false;

  Offset _doubleTapAt = Offset.zero;

  MyLocationMode _lastMode = MyLocationMode.none;
  int _lastCentreRequests = 0;
  bool _zoomInOnFollow = false;

  MarkerClusterSet<T>? _clusters;
  List<PlacedMarker<T>>? _clusteredFrom;
  List<double> _clusterScales = const [];
  int _clusterLevel = 0;

  @override
  void initState() {
    super.initState();
    _transform = TransformationController(_initialMatrix())
      ..addListener(_onTransformChanged);
    _animation = AnimationController(vsync: this)..addListener(_onTick);
    _follower = ImageFollower(
      vsync: this,
      read: () => CameraPose.of(_transform.value, viewport),
      write: (pose) => _transform.value = pose.matrix(viewport),
      blocked: () => _interacting || _animating,
    );
    widget.controller.attach(this);
    _listen(widget.myLocation);
    final location = widget.myLocation;
    if (location != null) {
      _lastMode = location.mode;
      _lastCentreRequests = location.centreRequests;
      // Sliding in while following: carry on following on this level.
      _zoomInOnFollow = location.mode != MyLocationMode.none;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reportOrientable();
        _followStep();
      });
    }
  }

  @override
  void didUpdateWidget(LevelViewport<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach(this);
      widget.controller.attach(this);
    }
    if (!identical(oldWidget.myLocation, widget.myLocation)) {
      _unlisten(oldWidget.myLocation);
      _listen(widget.myLocation);
    }
    if (oldWidget.viewport != widget.viewport) {
      final fromFit = ViewportMath.fitScale(oldWidget.viewport, level.size);
      _animation.stop();
      _transform.value = fromFit <= 0
          ? _fitted()
          : _clamped(
              ViewportMath.resize(
                _transform.value,
                from: oldWidget.viewport,
                to: widget.viewport,
                fromFit: fromFit,
                toFit: fitScale,
              ),
            );
    }
  }

  @override
  void dispose() {
    if (widget.options.rememberLevelView) {
      widget.controller.saveView(level.id, _transform.value.clone());
    }
    widget.controller.detach(this);
    _unlisten(widget.myLocation);
    _follower.dispose();
    _animation.dispose();
    _transform
      ..removeListener(_onTransformChanged)
      ..dispose();
    super.dispose();
  }

  // ImageViewportHandle

  @override
  MapLevel get level => widget.level;

  @override
  Size get viewport => widget.viewport;

  @override
  Matrix4 get matrix => _transform.value;

  @override
  double get fitScale => ViewportMath.fitScale(viewport, level.size);

  @override
  EdgeInsets get fitPadding => widget.fitPadding;

  @override
  ImageMapOptions get options => widget.options;

  @override
  double clampScale(double scale) {
    final fit = fitScale;
    if (fit <= 0) return scale;
    return scale.clamp(fit * options.minZoom, fit * options.maxZoom);
  }

  @override
  Future<void> animateMatrix(
    Matrix4 target, {
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (!mounted) return;
    final end = _clamped(target);
    final length = duration ?? options.cameraDuration;
    _animation.stop();
    if (length == Duration.zero) {
      _transform.value = end;
      return;
    }
    _tween = (
      CameraPose.of(_transform.value, viewport),
      CameraPose.of(end, viewport),
    );
    _tweenEnd = end;
    _curve = curve;
    _animation.duration = length;
    _animating = true;
    try {
      await _animation.forward(from: 0).orCancel;
    } on TickerCanceled {
      // Interrupted by a touch or another move; where it stopped is fine.
    } finally {
      _animating = false;
    }
  }

  void _onTick() {
    final tween = _tween;
    if (tween == null) return;
    final t = _curve.transform(_animation.value);
    _transform.value = t >= 1
        ? _tweenEnd!
        : CameraPose.lerp(tween.$1, tween.$2, t).matrix(viewport);
  }

  bool get _showing => widget.controller.isShowing(this);

  bool get _following =>
      (widget.myLocation?.mode ?? MyLocationMode.none) != MyLocationMode.none;

  Matrix4 _initialMatrix() {
    final saved = widget.options.rememberLevelView
        ? widget.controller.savedView(level.id)
        : null;
    return saved != null ? _clamped(saved) : _fitted();
  }

  Matrix4 _fitted() {
    final fit = fitScale;
    if (fit <= 0) return Matrix4.identity();
    return ViewportMath.fitRect(
      level.focusOrFrame,
      viewport: viewport,
      minScale: fit * options.minZoom,
      maxScale: fit * options.maxZoom,
      padding: widget.fitPadding,
      rotation: widget.controller.rotation,
    );
  }

  /// Keeps the picture in view.
  ///
  /// Without this the map has no bounds at all: a hard fling sends the plan
  /// off the screen and leaves it there, with nothing to say which way to
  /// drag to find it again. While the map follows the visitor it is held more
  /// loosely, so the dot can be in the middle even by the picture's edge.
  Matrix4 _clamped(Matrix4 matrix) => _following
      ? ViewportMath.clampCentre(
          matrix,
          viewport: viewport,
          content: level.size,
        )
      : ViewportMath.clamp(
          matrix,
          viewport: viewport,
          content: level.size,
          overscroll: options.overscroll,
          rest: level.focusOrFrame.center,
        );

  void _onTransformChanged() {
    if (!_clamping && !_animating) {
      final current = _transform.value;
      final clamped = _clamped(current);
      if (!identical(clamped, current)) {
        _clamping = true;
        _transform.value = clamped;
        _clamping = false;
      }
    }
    if (_showing) {
      widget.controller.noteRotation(ViewportMath.rotationOf(matrix));
    }
    _updateClusterLevel();
  }

  void _onDoubleTap() {
    final fit = fitScale;
    if (fit <= 0) return;
    final current = ViewportMath.scaleOf(matrix);
    final Matrix4 target;
    if (current >= fit * options.maxZoom * 0.99) {
      target = _fitted();
    } else {
      target = ViewportMath.zoomAbout(
        matrix,
        ViewportMath.toScreen(matrix, _doubleTapAt),
        clampScale(current * options.doubleTapZoom),
      );
    }
    unawaited(animateMatrix(target));
  }

  // The visitor's position.

  void _listen(MyLocationController? location) {
    location?.addListener(_onLocation);
    location?.heading.addListener(_onHeading);
  }

  void _unlisten(MyLocationController? location) {
    location?.removeListener(_onLocation);
    location?.heading.removeListener(_onHeading);
  }

  void _reportOrientable() {
    final location = widget.myLocation;
    if (location == null || !_showing) return;
    location.orientable =
        LevelLocation.north(level, level.frame.center) != null;
  }

  void _onLocation() {
    final location = widget.myLocation;
    if (location == null || !_showing) return;
    final mode = location.mode;
    if (mode != MyLocationMode.none &&
        (_lastMode == MyLocationMode.none ||
            location.centreRequests != _lastCentreRequests)) {
      _zoomInOnFollow = true;
    }
    _lastMode = mode;
    _lastCentreRequests = location.centreRequests;
    if (mode == MyLocationMode.none) {
      _follower.stop();
      if (!_interacting) _faceUp();
      return;
    }
    _followStep();
  }

  void _onHeading() {
    if (widget.myLocation?.mode == MyLocationMode.heading && _showing) {
      _followStep();
    }
  }

  /// Points the follower at where the visitor is now.
  void _followStep() {
    final location = widget.myLocation;
    final fix = location?.fix;
    if (location == null ||
        fix == null ||
        location.mode == MyLocationMode.none ||
        !_showing) {
      return;
    }
    final at = LevelLocation.place(fix, level);
    // Not on this level — the map switches levels for a fix on another — or
    // so far off the picture that following would show only background.
    if (at == null ||
        !level.frame.inflate(level.size.longestSide * 0.25).contains(at)) {
      return;
    }

    var rotation = 0.0;
    if (location.mode == MyLocationMode.heading) {
      final north = LevelLocation.north(level, at);
      final heading = location.heading.value;
      if (north != null && heading != null) {
        rotation = -(north + heading * math.pi / 180);
      } else {
        rotation = ViewportMath.rotationOf(matrix);
      }
    }

    double? scale;
    if (_zoomInOnFollow) {
      _zoomInOnFollow = false;
      final fit = fitScale;
      if (fit > 0 && ViewportMath.scaleOf(matrix) < fit * options.followZoom) {
        scale = clampScale(fit * options.followZoom);
      }
    }
    _follower.follow(centre: at, rotation: rotation, scale: scale);
  }

  /// Turns the picture back upright once the map stops facing the heading.
  void _faceUp() {
    if (ViewportMath.rotationOf(matrix) == 0) return;
    unawaited(
      animateMatrix(
        ViewportMath.rotateAbout(matrix, viewport.center(Offset.zero), 0),
      ),
    );
  }

  // Clustering.

  List<double> _scalesFor() {
    final fit = fitScale;
    if (fit <= 0) return const [1];
    double halfSteps(double scale) => 2 * math.log(scale) / math.ln2;
    final lo = halfSteps(fit * options.minZoom).floor();
    final hi = math.max(lo, halfSteps(fit * options.maxZoom).floor());
    return [for (var k = lo; k <= hi; k++) math.pow(2, k / 2).toDouble()];
  }

  void _ensureClusters() {
    final clustering = widget.clustering;
    if (clustering == null) {
      _clusters = null;
      _clusteredFrom = null;
      return;
    }
    final scales = _scalesFor();
    final markers = widget.markers;
    if (_clusters != null &&
        listEquals(_clusteredFrom, markers) &&
        listEquals(_clusterScales, scales)) {
      return;
    }
    final clusterable = [
      for (final m in markers)
        if (m.marker.clusterable) m,
    ];
    final clusters = MarkerClusterSet<T>(
      markers: [for (final m in clusterable) m.marker],
      world: [for (final m in clusterable) m.position],
      scales: scales,
      options: clustering,
      toPosition: ImagePosition.fromOffset,
    );
    _clusters = clusters;
    _clusteredFrom = markers;
    _clusterScales = scales;
    _clusterLevel = clusters.index.levelFor(ViewportMath.scaleOf(matrix));
  }

  /// Switches the clusters drawn as the zoom crosses a level, with a little
  /// give either side of the line, so a pinch resting on it does not make
  /// them flicker.
  void _updateClusterLevel() {
    final clusters = _clusters;
    if (clusters == null) return;
    final scale = ViewportMath.scaleOf(matrix);
    final index = clusters.index;
    final candidate = index.levelFor(scale);
    if (candidate == _clusterLevel) return;
    const give = 1.0533; // A sixth of a half-step: 2^(0.075).
    final next = candidate > _clusterLevel
        ? index.levelFor(scale / give)
        : index.levelFor(scale * give);
    if (next == _clusterLevel) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // Mid-build (a resize): the build under way draws the new level.
      _clusterLevel = next;
    } else {
      setState(() => _clusterLevel = next);
    }
  }

  void _tapCluster(GroupedMarkers<T> group) {
    final onTap = widget.onClusterTap;
    if (onTap != null) {
      onTap(group.cluster);
      return;
    }
    final scales = _clusterScales;
    final split = scales[math.min(group.expansionLevel, scales.length - 1)];
    final target = clampScale(
      math.max(ViewportMath.scaleOf(matrix), split * 1.1),
    );
    unawaited(
      animateMatrix(
        ViewportMath.centreOn(
          group.world,
          target,
          viewport.center(Offset.zero),
          rotation: ViewportMath.rotationOf(matrix),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fit = fitScale;
    final doubleTap = options.doubleTapZoom > 1;
    final onBackgroundTap = widget.onBackgroundTap;
    final location = widget.myLocation;

    _ensureClusters();
    final clusters = _clusters;
    final List<PlacedMarker<T>> markers;
    final List<GroupedMarkers<T>> groups;
    if (clusters == null) {
      markers = widget.markers;
      groups = const [];
    } else {
      final items = clusters.itemsAt(_clusterLevel);
      final lone = {
        for (final item in items)
          if (item is LoneMarker<T>) item.marker.id,
      };
      markers = [
        for (final m in widget.markers)
          if (!m.marker.clusterable || lone.contains(m.marker.id)) m,
      ];
      groups = items.whereType<GroupedMarkers<T>>().toList();
    }
    final clustering = widget.clustering;

    return InteractiveViewer(
      transformationController: _transform,
      // The child is laid out at the level's own size rather than the
      // viewport's, so the viewer cannot measure bounds against it; the clamp
      // above holds the picture in view instead.
      constrained: false,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: fit > 0 ? fit * options.minZoom : 0.01,
      maxScale: fit > 0 ? fit * options.maxZoom : 1,
      onInteractionStart: (_) {
        _interacting = true;
        if (_animation.isAnimating) _animation.stop();
      },
      onInteractionUpdate: (details) {
        // One finger dragging means the visitor wants to look elsewhere; two
        // fingers only zoom, and following carries on when they lift.
        if (details.pointerCount == 1 &&
            details.focalPointDelta != Offset.zero) {
          location?.stopFollowing();
        }
      },
      onInteractionEnd: (_) {
        _interacting = false;
        if (location == null) return;
        if (location.mode == MyLocationMode.none) {
          _faceUp();
        } else {
          _followStep();
        }
      },
      child: SizedBox.fromSize(
        size: level.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: onBackgroundTap == null
                    ? null
                    : (details) => onBackgroundTap(
                        ImagePosition.fromOffset(details.localPosition),
                      ),
                onDoubleTapDown: doubleTap
                    ? (details) => _doubleTapAt = details.localPosition
                    : null,
                onDoubleTap: doubleTap ? _onDoubleTap : null,
                child: Image(
                  image: level.image.provider(bundle: widget.bundle),
                  fit: BoxFit.fill,
                  // Keeps the last picture up rather than a blank frame while
                  // one that was not precached decodes.
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  filterQuality: options.filterQuality,
                  errorBuilder: widget.errorBuilder ?? _missingPicture,
                ),
              ),
            ),
            Positioned.fill(
              child: Flow(
                delegate: MarkerFlowDelegate(
                  transform: _transform,
                  positions: [
                    for (final m in markers) m.position,
                    for (final g in groups) g.world,
                  ],
                  anchors: [
                    for (final m in markers) m.marker.icon.anchor.alignment,
                    for (final g in groups)
                      clustering!.iconFor(g.cluster.count).anchor.alignment,
                  ],
                ),
                clipBehavior: Clip.none,
                children: [
                  for (final m in markers)
                    KeyedSubtree(
                      key: ValueKey(m.marker.id),
                      child: _buildMarker(context, m.marker),
                    ),
                  // A key of another type, so no marker id can collide.
                  for (final g in groups)
                    KeyedSubtree(
                      key: ValueKey(('cluster', g.cluster.id)),
                      child: _buildCluster(context, g),
                    ),
                ],
              ),
            ),
            if (location != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: MyLocationPainter(
                      transform: _transform,
                      controller: location,
                      level: level,
                      style: widget.myLocationStyle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarker(BuildContext context, MapMarker<T> marker) {
    final child =
        widget.markerBuilder?.call(context, marker) ??
        SizedBox.fromSize(
          size: marker.icon.size,
          child: MarkerIconView(marker.icon),
        );
    final onTap = widget.onMarkerTap;
    final tappable = marker.tappable && onTap != null;
    return Semantics(
      container: true,
      button: tappable,
      label: marker.semanticLabel,
      child: tappable
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(marker),
              child: child,
            )
          // A marker that only marks lets a tap through to the map.
          : IgnorePointer(child: child),
    );
  }

  Widget _buildCluster(BuildContext context, GroupedMarkers<T> group) {
    final cluster = group.cluster;
    final icon = widget.clustering!.iconFor(cluster.count);
    final child =
        widget.clusterBuilder?.call(context, cluster) ??
        SizedBox.fromSize(size: icon.size, child: MarkerIconView(icon));
    return Semantics(
      container: true,
      button: true,
      label: '${cluster.count} markers',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapCluster(group),
        child: child,
      ),
    );
  }

  static Widget _missingPicture(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => const ColoredBox(color: Color(0x14000000));
}
