import 'dart:async';
import 'dart:math' show Point, min;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'package:astronomican/astronomican.dart';
import 'geo_camera.dart';
import 'geo_follower.dart';
import 'geo_image_overlay.dart';
import 'geo_map_controller.dart';
import 'geo_map_source.dart';
import 'maplibre_convert.dart';
import 'scene/geo_scene.dart';
import 'scene/maplibre_style_ops.dart';

/// Whether a `GeoMap` shows MapLibre's own credit button.
enum MapAttribution {
  /// MapLibre's "i" button, which lists each source's attribution.
  platform,

  /// No button. The app is then responsible for crediting the data — for
  /// OpenStreetMap-derived tiles, the ODbL asks for it wherever the map is
  /// shown — in its own text.
  hidden,
}

/// A real map, drawn natively by MapLibre, with markers, pictures laid over
/// it and indoor floors.
///
/// * The base comes from a [GeoMapSource]: an online style, raster tiles, an
///   offline pack or a plain background.
/// * [markers] are drawn as icons registered with the style, so hundreds cost
///   no more than one Flutter widget. They stay the same size at any zoom.
/// * [overlays] are pictures pinned to the Earth, drawn under the markers.
/// * Indoor floors are the [controller]'s levels: the active one is drawn over
///   the streets, and markers on it appear with it. A `LevelSelector` bound to
///   the same controller switches them.
/// * [buildings] stand as one marker each until entered; a tap goes in, or
///   does what [onBuildingTap] says — open the floor plans, say.
/// * With [clustering], crowded markers merge into a count and split again
///   as the map zooms in.
/// * With [myLocation], the visitor is drawn with their heading, and the map
///   follows them and turns to face the way they do when asked.
///
/// Runs on Android and iOS. On the web it draws online sources and markers,
/// but not pictures (MapLibre's web plugin has no image source) or packs
/// (no file system). Elsewhere it shows [unsupportedBuilder].
///
/// ```dart
/// GeoMap<Stop>(
///   source: GeoMapSource.bundledPack(packs, 'assets/packs/town/pack.json'),
///   markers: [
///     for (final (i, stop) in stops.indexed)
///       MapMarker(
///         id: stop.id,
///         position: GeoPosition(stop.lat, stop.lng),
///         icon: MarkerIcon.pin(label: '${i + 1}'),
///         data: stop,
///       ),
///   ],
///   onMarkerTap: (marker) => open(marker.data!),
/// )
/// ```
class GeoMap<T> extends StatefulWidget {
  /// A map drawing [source].
  const GeoMap({
    super.key,
    required this.source,
    this.controller,
    this.markers = const [],
    this.overlays = const [],
    this.initialCamera,
    this.initialBounds,
    this.fitPadding = const EdgeInsets.all(32),
    this.minZoom,
    this.maxZoom,
    this.cameraBounds,
    this.interactive = true,
    this.rotateGestures = false,
    this.tiltGestures = false,
    this.attribution = MapAttribution.platform,
    this.onMarkerTap,
    this.onMapTap,
    this.onCameraIdle,
    this.onStyleLoaded,
    this.onError,
    this.placeholder,
    this.errorBuilder,
    this.unsupportedBuilder,
    this.gestureRecognizers,
    this.bundle,
    this.myLocation,
    this.myLocationStyle = const MyLocationStyle(),
    this.followZoom = 17,
    this.clustering,
    this.clusterMaxZoom = 16,
    this.onClusterTap,
    this.buildings = const [],
    this.onBuildingTap,
  });

  /// What is drawn underneath.
  final GeoMapSource source;

  /// Camera moves and indoor levels. One is made if none is given.
  final GeoMapController? controller;

  /// Everything drawn on the map.
  final List<MapMarker<T>> markers;

  /// Pictures pinned to the Earth.
  final List<GeoImageOverlay> overlays;

  /// Where the map opens. Takes precedence over everything else.
  final GeoCamera? initialCamera;

  /// What the map opens framed on, when [initialCamera] is not given.
  /// Without either, it frames the markers, or else the pack's area.
  final GeoBounds? initialBounds;

  /// Room left around whatever the map opens framed on.
  final EdgeInsets fitPadding;

  /// How far out the map can be zoomed.
  final double? minZoom;

  /// How far in the map can be zoomed.
  final double? maxZoom;

  /// Keeps the camera's centre inside these bounds — the tileset's area, say,
  /// past which there is only background.
  final GeoBounds? cameraBounds;

  /// False for a still preview: no panning, zooming or rotating.
  final bool interactive;

  /// Whether two fingers can turn the map.
  final bool rotateGestures;

  /// Whether two fingers can tilt the map.
  final bool tiltGestures;

  /// Whether MapLibre's credit button shows.
  final MapAttribution attribution;

  /// Called with a tappable marker that was tapped.
  final void Function(MapMarker<T> marker)? onMarkerTap;

  /// Called with the point tapped, when it was not a marker.
  final void Function(GeoPosition position)? onMapTap;

  /// Called when the camera comes to rest.
  final void Function(GeoCamera camera)? onCameraIdle;

  /// Called each time the style has loaded and the scene is being installed.
  final VoidCallback? onStyleLoaded;

  /// Told about anything that failed after the map was up — a marker icon
  /// that would not load, an overlay the platform refused. Defaults to
  /// reporting through [FlutterError].
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Shown while the source resolves — while a bundled pack is copied out on
  /// first launch, say.
  final WidgetBuilder? placeholder;

  /// Shown when the source cannot be resolved.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Shown on a platform MapLibre does not run on.
  final WidgetBuilder? unsupportedBuilder;

  /// Gestures the map should win inside a scrolling parent.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  /// Where asset pictures and icons are loaded from.
  final AssetBundle? bundle;

  /// The visitor's position, drawn and followed.
  ///
  /// A floor-plan fix is carried onto the streets through its floor's
  /// georeference — the floor of an entered building or of any in
  /// [buildings].
  final MyLocationController? myLocation;

  /// How the position is drawn.
  final MyLocationStyle myLocationStyle;

  /// The zoom the map comes in to when it starts following the visitor from
  /// further out than zoom 15.
  final double followZoom;

  /// How crowded markers merge, or null to draw every marker on its own.
  final MarkerClustering? clustering;

  /// Past this zoom nothing is clustered. 16 suits stops along streets; a map
  /// with indoor floors, read at 18 and closer, wants it nearer its
  /// `maxZoom`.
  final int clusterMaxZoom;

  /// Called with a tapped cluster. Without it, a tap zooms in to where the
  /// cluster splits.
  final void Function(MarkerCluster<T> cluster)? onClusterTap;

  /// Buildings with floors to open, each drawn as one marker.
  final List<MapBuilding> buildings;

  /// Called with a tapped building. Without it, a tap enters the building:
  /// see `GeoMapController.enterBuilding`.
  final void Function(MapBuilding building)? onBuildingTap;

  /// Whether MapLibre runs where the app is running.
  static bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<GeoMap<T>> createState() => _GeoMapState<T>();
}

class _GeoMapState<T> extends State<GeoMap<T>> {
  GeoMapController? _own;
  late final GeoScene<T> _scene = GeoScene<T>(
    rasterizer: MarkerRasterizer(bundle: widget.bundle),
    bundle: widget.bundle,
    onError: _report,
  );
  ml.MapLibreMapController? _map;
  ResolvedStyle? _style;
  Object? _error;
  int _resolving = 0;
  late int _epoch;
  GeoCamera? _openingCamera;
  GeoFollower? _follower;
  int _centreRequests = 0;
  final Map<int, Offset> _pointers = {};
  Offset? _dragFrom;

  GeoMapController get _controller =>
      widget.controller ?? (_own ??= GeoMapController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    _epoch = _controller.styleEpoch;
    _scene
      ..setMarkers(widget.markers)
      ..setOverlays(widget.overlays)
      ..setBuildings(widget.buildings)
      ..setClustering(widget.clustering, maxZoom: widget.clusterMaxZoom);
    _pushLevels();
    _listenLocation(widget.myLocation);
    if (GeoMap.isSupported) _resolve();
  }

  @override
  void didUpdateWidget(GeoMap<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.controller ?? _own;
    if (!identical(old, _controller)) {
      old?.removeListener(_onController);
      final map = _map;
      if (map != null) {
        old?.detach(map);
        _controller.attach(map, pixelRatio: _pixelRatio);
        if (_scene.isAttached) _controller.markStyleReady();
      }
      if (widget.controller != null && _own != null) {
        _own!.dispose();
        _own = null;
      }
      _controller.addListener(_onController);
      _epoch = _controller.styleEpoch;
      _pushLevels();
    }
    if (!listEquals(oldWidget.markers, widget.markers)) {
      _scene.setMarkers(widget.markers);
    }
    if (!listEquals(oldWidget.overlays, widget.overlays)) {
      _scene.setOverlays(widget.overlays);
    }
    if (!listEquals(oldWidget.buildings, widget.buildings)) {
      _scene.setBuildings(widget.buildings);
    }
    _scene.setClustering(widget.clustering, maxZoom: widget.clusterMaxZoom);
    if (!identical(oldWidget.myLocation, widget.myLocation)) {
      _unlistenLocation(oldWidget.myLocation);
      _listenLocation(widget.myLocation);
    }
    if (oldWidget.source != widget.source && GeoMap.isSupported) _resolve();
  }

  @override
  void dispose() {
    final map = _map;
    if (map != null) {
      map.onFeatureTapped.remove(_onFeatureTapped);
      map.removeListener(_onCamera);
      _controller.detach(map);
    }
    _unlistenLocation(widget.myLocation);
    _follower?.dispose();
    _scene.detach();
    _controller.removeListener(_onController);
    _own?.dispose();
    super.dispose();
  }

  double get _pixelRatio => MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;

  void _onController() {
    if (_controller.styleEpoch != _epoch) {
      _epoch = _controller.styleEpoch;
      _resolve();
    }
    _pushLevels();
  }

  void _pushLevels() {
    final controller = _controller;
    _scene.setLevels(
      controller.levels,
      active: controller.activeLevelId,
      opacity: controller.levelOpacity,
      minZoom: controller.indoorMinZoom,
    );
  }

  Future<void> _resolve() async {
    final token = ++_resolving;
    try {
      final style = await widget.source.resolve();
      if (!mounted || token != _resolving) return;
      if (_style != null && _style!.style != style.style) {
        // MapLibre will load the new style and call back when it has; until
        // then nothing may be sent to a style that is on its way out.
        _scene.detach();
        _controller.markStyleLoading();
      }
      setState(() {
        _style = style;
        _error = null;
      });
    } catch (error, stackTrace) {
      if (!mounted || token != _resolving) return;
      _report(error, stackTrace);
      setState(() => _error = error);
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    final onError = widget.onError;
    if (onError != null) {
      onError(error, stackTrace);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'astronomican',
        context: ErrorDescription('while drawing a GeoMap'),
      ),
    );
  }

  void _onMapCreated(ml.MapLibreMapController map) {
    _map = map;
    _controller.attach(map, pixelRatio: _pixelRatio);
    map.onFeatureTapped.add(_onFeatureTapped);
    map.addListener(_onCamera);
  }

  /// The camera moved: the scene redraws clusters and indoor markers when
  /// the zoom crosses a level.
  void _onCamera() {
    final zoom = _map?.cameraPosition?.zoom;
    if (zoom != null) _scene.setZoom(zoom);
  }

  // The visitor's position.

  void _listenLocation(MyLocationController? location) {
    if (location == null) return;
    location.addListener(_onLocation);
    location.heading.addListener(_onHeading);
    _centreRequests = location.centreRequests;
    _follower ??= GeoFollower(
      camera: _Camera(this),
      followZoom: widget.followZoom,
    );
    // A street map always knows which way north is. Told after this frame:
    // the button listening would otherwise rebuild in the middle of a build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.myLocation, location)) {
        location.orientable = true;
      }
    });
    _onLocation();
  }

  void _unlistenLocation(MyLocationController? location) {
    location?.removeListener(_onLocation);
    location?.heading.removeListener(_onHeading);
  }

  void _onLocation() {
    final location = widget.myLocation;
    final follower = _follower;
    if (location == null || follower == null) return;
    final fix = location.fix;
    _scene.setLocation(
      fix,
      heading: location.heading.value,
      style: widget.myLocationStyle,
    );
    final recentre = location.centreRequests != _centreRequests;
    _centreRequests = location.centreRequests;
    follower
      ..setTarget(fix == null ? null : _placeFix(fix))
      ..setHeading(location.heading.value)
      ..setMode(location.mode, recentre: recentre);
  }

  void _onHeading() {
    final location = widget.myLocation;
    if (location == null) return;
    _scene.setLocation(
      location.fix,
      heading: location.heading.value,
      style: widget.myLocationStyle,
    );
    _follower?.setHeading(location.heading.value);
  }

  /// Where a fix is on the Earth: a GPS position as it is, a floor-plan
  /// position through its floor.
  GeoPosition? _placeFix(LocationFix fix) {
    final position = fix.position;
    if (position is GeoPosition) return position;
    final placed = _controller.locate(position, levelId: fix.levelId);
    if (placed != null) return placed;
    for (final building in widget.buildings) {
      for (final level in building.levels) {
        if (level.id != fix.levelId) continue;
        return level.georeference?.toGeo(position as ImagePosition);
      }
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    _dragFrom = _pointers.length == 1 ? event.position : null;
    _follower?.pointerDown();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final from = _dragFrom;
    if (from == null || _pointers.length != 1) return;
    // One finger dragging past the slop means the visitor wants to look
    // elsewhere; two fingers only zoom, and following carries on.
    if ((event.position - from).distance > kTouchSlop) {
      _dragFrom = null;
      widget.myLocation?.stopFollowing();
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointers.remove(event.pointer) == null) return;
    if (_pointers.isEmpty) _dragFrom = null;
    _follower?.pointerUp();
  }

  void _onStyleLoaded() {
    final map = _map;
    if (map == null || !mounted) return;
    _scene
      ..pixelRatio = _pixelRatio
      ..attach(MapLibreStyleOps(map));
    _controller.markStyleReady();
    widget.onStyleLoaded?.call();
  }

  void _onFeatureTapped(
    Point<double> point,
    ml.LatLng coordinates,
    String id,
    String layerId,
    ml.Annotation? annotation,
  ) {
    final marker = _scene.markerFor(id, layerId);
    if (marker != null) {
      widget.onMarkerTap?.call(marker);
      return;
    }
    final group = _scene.clusterFor(id, layerId);
    if (group != null) {
      final onTap = widget.onClusterTap;
      if (onTap != null) {
        onTap(group.cluster);
        return;
      }
      // Just past the zoom where it splits, so the split is on screen.
      final split = group.expansionLevel + 0.1;
      unawaited(
        _controller.animateTo(
          group.cluster.position,
          zoom: min(split, widget.maxZoom ?? 22),
        ),
      );
      return;
    }
    final building = _scene.buildingFor(id, layerId);
    if (building != null) {
      final onTap = widget.onBuildingTap;
      if (onTap != null) {
        onTap(building);
      } else {
        unawaited(_controller.enterBuilding(building));
      }
    }
  }

  GeoCamera _opening(ResolvedStyle style, Size viewport) {
    final explicit = widget.initialCamera;
    if (explicit != null) return explicit;

    final bounds = widget.initialBounds ?? _markerBounds() ?? style.bounds;
    if (bounds == null) {
      return const GeoCamera(target: GeoPosition(0, 0), zoom: 1);
    }
    return GeoCamera.fit(
      bounds,
      viewport,
      padding: widget.fitPadding,
      minZoom: widget.minZoom ?? 0,
      // A single marker would otherwise open as close as the map goes.
      maxZoom: widget.maxZoom == null
          ? 17
          : (widget.maxZoom! < 17 ? widget.maxZoom! : 17),
    );
  }

  GeoBounds? _markerBounds() {
    final points = [
      for (final marker in widget.markers)
        ?_controller.locate(marker.position, levelId: marker.levelId),
    ];
    return points.isEmpty ? null : GeoBounds.around(points);
  }

  @override
  Widget build(BuildContext context) {
    if (!GeoMap.isSupported) {
      return widget.unsupportedBuilder?.call(context) ??
          const _Notice('Maps are not available on this platform.');
    }
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          const _Notice('The map could not be loaded.');
    }
    final style = _style;
    if (style == null) {
      return widget.placeholder?.call(context) ?? const SizedBox.expand();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.isFinite
            ? constraints.biggest
            : const Size(400, 400);
        final camera = _openingCamera ??= _opening(style, size);
        final cameraBounds = widget.cameraBounds;
        _controller.viewportSize = size;
        _scene.setZoom(_map?.cameraPosition?.zoom ?? camera.zoom);
        final map = ml.MapLibreMap(
          styleString: style.style,
          initialCameraPosition: ml.CameraPosition(
            target: camera.target.toLatLng(),
            zoom: camera.zoom,
            bearing: camera.bearing,
            tilt: camera.tilt,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          minMaxZoomPreference: ml.MinMaxZoomPreference(
            widget.minZoom,
            widget.maxZoom,
          ),
          cameraTargetBounds: cameraBounds == null
              ? ml.CameraTargetBounds.unbounded
              : ml.CameraTargetBounds(cameraBounds.toLatLngBounds()),
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          doubleClickZoomEnabled: widget.interactive,
          rotateGesturesEnabled: widget.interactive && widget.rotateGestures,
          tiltGesturesEnabled: widget.interactive && widget.tiltGestures,
          // A map turned to face the visitor's heading needs a way back to
          // north, and the compass is it.
          compassEnabled: widget.rotateGestures || widget.myLocation != null,
          // Markers are not draggable annotations; with none, MapLibre's
          // annotation managers are not created at all, which is faster on
          // Android and avoids their interference with addImage.
          dragEnabled: false,
          annotationOrder: const [],
          trackCameraPosition: true,
          onMapClick: (point, latLng) =>
              widget.onMapTap?.call(latLng.toGeoPosition()),
          onCameraIdle: widget.onCameraIdle == null
              ? null
              : () {
                  final camera = _controller.camera;
                  if (camera != null) widget.onCameraIdle!(camera);
                },
          logoEnabled: false,
          attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
          // MapLibre has no switch to turn its button off; off the edge of
          // the view is the accepted way to hide it.
          attributionButtonMargins: widget.attribution == MapAttribution.hidden
              ? const Point(-100, -100)
              : null,
          gestureRecognizers: widget.gestureRecognizers,
        );
        if (widget.myLocation == null) return map;
        // The platform view gets the touches either way; this only watches
        // them, to tell a drag from a pinch and to hold the follower off
        // while a finger is down.
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: map,
        );
      },
    );
  }
}

/// The map's camera, as the follower sees it.
class _Camera implements FollowCamera {
  _Camera(this._state);

  final _GeoMapState<Object?> _state;

  @override
  GeoCamera? get camera => _state._controller.camera;

  @override
  Future<void> move(GeoCamera camera, Duration duration) async {
    await _state._map?.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: camera.target.toLatLng(),
          zoom: camera.zoom,
          bearing: camera.bearing,
          tilt: camera.tilt,
        ),
      ),
      duration: duration,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      ),
    ),
  );
}
