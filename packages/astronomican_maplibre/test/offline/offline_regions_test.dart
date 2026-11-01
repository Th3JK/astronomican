import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_maplibre/astronomican_maplibre_testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const town = GeoBounds(south: 49.24, west: 13.87, north: 49.27, east: 13.93);
  const style = 'https://tiles.openfreemap.org/styles/liberty';
  late FakeOfflineRegionBackend backend;
  late OfflineRegions regions;

  setUp(() {
    backend = FakeOfflineRegionBackend();
    regions = OfflineRegions(backend: backend);
  });

  test('reports progress and completes with the area', () async {
    final download = regions.download(
      const OfflineAreaRequest(styleUrl: style, bounds: town, name: 'Town'),
    );
    final area = await download.area;
    final reports = <double>[];
    download.progress.listen((p) => reports.add(p.fraction));

    backend
      ..progress(area.id, 0.25)
      ..progress(area.id, 0.8)
      ..complete(area.id);

    expect((await download.result).id, area.id);
    await Future<void>.delayed(Duration.zero);
    expect(reports, [0.25, 0.8, 1]);
    expect(download.latest!.isComplete, isTrue);
  });

  test('tags its areas and lists only those by default', () async {
    await regions
        .download(const OfflineAreaRequest(styleUrl: style, bounds: town))
        .area;
    await backend.download(
      const OfflineAreaRequest(styleUrl: style, bounds: town),
      const {},
      (_) {},
    );
    expect(await regions.list(), hasLength(1));
    expect(await regions.list(onlyOwn: false), hasLength(2));
    expect(
      (await regions.list()).single.metadata[OfflineRegions.ownerKey],
      isTrue,
    );
  });

  test('a tile-limit failure says so', () async {
    final download = regions.download(
      const OfflineAreaRequest(styleUrl: style, bounds: town, maxZoom: 20),
    );
    final area = await download.area;
    backend.fail(area.id, 'tileCountLimitExceeded');
    await expectLater(
      download.result,
      throwsA(
        isA<OfflineRegionException>().having(
          (e) => e.isTileLimit,
          'isTileLimit',
          isTrue,
        ),
      ),
    );
  });

  test('pause, resume, delete, limit and offline reach the database', () async {
    final area = await regions
        .download(const OfflineAreaRequest(styleUrl: style, bounds: town))
        .area;
    await regions.pause(area);
    expect(backend.paused, {area.id});
    await regions.resume(area);
    expect(backend.paused, isEmpty);
    await regions.setTileCountLimit(12000);
    expect(backend.tileCountLimit, 12000);
    await regions.setOffline(offline: true);
    expect(backend.offline, isTrue);
    await regions.delete(area, clearAmbientCache: true);
    expect(backend.areas, isEmpty);
    expect(backend.ambientCacheClears, 1);
  });

  test('estimateTileCount counts the pyramid over the area', () {
    // The whole world: 1 + 4 + 16 tiles for zooms 0 to 2.
    expect(
      OfflineRegions.estimateTileCount(
        const GeoBounds(south: -85, west: -180, north: 85, east: 179.999),
        0,
        2,
      ),
      21,
    );
    final z12to16 = OfflineRegions.estimateTileCount(town, 12, 16);
    final z12to15 = OfflineRegions.estimateTileCount(town, 12, 15);
    // The top zoom holds most of the tiles.
    expect(z12to16 - z12to15, greaterThan(z12to15 * 2));
  });
}
