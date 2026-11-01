import 'dart:typed_data';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_maplibre/src/geo/scene/style_ops.dart';

/// A [StyleOps] that writes down what it was asked to do.
class RecordingStyleOps implements StyleOps {
  /// Every call, as a short description.
  final List<String> calls = [];

  /// The last data given to each GeoJSON source.
  final Map<String, Map<String, Object?>> sources = {};

  /// The last filter of each layer.
  final Map<String, Object> filters = {};

  /// The last opacity and visibility of each raster layer.
  final Map<String, (double, bool)> rasters = {};

  /// The corners each image source was last given.
  final Map<String, GeoQuad> quads = {};

  /// Calls whose description starts with [prefix].
  List<String> starting(String prefix) =>
      calls.where((c) => c.startsWith(prefix)).toList();

  @override
  Future<void> addImage(String name, Uint8List png) async =>
      calls.add('addImage $name');

  @override
  Future<void> addGeoJsonSource(String id, Map<String, Object?> data) async {
    calls.add('addGeoJsonSource $id');
    sources[id] = data;
  }

  @override
  Future<void> setGeoJsonSource(String id, Map<String, Object?> data) async {
    calls.add('setGeoJsonSource $id');
    sources[id] = data;
  }

  @override
  Future<void> addMarkerLayer(
    String sourceId,
    String layerId, {
    required Object filter,
    required bool interactive,
  }) async {
    calls.add('addMarkerLayer $layerId interactive=$interactive');
    filters[layerId] = filter;
  }

  @override
  Future<void> setFilter(String layerId, Object filter) async {
    calls.add('setFilter $layerId');
    filters[layerId] = filter;
  }

  @override
  Future<void> addAccuracyLayer(
    String sourceId,
    String layerId, {
    required MyLocationStyle style,
    String? belowLayerId,
  }) async => calls.add('addAccuracyLayer $layerId below=$belowLayerId');

  @override
  Future<void> addPuckLayer(String sourceId, String layerId) async =>
      calls.add('addPuckLayer $layerId');

  @override
  Future<void> addImageSource(String id, Uint8List bytes, GeoQuad quad) async {
    calls.add('addImageSource $id');
    quads[id] = quad;
  }

  @override
  Future<void> updateImageSource(
    String id, {
    Uint8List? bytes,
    GeoQuad? quad,
  }) async {
    calls.add(
      'updateImageSource $id bytes=${bytes != null} quad=${quad != null}',
    );
    if (quad != null) quads[id] = quad;
  }

  @override
  Future<void> addRasterLayer(
    String sourceId,
    String layerId, {
    required double opacity,
    required bool visible,
    String? belowLayerId,
    double? minZoom,
  }) async {
    calls.add('addRasterLayer $layerId below=$belowLayerId');
    rasters[layerId] = (opacity, visible);
  }

  @override
  Future<void> setRasterLayer(
    String layerId, {
    required double opacity,
    required bool visible,
  }) async {
    calls.add('setRasterLayer $layerId opacity=$opacity visible=$visible');
    rasters[layerId] = (opacity, visible);
  }

  @override
  Future<void> removeLayer(String id) async => calls.add('removeLayer $id');

  @override
  Future<void> removeSource(String id) async => calls.add('removeSource $id');
}
