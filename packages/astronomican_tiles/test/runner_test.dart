import 'dart:convert';
import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  Future<(int, String, String)> run(
    List<String> args, {
    FakeFetcher? fetcher,
  }) async {
    final ctx = testContext(fetcher: fetcher, cache: tempDir());
    final code = await TilesRunner(ctx.context).execute(args);
    return (code, '${ctx.out}', '${ctx.err}');
  }

  test('help lists every command', () async {
    final (code, out, _) = await run(['--help']);
    expect(code, 0);
    for (final command in [
      'init',
      'doctor',
      'generate',
      'style',
      'pack',
      'build',
      'preview',
      'validate',
      'manifest',
      'clean',
    ]) {
      expect(out, contains(command));
    }
  });

  test('an unknown command is a usage error', () async {
    final (code, _, err) = await run(['nope']);
    expect(code, ExitCodes.usage);
    expect(err, contains('nope'));
  });

  test('manifest writes pack.json and prints the asset lines', () async {
    final dir = tempDir();
    File(p.join(dir.path, 'fonts', 'Noto Sans Regular', '0-255.pbf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('g');
    File(p.join(dir.path, 'town.mbtiles')).writeAsStringSync('t');
    final (code, out, _) = await run([
      'manifest',
      dir.path,
      '--id',
      'town',
      '--version',
      '4',
      '--max-zoom',
      '14',
      '--bounds',
      '13.8,49.2,13.9,49.3',
      '--asset-prefix',
      'assets/packs/town',
    ]);
    expect(code, 0);
    expect(out, contains('Wrote pack.json: town v4, 2 files'));
    expect(out, contains('- assets/packs/town/fonts/Noto Sans Regular/'));
    final manifest = MapPackManifest.parse(
      File(p.join(dir.path, 'pack.json')).readAsStringSync(),
    );
    expect((manifest.version, manifest.maxZoom), (4, 14));
    expect(manifest.bounds, [13.8, 49.2, 13.9, 49.3]);
  });

  test('manifest without --id is a usage error', () async {
    final (code, _, _) = await run([
      'manifest',
      tempDir().path,
      '--version',
      '1',
    ]);
    expect(code, ExitCodes.usage);
  });

  test('validate passes the example pack and fails a broken one', () async {
    expect((await run(['validate', examplePack.path])).$1, 0);
    final broken = tempDir();
    File(p.join(broken.path, 'pack.json')).writeAsStringSync('{}');
    final (code, _, err) = await run(['validate', broken.path]);
    expect(code, ExitCodes.config);
    expect(err, contains('pack.json'));
  });

  test('init writes a map.yaml that loads', () async {
    final dir = Directory(p.join(tempDir().path, 'my-town'));
    final (code, out, _) = await run([
      'init',
      dir.path,
      '--area',
      'monaco',
      '--style',
      'positron',
    ]);
    expect(code, 0);
    expect(out, contains('Next:'));
    final config = MapConfig.load(dir.path);
    expect((config.id, config.style), ('my-town', 'positron'));
    expect((await run(['init', dir.path])).$1, ExitCodes.usage);
  });

  test('style --list names all six presets', () async {
    final (code, out, _) = await run(['style', '--list']);
    expect(code, 0);
    for (final preset in StylePreset.values) {
      expect(out, contains(preset.id));
    }
  });

  test('a bad map.yaml exits with the config code', () async {
    final dir = tempDir();
    File(p.join(dir.path, 'map.yaml')).writeAsStringSync('id: x\n');
    final (code, _, err) = await run(['generate', dir.path]);
    expect(code, ExitCodes.config);
    expect(err, contains('version'));
  });
  group('preview --stop', () {
    const original = {
      'version': 8,
      'sources': {
        'openmaptiles': {'type': 'vector', 'url': 'pack://town.mbtiles'},
      },
      'sprite': 'pack://sprite',
      'glyphs': 'pack://fonts/{fontstack}/{range}.pbf',
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#f0e0c6'},
        },
      ],
    };
    const originalText = '{"version": 8}\n';

    // A map stopped after `preview --edit --detach`: what Maputnik was given
    // is fingerprinted in .seed, and [saved] is what it holds now.
    Directory stoppedEdit(
      Map<String, Object?> Function(Map<String, Object?>) saved,
    ) {
      final dir = tempDir();
      File(p.join(dir.path, 'map.yaml')).writeAsStringSync(
        'id: town\nversion: 1\ntiles: tiles.mbtiles\nstyle: style.json\n',
      );
      File(p.join(dir.path, 'style.json')).writeAsStringSync(originalText);
      File(p.join(dir.path, '.work', 'docker-compose.yml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('services: {}\n');
      final browser = StyleForms.packToBrowser(
        original,
        'town',
        Uri.parse('http://localhost:8080'),
      );
      final seeded = const JsonEncoder.withIndent('  ').convert(browser);
      final now = saved(browser);
      File(p.join(dir.path, '.work', 'edit', 'style.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(identical(now, browser) ? seeded : jsonEncode(now));
      File(
        p.join(dir.path, '.work', 'edit', '.seed'),
      ).writeAsStringSync(sha256.convert(utf8.encode(seeded)).toString());
      return dir;
    }

    test('writes Maputnik\'s edits back to the style, in pack form', () async {
      final dir = stoppedEdit((browser) {
        final edited = jsonDecode(jsonEncode(browser)) as Map<String, Object?>;
        ((edited['layers']! as List<Object?>).single!
            as Map<String, Object?>)['paint'] = {
          'background-color': '#123456',
        };
        edited['metadata'] = {'maputnik:renderer': 'mlgljs'};
        return edited;
      });

      final (code, out, _) = await run(['preview', dir.path, '--stop']);

      expect(code, 0);
      expect(out, contains('pack --bump'));
      final saved =
          jsonDecode(File(p.join(dir.path, 'style.json')).readAsStringSync())
              as Map<String, Object?>;
      expect(saved['sources'], original['sources']);
      expect(saved['sprite'], 'pack://sprite');
      expect(saved['glyphs'], original['glyphs']);
      expect(jsonEncode(saved['layers']), contains('#123456'));
      expect(saved['metadata'], anyOf(isNull, isEmpty));
      expect(
        File(p.join(dir.path, '.work', 'edit', '.seed')).existsSync(),
        isFalse,
      );
    });

    test('leaves the style alone when nothing was edited', () async {
      final dir = stoppedEdit((browser) => browser);

      final (code, out, _) = await run(['preview', dir.path, '--stop']);

      expect(code, 0);
      expect(out, isNot(contains('Saved')));
      expect(
        File(p.join(dir.path, 'style.json')).readAsStringSync(),
        originalText,
      );
      expect(
        File(p.join(dir.path, '.work', 'edit', '.seed')).existsSync(),
        isFalse,
      );
    });
  });
}
