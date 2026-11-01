import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'package:astronomican/astronomican.dart';
import 'geo_camera.dart';
import 'maplibre_convert.dart';

/// Drives a `GeoMap`: its camera, and which indoor level is laid over it.
///
/// Levels here are floors drawn on the streets through their georeference —
/// the indoor half of a map that is otherwise outdoor. Markers placed on a
/// level (by `levelId`) show only while that level does, and markers given in
/// a level's image coordinates are carried onto the streets through it.
///
/// Camera methods need the map to be on screen with its style loaded; before
/// that they do nothing. [ready] completes when it is.
class GeoMapController extends ChangeNotifier implements LevelController {
  /// A controller over indoor [levels], showing [initialLevelId] or the first
  /// one.
  ///
  /// [indoorMinZoom] hides the floors when zoomed out past it, and
  /// [levelOpacity] lets the streets show through them.
  GeoMapController({
    List<MapLevel> levels = const [],
    String? initialLevelId,
    this.indoorMinZoom,
    this.levelOpacity = 1,
  }) : _levels = _checked(levels),
       _activeId = _pick(levels, initialLevelId);

  /// Below this zoom the floors are not drawn.
  final double? indoorMinZoom;

  /// How opaque the floors are drawn.
  final double levelOpacity;

  List<MapLevel> _levels;
  String? _activeId;
  MapBuilding? _building;
  Size? _viewportSize;
  ml.MapLibreMapController? _map;
  double _pixelRatio = 1;
  bool _styleReady = false;
  int _styleEpoch = 0;
  var _ready = _ReadySignal();

  @override
  List<MapLevel> get levels => _levels;

  @override
  String? get activeLevelId => _activeId;

  @override
  MapLevel? get activeLevel {
    for (final level in _levels) {
      if (level.id == _activeId) return level;
    }
    return null;
  }

  @override
  void showLevel(String id) {
    if (id == _activeId || !_levels.any((level) => level.id == id)) return;
    _activeId = id;
    notifyListeners();
  }

  /// Shows no level: the map is outdoors, and only markers on no level show.
  /// A building that was entered is left.
  void clearLevel() {
    if (_activeId == null && _building == null) return;
    _activeId = null;
    _building = null;
    notifyListeners();
  }

  /// Swaps in another building's floors.
  void setLevels(List<MapLevel> levels, {String? initialLevelId}) {
    _levels = _checked(levels);
    _activeId = _pick(levels, initialLevelId);
    _building = null;
    notifyListeners();
  }

  /// The building whose floors are laid over the streets, when one was
  /// entered with [enterBuilding].
  MapBuilding? get activeBuilding => _building;

  /// Goes into [building]: its floors become the levels, [levelId] or its
  /// own first floor shows, and the camera frames it close enough for the
  /// floors to be drawn.
  ///
  /// What a tap on a building's marker does by default. Its marker gives way
  /// to its floors, and comes back when the visitor leaves with
  /// [leaveBuilding], goes outside with [clearLevel], or zooms out past the
  /// indoor zoom.
  Future<void> enterBuilding(
    MapBuilding building, {
    String? levelId,
    EdgeInsets padding = const EdgeInsets.all(48),
    Duration? duration,
  }) async {
    setLevels(
      building.levels,
      initialLevelId: levelId ?? building.initialLevelId,
    );
    _building = building;
    notifyListeners();

    final map = _map;
    final size = _viewportSize;
    final footprint = building.footprint;
    final floor = indoorMinZoom ?? 17;
    if (map == null) return;
    if (footprint == null || size == null || size.isEmpty) {
      final at = building.position;
      if (at == null) return;
      final zoom = camera?.zoom ?? floor;
      return animateTo(at, zoom: zoom < floor ? floor : zoom);
    }
    final fitted = GeoCamera.fit(
      footprint,
      size,
      padding: padding,
      minZoom: floor,
      maxZoom: 21,
    );
    await map.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: fitted.target.toLatLng(),
          zoom: fitted.zoom,
          bearing: camera?.bearing ?? 0,
        ),
      ),
      duration: duration,
    );
  }

  /// Leaves the building entered with [enterBuilding]: the map is outdoors
  /// again, and the building's marker stands in for its floors.
  void leaveBuilding() => clearLevel();

  /// Called by the map with its size, which framing a building needs.
  @internal
  set viewportSize(Size size) => _viewportSize = size;

  /// Whether the map is on screen with its style loaded.
  bool get isReady => _map != null && _styleReady;

  /// Completes once the map is ready for camera moves.
  Future<void> get ready => _ready.future;

  /// Where the camera is, once the map is up.
  GeoCamera? get camera {
    final position = _map?.cameraPosition;
    if (position == null) return null;
    return GeoCamera(
      target: position.target.toGeoPosition(),
      zoom: position.zoom,
      bearing: position.bearing,
      tilt: position.tilt,
    );
  }

  /// Bumped by [reloadStyle]; the map re-resolves its source when it moves.
  @internal
  int get styleEpoch => _styleEpoch;

  /// Moves the camera to [position], at [zoom] or the current zoom.
  ///
  /// An [ImagePosition] is read on [levelId]'s level, or the active one, and
  /// carried onto the map through its georeference.
  Future<void> animateTo(
    MapPosition position, {
    String? levelId,
    double? zoom,
    Duration? duration,
  }) async {
    final map = _map;
    final target = locate(position, levelId: levelId);
    if (map == null || target == null) return;
    await map.animateCamera(
      zoom == null
          ? ml.CameraUpdate.newLatLng(target.toLatLng())
          : ml.CameraUpdate.newLatLngZoom(target.toLatLng(), zoom),
      duration: duration,
    );
  }

  /// Moves the camera without animating.
  Future<void> jumpTo(GeoCamera camera) async {
    await _map?.moveCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: camera.target.toLatLng(),
          zoom: camera.zoom,
          bearing: camera.bearing,
          tilt: camera.tilt,
        ),
      ),
    );
  }

  /// Frames [bounds], leaving [padding] around them.
  Future<void> fitBounds(
    GeoBounds bounds, {
    EdgeInsets padding = const EdgeInsets.all(32),
    Duration? duration,
  }) async {
    final map = _map;
    if (map == null) return;
    await map.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        bounds.toLatLngBounds(),
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      ),
      duration: duration,
    );
  }

  /// Frames every one of [positions]; a single one is centred at [zoom].
  Future<void> fitPositions(
    Iterable<MapPosition> positions, {
    EdgeInsets padding = const EdgeInsets.all(32),
    double zoom = 17,
    Duration? duration,
  }) async {
    final points = [for (final position in positions) ?locate(position)];
    if (points.isEmpty) return;
    if (points.length == 1) {
      return animateTo(points.single, zoom: zoom, duration: duration);
    }
    final bounds = GeoBounds.around(points);
    if (bounds.south == bounds.north && bounds.west == bounds.east) {
      return animateTo(points.first, zoom: zoom, duration: duration);
    }
    return fitBounds(bounds, padding: padding, duration: duration);
  }

  /// Zooms in by [delta] levels, or out for a negative one.
  Future<void> zoomBy(double delta, {Duration? duration}) async {
    await _map?.animateCamera(
      ml.CameraUpdate.zoomBy(delta),
      duration: duration,
    );
  }

  /// Where [position] is drawn, in logical pixels from the map's top left.
  Future<Offset?> toScreen(MapPosition position, {String? levelId}) async {
    final map = _map;
    final target = locate(position, levelId: levelId);
    if (map == null || target == null) return null;
    final point = await map.toScreenLocation(target.toLatLng());
    // Android answers in physical pixels, iOS in points.
    final scale = _nativePixels ? _pixelRatio : 1.0;
    return Offset(point.x / scale, point.y / scale);
  }

  /// The point on the Earth drawn at [offset], in logical pixels from the
  /// map's top left.
  Future<GeoPosition?> fromScreen(Offset offset) async {
    final map = _map;
    if (map == null) return null;
    final scale = _nativePixels ? _pixelRatio : 1.0;
    final latLng = await map.toLatLng(
      Point<double>(offset.dx * scale, offset.dy * scale),
    );
    return latLng.toGeoPosition();
  }

  /// Resolves the map's source again and reloads its style — after a newer
  /// pack has been installed, say. Markers, overlays and levels come back by
  /// themselves.
  void reloadStyle() {
    _styleEpoch++;
    notifyListeners();
  }

  /// Where [position] is on the Earth: itself, or an image position carried
  /// through [levelId]'s level (or the active one's) georeference.
  GeoPosition? locate(MapPosition position, {String? levelId}) {
    switch (position) {
      case GeoPosition():
        return position;
      case ImagePosition():
        final id = levelId ?? _activeId;
        for (final level in _levels) {
          if (level.id == id) return level.georeference?.toGeo(position);
        }
        return null;
    }
  }

  /// Called by the map when its native view exists.
  @internal
  void attach(ml.MapLibreMapController map, {required double pixelRatio}) {
    _map = map;
    _pixelRatio = pixelRatio;
  }

  /// Called by the map each time its style has loaded.
  @internal
  void markStyleReady() {
    _styleReady = true;
    _ready.complete();
  }

  /// Called by the map as its style is replaced.
  @internal
  void markStyleLoading() {
    _styleReady = false;
    if (_ready.isCompleted) _ready = _ReadySignal();
  }

  /// Called by the map as it goes away.
  @internal
  void detach(ml.MapLibreMapController map) {
    if (!identical(_map, map)) return;
    _map = null;
    _styleReady = false;
    if (_ready.isCompleted) _ready = _ReadySignal();
  }

  static bool get _nativePixels =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static List<MapLevel> _checked(List<MapLevel> levels) {
    final ids = <String>{};
    for (final level in levels) {
      if (!ids.add(level.id)) {
        throw ArgumentError.value(level.id, 'levels', 'duplicate level id');
      }
    }
    return List.unmodifiable(levels);
  }

  static String? _pick(List<MapLevel> levels, String? id) {
    if (levels.isEmpty) return null;
    if (id != null && levels.any((level) => level.id == id)) return id;
    return levels.first.id;
  }
}

/// Completes once, however often it is told to: every style load marks the
/// map ready, and only the first after a reset counts.
class _ReadySignal {
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
