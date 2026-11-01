import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:test/test.dart';

void main() {
  MapPackManifest withFiles(List<PackFileEntry> files, {String id = 'town'}) =>
      MapPackManifest(id: id, version: 1, files: files);

  void rejects(String path) => expect(
    () => withFiles([PackFileEntry(path: path, size: 1)]).validate(),
    throwsA(isA<PackManifestException>()),
    reason: path,
  );

  test('parses what it encodes', () {
    const manifest = MapPackManifest(
      id: 'strakonice',
      version: 3,
      name: 'Strakonice',
      style: 'style.json',
      bounds: [13.87, 49.24, 13.93, 49.27],
      maxZoom: 14,
      attribution: '© OpenStreetMap contributors',
      files: [
        PackFileEntry(path: 'style.json', size: 10),
        PackFileEntry(
          path: 'strakonice.mbtiles',
          size: 100,
          sha256:
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          parts: ['strakonice.mbtiles.000'],
        ),
      ],
    );
    final back = MapPackManifest.parse(manifest.encode());
    expect(back, manifest);
    expect(back.mbtilesPath, 'strakonice.mbtiles');
    expect(back.stylePath, 'style.json');
    expect(back.totalBytes, 110);
  });

  test('tolerates a byte-order mark', () {
    final text =
        '\uFEFF${withFiles(const [PackFileEntry(path: 'a', size: 1)]).encode()}';
    expect(MapPackManifest.parse(text).id, 'town');
  });

  test('refuses paths that could leave the pack', () {
    for (final path in [
      '../outside',
      'a/../../b',
      '/etc/passwd',
      r'C:\x',
      r'fonts\a.pbf',
      'a//b',
      './a',
      '',
    ]) {
      rejects(path);
    }
  });

  test('refuses reserved names and the download suffix', () {
    rejects('.pack.json');
    rejects('.remote.json');
    rejects('tiles.mbtiles.part');
  });

  test('refuses the same file twice, whatever the case', () {
    expect(
      () => withFiles(const [
        PackFileEntry(path: 'Style.json', size: 1),
        PackFileEntry(path: 'style.json', size: 1),
      ]).validate(),
      throwsA(isA<PackManifestException>()),
    );
  });

  test('refuses bad ids, versions and checksums', () {
    expect(
      () => withFiles(const [
        PackFileEntry(path: 'a', size: 1),
      ], id: 'Town').validate(),
      throwsA(isA<PackManifestException>()),
    );
    expect(
      () => const MapPackManifest(
        id: 'town',
        version: 0,
        files: [PackFileEntry(path: 'a', size: 1)],
      ).validate(),
      throwsA(isA<PackManifestException>()),
    );
    expect(
      () => withFiles(const [
        PackFileEntry(path: 'a', size: 1, sha256: 'ABC'),
      ]).validate(),
      throwsA(isA<PackManifestException>()),
    );
  });

  test('refuses a style that is not in the pack', () {
    expect(
      () => const MapPackManifest(
        id: 'town',
        version: 1,
        style: 'missing.json',
        files: [PackFileEntry(path: 'a', size: 1)],
      ).validate(),
      throwsA(isA<PackManifestException>()),
    );
  });

  test('refuses bounds in the wrong order', () {
    expect(
      () => const MapPackManifest(
        id: 'town',
        version: 1,
        bounds: [49.24, 13.87, 49.27, 13.93, 0],
        files: [PackFileEntry(path: 'a', size: 1)],
      ).validate(),
      throwsA(isA<PackManifestException>()),
    );
  });

  test('refuses what is not a manifest at all', () {
    expect(
      () => MapPackManifest.parse('nope'),
      throwsA(isA<PackManifestException>()),
    );
    expect(
      () => MapPackManifest.parse('[]'),
      throwsA(isA<PackManifestException>()),
    );
    expect(
      () => MapPackManifest.parse(
        '{"id":"a","version":1,"files":[{"path":"x"}]}',
      ),
      throwsA(isA<PackManifestException>()),
    );
  });
}
