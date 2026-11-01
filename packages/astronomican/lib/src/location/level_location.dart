import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import '../core/map_level.dart';
import '../core/map_position.dart';
import 'location_fix.dart';

/// Where the visitor stands on one level of a picture, and which way the
/// picture points.
@internal
abstract final class LevelLocation {
  /// Where [fix] falls on [level], in its logical frame; null when it cannot
  /// be placed there — a GPS fix on a picture with no georeference, or a
  /// floor-plan fix on another floor.
  static Offset? place(LocationFix fix, MapLevel level) {
    switch (fix.position) {
      case final GeoPosition geo:
        return level.georeference?.toImage(geo).toOffset();
      case final ImagePosition image:
        final on = fix.levelId;
        return on == null || on == level.id ? image.toOffset() : null;
    }
  }

  /// Which way true north points on [level] near [at], in radians clockwise
  /// from the top of the picture; null when the picture has neither a
  /// georeference nor a bearing.
  ///
  /// Found by stepping north on the Earth and seeing where that lands on the
  /// picture, which also accounts for a plan that is sheared or mirrored.
  static double? north(MapLevel level, Offset at) {
    final reference = level.georeference;
    if (reference != null) {
      final here = reference.toGeo(ImagePosition.fromOffset(at));
      final step = reference
          .toImage(GeoPosition(here.latitude + 1e-4, here.longitude))
          .toOffset();
      final d = step - at;
      if (d.distance == 0) return null;
      return math.atan2(d.dx, -d.dy);
    }
    final bearing = level.bearing;
    if (bearing != null) return -bearing * math.pi / 180;
    return null;
  }

  /// How many units of [level]'s frame make a metre near [at]; null without
  /// a georeference.
  static double? unitsPerMetre(MapLevel level, Offset at) {
    final reference = level.georeference;
    if (reference == null) return null;
    final here = reference.toGeo(ImagePosition.fromOffset(at));
    const metres = 10.0;
    final east =
        metres / (111320 * math.cos(here.latitude * math.pi / 180).abs());
    if (!east.isFinite) return null;
    final there = reference
        .toImage(GeoPosition(here.latitude, here.longitude + east))
        .toOffset();
    return (there - at).distance / metres;
  }
}
