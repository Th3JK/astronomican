import 'dart:convert';
import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fakes.dart';

/// A copy of the example's real pack, to break in various ways.
Directory _copyOfExample() {
  final dir = tempDir();
  for (final entity in examplePack.listSync(recursive: true)) {
    if (entity is! File) continue;
    final target = File(
      p.join(dir.path, p.relative(entity.path, from: examplePack.path)),
    );
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
  return dir;
}

void main() {
  group('ManifestWriter', () {
    test(
      'lists every file with size and checksum, sorted, hidden ones left out',
      () async {
        final dir = tempDir();
        File(p.join(dir.path, 'b.txt')).writeAsStringSync('bb');
        File(p.join(dir.path, 'a', 'x.pbf'))
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
        File(p.join(dir.path, '.DS_Store')).writeAsStringSync('junk');
        final manifest = await const ManifestWriter().write(
          dir,
          id: 'town',
          version: 2,
        );
        expect(manifest.files.map((f) => f.path), ['a/x.pbf', 'b.txt']);
        expect(
          manifest.file('b.txt')!.sha256,
          sha256.convert(utf8.encode('bb')).toString(),
        );
        expect(
          MapPackManifest.parse(
            File(p.join(dir.path, 'pack.json')).readAsStringSync(),
          ),
          manifest,
        );
      },
    );

    test(
      'splits large files, and a second run over the pieces keeps them',
      () async {
        final dir = tempDir();
        final big = List<int>.generate(3 * 1024 + 10, (i) => i & 0xff);
        File(p.join(dir.path, 'town.mbtiles')).writeAsBytesSync(big);
        final first = await const ManifestWriter().write(
          dir,
          id: 'town',
          version: 1,
          splitBytes: 1024,
        );
        final entry = first.file('town.mbtiles')!;
        expect(entry.parts, [
          'town.mbtiles.000',
          'town.mbtiles.001',
          'town.mbtiles.002',
          'town.mbtiles.003',
        ]);
        expect(File(p.join(dir.path, 'town.mbtiles')).existsSync(), isFalse);
        expect(entry.sha256, sha256.convert(big).toString());

        final second = await const ManifestWriter().write(
          dir,
          id: 'town',
          version: 1,
        );
        expect(second.files.single, entry);
      },
    );

    test('prints one asset line per folder holding files', () {
      final manifest = MapPackManifest(
        id: 't',
        version: 1,
        files: const [
          PackFileEntry(path: 'style.json', size: 1),
          PackFileEntry(path: 'fonts/A,B/0-255.pbf', size: 1),
        ],
      );
      expect(ManifestWriter.assetLines(manifest, 'assets/packs/t'), [
        '- assets/packs/t/',
        '- assets/packs/t/fonts/A,B/',
      ]);
    });
  });

  group('PackValidator', () {
    test('the example\'s bundled pack is valid', () async {
      final report = await const PackValidator().validate(examplePack);
      expect(report.errors, isEmpty);
    });

    test('names each thing that would break the map', () async {
      final dir = _copyOfExample();
      File(p.join(dir.path, 'sprite@2x.png')).deleteSync();
      File(
        p.join(dir.path, 'fonts', 'Noto Sans Italic', '256-511.pbf'),
      ).deleteSync();
      final style = File(p.join(dir.path, 'style.json'));
      style.writeAsStringSync(
        style.readAsStringSync().replaceFirst(
          'pack://sprite',
          'pack://sprite?key=abc',
        ),
      );
      final report = await const PackValidator().validate(dir);
      final all = report.errors.join('\n');
      expect(all, contains('sprite@2x.png'));
      expect(all, contains('ship different ranges'));
      expect(all, contains('key'));
      // Edited after pack.json was written: caught by size or checksum.
      expect(all, contains('style.json: '));
    });

    test('an empty folder has no pack', () async {
      expect(
        (await const PackValidator().validate(tempDir())).errors.single,
        contains('no pack.json'),
      );
    });
  });

  group('Publisher', () {
    Future<Directory> built(String content, {int version = 1}) async {
      final dir = tempDir();
      File(p.join(dir.path, 'town.mbtiles')).writeAsStringSync(content);
      await const ManifestWriter().write(dir, id: 'town', version: version);
      return dir;
    }

    test('publishes, then finds the same pack up to date', () async {
      final output = Directory(
        p.join(tempDir().path, 'assets', 'packs', 'town'),
      );
      final (first, _) = await const Publisher().publish(
        pack: await built('a'),
        output: output,
      );
      expect(first, PublishOutcome.published);
      final (second, _) = await const Publisher().publish(
        pack: await built('a'),
        output: output,
      );
      expect(second, PublishOutcome.upToDate);
    });

    test(
      'refuses new content under the same version, and a lower version',
      () async {
        final output = Directory(p.join(tempDir().path, 'out'));
        await const Publisher().publish(
          pack: await built('a', version: 2),
          output: output,
        );
        await expectLater(
          const Publisher().publish(
            pack: await built('b', version: 2),
            output: output,
          ),
          throwsA(
            isA<VersionConflict>().having((e) => e.published, 'published', 2),
          ),
        );
        await expectLater(
          const Publisher().publish(
            pack: await built('b', version: 1),
            output: output,
          ),
          throwsA(
            isA<TilesException>().having(
              (e) => e.message,
              'message',
              contains('backwards'),
            ),
          ),
        );
        final (outcome, manifest) = await const Publisher().publish(
          pack: await built('b', version: 3),
          output: output,
        );
        expect((outcome, manifest.version), (PublishOutcome.published, 3));
      },
    );

    test('will not overwrite a folder that is not this pack', () async {
      final output = tempDir();
      File(p.join(output.path, 'keep.txt')).writeAsStringSync('mine');
      await expectLater(
        const Publisher().publish(pack: await built('a'), output: output),
        throwsA(isA<TilesException>()),
      );
      expect(File(p.join(output.path, 'keep.txt')).existsSync(), isTrue);
    });

    test('splits on the way out, leaving the built pack whole', () async {
      final pack = tempDir();
      File(
        p.join(pack.path, 'town.mbtiles'),
      ).writeAsBytesSync(List.filled(3000, 7));
      await const ManifestWriter().write(pack, id: 'town', version: 1);
      final output = Directory(p.join(tempDir().path, 'out'));
      final (_, manifest) = await const Publisher().publish(
        pack: pack,
        output: output,
        splitBytes: 1024,
      );
      expect(manifest.file('town.mbtiles')!.parts, hasLength(3));
      expect(File(p.join(pack.path, 'town.mbtiles')).existsSync(), isTrue);
      expect((await const PackValidator().validate(output)).errors, isEmpty);
    });
  });

  test('assembling the example\'s own style reproduces a valid pack', () async {
    // The style, sprite and fonts of the bundled pack, as a local style.
    final source = _copyOfExample();
    final style = await StyleLoader(
      FakeFetcher(),
      tempDir(),
    ).load('style.json', source);
    final conversion = const StyleConverter().convert(
      style,
      id: 'strakonice',
      attribution: Upstream.attribution,
    );
    final into = Directory(p.join(tempDir().path, 'pack'));
    final members = Directory(p.join(tempDir().path, 'members'));
    final ctx = testContext();
    final manifest = await PackAssembler(FakeFetcher(), ctx.context.console)
        .assemble(
          into: into,
          id: 'strakonice',
          version: 1,
          tiles: File(p.join(source.path, 'strakonice.mbtiles')),
          style: conversion,
          fonts: FontResolver([
            for (final s in conversion.fontSources)
              DirectoryFontProvider(Directory(s)),
          ]),
          ranges: GlyphRange.latin,
          memberFonts: members,
        );
    expect(manifest.id, 'strakonice');
    expect((await const PackValidator().validate(into)).errors, isEmpty);
    // Single-font stacks are the source files, unchanged.
    for (final font in [
      'Noto Sans Regular',
      'Noto Sans Medium',
      'Noto Sans Italic',
    ]) {
      expect(
        File(p.join(into.path, 'fonts', font, '256-511.pbf')).readAsBytesSync(),
        File(
          p.join(examplePack.path, 'fonts', font, '256-511.pbf'),
        ).readAsBytesSync(),
      );
      expect(
        File(p.join(members.path, font, '0-255.pbf')).existsSync(),
        isTrue,
      );
    }
    expect(Directory('${into.path}.next').existsSync(), isFalse);
  });
}
