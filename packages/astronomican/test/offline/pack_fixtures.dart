import 'dart:convert';
import 'dart:io';

import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the test packs are bundled.
const String packDir = 'assets/packs/town';

/// The bundled manifest's asset key.
const String manifestAsset = '$packDir/pack.json';

/// A fresh temporary root, removed after the test.
Future<Directory> tempRoot() async {
  final dir = await Directory.systemTemp.createTemp('astronomican_packs_');
  addTearDown(() async {
    // Windows can take a moment to release handles; try a few times.
    for (var i = 0; i < 5; i++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });
  return dir;
}

/// Bytes of a given length, different for every [seed].
List<int> blob(int length, {int seed = 1}) =>
    List<int>.generate(length, (i) => (i * 31 + seed * 17) & 0xFF);

/// A manifest for [files], with sizes and checksums filled in.
MapPackManifest manifestFor(
  Map<String, List<int>> files, {
  String id = 'town',
  int version = 1,
  Map<String, List<String>> parts = const {},
  bool checksums = true,
}) => MapPackManifest(
  id: id,
  version: version,
  style: files.containsKey('style.json') ? 'style.json' : null,
  bounds: const [13.87, 49.24, 13.93, 49.27],
  maxZoom: 14,
  files: [
    for (final MapEntry(key: path, value: bytes) in files.entries)
      PackFileEntry(
        path: path,
        size: bytes.length,
        sha256: checksums ? sha256.convert(bytes).toString() : null,
        parts: parts[path],
      ),
  ],
);

/// Puts a pack of [files] at version [version] into [bundle], as an app
/// build would ship it.
MapPackManifest bundlePack(
  MemoryAssetBundle bundle,
  Map<String, List<int>> files, {
  int version = 1,
}) {
  final manifest = manifestFor(files, version: version);
  bundle.putString(manifestAsset, manifest.encode());
  files.forEach((path, bytes) => bundle.put('$packDir/$path', bytes));
  return manifest;
}

/// Puts a pack of [files] on [server] under [base], and returns the
/// manifest's URL.
Uri servePack(
  FakePackTransport server,
  Map<String, List<int>> files, {
  required int version,
  String base = 'https://maps.example.com/town/',
  bool checksums = true,
}) {
  final root = Uri.parse(base);
  final manifest = manifestFor(files, version: version, checksums: checksums);
  final url = root.resolve('pack.json');
  server.putString(url, manifest.encode());
  files.forEach((path, bytes) => server.put(root.resolve(path), bytes));
  return url;
}

/// The files of the first sample pack.
Map<String, List<int>> sampleFiles({int seed = 1}) => {
  'town.mbtiles': blob(20000, seed: seed),
  'style.json': utf8.encode('{"version":8,"sources":{},"layers":[]}'),
  'fonts/Noto Sans Regular/0-255.pbf': blob(700, seed: seed + 2),
};

/// Every file under [dir], relative, with `/`.
Future<Set<String>> filesIn(Directory dir) async => {
  await for (final entity in dir.list(recursive: true))
    if (entity is File)
      entity.path
          .substring(dir.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/'),
};
