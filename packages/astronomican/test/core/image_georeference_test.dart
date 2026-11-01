import 'dart:math' as math;
import 'dart:ui';

import 'package:astronomican/astronomican.dart';
import 'package:flutter_test/flutter_test.dart';

/// About 1 cm at Strakonice's latitude, in degrees.
const _cm = 1e-7;

void main() {
  group('WebMercator', () {
    test('puts Greenwich on the equator in the middle', () {
      final p = WebMercator.project(const GeoPosition(0, 0));
      expect(p.dx, closeTo(0.5, 1e-12));
      expect(p.dy, closeTo(0.5, 1e-12));
    });

    test('round-trips', () {
      for (final g in const [
        GeoPosition(49.2587, 13.9027),
        GeoPosition(-33.8688, 151.2093),
        GeoPosition(64.1466, -21.9426),
      ]) {
        final back = WebMercator.unproject(WebMercator.project(g));
        expect(back.latitude, closeTo(g.latitude, 1e-9));
        expect(back.longitude, closeTo(g.longitude, 1e-9));
      }
    });

    test('clamps the poles to the square', () {
      expect(
        WebMercator.project(const GeoPosition(90, 0)).dy,
        closeTo(0, 1e-9),
      );
    });
  });

  group('ImageGeoreference', () {
    const size = Size(2000, 1000);
    const north = 49.262, south = 49.258, west = 13.900, east = 13.906;

    test('fromBounds puts the corners on the edges', () {
      final ref = ImageGeoreference.fromBounds(
        north: north,
        south: south,
        east: east,
        west: west,
        imageSize: size,
      );
      final quad = ref.quad(size);
      expect(quad.topLeft.latitude, closeTo(north, _cm));
      expect(quad.topLeft.longitude, closeTo(west, _cm));
      expect(quad.bottomRight.latitude, closeTo(south, _cm));
      expect(quad.bottomRight.longitude, closeTo(east, _cm));
      expect(quad.topRight.latitude, closeTo(north, _cm));
      expect(quad.bottomLeft.longitude, closeTo(west, _cm));
    });

    test('three control points are fitted exactly', () {
      final points = [
        (const ImagePosition(100, 80), const GeoPosition(49.2611, 13.9012)),
        (const ImagePosition(1800, 120), const GeoPosition(49.2613, 13.9061)),
        (const ImagePosition(900, 950), const GeoPosition(49.2586, 13.9039)),
      ];
      final ref = ImageGeoreference.fromControlPoints(points);
      expect(ref.maxResidual(points), lessThan(1e-15));
      for (final (image, geo) in points) {
        final g = ref.toGeo(image);
        expect(g.latitude, closeTo(geo.latitude, _cm));
        expect(g.longitude, closeTo(geo.longitude, _cm));
      }
    });

    test('many noisy points recover a rotated plan by least squares', () {
      // A plan turned 30° and scaled, as a real calibration would find it.
      final truth = _rotated(30);
      final random = math.Random(7);
      final points = <(ImagePosition, GeoPosition)>[];
      for (var i = 0; i < 12; i++) {
        final image = ImagePosition(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        );
        final geo = truth.toGeo(image);
        // ±20 cm of error on every point.
        points.add((
          image,
          GeoPosition(
            geo.latitude + (random.nextDouble() - 0.5) * 4e-6,
            geo.longitude + (random.nextDouble() - 0.5) * 6e-6,
          ),
        ));
      }
      final fitted = ImageGeoreference.fromControlPoints(points);
      final probe = fitted.toGeo(const ImagePosition(1000, 500));
      final expected = truth.toGeo(const ImagePosition(1000, 500));
      expect(probe.latitude, closeTo(expected.latitude, 2e-6));
      expect(probe.longitude, closeTo(expected.longitude, 2e-6));
    });

    test('toImage undoes toGeo', () {
      final ref = _rotated(-12);
      for (final p in const [
        ImagePosition(0, 0),
        ImagePosition(1234.5, 678.9),
        ImagePosition(-50, 1200),
      ]) {
        final back = ref.toImage(ref.toGeo(p));
        expect(back.x, closeTo(p.x, 1e-6));
        expect(back.y, closeTo(p.y, 1e-6));
      }
    });

    test('rejects fewer than three points', () {
      expect(
        () => ImageGeoreference.fromControlPoints([
          (const ImagePosition(0, 0), const GeoPosition(49, 13)),
          (const ImagePosition(1, 1), const GeoPosition(49.1, 13.1)),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects points on one line on the picture', () {
      expect(
        () => ImageGeoreference.fromControlPoints([
          (const ImagePosition(0, 0), const GeoPosition(49.0, 13.0)),
          (const ImagePosition(10, 10), const GeoPosition(49.1, 13.0)),
          (const ImagePosition(20, 20), const GeoPosition(49.1, 13.1)),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects points on one line on the Earth', () {
      expect(
        () => ImageGeoreference.fromControlPoints([
          // One parallel: a straight line in Mercator, unlike a diagonal in
          // degrees, whose latitude steps are not evenly spaced there.
          (const ImagePosition(0, 0), const GeoPosition(49.0, 13.0)),
          (const ImagePosition(10, 0), const GeoPosition(49.0, 13.1)),
          (const ImagePosition(0, 10), const GeoPosition(49.0, 13.2)),
        ]),
        throwsArgumentError,
      );
    });

    test('fromCorners accepts the corners of a rotated rectangle', () {
      final truth = _rotated(20);
      final quad = truth.quad(size);
      final ref = ImageGeoreference.fromCorners(
        topLeft: quad.topLeft,
        topRight: quad.topRight,
        bottomRight: quad.bottomRight,
        bottomLeft: quad.bottomLeft,
        imageSize: size,
      );
      final p = ref.toGeo(const ImagePosition(500, 500));
      final e = truth.toGeo(const ImagePosition(500, 500));
      expect(p.latitude, closeTo(e.latitude, _cm));
      expect(p.longitude, closeTo(e.longitude, _cm));
    });

    test('fromCorners refuses a perspective warp', () {
      expect(
        () => ImageGeoreference.fromCorners(
          topLeft: const GeoPosition(north, west),
          topRight: const GeoPosition(north, east),
          bottomRight: const GeoPosition(south, east + 0.002),
          bottomLeft: const GeoPosition(south, west),
          imageSize: size,
        ),
        throwsArgumentError,
      );
    });

    test('the quad agrees with toGeo at every corner', () {
      final ref = _rotated(45);
      final quad = ref.quad(size);
      expect(
        quad.bottomRight,
        ref.toGeo(ImagePosition(size.width, size.height)),
      );
      expect(quad.corners, hasLength(4));
      expect(
        quad.bounds.contains(ref.toGeo(const ImagePosition(1000, 500))),
        isTrue,
      );
    });
  });

  group('GeoBounds', () {
    test('around finds the extremes', () {
      final b = GeoBounds.around(const [
        GeoPosition(49.25, 13.91),
        GeoPosition(49.27, 13.88),
        GeoPosition(49.26, 13.93),
      ]);
      expect(
        b,
        const GeoBounds(south: 49.25, west: 13.88, north: 49.27, east: 13.93),
      );
      expect(b.center.latitude, closeTo(49.26, 1e-12));
    });

    test('around refuses nothing', () {
      expect(() => GeoBounds.around(const []), throwsArgumentError);
    });

    test('inflate grows every side', () {
      const b = GeoBounds(south: 0, west: 0, north: 10, east: 20);
      expect(
        b.inflate(0.1),
        const GeoBounds(south: -1, west: -2, north: 11, east: 22),
      );
    });
  });
}

/// A 2000 × 1000 plan turned [degrees] about its middle, about 400 m across,
/// in Strakonice.
ImageGeoreference _rotated(double degrees) {
  const centre = GeoPosition(49.2600, 13.9030);
  final c = WebMercator.project(centre);
  const unitsPerImagePixel = 1.1e-8; // ≈ 0.2 m per pixel at this latitude
  final t = degrees * math.pi / 180;
  GeoPosition at(double u, double v) {
    final du = (u - 1000) * unitsPerImagePixel;
    final dv = (v - 500) * unitsPerImagePixel;
    return WebMercator.unproject(
      Offset(
        c.dx + du * math.cos(t) - dv * math.sin(t),
        c.dy + du * math.sin(t) + dv * math.cos(t),
      ),
    );
  }

  return ImageGeoreference.fromControlPoints([
    (const ImagePosition(0, 0), at(0, 0)),
    (const ImagePosition(2000, 0), at(2000, 0)),
    (const ImagePosition(0, 1000), at(0, 1000)),
  ]);
}
