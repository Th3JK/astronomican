import 'dart:ui';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_maplibre/astronomican_maplibre_testing.dart';
import 'package:astronomican_maplibre/src/geo/scene/geo_scene.dart';
import 'package:astronomican_maplibre/src/geo/scene/marker_features.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recording_style_ops.dart';

const _dot = MarkerIcon.dot(diameter: 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GeoScene<String> scene;
  late RecordingStyleOps ops;
  late List<Object> errors;

  final plan = ImageGeoreference.fromBounds(
    north: 49.2615,
    south: 49.2605,
    east: 13.9045,
    west: 13.9025,
    imageSize: const Size(2000, 1000),
  );

  MapLevel floor(String id) => MapLevel(
    id: id,
    label: id,
    image: MapImage.memory(transparentPng),
    size: const Size(2000, 1000),
    georeference: plan,
  );

  final museum = MapBuilding(
    id: 'museum',
    name: 'Museum',
    levels: [floor('g'), floor('1')],
  );

  // Three stops a few metres apart, and one across town.
  final stops = [
    for (var i = 0; i < 3; i++)
      MapMarker<String>(
        id: 's$i',
        position: GeoPosition(49.2610, 13.9030 + i * 0.0001),
        icon: _dot,
      ),
    const MapMarker<String>(
      id: 'far',
      position: GeoPosition(49.30, 13.95),
      icon: _dot,
    ),
  ];

  List<Map<String, Object?>> features() => [
    for (final f in ops.sources[GeoScene.markerSource]!['features']! as List)
      f as Map<String, Object?>,
  ];

  List<String> kinds(String kind) => [
    for (final f in features())
      if ((f['properties']! as Map)['kind'] == kind) f['id']! as String,
  ];

  setUp(() {
    errors = [];
    scene = GeoScene<String>(
      rasterizer: MarkerRasterizer(),
      onError: (e, _) => errors.add(e),
    );
    ops = RecordingStyleOps();
  });

  group('clusters', () {
    test('merge crowded markers zoomed out, and split zoomed in', () async {
      scene
        ..setMarkers(stops)
        ..setClustering(const MarkerClustering())
        ..setZoom(12.4);
      scene.attach(ops);
      await scene.idle;

      final clusters = kinds(MarkerFeatures.cluster);
      expect(clusters, hasLength(1));
      expect(kinds(MarkerFeatures.marker), ['far']);
      final group = scene.clusterFor(clusters.single, GeoScene.clusterLayer)!;
      expect(group.cluster.markers.map((m) => m.id), ['s0', 's1', 's2']);
      expect(group.expansionLevel, greaterThan(12));
      // Only taps on the cluster layer are clusters.
      expect(scene.clusterFor(clusters.single, GeoScene.tappableLayer), isNull);

      ops.calls.clear();
      scene.setZoom(12.9);
      await scene.idle;
      expect(ops.starting('setGeoJsonSource'), isEmpty);

      scene.setZoom(19);
      await scene.idle;
      expect(kinds(MarkerFeatures.cluster), isEmpty);
      expect(kinds(MarkerFeatures.marker), ['s0', 's1', 's2', 'far']);
      expect(errors, isEmpty);
    });

    test('draws every cluster size ahead of time', () async {
      scene
        ..setMarkers(stops)
        ..setClustering(const MarkerClustering())
        ..setZoom(19);
      scene.attach(ops);
      await scene.idle;
      // Nothing is clustered at 19, yet the badge for three is ready.
      final three = MarkerClustering.defaultIcon(3).key;
      expect(ops.calls, contains('addImage astro:$three'));
    });

    test('a marker kept out of clustering stands alone', () async {
      scene
        ..setMarkers([
          ...stops,
          MapMarker<String>(
            id: 'open',
            position: const GeoPosition(49.2610, 13.90305),
            icon: _dot,
            clusterable: false,
          ),
        ])
        ..setClustering(const MarkerClustering())
        ..setZoom(12);
      scene.attach(ops);
      await scene.idle;
      expect(kinds(MarkerFeatures.marker), containsAll(['open', 'far']));
    });
  });

  group('buildings', () {
    test('stand as one marker, hidden while their floors show', () async {
      scene
        ..setBuildings([museum])
        ..setMarkers(const [
          MapMarker(
            id: 'she-wolf',
            position: ImagePosition(500, 500),
            levelId: 'g',
          ),
        ])
        ..setZoom(18);
      scene.attach(ops);
      await scene.idle;

      // Placed through the museum's floor although nobody has gone in.
      expect(errors, isEmpty);
      expect(kinds(MarkerFeatures.building), ['museum']);
      expect(kinds(MarkerFeatures.marker), ['she-wolf']);
      expect(scene.buildingFor('museum', GeoScene.buildingLayer), same(museum));
      expect(
        ops.filters[GeoScene.buildingLayer].toString(),
        isNot(contains('!=')),
      );

      scene.setLevels(museum.levels, active: 'g', minZoom: 16);
      await scene.idle;
      expect(
        ops.filters[GeoScene.buildingLayer].toString(),
        contains('museum'),
      );
      expect(
        ops.filters[GeoScene.tappableLayer].toString(),
        contains('level], g]'),
      );
    });

    test('zoomed out past the indoor zoom, the building comes back', () async {
      scene
        ..setBuildings([museum])
        ..setLevels(museum.levels, active: 'g', minZoom: 16)
        ..setZoom(17);
      scene.attach(ops);
      await scene.idle;
      expect(scene.visibleLevel, 'g');

      ops.calls.clear();
      scene.setZoom(15);
      await scene.idle;
      expect(scene.visibleLevel, isNull);
      expect(
        ops.filters[GeoScene.buildingLayer].toString(),
        isNot(contains('museum')),
      );
      expect(
        ops.filters[GeoScene.tappableLayer].toString(),
        isNot(contains('level], g]')),
      );
    });

    test('sends filters before data when the floor changes', () async {
      scene
        ..setMarkers([
          for (var i = 0; i < 3; i++)
            MapMarker<String>(
              id: 'r$i',
              position: ImagePosition(500.0 + i, 500),
              levelId: i == 0 ? 'g' : '1',
              icon: _dot,
            ),
        ])
        ..setClustering(const MarkerClustering())
        ..setBuildings([museum])
        ..setLevels(museum.levels, active: 'g')
        ..setZoom(15);
      scene.attach(ops);
      await scene.idle;

      ops.calls.clear();
      scene.setLevels(museum.levels, active: '1');
      await scene.idle;
      final firstData = ops.calls.indexWhere(
        (c) => c.startsWith('setGeoJsonSource'),
      );
      final lastFilter = ops.calls.lastIndexWhere(
        (c) => c.startsWith('setFilter'),
      );
      expect(firstData, greaterThan(lastFilter));
      // On floor 1 the two there cluster; the ground floor's stands apart.
      expect(kinds(MarkerFeatures.cluster), hasLength(1));
    });
  });

  group('the visitor', () {
    test('appears once there is a fix, under the markers', () async {
      scene.setMarkers(stops);
      scene.attach(ops);
      await scene.idle;
      expect(ops.starting('addPuckLayer'), isEmpty);

      scene.setLocation(
        const LocationFix(position: GeoPosition(49.261, 13.903), accuracy: 12),
      );
      await scene.idle;
      expect(
        ops.calls,
        containsAllInOrder([
          'addGeoJsonSource ${GeoScene.locationSource}',
          'addAccuracyLayer ${GeoScene.accuracyLayer} '
              'below=${GeoScene.staticLayer}',
          'addPuckLayer ${GeoScene.puckLayer}',
        ]),
      );
      final dot =
          (ops.sources[GeoScene.locationSource]!['features']! as List).single
              as Map<String, Object?>;
      final properties = dot['properties']! as Map;
      expect(properties['r0'] as double, greaterThan(0));
      expect(
        properties['icon'],
        'astro:${const MyLocationStyle().puckIcon(cone: false).key}',
      );

      ops.calls.clear();
      scene.setLocation(
        const LocationFix(position: GeoPosition(49.2611, 13.903)),
        heading: 80,
      );
      await scene.idle;
      // A new fix only changes the data; the marker layers are untouched.
      expect(ops.starting('setGeoJsonSource'), [
        'setGeoJsonSource ${GeoScene.locationSource}',
      ]);
      final turned =
          (ops.sources[GeoScene.locationSource]!['features']! as List).single
              as Map<String, Object?>;
      expect((turned['properties']! as Map)['heading'], 80);
    });

    test('a floor-plan fix is carried through its floor', () async {
      scene.setBuildings([museum]);
      scene.attach(ops);
      await scene.idle;
      scene.setLocation(
        const LocationFix(position: ImagePosition(1000, 500), levelId: '1'),
      );
      await scene.idle;
      final at =
          ((ops.sources[GeoScene.locationSource]!['features']! as List).single
                  as Map)['geometry']
              as Map;
      final expected = plan.toGeo(const ImagePosition(1000, 500));
      expect(
        (at['coordinates'] as List)[1] as double,
        closeTo(expected.latitude, 1e-9),
      );
    });

    test('a style reload puts the visitor back', () async {
      scene.setLocation(const LocationFix(position: GeoPosition(49.26, 13.9)));
      scene.attach(ops);
      await scene.idle;
      final fresh = RecordingStyleOps();
      scene.attach(fresh);
      await scene.idle;
      expect(fresh.starting('addPuckLayer'), hasLength(1));
    });
  });
}
