import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'map_position.dart';

/// A rectangle of latitude and longitude.
///
/// Used for fitting the camera, for restricting it, and as the area of an
/// offline region. Does not cross the antimeridian: nothing a tour app maps
/// straddles it, and supporting it would make every consumer of [west] and
/// [east] think about wrapping.
@immutable
final class GeoBounds {
  /// A rectangle from its four edges, in degrees.
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  }) : assert(south <= north, 'south must not be above north'),
       assert(west <= east, 'west must not be east of east');

  /// The smallest rectangle holding every one of [positions].
  ///
  /// Throws [ArgumentError] when there are none: an empty rectangle has no
  /// sensible centre, and a camera fitted to it would fly to 0, 0.
  factory GeoBounds.around(Iterable<GeoPosition> positions) {
    final iterator = positions.iterator;
    if (!iterator.moveNext()) {
      throw ArgumentError.value(positions, 'positions', 'must not be empty');
    }
    var south = iterator.current.latitude;
    var north = south;
    var west = iterator.current.longitude;
    var east = west;
    while (iterator.moveNext()) {
      final p = iterator.current;
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    return GeoBounds(south: south, west: west, north: north, east: east);
  }

  /// Southern edge, in degrees latitude.
  final double south;

  /// Western edge, in degrees longitude.
  final double west;

  /// Northern edge, in degrees latitude.
  final double north;

  /// Eastern edge, in degrees longitude.
  final double east;

  /// The south-west corner.
  GeoPosition get southwest => GeoPosition(south, west);

  /// The north-east corner.
  GeoPosition get northeast => GeoPosition(north, east);

  /// The middle, by plain average. Exact enough for anything a city wide; the
  /// camera works in Mercator anyway and refits on the first frame.
  GeoPosition get center => GeoPosition((south + north) / 2, (west + east) / 2);

  /// Whether [position] lies inside or on the edge.
  bool contains(GeoPosition position) =>
      position.latitude >= south &&
      position.latitude <= north &&
      position.longitude >= west &&
      position.longitude <= east;

  /// The smallest rectangle holding both this and [other].
  GeoBounds union(GeoBounds other) => GeoBounds(
    south: math.min(south, other.south),
    west: math.min(west, other.west),
    north: math.max(north, other.north),
    east: math.max(east, other.east),
  );

  /// This rectangle grown by [fraction] of its own size on every side.
  ///
  /// A fraction of the size rather than a fixed margin, because the same
  /// breathing room reads right whether the rectangle is a building or a town.
  GeoBounds inflate(double fraction) {
    final dLat = (north - south) * fraction;
    final dLng = (east - west) * fraction;
    return GeoBounds(
      south: math.max(-90, south - dLat),
      west: math.max(-180, west - dLng),
      north: math.min(90, north + dLat),
      east: math.min(180, east + dLng),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.south == south &&
      other.west == west &&
      other.north == north &&
      other.east == east;

  @override
  int get hashCode => Object.hash(south, west, north, east);

  @override
  String toString() => 'GeoBounds(s: $south, w: $west, n: $north, e: $east)';
}
