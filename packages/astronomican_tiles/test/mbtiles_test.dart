import 'dart:io';

import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  Future<(Map<String, String>, Set<String>, int)> read(String path) async {
    final reader = await MbtilesReader.open(fixture(path));
    try {
      final metadata = await reader.metadata();
      final labels = <String>{};
      var tiles = 0;
      for (final blob in reader.tileBlobs()) {
        tiles++;
        MvtStrings.collect(
          blob,
          (k) => k == 'name' || k.startsWith('name:'),
          labels,
        );
      }
      return (metadata, labels, tiles);
    } finally {
      await reader.close();
    }
  }

  for (final layout in ['tilemaker', 'planetiler', 'small-pages']) {
    test('reads the $layout layout', () async {
      final (metadata, labels, tiles) = await read('mbtiles/$layout.mbtiles');
      expect(metadata['bounds'], '13.87,49.24,13.93,49.27');
      expect(metadata['maxzoom'], '14');
      expect(metadata['json'], contains('vector_layers'));
      // 200 padding rows push metadata over several pages.
      expect(metadata['pad199'], 'x' * 50);
      expect(tiles, 2);
      // Only name keys: "town" is a class value.
      expect(labels, contains('Strakonice'));
      expect(labels, contains('Třeboň'));
      expect(labels, isNot(contains('town')));
      // A label larger than a page arrives whole, through overflow pages.
      expect(
        labels.any((l) => l.startsWith('ČČČ') && l.endsWith(' Otava')),
        isTrue,
      );
    });
  }

  test('reads the example\'s real tilemaker tiles', () async {
    final reader = await MbtilesReader.open(
      File(p.join(examplePack.path, 'strakonice.mbtiles')),
    );
    final metadata = await reader.metadata();
    final labels = <String>{};
    var tiles = 0;
    for (final blob in reader.tileBlobs()) {
      tiles++;
      MvtStrings.collect(blob, (k) => k.startsWith('name'), labels);
    }
    await reader.close();
    expect(metadata['bounds'], '13.874796,49.243512,13.930929,49.274931');
    expect(tiles, 37);
    expect(labels, contains('České Budějovice'));
  });

  test('refuses what is not SQLite', () async {
    expect(
      () => MbtilesReader.open(fixture('glyphs/noto-sans-regular-0-255.pbf')),
      throwsFormatException,
    );
  });
}
