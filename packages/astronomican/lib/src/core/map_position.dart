import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

/// Where something stands on a map.
///
/// There are two kinds of place, and they are not interchangeable: a spot on
/// the Earth, and a spot on a picture. Which one a marker uses decides how it
/// can be drawn —
///
/// * A [GeoPosition] draws on a `GeoMap` directly, and on an image map or an
///   indoor level only when that level is georeferenced.
/// * An [ImagePosition] draws on an image map directly, and on a `GeoMap` only
///   when it names a georeferenced level to be converted through.
///
/// Sealed, so a `switch` over a position is checked to cover both.
sealed class MapPosition {
  const MapPosition();
}

/// A point on the Earth, in WGS 84 degrees.
@immutable
final class GeoPosition extends MapPosition {
  /// A point at [latitude], [longitude].
  const GeoPosition(this.latitude, this.longitude);

  /// Degrees north of the equator; negative is south.
  final double latitude;

  /// Degrees east of Greenwich; negative is west.
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPosition &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPosition($latitude, $longitude)';
}

/// A point on a picture, in the picture's **logical frame**.
///
/// The frame is whatever size the level declares, not the pixel size of the
/// file: a plan authored at 2664 × 2048 can ship as a 1400-pixel-tall webp and
/// every position written against the original still lands in the same room.
/// See `MapLevel.size`.
@immutable
final class ImagePosition extends MapPosition {
  /// A point [x] units from the left edge and [y] units down from the top.
  const ImagePosition(this.x, this.y);

  /// The same point as an [ImagePosition].
  ImagePosition.fromOffset(Offset offset) : this(offset.dx, offset.dy);

  /// Units from the left edge of the frame.
  final double x;

  /// Units down from the top edge of the frame.
  final double y;

  /// The same point as an [Offset], for drawing.
  Offset toOffset() => Offset(x, y);

  @override
  bool operator ==(Object other) =>
      other is ImagePosition && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'ImagePosition($x, $y)';
}
