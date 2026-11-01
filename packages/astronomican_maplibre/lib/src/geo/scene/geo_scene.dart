import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:astronomican/astronomican.dart';
import '../geo_image_overlay.dart';
import 'location_features.dart';
import 'marker_features.dart';
import 'style_ops.dart';

/// Keeps a MapLibre style holding what a `GeoMap` was asked to show.
///
/// MapLibre forgets everything added at runtime whenever its style loads —
/// which happens on first show, on every change of source, and on Android
/// whenever the activity is recreated. So nothing is added once and trusted
/// to stay: each style load is a new **generation**, and [attach] installs the
/// whole scene into it from scratch. Changes in between are diffed against
/// what this generation has been given, and only the difference is sent.
///
/// Every operation runs on one queue, in order, and checks before each call
/// that its generation is still current. A style that reloads halfway through
/// an install simply abandons it; the new generation's install follows.
///
/// Three things depend on the zoom, which the map reports through [setZoom]:
/// which clusters are drawn (they are worked out in Dart for each whole zoom
/// level), and — below the indoor zoom — whether the floors' markers show or
/// the building they belong to stands in their place.
@internal
final class GeoScene<T> {
  /// A scene drawing its icons through [rasterizer].
  GeoScene({required this.rasterizer, this.bundle, this.onError});

  /// The GeoJSON source holding the markers, clusters and buildings.
  static const String markerSource = 'astronomican-markers';

  /// The layer of markers that report taps.
  static const String tappableLayer = 'astronomican-markers';

  /// The layer of markers that only mark.
  static const String staticLayer = 'astronomican-markers-static';

  /// The layer of buildings.
  static const String buildingLayer = 'astronomican-buildings';

  /// The layer of clusters.
  static const String clusterLayer = 'astronomican-clusters';

  /// The GeoJSON source holding the visitor's position.
  static const String locationSource = 'astronomican-location';

  /// The circle of the position's accuracy, under the markers.
  static const String accuracyLayer = 'astronomican-location-accuracy';

  /// The dot and its cone, over everything.
  static const String puckLayer = 'astronomican-location-puck';

  /// Paints marker icons.
  final MarkerRasterizer rasterizer;

  /// Where asset pictures are loaded from.
  final AssetBundle? bundle;

  /// Told about anything that failed, instead of it being thrown into a void.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// The display's pixel ratio, which icons are painted at.
  double pixelRatio = 1;

  StyleOps? _ops;
  int _generation = 0;
  Future<void> _queue = Future.value();
  bool _syncQueued = false;
  bool _locationQueued = false;

  List<MapMarker<T>> _markers = const [];
  final Map<String, MapMarker<T>> _byId = {};
  List<GeoImageOverlay> _overlays = const [];
  Map<String, MapLevel> _levels = const {};
  String? _activeLevel;
  double _levelOpacity = 1;
  double? _indoorMinZoom;
  List<MapBuilding> _buildings = const [];
  Map<String, MapBuilding> _buildingsById = const {};
  MarkerClustering? _clustering;
  int _clusterMaxZoom = 16;
  double? _zoom;
  LocationFix? _fix;
  double? _heading;
  MyLocationStyle _locationStyle = const MyLocationStyle();

  // What the current generation holds.
  final Set<String> _icons = {};
  final Map<String, _Picture> _pictures = {};
  final Map<String, String> _filters = {};
  String? _features;
  bool _installed = false;
  bool _locationInstalled = false;
  String? _location;

  final Map<MapImage, Future<Uint8List>> _bytes = {};
  final Set<String> _unplaced = {};

  MarkerClusterSet<T>? _clusterSet;
  List<MapMarker<T>>? _clusteredMarkers;
  List<Offset>? _clusteredWorld;
  (MarkerClustering, int)? _clusteredWith;
  Map<String, GroupedMarkers<T>> _groups = const {};

  /// Whether a style is attached.
  bool get isAttached => _ops != null;

  /// Completes when every queued operation has run.
  Future<void> get idle => _queue;

  /// The level whose markers show: the active one, unless the map is zoomed
  /// out past the indoor zoom, where the floors are not drawn either.
  String? get visibleLevel {
    final active = _activeLevel;
    final min = _indoorMinZoom;
    final zoom = _zoom;
    if (active == null) return null;
    if (min != null && zoom != null && zoom < min) return null;
    return active;
  }

  /// The whole zoom level the clusters are worked out for.
  int get clusterZoom {
    final zoom = _zoom;
    if (zoom == null) return 0;
    return zoom.floor().clamp(0, _clusterMaxZoom + 1);
  }

  /// Starts a new generation on [ops], a freshly loaded style, and installs
  /// everything into it.
  void attach(StyleOps ops) {
    _ops = ops;
    final generation = ++_generation;
    _icons.clear();
    _pictures.clear();
    _filters.clear();
    _features = null;
    _installed = false;
    _locationInstalled = false;
    _location = null;
    _syncQueued = false;
    _locationQueued = false;
    _enqueue(generation, _install);
  }

  /// Forgets the style: it is gone, or about to be replaced.
  void detach() {
    _ops = null;
    _generation++;
  }

  /// Shows [markers].
  void setMarkers(List<MapMarker<T>> markers) {
    _markers = markers;
    _byId
      ..clear()
      ..addEntries(markers.map((m) => MapEntry(m.id, m)));
    _scheduleSync();
  }

  /// Shows [overlays].
  void setOverlays(List<GeoImageOverlay> overlays) {
    _overlays = overlays;
    _scheduleSync();
  }

  /// Shows [levels], [active] among them, at [opacity], from [minZoom].
  void setLevels(
    List<MapLevel> levels, {
    required String? active,
    double opacity = 1,
    double? minZoom,
  }) {
    _levels = {for (final level in levels) level.id: level};
    _activeLevel = active;
    _levelOpacity = opacity;
    _indoorMinZoom = minZoom;
    _scheduleSync();
  }

  /// Shows [buildings], each as one marker while its floors are not shown.
  /// Markers on their floors are placed through those floors'
  /// georeferences, whether the building has been entered or not.
  void setBuildings(List<MapBuilding> buildings) {
    _buildings = buildings;
    _buildingsById = {for (final b in buildings) b.id: b};
    _scheduleSync();
  }

  /// Clusters crowded markers by [clustering], up to zoom [maxZoom]; past it
  /// every marker stands on its own. Null draws every marker on its own.
  void setClustering(MarkerClustering? clustering, {int maxZoom = 16}) {
    if (clustering == _clustering && maxZoom == _clusterMaxZoom) return;
    _clustering = clustering;
    _clusterMaxZoom = maxZoom;
    _scheduleSync();
  }

  /// The camera's zoom, as it moves.
  void setZoom(double zoom) {
    final before = (clusterZoom, visibleLevel);
    _zoom = zoom;
    if ((clusterZoom, visibleLevel) != before) _scheduleSync();
  }

  /// Shows the visitor at [fix], facing [heading], drawn in [style]; null
  /// hides them.
  void setLocation(
    LocationFix? fix, {
    double? heading,
    MyLocationStyle style = const MyLocationStyle(),
  }) {
    _fix = fix;
    _heading = heading;
    _locationStyle = style;
    _scheduleLocation();
  }

  /// The marker a tap on feature [featureId] of layer [layerId] was on, if
  /// it was a tappable marker.
  MapMarker<T>? markerFor(String featureId, String layerId) =>
      layerId == tappableLayer ? _byId[featureId] : null;

  /// The cluster a tap on feature [featureId] of layer [layerId] was on.
  GroupedMarkers<T>? clusterFor(String featureId, String layerId) =>
      layerId == clusterLayer ? _groups[featureId] : null;

  /// The building a tap on feature [featureId] of layer [layerId] was on.
  MapBuilding? buildingFor(String featureId, String layerId) =>
      layerId == buildingLayer ? _buildingsById[featureId] : null;

  void _scheduleSync() {
    if (_ops == null || _syncQueued) return;
    _syncQueued = true;
    _enqueue(_generation, (ops, generation) {
      _syncQueued = false;
      return _sync(ops, generation);
    });
  }

  void _scheduleLocation() {
    if (_ops == null || _locationQueued) return;
    _locationQueued = true;
    _enqueue(_generation, (ops, generation) {
      _locationQueued = false;
      return _syncLocation(ops, generation);
    });
  }

  void _enqueue(
    int generation,
    Future<void> Function(StyleOps ops, int generation) step,
  ) {
    _queue = _queue.then((_) async {
      final ops = _ops;
      if (ops == null || generation != _generation) {
        _syncQueued = false;
        _locationQueued = false;
        return;
      }
      try {
        await step(ops, generation);
      } catch (error, stackTrace) {
        if (generation == _generation) onError?.call(error, stackTrace);
      }
    });
  }

  bool _stale(int generation) => generation != _generation || _ops == null;

  Future<void> _install(StyleOps ops, int generation) async {
    // Pictures first, so the markers added after them draw on top.
    for (final MapEntry(key: layer, value: picture)
        in _wantedPictures().entries) {
      if (_stale(generation)) return;
      await _addPicture(ops, layer, picture, below: null);
    }
    if (_stale(generation)) return;

    final features = await _buildFeatures(ops, generation);
    if (features == null || _stale(generation)) return;
    await ops.addGeoJsonSource(markerSource, features.$1);
    _features = features.$2;

    final filters = _wantedFilters();
    for (final MapEntry(key: layer, value: filter) in filters.entries) {
      if (_stale(generation)) return;
      await ops.addMarkerLayer(
        markerSource,
        layer,
        filter: filter,
        interactive: layer != staticLayer,
      );
      _filters[layer] = jsonEncode(filter);
    }
    _installed = true;
    if (_fix != null) await _syncLocation(ops, generation);
    await _warmClusterIcons(ops, generation);
  }

  Future<void> _sync(StyleOps ops, int generation) async {
    if (!_installed) return;

    final wanted = _wantedPictures();
    for (final layer in _pictures.keys.toList()) {
      if (wanted.containsKey(layer)) continue;
      if (_stale(generation)) return;
      final gone = _pictures.remove(layer)!;
      await ops.removeLayer(layer);
      await ops.removeSource(gone.source);
    }
    for (final MapEntry(key: layer, value: picture) in wanted.entries) {
      if (_stale(generation)) return;
      final applied = _pictures[layer];
      if (applied == null) {
        await _addPicture(ops, layer, picture, below: _lowestLayer);
        continue;
      }
      if (applied.minZoom != picture.minZoom) {
        await ops.removeLayer(layer);
        await ops.removeSource(applied.source);
        _pictures.remove(layer);
        await _addPicture(ops, layer, picture, below: _lowestLayer);
        continue;
      }
      if (applied.image != picture.image || applied.quad != picture.quad) {
        await ops.updateImageSource(
          picture.source,
          bytes: applied.image != picture.image
              ? await _load(picture.image)
              : null,
          quad: applied.quad != picture.quad ? picture.quad : null,
        );
      }
      if (applied.opacity != picture.opacity ||
          applied.visible != picture.visible) {
        await ops.setRasterLayer(
          layer,
          opacity: picture.opacity,
          visible: picture.visible,
        );
      }
      _pictures[layer] = picture;
    }

    // Filters before data: while a level changes, for a moment something
    // may be missing, but nothing from the other floor is ever shown.
    for (final MapEntry(key: layer, value: filter)
        in _wantedFilters().entries) {
      if (_stale(generation)) return;
      final text = jsonEncode(filter);
      if (_filters[layer] == text) continue;
      await ops.setFilter(layer, filter);
      _filters[layer] = text;
    }

    if (_stale(generation)) return;
    final features = await _buildFeatures(ops, generation);
    if (features == null || _stale(generation)) return;
    if (features.$2 != _features) {
      await ops.setGeoJsonSource(markerSource, features.$1);
      _features = features.$2;
    }
    await _warmClusterIcons(ops, generation);
  }

  /// Where a picture added later goes: under the accuracy circle when there
  /// is one, and under every marker in any case.
  String get _lowestLayer => _locationInstalled ? accuracyLayer : staticLayer;

  Map<String, Object> _wantedFilters() {
    final level = visibleLevel;
    String? hidden;
    if (level != null) {
      for (final building in _buildings) {
        if (building.levels.any((l) => l.id == level)) hidden = building.id;
      }
    }
    return {
      staticLayer: MarkerFeatures.layerFilter(level, tappable: false),
      tappableLayer: MarkerFeatures.layerFilter(level, tappable: true),
      buildingLayer: MarkerFeatures.buildingFilter(hidden),
      clusterLayer: MarkerFeatures.clusterFilter(level),
    };
  }

  /// Every level a marker may name: the floors of every building, and the
  /// levels the map is showing.
  Map<String, MapLevel> get _placement => {
    for (final building in _buildings)
      for (final level in building.levels) level.id: level,
    ..._levels,
  };

  /// The markers, clusters and buildings as GeoJSON and as text to compare,
  /// with every icon they use registered first — a feature naming an icon
  /// the style does not have yet is drawn as nothing and not redrawn when
  /// the icon arrives.
  Future<(Map<String, Object?>, String)?> _buildFeatures(
    StyleOps ops,
    int generation,
  ) async {
    final placement = _placement;
    final features = <Map<String, Object?>>[];
    final icons = <String, MarkerIcon>{};

    var drawn = _markers;
    var groups = <GroupedMarkers<T>>[];
    final clustering = _clustering;
    if (clustering != null) {
      final level = visibleLevel;
      final candidates = <MapMarker<T>>[];
      final world = <Offset>[];
      for (final m in _markers) {
        if (!m.clusterable || (m.levelId != null && m.levelId != level)) {
          continue;
        }
        final at = MarkerFeatures.locate(m, placement);
        if (at == null) continue;
        candidates.add(m);
        world.add(WebMercator.project(at));
      }
      final items = _clusterSetFor(
        candidates,
        world,
        clustering,
      ).itemsAt(clusterZoom);
      final alone = {
        for (final item in items)
          if (item is LoneMarker<T>) item.marker.id,
      };
      final merged = {
        for (final m in candidates)
          if (!alone.contains(m.id)) m.id,
      };
      drawn = [
        for (final m in _markers)
          if (!merged.contains(m.id)) m,
      ];
      groups = items.whereType<GroupedMarkers<T>>().toList();
    }

    for (final marker in drawn) {
      final at = MarkerFeatures.locate(marker, placement);
      if (at == null) {
        if (_unplaced.add(marker.id)) {
          onError?.call(
            StateError(
              'Marker "${marker.id}" is at an image position, so its level '
              '"${marker.levelId}" must be one of the map\'s levels and be '
              'georeferenced.',
            ),
            StackTrace.current,
          );
        }
        continue;
      }
      features.add(MarkerFeatures.feature(marker, at));
      icons[marker.icon.key] = marker.icon;
    }

    _groups = {for (final g in groups) g.cluster.id: g};
    for (final group in groups) {
      final icon = clustering!.iconFor(group.cluster.count);
      features.add(
        MarkerFeatures.clusterFeature(
          group.cluster,
          group.cluster.position as GeoPosition,
          icon,
        ),
      );
      icons[icon.key] = icon;
    }

    for (final building in _buildings) {
      final at = building.position;
      if (at == null) {
        if (_unplaced.add('building:${building.id}')) {
          onError?.call(
            StateError(
              'Building "${building.id}" needs a position or a georeferenced '
              'floor to stand on the map.',
            ),
            StackTrace.current,
          );
        }
        continue;
      }
      features.add(MarkerFeatures.buildingFeature(building, at));
      icons[building.icon.key] = building.icon;
    }

    if (!await _register(ops, generation, icons.values)) return null;
    final collection = MarkerFeatures.collection(features);
    return (collection, jsonEncode(collection));
  }

  MarkerClusterSet<T> _clusterSetFor(
    List<MapMarker<T>> markers,
    List<Offset> world,
    MarkerClustering clustering,
  ) {
    final set = _clusterSet;
    final using = (clustering, _clusterMaxZoom);
    if (set != null &&
        _clusteredWith == using &&
        listEquals(_clusteredMarkers, markers) &&
        listEquals(_clusteredWorld, world)) {
      return set;
    }
    _clusteredMarkers = markers;
    _clusteredWorld = world;
    _clusteredWith = using;
    return _clusterSet = MarkerClusterSet<T>(
      markers: markers,
      world: world,
      // A world unit is the whole Mercator square: MapLibre draws it 512
      // pixels across at zoom 0, twice that at each zoom level up.
      scales: [
        for (var z = 0; z <= _clusterMaxZoom + 1; z++)
          512 * math.pow(2, z).toDouble(),
      ],
      options: clustering,
      toPosition: WebMercator.unproject,
    );
  }

  /// Registers the icon of every cluster size the markers can make, once the
  /// map is showing, so zooming never waits on painting one.
  Future<void> _warmClusterIcons(StyleOps ops, int generation) async {
    final clustering = _clustering;
    final set = _clusterSet;
    if (clustering == null || set == null) return;
    await _register(ops, generation, set.counts.map(clustering.iconFor));
  }

  /// Registers [icons] not yet in this generation's style. False when the
  /// style went away meanwhile.
  Future<bool> _register(
    StyleOps ops,
    int generation,
    Iterable<MarkerIcon> icons,
  ) async {
    for (final icon in icons) {
      if (_icons.contains(icon.key)) continue;
      try {
        final png = await rasterizer.rasterize(icon, pixelRatio: pixelRatio);
        if (_stale(generation)) return false;
        await ops.addImage(MarkerFeatures.iconName(icon.key), png);
        _icons.add(icon.key);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    }
    return !_stale(generation);
  }

  Future<void> _syncLocation(StyleOps ops, int generation) async {
    if (!_installed) return;
    final fix = _fix;
    if (fix == null && !_locationInstalled) return;
    final at = fix == null
        ? null
        : MarkerFeatures.place(
            fix.position,
            fix.levelId ?? visibleLevel,
            _placement,
          );
    final icon = _locationStyle.puckIcon(cone: _heading != null);
    if (!await _register(ops, generation, [icon])) return;
    final data = LocationFeatures.collection(
      at,
      icon: icon,
      accuracy: fix?.accuracy,
      heading: _heading,
    );
    final text = jsonEncode(data);
    if (!_locationInstalled) {
      await ops.addGeoJsonSource(locationSource, data);
      if (_stale(generation)) return;
      await ops.addAccuracyLayer(
        locationSource,
        accuracyLayer,
        style: _locationStyle,
        belowLayerId: staticLayer,
      );
      if (_stale(generation)) return;
      await ops.addPuckLayer(locationSource, puckLayer);
      _locationInstalled = true;
      _location = text;
      return;
    }
    if (text == _location) return;
    await ops.setGeoJsonSource(locationSource, data);
    _location = text;
  }

  Map<String, _Picture> _wantedPictures() {
    final wanted = <String, _Picture>{};
    for (final overlay in _overlays) {
      wanted['astro-overlay-${overlay.id}'] = _Picture(
        source: 'astro-overlay-src-${overlay.id}',
        image: overlay.image,
        quad: overlay.quad,
        opacity: overlay.opacity,
        visible: true,
        minZoom: overlay.minZoom,
      );
    }
    for (final level in _levels.values) {
      final georeference = level.georeference;
      if (georeference == null) continue;
      wanted['astro-level-${level.id}'] = _Picture(
        source: 'astro-level-src-${level.id}',
        image: level.image,
        quad: georeference.quad(level.size),
        opacity: _levelOpacity,
        visible: level.id == _activeLevel,
        minZoom: _indoorMinZoom,
      );
    }
    return wanted;
  }

  Future<void> _addPicture(
    StyleOps ops,
    String layer,
    _Picture picture, {
    required String? below,
  }) async {
    final bytes = await _load(picture.image);
    await ops.addImageSource(picture.source, bytes, picture.quad);
    await ops.addRasterLayer(
      picture.source,
      layer,
      opacity: picture.opacity,
      visible: picture.visible,
      belowLayerId: below,
      minZoom: picture.minZoom,
    );
    _pictures[layer] = picture;
  }

  /// A picture's bytes, kept: every style reload needs them again, and an
  /// indoor map switching floors should not decode a file per tap.
  Future<Uint8List> _load(MapImage image) async {
    final pending = _bytes.putIfAbsent(
      image,
      () => image.bytes(bundle: bundle),
    );
    try {
      return await pending;
    } catch (_) {
      if (identical(_bytes[image], pending)) _bytes.remove(image)?.ignore();
      rethrow;
    }
  }
}

@immutable
final class _Picture {
  const _Picture({
    required this.source,
    required this.image,
    required this.quad,
    required this.opacity,
    required this.visible,
    required this.minZoom,
  });

  final String source;
  final MapImage image;
  final GeoQuad quad;
  final double opacity;
  final bool visible;
  final double? minZoom;
}
