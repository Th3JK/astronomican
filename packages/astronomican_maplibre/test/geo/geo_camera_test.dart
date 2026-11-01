import 'dart:convert';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoCamera.fit', () {
    test('a whole-world square fits a 512 square at zoom 0', () {
      final camera = GeoCamera.fit(
        const GeoBounds(
          south: -WebMercator.maxLatitude,
          west: -180,
          north: WebMercator.maxLatitude,
          east: 180,
        ),
        const Size(512, 512),
      );
      expect(camera.zoom, closeTo(0, 1e-9));
      expect(camera.target.latitude, closeTo(0, 1e-9));
    });

    test('doubling the screen adds one zoom level', () {
      const town = GeoBounds(
        south: 49.24,
        west: 13.87,
        north: 49.27,
        east: 13.93,
      );
      final small = GeoCamera.fit(town, const Size(400, 400));
      final large = GeoCamera.fit(town, const Size(800, 800));
      expect(large.zoom - small.zoom, closeTo(1, 1e-9));
      expect(small.target.longitude, closeTo(13.90, 1e-9));
    });

    test('padding moves the target away from the padded side', () {
      const town = GeoBounds(
        south: 49.24,
        west: 13.87,
        north: 49.27,
        east: 13.93,
      );
      final plain = GeoCamera.fit(town, const Size(400, 800));
      final sheet = GeoCamera.fit(
        town,
        const Size(400, 800),
        padding: const EdgeInsets.only(bottom: 300),
      );
      // With a sheet over the bottom, the camera looks further south so the
      // town sits in the visible top part.
      expect(sheet.target.latitude, lessThan(plain.target.latitude));
    });

    test('a single point opens at the maximum zoom', () {
      const point = GeoBounds(
        south: 49.26,
        west: 13.9,
        north: 49.26,
        east: 13.9,
      );
      expect(GeoCamera.fit(point, const Size(400, 400), maxZoom: 17).zoom, 17);
    });
  });

  group('styles', () {
    test('RasterStyle expands subdomains and keeps the attribution', () {
      final style =
          jsonDecode(
                RasterStyle.build(
                  urlTemplate: 'https://{s}.tile.example.org/{z}/{x}/{y}.png',
                  attribution: '© OpenStreetMap contributors',
                ),
              )
              as Map<String, Object?>;
      final raster = (style['sources']! as Map)['raster'] as Map;
      expect(raster['tiles'], hasLength(3));
      expect(raster['attribution'], '© OpenStreetMap contributors');
      expect((style['layers']! as List).last, containsPair('type', 'raster'));
    });

    test('BlankStyle is a background and nothing else', () {
      final style =
          jsonDecode(BlankStyle.build(background: const Color(0x80FF0000)))
              as Map<String, Object?>;
      expect(style['sources'], isEmpty);
      final paint = ((style['layers']! as List).single as Map)['paint'] as Map;
      expect(paint['background-color'], 'rgba(255,0,0,0.502)');
    });
  });
}
