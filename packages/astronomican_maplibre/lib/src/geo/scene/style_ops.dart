import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';

/// The handful of style operations a `GeoMap` performs, in its own terms.
///
/// A seam between the scene — which decides *what* the style should hold —
/// and MapLibre's controller, which only exists on a device. Tests put a
/// recording fake here and check the scene's decisions without a map.
@internal
abstract interface class StyleOps {
  /// Registers [png] as the icon [name].
  Future<void> addImage(String name, Uint8List png);

  /// Adds a GeoJSON source [id] holding [data].
  Future<void> addGeoJsonSource(String id, Map<String, Object?> data);

  /// Replaces the data of GeoJSON source [id].
  Future<void> setGeoJsonSource(String id, Map<String, Object?> data);

  /// Adds a symbol layer [layerId] drawing the markers in [sourceId], shown
  /// through [filter]. Only an [interactive] layer reports taps.
  Future<void> addMarkerLayer(
    String sourceId,
    String layerId, {
    required Object filter,
    required bool interactive,
  });

  /// Replaces the filter of [layerId].
  Future<void> setFilter(String layerId, Object filter);

  /// Adds a circle layer [layerId] drawing the accuracy circle of the
  /// position in [sourceId], in [style], under [belowLayerId].
  Future<void> addAccuracyLayer(
    String sourceId,
    String layerId, {
    required MyLocationStyle style,
    String? belowLayerId,
  });

  /// Adds a symbol layer [layerId] drawing the position in [sourceId] as its
  /// icon, turned to its heading on the map.
  Future<void> addPuckLayer(String sourceId, String layerId);

  /// Adds an image source [id] showing [bytes] pinned to [quad].
  Future<void> addImageSource(String id, Uint8List bytes, GeoQuad quad);

  /// Changes the picture or the corners of image source [id].
  Future<void> updateImageSource(String id, {Uint8List? bytes, GeoQuad? quad});

  /// Adds a raster layer [layerId] drawing [sourceId].
  Future<void> addRasterLayer(
    String sourceId,
    String layerId, {
    required double opacity,
    required bool visible,
    String? belowLayerId,
    double? minZoom,
  });

  /// Sets a raster layer's opacity and visibility together.
  Future<void> setRasterLayer(
    String layerId, {
    required double opacity,
    required bool visible,
  });

  /// Removes the layer [id].
  Future<void> removeLayer(String id);

  /// Removes the source [id].
  Future<void> removeSource(String id);
}
