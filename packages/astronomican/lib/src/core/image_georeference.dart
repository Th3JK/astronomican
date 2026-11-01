import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:meta/meta.dart';

import 'geo_bounds.dart';
import 'map_position.dart';
import 'web_mercator.dart';

/// Pins a picture to the Earth, so a point on the one can be found on the
/// other.
///
/// This is what lets a floor plan sit on a street map in the right place, and
/// what lets a marker authored as "pixel 870, 1585 on the ground floor" be drawn
/// on that street map, or a GPS fix be drawn on the plan.
///
/// The mapping is **affine in Web Mercator**: the picture may be moved, scaled,
/// rotated and sheared, but its straight lines stay straight and its parallel
/// lines stay parallel. That is not a simplification of convenience. MapLibre
/// draws an image source as two triangles, so any mapping richer than affine
/// would put the markers in one place and the picture's pixels in another. By
/// always deriving the picture's corners from this mapping ([quad]), the
/// picture and everything placed through it agree by construction.
///
/// Coordinates on the picture side are in the level's logical frame (see
/// `MapLevel.size`), not in the file's pixels.
@immutable
final class ImageGeoreference {
  const ImageGeoreference._(
    this._a,
    this._b,
    this._c,
    this._d,
    this._e,
    this._f,
  );

  /// Fitted through three or more pairs of a point on the picture and where
  /// that point is on the Earth.
  ///
  /// This is the calibration most people can actually do: find three corners of
  /// the building on the plan and on a satellite view. Three points are fitted
  /// exactly; more are fitted by least squares, which averages out the error in
  /// each one.
  ///
  /// Throws [ArgumentError] with fewer than three points, or when the points
  /// lie on one line on either side — a line says nothing about which way the
  /// picture is turned.
  factory ImageGeoreference.fromControlPoints(
    List<(ImagePosition, GeoPosition)> points,
  ) {
    if (points.length < 3) {
      throw ArgumentError.value(
        points.length,
        'points',
        'at least three control points are needed',
      );
    }

    final n = points.length;
    final projected = [for (final (_, geo) in points) WebMercator.project(geo)];

    // Centred first. Mercator coordinates for one building agree to five
    // decimal places, and summing their squares uncentred loses most of the
    // digits the fit depends on.
    var um = 0.0, vm = 0.0, xm = 0.0, ym = 0.0;
    for (var i = 0; i < n; i++) {
      um += points[i].$1.x;
      vm += points[i].$1.y;
      xm += projected[i].dx;
      ym += projected[i].dy;
    }
    um /= n;
    vm /= n;
    xm /= n;
    ym /= n;

    var suu = 0.0, suv = 0.0, svv = 0.0;
    var sux = 0.0, svx = 0.0, suy = 0.0, svy = 0.0;
    for (var i = 0; i < n; i++) {
      final u = points[i].$1.x - um;
      final v = points[i].$1.y - vm;
      final x = projected[i].dx - xm;
      final y = projected[i].dy - ym;
      suu += u * u;
      suv += u * v;
      svv += v * v;
      sux += u * x;
      svx += v * x;
      suy += u * y;
      svy += v * y;
    }

    final det = suu * svv - suv * suv;
    if (suu == 0 || svv == 0 || det <= 1e-9 * suu * svv) {
      throw ArgumentError.value(
        points,
        'points',
        'the points on the picture lie on one line',
      );
    }

    final a = (sux * svv - svx * suv) / det;
    final b = (svx * suu - sux * suv) / det;
    final d = (suy * svv - svy * suv) / det;
    final e = (svy * suu - suy * suv) / det;
    final c = xm - a * um - b * vm;
    final f = ym - d * um - e * vm;

    final linear = a * e - b * d;
    final scale = math.sqrt((a * a + b * b + d * d + e * e) / 2);
    if (scale == 0 || linear.abs() <= 1e-9 * scale * scale) {
      throw ArgumentError.value(
        points,
        'points',
        'the points on the Earth lie on one line',
      );
    }

    return ImageGeoreference._(a, b, c, d, e, f);
  }

  /// A picture drawn north-up, filling the rectangle between [north], [south],
  /// [east] and [west].
  ///
  /// The simplest case, and the one most tile-cutting tools export. Like
  /// MapLibre itself, the picture is stretched evenly in Mercator, so its
  /// vertical scale follows the map's rather than degrees of latitude.
  factory ImageGeoreference.fromBounds({
    required double north,
    required double south,
    required double east,
    required double west,
    required Size imageSize,
  }) {
    return ImageGeoreference.fromControlPoints([
      (const ImagePosition(0, 0), GeoPosition(north, west)),
      (ImagePosition(imageSize.width, 0), GeoPosition(north, east)),
      (ImagePosition(0, imageSize.height), GeoPosition(south, west)),
    ]);
  }

  /// The picture's four corners, as MapLibre's image source takes them.
  ///
  /// Accepted only when the corners form a parallelogram in Mercator, give or
  /// take [tolerance] of the picture's diagonal. Four arbitrary corners describe
  /// a perspective warp, which MapLibre would draw as two differently skewed
  /// triangles — so a marker placed through this reference would drift off the
  /// picture towards the middle. Refusing that up front is kinder than a plan
  /// that is slightly wrong in a way nobody can see until they walk it.
  ///
  /// Throws [ArgumentError] when the corners are not close enough.
  factory ImageGeoreference.fromCorners({
    required GeoPosition topLeft,
    required GeoPosition topRight,
    required GeoPosition bottomRight,
    required GeoPosition bottomLeft,
    required Size imageSize,
    double tolerance = 0.005,
  }) {
    final w = imageSize.width;
    final h = imageSize.height;
    final points = [
      (const ImagePosition(0, 0), topLeft),
      (ImagePosition(w, 0), topRight),
      (ImagePosition(w, h), bottomRight),
      (ImagePosition(0, h), bottomLeft),
    ];
    final fitted = ImageGeoreference.fromControlPoints(points);

    final diagonal =
        (WebMercator.project(bottomRight) - WebMercator.project(topLeft))
            .distance;
    final residual = fitted.maxResidual(points);
    if (residual > tolerance * diagonal) {
      throw ArgumentError(
        'The corners are not a parallelogram (off by '
        '${(residual / diagonal * 100).toStringAsFixed(2)}% of the diagonal). '
        'MapLibre cannot draw a perspective warp faithfully; use '
        'ImageGeoreference.fromControlPoints instead.',
      );
    }
    return fitted;
  }

  // Web Mercator (unit square) = [a b; d e] · (u, v) + (c, f).
  final double _a;
  final double _b;
  final double _c;
  final double _d;
  final double _e;
  final double _f;

  /// Where the point [position] on the picture is on the Earth.
  GeoPosition toGeo(ImagePosition position) =>
      WebMercator.unproject(_forward(position.x, position.y));

  /// Where [position] on the Earth falls on the picture. May be outside the
  /// picture's frame: a GPS fix in the car park is still somewhere.
  ImagePosition toImage(GeoPosition position) {
    final m = WebMercator.project(position);
    final dx = m.dx - _c;
    final dy = m.dy - _f;
    final det = _a * _e - _b * _d;
    return ImagePosition((_e * dx - _b * dy) / det, (-_d * dx + _a * dy) / det);
  }

  /// The corners of a picture [imageSize] across, placed through this
  /// reference.
  GeoQuad quad(Size imageSize) => GeoQuad(
    topLeft: toGeo(const ImagePosition(0, 0)),
    topRight: toGeo(ImagePosition(imageSize.width, 0)),
    bottomRight: toGeo(ImagePosition(imageSize.width, imageSize.height)),
    bottomLeft: toGeo(ImagePosition(0, imageSize.height)),
  );

  /// The largest distance, in Mercator units, between where one of [points]
  /// says a spot is and where this reference puts it.
  ///
  /// Zero for three control points. For more, it is how badly the calibration
  /// disagrees with itself — worth checking before trusting a plan.
  double maxResidual(List<(ImagePosition, GeoPosition)> points) {
    var worst = 0.0;
    for (final (image, geo) in points) {
      final error =
          (_forward(image.x, image.y) - WebMercator.project(geo)).distance;
      worst = math.max(worst, error);
    }
    return worst;
  }

  Offset _forward(double u, double v) =>
      Offset(_a * u + _b * v + _c, _d * u + _e * v + _f);

  @override
  bool operator ==(Object other) =>
      other is ImageGeoreference &&
      other._a == _a &&
      other._b == _b &&
      other._c == _c &&
      other._d == _d &&
      other._e == _e &&
      other._f == _f;

  @override
  int get hashCode => Object.hash(_a, _b, _c, _d, _e, _f);
}

/// Four corners of a picture on the Earth, in the order MapLibre takes them.
@immutable
final class GeoQuad {
  /// A quad from its corners.
  const GeoQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Where the picture's top-left corner is.
  final GeoPosition topLeft;

  /// Where the picture's top-right corner is.
  final GeoPosition topRight;

  /// Where the picture's bottom-right corner is.
  final GeoPosition bottomRight;

  /// Where the picture's bottom-left corner is.
  final GeoPosition bottomLeft;

  /// All four, clockwise from the top left.
  List<GeoPosition> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  /// The rectangle the picture covers.
  GeoBounds get bounds => GeoBounds.around(corners);

  @override
  bool operator ==(Object other) =>
      other is GeoQuad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}
