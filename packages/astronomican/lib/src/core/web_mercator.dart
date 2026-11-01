import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'map_position.dart';

/// The projection every web map draws in, normalised to a unit square.
///
/// `(0, 0)` is the north-west corner of the world at about 85.05° N, 180° W,
/// and `(1, 1)` its south-east corner. Anything that has to agree with the
/// picture MapLibre draws — an image laid over the map, a camera fitted to a
/// rectangle — is worked out here rather than in degrees, because degrees of
/// latitude are not evenly spaced on screen and Mercator units are.
abstract final class WebMercator {
  /// The latitude at which the projection's square ends.
  static const double maxLatitude = 85.0511287798066;

  /// Where [position] falls in the unit square.
  static Offset project(GeoPosition position) {
    final lat = position.latitude.clamp(-maxLatitude, maxLatitude);
    final phi = lat * math.pi / 180;
    final x = (position.longitude + 180) / 360;
    final y = (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2;
    return Offset(x, y);
  }

  /// The point on the Earth at [point] in the unit square.
  static GeoPosition unproject(Offset point) {
    final longitude = point.dx * 360 - 180;
    final n = math.pi * (1 - 2 * point.dy);
    final latitude =
        math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
    return GeoPosition(latitude, longitude);
  }
}
