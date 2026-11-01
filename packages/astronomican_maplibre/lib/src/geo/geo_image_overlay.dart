import 'dart:ui' show Size;

import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';

/// A picture laid over a `GeoMap`, pinned to the Earth: a historic town plan,
/// an artist's map of a park, a festival site drawn over the streets.
///
/// Drawn under the markers and over the base map. For floors of a building,
/// which switch with a level selector, use levels on the `GeoMapController`
/// instead; this is for pictures that are always there.
@immutable
final class GeoImageOverlay {
  /// [image], [imageSize] across in its logical frame, placed by
  /// [georeference].
  const GeoImageOverlay({
    required this.id,
    required this.image,
    required this.georeference,
    required this.imageSize,
    this.opacity = 1,
    this.minZoom,
  });

  /// The overlay drawn by [level], which must be georeferenced.
  factory GeoImageOverlay.fromLevel(MapLevel level, {double opacity = 1}) {
    final georeference = level.georeference;
    if (georeference == null) {
      throw ArgumentError.value(level, 'level', 'has no georeference');
    }
    return GeoImageOverlay(
      id: 'level-${level.id}',
      image: level.image,
      georeference: georeference,
      imageSize: level.size,
      opacity: opacity,
    );
  }

  /// Unique among a map's overlays.
  final String id;

  /// The picture.
  final MapImage image;

  /// Where it is.
  final ImageGeoreference georeference;

  /// Its logical frame; the picture is stretched over it.
  final Size imageSize;

  /// From 0, invisible, to 1.
  final double opacity;

  /// Hidden below this zoom — a building's plan means nothing from across
  /// town.
  final double? minZoom;

  /// The corners MapLibre pins the picture to.
  GeoQuad get quad => georeference.quad(imageSize);

  @override
  bool operator ==(Object other) =>
      other is GeoImageOverlay &&
      other.id == id &&
      other.image == image &&
      other.georeference == georeference &&
      other.imageSize == imageSize &&
      other.opacity == opacity &&
      other.minZoom == minZoom;

  @override
  int get hashCode =>
      Object.hash(id, image, georeference, imageSize, opacity, minZoom);
}
