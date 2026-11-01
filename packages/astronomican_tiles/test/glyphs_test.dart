import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fakes.dart';

Uint8List _range(String name, List<int> ids, {int advance = 10}) =>
    GlyphPbf.encode([
      GlyphStack(
        name: name,
        range: '0-255',
        glyphs: [
          for (final id in ids)
            Glyph(
              id: id,
              bitmap: Uint8List.fromList([id]),
              width: 1,
              height: 1,
              left: -2,
              top: -9,
              advance: advance,
            ),
        ],
      ),
    ]);

void main() {
  final zero = GlyphRange.parse('0-255');

  group('GlyphPbf', () {
    test('decodes a real range and keeps its content through a round trip', () {
      final bytes = fixture(
        'glyphs/noto-sans-regular-0-255.pbf',
      ).readAsBytesSync();
      final stack = GlyphPbf.decode(bytes).single;
      expect(stack.range, '0-255');
      expect(stack.glyphs.length, greaterThan(150));
      final again = GlyphPbf.decode(GlyphPbf.encode([stack])).single;
      expect(again.glyphs.length, stack.glyphs.length);
      for (var i = 0; i < stack.glyphs.length; i++) {
        final a = stack.glyphs[i], b = again.glyphs[i];
        expect(
          (b.id, b.width, b.height, b.left, b.top, b.advance),
          (a.id, a.width, a.height, a.left, a.top, a.advance),
        );
        expect(b.bitmap, a.bitmap);
      }
    });

    test('negative bearings survive, and gzipped files read', () {
      final bytes = _range('A', [65]);
      final g = GlyphPbf.decode(
        Uint8List.fromList(gzip.encode(bytes)),
      ).single.glyphs.single;
      expect((g.left, g.top), (-2, -9));
    });

    test('an empty range is a valid file', () {
      final empty = GlyphPbf.decode(GlyphPbf.empty('A,B', '512-767')).single;
      expect((empty.name, empty.range), ('A,B', '512-767'));
      expect(empty.glyphs, isEmpty);
    });
  });

  group('GlyphComposer', () {
    test('the first font wins, the later ones fill gaps, sorted', () {
      final out = GlyphComposer.composite('A,B', zero, [
        _range('A', [66, 65], advance: 1),
        _range('B', [65, 67], advance: 2),
      ]);
      final stack = GlyphPbf.decode(out).single;
      expect(stack.name, 'A,B');
      expect(
        [for (final g in stack.glyphs) (g.id, g.advance)],
        [(65, 1), (66, 1), (67, 2)],
      );
    });

    test('a missing member is skipped; none at all is an empty file', () {
      expect(
        GlyphPbf.decode(
          GlyphComposer.composite('A,B', zero, [
            null,
            _range('B', [70]),
          ]),
        ).single.glyphs.single.id,
        70,
      );
      expect(
        GlyphPbf.decode(
          GlyphComposer.composite('A,B', zero, [null, null]),
        ).single.glyphs,
        isEmpty,
      );
    });

    test('a single font is copied byte for byte', () {
      final bytes = fixture(
        'glyphs/noto-sans-regular-0-255.pbf',
      ).readAsBytesSync();
      expect(
        GlyphComposer.composite('Noto Sans Regular', zero, [bytes]),
        same(bytes),
      );
    });
  });

  group('font providers', () {
    test(
      'a folder, a URL template, then the release zip, in that order',
      () async {
        final folder = tempDir();
        File(p.join(folder.path, 'Local Font', '0-255.pbf'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(_range('Local Font', [1]));

        final fetcher = FakeFetcher({
          'https://fonts.test/Url%20Font/0-255.pbf': _range('Url Font', [2]),
        });
        final archive = Archive()
          ..addFile(
            ArchiveFile.bytes(
              'fonts/Zip Font/0-255.pbf',
              _range('Zip Font', [3]),
            ),
          );
        final zip = File(p.join(tempDir().path, 'fonts.zip'))
          ..writeAsBytesSync(ZipEncoder().encode(archive));

        final resolver = FontResolver([
          DirectoryFontProvider(folder),
          UrlFontProvider(
            'https://fonts.test/{fontstack}/{range}.pbf',
            fetcher,
            tempDir(),
          ),
          OpenMapTilesFontsProvider(zip, fetcher),
        ]);
        Future<int> id(String font) async => GlyphPbf.decode(
          (await resolver.read(font, zero))!,
        ).single.glyphs.single.id;
        expect(await id('Local Font'), 1);
        expect(await id('Url Font'), 2);
        expect(await id('Zip Font'), 3);
        await resolver.check(['Local Font,Zip Font', 'Url Font']);
        await expectLater(
          resolver.check(['Nowhere Sans']),
          throwsA(
            isA<TilesException>().having(
              (e) => e.message,
              'message',
              contains('glyphs.sources'),
            ),
          ),
        );
      },
    );

    test('a URL font is fetched once, and a 404 remembered', () async {
      final fetcher = FakeFetcher({
        'https://f/A/0-255.pbf': _range('A', [1]),
      });
      final cache = tempDir();
      final provider = UrlFontProvider(
        'https://f/{fontstack}/{range}.pbf',
        fetcher,
        cache,
      );
      await provider.read('A', zero);
      await provider.read('A', zero);
      await provider.read('B', zero);
      await provider.read('B', zero);
      expect(fetcher.requests, [
        'https://f/A/0-255.pbf',
        'https://f/B/0-255.pbf',
      ]);
    });
  });
}
