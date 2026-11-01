import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:astronomican_tiles/src/cli/commands/init_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  MapConfig load(String yaml) {
    final dir = tempDir();
    final file = File(p.join(dir.path, 'map.yaml'))..writeAsStringSync(yaml);
    return MapConfig.load(file.path);
  }

  Matcher failsWith(String text) => throwsA(
    isA<TilesException>()
        .having((e) => e.message, 'message', contains(text))
        .having((e) => e.exitCode, 'exitCode', ExitCodes.config),
  );

  test('reads a full map.yaml', () {
    final config = load('''
id: strakonice
name: Strakonice
version: 3
area: europe/czech-republic/jihocesky
bounds: [13.8748, 49.2435, 13.9309, 49.2749]
maxZoom: 14
style: style.json
glyphs:
  ranges: [0-255, 256-511, 1024-1279]
  sources:
    - https://example.org/fonts/{fontstack}/{range}.pbf
    - fonts
planetiler:
  memory: 3g
  languages: [cs, en]
output: ../app/assets/packs/strakonice
split: 8
preview:
  port: 9090
''');
    expect(config.id, 'strakonice');
    expect(config.version, 3);
    expect((config.input as AreaInput).area, 'jihocesky');
    expect(config.bounds, [13.8748, 49.2435, 13.9309, 49.2749]);
    expect(config.glyphRanges.map((r) => r.name), [
      '0-255',
      '256-511',
      '1024-1279',
    ]);
    expect(config.glyphSources.first, startsWith('https://'));
    expect(p.isAbsolute(config.glyphSources.last), isTrue);
    expect(config.memory, '3g');
    expect(config.languages, ['cs', 'en']);
    expect(
      config.output!.path,
      endsWith(p.join('app', 'assets', 'packs', 'strakonice')),
    );
    expect(config.splitMegabytes, 8);
    expect(config.previewPort, 9090);
    expect(config.editorPort, 8888);
    expect(config.attribution, Upstream.attribution);
    expect(config.workDirectory.path, endsWith('.work'));
  });

  test('defaults: osm-bright, zooms 0-14, Latin ranges, detection on', () {
    final config = load('id: town\nversion: 1\narea: monaco\n');
    expect(config.style, 'osm-bright');
    expect((config.minZoom, config.maxZoom), (0, 14));
    expect(config.baseGlyphRanges, GlyphRange.latin);
    expect(config.detectGlyphRanges, isTrue);
  });

  test('0-255 is always shipped', () {
    final config = load(
      'id: t\nversion: 1\narea: monaco\nglyphs:\n  ranges: [256-511]\n',
    );
    expect(config.baseGlyphRanges.first.name, '0-255');
  });

  test('errors carry the line and a suggestion', () {
    expect(
      () => load('id: t\nversion: 1\narea: monaco\nmaxZom: 12\n'),
      failsWith('map.yaml:4:1: unknown key "maxZom" — did you mean "maxZoom"?'),
    );
  });

  test('refuses what makes no pack', () {
    expect(
      () => load('id: Town\nversion: 1\narea: monaco\n'),
      failsWith('not a valid pack id'),
    );
    expect(
      () => load('id: t\nversion: 0\narea: monaco\n'),
      failsWith('version must be 1 or more'),
    );
    expect(
      () => load('id: t\nversion: 1\n'),
      failsWith('say where the tiles come from'),
    );
    expect(
      () => load('id: t\nversion: 1\narea: monaco\ntiles: x.mbtiles\n'),
      failsWith('only one of area, osm and tiles'),
    );
    expect(
      () => load('id: t\nversion: 1\narea: monaco\nmaxZoom: 16\n'),
      failsWith('maxZoom ≤ 15'),
    );
    expect(
      () => load(
        'id: t\nversion: 1\narea: monaco\nbounds: [13.9, 49.2, 13.8, 49.3]\n',
      ),
      failsWith('west < east'),
    );
    expect(
      () =>
          load('id: t\nversion: 1\narea: monaco\nglyphs:\n  ranges: [0-256]\n'),
      failsWith('not a glyph range'),
    );
    expect(
      () => load('id: t\nversion: 1\nosm: region.osm.pbf\n'),
      failsWith('give bounds'),
    );
  });

  test('a folder stands for its map.yaml, and a missing one is named', () {
    final dir = tempDir();
    File(
      p.join(dir.path, 'map.yaml'),
    ).writeAsStringSync('id: t\nversion: 1\narea: monaco\n');
    expect(MapConfig.load(dir.path).id, 't');
    expect(
      () => MapConfig.load(p.join(dir.path, 'nope')),
      throwsA(
        isA<TilesException>().having(
          (e) => e.exitCode,
          'code',
          ExitCodes.missing,
        ),
      ),
    );
  });

  test('the init template parses back', () {
    final dir = tempDir();
    File(p.join(dir.path, 'map.yaml')).writeAsStringSync(
      InitCommand.template(
        id: 'town',
        name: 'My "Town"',
        style: 'positron',
        inputKey: 'area',
        inputValue: 'monaco',
        bounds: '7.40,43.72,7.44,43.75',
        minZoom: '0',
        maxZoom: '14',
        output: 'out',
      ),
    );
    final config = MapConfig.load(dir.path);
    expect(config.name, 'My "Town"');
    expect(config.style, 'positron');
    expect(config.bounds, [7.40, 43.72, 7.44, 43.75]);
  });

  test('the cache follows the platform, or the override', () {
    expect(
      defaultCacheDirectory(
        environment: {'LOCALAPPDATA': r'C:\Users\a\AppData\Local'},
        operatingSystem: 'windows',
      ).path,
      contains('astronomican_tiles'),
    );
    expect(
      defaultCacheDirectory(
        environment: {'HOME': '/Users/a'},
        operatingSystem: 'macos',
      ).path,
      p.join('/Users/a', 'Library', 'Caches', 'astronomican_tiles'),
    );
    expect(
      defaultCacheDirectory(
        environment: {'XDG_CACHE_HOME': '/x'},
        operatingSystem: 'linux',
      ).path,
      p.join('/x', 'astronomican_tiles'),
    );
    expect(
      defaultCacheDirectory(
        environment: {'ASTRONOMICAN_TILES_CACHE': '/c'},
        operatingSystem: 'linux',
      ).path,
      '/c',
    );
  });
}
