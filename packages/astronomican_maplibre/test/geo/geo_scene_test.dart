import 'dart:ui';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_maplibre/astronomican_maplibre_testing.dart';
import 'package:astronomican_maplibre/src/geo/scene/geo_scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recording_style_ops.dart';

const _dot = MarkerIcon.dot(diameter: 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GeoScene<String> scene;
  late List<Object> errors;

  final ground = ImageGeoreference.fromBounds(
    north: 49.2615,
    south: 49.2605,
    east: 13.9045,
    west: 13.9025,
    imageSize: const Size(2000, 1000),
  );

  MapLevel level(String id, {ImageGeoreference? georeference}) => MapLevel(
    id: id,
    label: id,
    image: MapImage.memory(transparentPng),
    size: const Size(2000, 1000),
    georeference: georeference,
  );

  setUp(() {
    errors = [];
    scene = GeoScene<String>(
      rasterizer: MarkerRasterizer(),
      onError: (e, _) => errors.add(e),
    );
  });

  test('installs pictures, icons, then the marker layers on top', () async {
    scene
      ..setMarkers(const [
        MapMarker(id: 'a', position: GeoPosition(49.26, 13.90)),
        MapMarker(id: 'b', position: GeoPosition(49.27, 13.91)),
      ])
      ..setOverlays([
        GeoImageOverlay(
          id: 'old-town',
          image: MapImage.memory(transparentPng),
          georeference: ground,
          imageSize: const Size(2000, 1000),
        ),
      ]);
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;

    expect(ops.calls, [
      'addImageSource astro-overlay-src-old-town',
      'addRasterLayer astro-overlay-old-town below=null',
      'addImage astro:${const MarkerIcon.pin().key}',
      'addGeoJsonSource ${GeoScene.markerSource}',
      'addMarkerLayer ${GeoScene.staticLayer} interactive=false',
      'addMarkerLayer ${GeoScene.tappableLayer} interactive=true',
      'addMarkerLayer ${GeoScene.buildingLayer} interactive=true',
      'addMarkerLayer ${GeoScene.clusterLayer} interactive=true',
    ]);
    final features = ops.sources[GeoScene.markerSource]!['features']! as List;
    expect(features, hasLength(2));
    final first = features.first as Map<String, Object?>;
    expect(first['id'], 'a');
    expect((first['geometry']! as Map)['coordinates'], [13.90, 49.26]);
    expect(errors, isEmpty);
  });

  test('sends nothing when the markers have not changed', () async {
    const markers = [MapMarker<String>(id: 'a', position: GeoPosition(49, 13))];
    scene.setMarkers(markers);
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;
    ops.calls.clear();

    scene.setMarkers(List.of(markers));
    await scene.idle;
    expect(ops.calls, isEmpty);
  });

  test('registers a new icon before the features that use it', () async {
    scene.setMarkers(const [MapMarker(id: 'a', position: GeoPosition(49, 13))]);
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;
    ops.calls.clear();

    scene.setMarkers(const [
      MapMarker(id: 'a', position: GeoPosition(49, 13), icon: _dot),
    ]);
    await scene.idle;
    expect(ops.calls, [
      'addImage astro:${_dot.key}',
      'setGeoJsonSource ${GeoScene.markerSource}',
    ]);
  });

  test('a style reload installs everything again', () async {
    scene.setMarkers(const [MapMarker(id: 'a', position: GeoPosition(49, 13))]);
    final first = RecordingStyleOps();
    scene.attach(first);
    await scene.idle;

    final second = RecordingStyleOps();
    scene.attach(second);
    await scene.idle;
    expect(second.calls, first.calls);
  });

  test('abandons an install when the style reloads under it', () async {
    scene.setMarkers(const [MapMarker(id: 'a', position: GeoPosition(49, 13))]);
    final stale = RecordingStyleOps();
    final fresh = RecordingStyleOps();
    scene
      ..attach(stale)
      ..attach(fresh);
    await scene.idle;
    expect(stale.calls, isEmpty);
    expect(fresh.starting('addMarkerLayer'), hasLength(4));
  });

  test('switching level swaps the floor drawn and the markers shown', () async {
    final east = ImageGeoreference.fromBounds(
      north: 49.2615,
      south: 49.2605,
      east: 13.9065,
      west: 13.9045,
      imageSize: const Size(2000, 1000),
    );
    scene
      ..setLevels([
        level('g', georeference: ground),
        level('1', georeference: east),
      ], active: 'g')
      ..setMarkers(const [
        MapMarker(id: 'on-g', position: ImagePosition(1000, 500), levelId: 'g'),
        MapMarker(id: 'on-1', position: ImagePosition(1000, 500), levelId: '1'),
      ]);
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;
    expect(ops.rasters['astro-level-g'], (1.0, true));
    expect(ops.rasters['astro-level-1'], (1.0, false));
    expect(ops.filters[GeoScene.tappableLayer].toString(), contains('g'));

    ops.calls.clear();
    scene.setLevels([
      level('g', georeference: ground),
      level('1', georeference: east),
    ], active: '1');
    await scene.idle;
    expect(ops.rasters['astro-level-g'], (1.0, false));
    expect(ops.rasters['astro-level-1'], (1.0, true));
    // The two marker layers and the cluster layer read the level; the
    // markers themselves are all in the source already.
    expect(ops.starting('setFilter'), hasLength(3));
    expect(ops.starting('setGeoJsonSource'), isEmpty);
  });

  test('carries floor-plan positions onto the Earth', () async {
    scene
      ..setLevels([level('g', georeference: ground)], active: 'g')
      ..setMarkers(const [
        MapMarker(id: 'x', position: ImagePosition(500, 250), levelId: 'g'),
      ]);
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;

    final expected = ground.toGeo(const ImagePosition(500, 250));
    final feature =
        (ops.sources[GeoScene.markerSource]!['features']! as List).single
            as Map<String, Object?>;
    final coordinates = (feature['geometry']! as Map)['coordinates'] as List;
    expect(coordinates[0], closeTo(expected.longitude, 1e-12));
    expect(coordinates[1], closeTo(expected.latitude, 1e-12));
    expect((feature['properties']! as Map)['level'], 'g');
  });

  test('reports a floor-plan marker it cannot place, once', () async {
    scene
      ..setLevels([level('g')], active: 'g')
      ..setMarkers(const [
        MapMarker(id: 'x', position: ImagePosition(1, 1), levelId: 'g'),
      ]);
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;
    scene.attach(RecordingStyleOps());
    await scene.idle;

    expect(errors, hasLength(1));
    expect((ops.sources[GeoScene.markerSource]!['features']! as List), isEmpty);
  });

  test('changes overlays in place, and removes them', () async {
    GeoImageOverlay overlay({double opacity = 1}) => GeoImageOverlay(
      id: 'plan',
      image: MapImage.memory(transparentPng),
      georeference: ground,
      imageSize: const Size(2000, 1000),
      opacity: opacity,
    );
    scene.setOverlays([overlay()]);
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;

    ops.calls.clear();
    scene.setOverlays([overlay(opacity: 0.5)]);
    await scene.idle;
    expect(ops.calls, [
      'setRasterLayer astro-overlay-plan opacity=0.5 visible=true',
    ]);

    ops.calls.clear();
    scene.setOverlays(const []);
    await scene.idle;
    expect(ops.calls, [
      'removeLayer astro-overlay-plan',
      'removeSource astro-overlay-src-plan',
    ]);
  });

  test('an overlay added later goes under the markers', () async {
    final ops = RecordingStyleOps();
    scene.attach(ops);
    await scene.idle;
    scene.setOverlays([
      GeoImageOverlay(
        id: 'late',
        image: MapImage.memory(transparentPng),
        georeference: ground,
        imageSize: const Size(2000, 1000),
      ),
    ]);
    await scene.idle;
    expect(
      ops.starting('addRasterLayer').single,
      'addRasterLayer astro-overlay-late below=${GeoScene.staticLayer}',
    );
  });

  test('routes taps on the tappable layer back to the marker', () async {
    scene.setMarkers(const [
      MapMarker(id: 'a', position: GeoPosition(49, 13), data: 'stop A'),
      MapMarker(id: 'me', position: GeoPosition(49, 13), tappable: false),
    ]);
    expect(scene.markerFor('a', GeoScene.tappableLayer)?.data, 'stop A');
    expect(scene.markerFor('me', GeoScene.staticLayer), isNull);
    expect(scene.markerFor('nope', GeoScene.tappableLayer), isNull);
  });
}
