import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';

import 'marker_features.dart';

/// Turns the visitor's position into the GeoJSON the location layers draw.
///
/// The accuracy circle is a circle layer whose radius follows the zoom: the
/// feature carries its radius in pixels at zoom 0, `r0`, and the layer
/// doubles it with each zoom level, so a new fix changes only the data and
/// never the layer.
@internal
abstract final class LocationFeatures {
  /// Metres per pixel at zoom 0 on the equator, for MapLibre's 512-pixel
  /// tiles.
  static const double metresPerPixelAtZoom0 = 78271.51696402048;

  /// The radius, in pixels at zoom 0, of a circle [metres] across at
  /// [latitude].
  static double r0(double metres, double latitude) =>
      metres / (metresPerPixelAtZoom0 * math.cos(latitude * math.pi / 180));

  /// The puck at [at], drawn with [icon] and turned to [heading] degrees
  /// clockwise from north, inside an accuracy circle of [accuracy] metres.
  static Map<String, Object?> collection(
    GeoPosition? at, {
    required MarkerIcon icon,
    double? accuracy,
    double? heading,
  }) => MarkerFeatures.collection([
    if (at != null)
      {
        'type': 'Feature',
        'id': 'my-location',
        'geometry': {
          'type': 'Point',
          'coordinates': [at.longitude, at.latitude],
        },
        'properties': {
          'icon': MarkerFeatures.iconName(icon.key),
          'heading': heading ?? 0,
          'r0': accuracy == null ? 0 : r0(accuracy, at.latitude),
        },
      },
  ]);
}
