import 'dart:io';

import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'pack_fixtures.dart';

void main() {
  late Directory root;
  late MemoryAssetBundle bundle;
  late FakePackTransport server;
  final base = Uri.parse('https://maps.example.com/town/');

  setUp(() async {
    root = await tempRoot();
    bundle = MemoryAssetBundle();
    server = FakePackTransport();
  });

  MapPackManager launch() =>
      MapPackManager(root: root, bundle: bundle, transport: server);

  Future<InstalledPack> installBundled(Map<String, List<int>> files) {
    bundlePack(bundle, files);
    return launch().ensureBundled(manifestAsset);
  }

  test('downloads a newer version beside the installed one', () async {
    await installBundled(sampleFiles());
    final files = sampleFiles(seed: 2);
    final url = servePack(server, files, version: 2);

    final manager = launch();
    final announced = manager.changes.first;
    final pack = await manager.download(url).result;

    expect(pack.version, 2);
    expect(pack.origin, PackOrigin.downloaded);
    for (final MapEntry(key: path, value: bytes) in files.entries) {
      expect(await pack.file(path).readAsBytes(), bytes, reason: path);
    }
    expect((await announced).version, 2);
    expect((await launch().installed('town'))?.version, 2);
  });

  test('does nothing when the server is not newer', () async {
    await installBundled(sampleFiles());
    final url = servePack(server, sampleFiles(), version: 1);

    final task = launch().download(url);
    final pack = await task.result;

    expect(pack.version, 1);
    expect(task.latest?.phase, PackPhase.upToDate);
    expect(server.requests.map((r) => r.$1), [url]);
  });

  test('checkForUpdate says whether there is anything newer', () async {
    await installBundled(sampleFiles());
    final same = servePack(server, sampleFiles(), version: 1);
    expect(await launch().checkForUpdate(same), isNull);
    final newer = servePack(
      server,
      sampleFiles(seed: 3),
      version: 4,
      base: 'https://maps.example.com/v4/',
    );
    expect((await launch().checkForUpdate(newer))?.version, 4);
  });

  test('reuses installed files whose checksum has not changed', () async {
    final v1 = sampleFiles();
    await installBundled(v1);
    // Only the tileset changes.
    final v2 = {...v1, 'town.mbtiles': blob(20000, seed: 8)};
    final url = servePack(server, v2, version: 2);

    final pack = await launch().download(url).result;

    expect(pack.version, 2);
    expect(server.requestsFor(base.resolve('town.mbtiles')), 1);
    expect(server.requestsFor(base.resolve('style.json')), 0);
    expect(await pack.file('style.json').readAsBytes(), v1['style.json']);
  });

  test('resumes an interrupted file from where it stopped', () async {
    await installBundled(sampleFiles());
    final files = sampleFiles(seed: 6);
    final url = servePack(server, files, version: 2);
    final tiles = base.resolve('town.mbtiles');
    server.dropAfter(tiles, 7000);

    await expectLater(
      launch().download(url).result,
      throwsA(isA<HttpException>()),
    );
    expect((await launch().installed('town'))?.version, 1);

    final pack = await launch().download(url).result;
    expect(pack.version, 2);
    expect(server.requests.where((r) => r.$1 == tiles).map((r) => r.$2), [
      0,
      7000,
    ]);
    expect(
      await pack.file('town.mbtiles').readAsBytes(),
      files['town.mbtiles'],
    );
  });

  test('copes with a server that ignores ranges', () async {
    final files = sampleFiles(seed: 6);
    final url = servePack(server, files, version: 2);
    final tiles = base.resolve('town.mbtiles');
    server.dropAfter(tiles, 5000);
    await expectLater(launch().download(url).result, throwsA(anything));

    server.honourRanges = false;
    final pack = await launch().download(url).result;
    expect(
      await pack.file('town.mbtiles').readAsBytes(),
      files['town.mbtiles'],
    );
  });

  test('a checksum mismatch activates nothing', () async {
    await installBundled(sampleFiles());
    final url = servePack(server, sampleFiles(seed: 2), version: 2);
    // The server's copy is corrupted after the manifest was written.
    server.put(base.resolve('town.mbtiles'), blob(20000, seed: 99));

    await expectLater(
      launch().download(url).result,
      throwsA(isA<PackIntegrityException>()),
    );
    expect((await launch().installed('town'))?.version, 1);
    expect(
      await Directory(p.join(root.path, 'town', 'v000002')).exists(),
      isFalse,
    );
  });

  test('cancel stops at once and keeps what arrived', () async {
    final files = sampleFiles(seed: 2);
    final url = servePack(server, files, version: 1);
    final tiles = base.resolve('town.mbtiles');
    final gate = server.stallAfter(tiles, 4096);

    final task = launch().download(url);
    await task.progress.firstWhere(
      (p) => p.file == 'town.mbtiles' && p.bytesDone >= 4096,
    );
    task.cancel();

    await expectLater(task.result, throwsA(isA<PackCancelledException>()));
    gate.complete();
    final part = File(
      p.join(root.path, 'town', '.stage-remote-v000001', 'town.mbtiles.part'),
    );
    expect(await part.length(), 4096);

    final pack = await launch().download(url).result;
    expect(
      await pack.file('town.mbtiles').readAsBytes(),
      files['town.mbtiles'],
    );
    expect(
      server.requests.where((r) => r.$1 == tiles).map((r) => r.$2).last,
      4096,
    );
  });

  test('a map opening mid-download does not wait for it', () async {
    await installBundled(sampleFiles());
    final url = servePack(server, sampleFiles(seed: 2), version: 2);
    final gate = server.stallAfter(base.resolve('town.mbtiles'), 4096);
    final manager = launch();

    final task = manager.download(url);
    await task.progress.firstWhere((p) => p.bytesDone >= 4096);

    final active = await manager
        .ensureBundled(manifestAsset)
        .timeout(const Duration(seconds: 2));
    expect(active.version, 1);
    await expectLater(manager.download(url).result, throwsStateError);

    gate.complete();
    expect((await task.result).version, 2);
  });

  test('progress only goes forward and ends finished', () async {
    final url = servePack(server, sampleFiles(seed: 2), version: 1);
    final task = launch().download(url);
    final reports = await task.progress.toList();
    final downloading = reports.where((r) => r.phase == PackPhase.downloading);
    var last = -1;
    for (final r in downloading) {
      expect(r.bytesDone, greaterThanOrEqualTo(last));
      last = r.bytesDone;
    }
    expect(reports.last.phase, PackPhase.done);
    expect(reports.last.fraction, 1);
  });

  test('a bad manifest fails the download', () async {
    final url = base.resolve('pack.json');
    server.putString(url, '{"id": "../evil", "version": 1, "files": []}');
    await expectLater(
      launch().download(url).result,
      throwsA(isA<PackManifestException>()),
    );
  });
}
