import 'dart:convert';
import 'dart:io';

import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'pack_fixtures.dart';

void main() {
  late Directory root;
  late MemoryAssetBundle bundle;

  setUp(() async {
    root = await tempRoot();
    bundle = MemoryAssetBundle();
  });

  MapPackManager launch({FakePackTransport? transport}) =>
      MapPackManager(root: root, bundle: bundle, transport: transport);

  test('the first launch copies the pack out of the bundle', () async {
    final files = sampleFiles();
    bundlePack(bundle, files);

    final pack = await launch().ensureBundled(manifestAsset);

    expect(pack.id, 'town');
    expect(pack.version, 1);
    expect(pack.origin, PackOrigin.bundled);
    expect(p.basename(pack.directory.path), 'v000001');
    for (final MapEntry(key: path, value: bytes) in files.entries) {
      expect(await pack.file(path).readAsBytes(), bytes, reason: path);
    }
    expect(
      pack.bounds,
      const GeoBounds(west: 13.87, south: 49.24, east: 13.93, north: 49.27),
    );
  });

  test('a relaunch reads the manifest and copies nothing', () async {
    bundlePack(bundle, sampleFiles());
    final first = await launch().ensureBundled(manifestAsset);
    final stamp = await first.file('town.mbtiles').lastModified();
    bundle.loads.clear();

    final second = await launch().ensureBundled(manifestAsset);

    expect(second.directory.path, first.directory.path);
    expect(bundle.loads, {manifestAsset: 1});
    expect(await second.file('town.mbtiles').lastModified(), stamp);
  });

  test('a higher bundled version is copied, and the old one cleared', () async {
    bundlePack(bundle, sampleFiles());
    final v1 = await launch().ensureBundled(manifestAsset);

    final updated = sampleFiles(seed: 9);
    bundlePack(bundle, updated, version: 2);
    final v2 = await launch().ensureBundled(manifestAsset);

    expect(v2.version, 2);
    expect(
      await v2.file('town.mbtiles').readAsBytes(),
      updated['town.mbtiles'],
    );
    expect(await v1.directory.exists(), isFalse);
  });

  test('the same bundle without a version bump is not copied again', () async {
    bundlePack(bundle, sampleFiles());
    await launch().ensureBundled(manifestAsset);
    // Contents changed, version not: by the rules, nothing is new.
    bundle.put('$packDir/town.mbtiles', blob(20000, seed: 42));
    bundle.loads.clear();

    await launch().ensureBundled(manifestAsset);
    expect(bundle.loads.keys, [manifestAsset]);
  });

  test('a version handed out in this run is kept until the next', () async {
    final manager = launch();
    bundlePack(bundle, sampleFiles());
    final v1 = await manager.ensureBundled(manifestAsset);

    bundlePack(bundle, sampleFiles(seed: 5), version: 2);
    final v2 = await manager.ensureBundled(manifestAsset);
    expect(v2.version, 2);
    expect(await v1.directory.exists(), isTrue, reason: 'a map may hold it');

    await launch().ensureBundled(manifestAsset);
    expect(await v1.directory.exists(), isFalse);
  });

  test('announces a new install on changes', () async {
    final manager = launch();
    final announced = <int>[];
    manager.changes.listen((pack) => announced.add(pack.version));
    bundlePack(bundle, sampleFiles());
    await manager.ensureBundled(manifestAsset);
    await manager.ensureBundled(manifestAsset);
    await Future<void>.delayed(Duration.zero);
    expect(announced, [1]);
  });

  test('a file that has gone missing is restored', () async {
    bundlePack(bundle, sampleFiles());
    final first = await launch().ensureBundled(manifestAsset);
    await first.file('town.mbtiles').delete();

    final again = await launch().ensureBundled(manifestAsset);
    expect(await again.file('town.mbtiles').exists(), isTrue);
  });

  test('an interrupted copy is swept up and redone', () async {
    bundlePack(bundle, sampleFiles());
    final stale = Directory(p.join(root.path, 'town', '.stage-bundle-v000001'));
    await File(p.join(stale.path, 'town.mbtiles')).create(recursive: true);

    final pack = await launch().ensureBundled(manifestAsset);
    expect(pack.version, 1);
    expect(await stale.exists(), isFalse);
  });

  test('a version folder without its marker is not taken for one', () async {
    bundlePack(bundle, sampleFiles());
    final junk = Directory(p.join(root.path, 'town', 'v000009'));
    await File(p.join(junk.path, 'town.mbtiles')).create(recursive: true);

    final pack = await launch().ensureBundled(manifestAsset);
    expect(pack.version, 1);
  });

  test('concurrent calls share one copy', () async {
    bundlePack(bundle, sampleFiles());
    final manager = launch();
    final results = await Future.wait([
      manager.ensureBundled(manifestAsset),
      manager.ensureBundled(manifestAsset),
      manager.ensureBundled(manifestAsset),
    ]);
    expect(results.map((r) => r.directory.path).toSet(), hasLength(1));
    expect(bundle.loads['$packDir/town.mbtiles'], 1);
  });

  test('a split file is put together piece by piece', () async {
    final whole = blob(30000, seed: 3);
    final manifest = MapPackManifest(
      id: 'town',
      version: 1,
      files: [
        PackFileEntry(
          path: 'town.mbtiles',
          size: whole.length,
          parts: const ['town.mbtiles.000', 'town.mbtiles.001'],
        ),
      ],
    );
    bundle
      ..putString(manifestAsset, manifest.encode())
      ..put('$packDir/town.mbtiles.000', whole.sublist(0, 16384))
      ..put('$packDir/town.mbtiles.001', whole.sublist(16384));

    final pack = await launch().ensureBundled(manifestAsset);
    expect(await pack.file('town.mbtiles').readAsBytes(), whole);
    expect(bundle.loads.containsKey('$packDir/town.mbtiles'), isFalse);
  });

  test(
    'a missing asset names itself and leaves the old version active',
    () async {
      bundlePack(bundle, sampleFiles());
      await launch().ensureBundled(manifestAsset);

      bundlePack(bundle, sampleFiles(seed: 4), version: 2);
      bundle.remove('$packDir/fonts/Noto Sans Regular/0-255.pbf');

      await expectLater(
        launch().ensureBundled(manifestAsset),
        throwsA(
          isA<PackMissingAssetException>().having(
            (e) => e.key,
            'key',
            '$packDir/fonts/Noto Sans Regular/0-255.pbf',
          ),
        ),
      );
      final active = await launch().installed('town');
      expect(active?.version, 1);
      expect(
        await filesIn(Directory(p.join(root.path, 'town'))),
        isNot(contains(startsWith('.stage'))),
      );
    },
  );

  test('a size that disagrees with the manifest is refused', () async {
    bundlePack(bundle, sampleFiles());
    bundle.put('$packDir/town.mbtiles', blob(123));
    await expectLater(
      launch().ensureBundled(manifestAsset),
      throwsA(isA<PackIntegrityException>()),
    );
    expect(await launch().installed('town'), isNull);
  });

  test('a manifest from a newer format is refused', () async {
    final manifest = manifestFor(sampleFiles()).toJson()..['format'] = 99;
    bundle.putString(manifestAsset, jsonEncode(manifest));
    await expectLater(
      launch().ensureBundled(manifestAsset),
      throwsA(isA<PackIncompatibleException>()),
    );
  });

  test('a newer download is not replaced by an older bundle', () async {
    final server = FakePackTransport();
    final url = servePack(server, sampleFiles(seed: 7), version: 3);
    final downloaded = await launch(transport: server).download(url).result;
    expect(downloaded.version, 3);

    bundlePack(bundle, sampleFiles(), version: 2);
    bundle.loads.clear();
    final active = await launch().ensureBundled(manifestAsset);

    expect(active.version, 3);
    expect(active.origin, PackOrigin.downloaded);
    expect(bundle.loads.keys, [manifestAsset]);
  });

  test('list and remove', () async {
    bundlePack(bundle, sampleFiles());
    final manager = launch();
    await manager.ensureBundled(manifestAsset);
    expect((await manager.list()).map((p) => p.id), ['town']);
    await manager.remove('town');
    expect(await manager.list(), isEmpty);
    expect(await manager.installed('town'), isNull);
  });
}
