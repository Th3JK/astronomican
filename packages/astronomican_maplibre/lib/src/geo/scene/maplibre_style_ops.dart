import 'dart:typed_data';

import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';
import '../maplibre_convert.dart';
import '../style/style_color.dart';
import 'style_ops.dart';

/// [StyleOps] on a live MapLibre map.
@internal
final class MapLibreStyleOps implements StyleOps {
  /// Operations on [controller]'s current style.
  MapLibreStyleOps(this.controller);

  /// The map.
  final ml.MapLibreMapController controller;

  @override
  Future<void> addImage(String name, Uint8List png) =>
      controller.addImage(name, png);

  @override
  Future<void> addGeoJsonSource(String id, Map<String, Object?> data) =>
      controller.addGeoJsonSource(id, data);

  @override
  Future<void> setGeoJsonSource(String id, Map<String, Object?> data) =>
      controller.setGeoJsonSource(id, data);

  @override
  Future<void> addMarkerLayer(
    String sourceId,
    String layerId, {
    required Object filter,
    required bool interactive,
  }) => controller.addSymbolLayer(
    sourceId,
    layerId,
    const ml.SymbolLayerProperties(
      iconImage: ['get', 'icon'],
      iconAnchor: ['get', 'anchor'],
      // Every marker is drawn. MapLibre hides symbols that collide, which is
      // right for place names and wrong for a tour's stops: squeezed into a
      // preview, half of them would simply vanish.
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      symbolSortKey: ['get', 'z'],
    ),
    filter: filter,
    enableInteraction: interactive,
  );

  @override
  Future<void> setFilter(String layerId, Object filter) =>
      controller.setFilter(layerId, filter);

  @override
  Future<void> addAccuracyLayer(
    String sourceId,
    String layerId, {
    required MyLocationStyle style,
    String? belowLayerId,
  }) => controller.addCircleLayer(
    sourceId,
    layerId,
    ml.CircleLayerProperties(
      // r0 is the radius at zoom 0; each zoom level doubles it.
      circleRadius: const [
        'interpolate',
        ['exponential', 2],
        ['zoom'],
        0,
        ['get', 'r0'],
        24,
        [
          '*',
          ['get', 'r0'],
          16777216,
        ],
      ],
      circleColor: cssColor(style.accuracyColor),
      circleStrokeColor: cssColor(style.accuracyBorderColor),
      circleStrokeWidth: 1,
      circlePitchAlignment: 'map',
    ),
    belowLayerId: belowLayerId,
    enableInteraction: false,
  );

  @override
  Future<void> addPuckLayer(String sourceId, String layerId) =>
      controller.addSymbolLayer(
        sourceId,
        layerId,
        const ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconRotate: ['get', 'heading'],
          // Turned with the map, so the cone points the way the visitor
          // faces on the ground whichever way the map is turned.
          iconRotationAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: false,
      );

  @override
  Future<void> addImageSource(String id, Uint8List bytes, GeoQuad quad) =>
      controller.addImageSource(id, bytes, quad.toLatLngQuad());

  @override
  Future<void> updateImageSource(
    String id, {
    Uint8List? bytes,
    GeoQuad? quad,
  }) => controller.updateImageSource(id, bytes, quad?.toLatLngQuad());

  @override
  Future<void> addRasterLayer(
    String sourceId,
    String layerId, {
    required double opacity,
    required bool visible,
    String? belowLayerId,
    double? minZoom,
  }) => controller.addRasterLayer(
    sourceId,
    layerId,
    ml.RasterLayerProperties(
      rasterOpacity: opacity,
      visibility: visible ? 'visible' : 'none',
    ),
    belowLayerId: belowLayerId,
    minzoom: minZoom,
  );

  // Both at once: setLayerProperties resets whatever it is not given, so
  // setting the opacity alone would make a hidden floor visible again.
  @override
  Future<void> setRasterLayer(
    String layerId, {
    required double opacity,
    required bool visible,
  }) => controller.setLayerProperties(
    layerId,
    ml.RasterLayerProperties(
      rasterOpacity: opacity,
      visibility: visible ? 'visible' : 'none',
    ),
  );

  @override
  Future<void> removeLayer(String id) => controller.removeLayer(id);

  @override
  Future<void> removeSource(String id) => controller.removeSource(id);
}
