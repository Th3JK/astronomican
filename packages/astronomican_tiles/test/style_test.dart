import 'dart:convert';
import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fakes.dart';

/// Every font in the OpenMapTiles fonts release v2.0.
const _releaseFonts = {
  'Metropolis Black',
  'Metropolis Black Italic',
  'Metropolis Bold',
  'Metropolis Bold Italic',
  'Metropolis Extra Bold',
  'Metropolis Extra Bold Italic',
  'Metropolis Extra Light',
  'Metropolis Extra Light Italic',
  'Metropolis Light',
  'Metropolis Light Italic',
  'Metropolis Medium',
  'Metropolis Medium Italic',
  'Metropolis Regular',
  'Metropolis Regular Italic',
  'Metropolis Semi Bold',
  'Metropolis Semi Bold Italic',
  'Metropolis Thin',
  'Metropolis Thin Italic',
  'Noto Sans Bold',
  'Noto Sans Italic',
  'Noto Sans Regular',
  'Open Sans Bold',
  'Open Sans Bold Italic',
  'Open Sans Extra Bold',
  'Open Sans Extra Bold Italic',
  'Open Sans Italic',
  'Open Sans Light',
  'Open Sans Light Italic',
  'Open Sans Regular',
  'Open Sans Semibold',
  'Open Sans Semibold Italic',
  'PT Sans Bold',
  'PT Sans Bold Italic',
  'PT Sans Caption Regular',
  'PT Sans Caption Web Bold',
  'PT Sans Italic',
  'PT Sans Narrow Bold',
  'PT Sans Narrow Regular',
  'PT Sans Regular',
  'Roboto Black',
  'Roboto Black Italic',
  'Roboto Bold',
  'Roboto Bold Italic',
  'Roboto Condensed Bold',
  'Roboto Condensed Bold Italic',
  'Roboto Condensed Italic',
  'Roboto Condensed Light',
  'Roboto Condensed Light Italic',
  'Roboto Condensed Regular',
  'Roboto Italic',
  'Roboto Light',
  'Roboto Light Italic',
  'Roboto Medium',
  'Roboto Medium Italic',
  'Roboto Regular',
  'Roboto Thin',
  'Roboto Thin Italic',
};

const _metropolisStacks = {
  'Metropolis Light Italic,Noto Sans Italic',
  'Metropolis Light,Noto Sans Regular',
  'Metropolis Medium Italic,Noto Sans Italic',
  'Metropolis Regular,Noto Sans Regular',
};

void main() {
  LoadedStyle preset(StylePreset preset) => LoadedStyle(
    jsonDecode(fixture('styles/${preset.id}.json').readAsStringSync())
        as Map<String, Object?>,
    preset.url!,
    label: preset.id,
  );

  group('every published preset converts to a fully offline pack style', () {
    final expected = {
      StylePreset.maptilerBasic: {'Noto Sans Bold', 'Noto Sans Regular'},
      StylePreset.osmBright: {
        'Noto Sans Bold',
        'Noto Sans Italic',
        'Noto Sans Regular',
      },
      StylePreset.positron: _metropolisStacks,
      StylePreset.darkMatter: _metropolisStacks,
      StylePreset.fiordColor: _metropolisStacks,
    };
    for (final MapEntry(key: style, value: stacks) in expected.entries) {
      test(style.id, () {
        final result = const StyleConverter().convert(
          preset(style),
          id: 'town',
          attribution: Upstream.attribution,
          vectorLayers: _omtLayers,
        );
        final json = result.style;
        expect((json['sources']! as Map)['openmaptiles'], {
          'type': 'vector',
          'url': 'pack://town.mbtiles',
          'attribution': Upstream.attribution,
        });
        expect(json['sprite'], 'pack://sprite');
        expect(json['glyphs'], 'pack://fonts/{fontstack}/{range}.pbf');
        final text = jsonEncode(json..remove('metadata'));
        expect(text, isNot(contains('key=')));
        expect(text, isNot(contains('maptiler.com')));
        expect(
          result.sprites.single.source.toString(),
          'https://openmaptiles.github.io/${style.repository}/sprite',
        );
        expect(result.fontStacks, stacks);
        // Every font the preset needs is in the OpenMapTiles fonts release,
        // so the pack can always be made offline.
        for (final stack in result.fontStacks) {
          for (final font in stack.split(',')) {
            expect(_releaseFonts, contains(font), reason: font);
          }
        }
        // The keyed MapTiler glyphs are never used as a font source.
        expect(result.fontSources, isEmpty);
        expect(result.warnings, isEmpty);
        expect(
          result.textKeys,
          anyOf(contains('name:latin'), contains('name')),
        );
      });
    }
  });

  test('strakonice\'s placeholders and a local sprite and fonts', () {
    final dir = tempDir();
    final style = {
      'version': 8,
      'sources': {
        'openmaptiles': {'type': 'vector', 'url': '___MBTILES_URI___'},
      },
      'sprite': '___SPRITE_URI___',
      'glyphs': '___FONTS_URI___',
      'layers': [
        {
          'id': 'label',
          'type': 'symbol',
          'source': 'openmaptiles',
          'source-layer': 'place',
          'layout': {
            'text-field': '{name:latin}',
            'text-font': ['Noto Sans Medium'],
          },
        },
      ],
    };
    final loaded = LoadedStyle(
      style,
      Uri.directory(dir.path),
      label: 'parchment',
    );
    final result = const StyleConverter().convert(
      loaded,
      id: 'strakonice',
      attribution: 'x',
    );
    expect(
      ((result.style['sources']! as Map)['openmaptiles'] as Map)['url'],
      'pack://strakonice.mbtiles',
    );
    expect(
      result.sprites.single.source,
      Uri.directory(dir.path).resolve('sprite'),
    );
    expect(result.fontSources.single, p.join(dir.path, 'fonts') + p.separator);
    expect(result.fontStacks, {'Noto Sans Medium'});
    expect(result.textKeys, {'name:latin'});
  });

  test('OSM OpenMapTiles: the attribution-only source goes', () {
    final style = {
      'version': 8,
      'sources': {
        'openmaptiles': {
          'type': 'vector',
          'url': 'mbtiles:///data/tiles.mbtiles',
        },
        'attribution': {'type': 'vector', 'attribution': '© OpenMapTiles'},
      },
      'glyphs': '{fontstack}/{range}.pbf',
      'sprite': 'sprite',
      'layers': [
        {'id': 'bg', 'type': 'background'},
      ],
    };
    final result = const StyleConverter().convert(
      LoadedStyle(style, Uri.directory(tempDir().path), label: 'omt'),
      id: 'x',
      attribution: 'a',
    );
    expect((result.style['sources']! as Map).keys, ['openmaptiles']);
  });

  test('online sources are dropped with their layers, or kept on request', () {
    Map<String, Object?> style() => {
      'version': 8,
      'sources': {
        'openmaptiles': {'type': 'vector', 'url': 'https://x/tiles.json'},
        'hillshade': {
          'type': 'raster',
          'tiles': ['https://x/{z}/{x}/{y}.png'],
        },
      },
      'layers': [
        {'id': 'hill', 'type': 'raster', 'source': 'hillshade'},
        {
          'id': 'roads',
          'type': 'line',
          'source': 'openmaptiles',
          'source-layer': 'transportation',
        },
      ],
    };
    final base = Uri.parse('https://x/style.json');
    final dropped = const StyleConverter().convert(
      LoadedStyle(style(), base, label: 's'),
      id: 'x',
      attribution: 'a',
    );
    expect((dropped.style['layers']! as List).map((l) => (l as Map)['id']), [
      'roads',
    ]);
    expect(dropped.warnings.single, contains('hillshade'));

    final kept = const StyleConverter().convert(
      LoadedStyle(style(), base, label: 's'),
      id: 'x',
      attribution: 'a',
      otherSources: OtherSources.keep,
    );
    expect((kept.style['layers']! as List), hasLength(2));

    final keyed = style();
    (keyed['sources']! as Map)['hillshade'] = {
      'type': 'raster',
      'tiles': ['https://x/{z}/{x}/{y}.png?key=abc'],
    };
    expect(
      () => const StyleConverter().convert(
        LoadedStyle(keyed, base, label: 's'),
        id: 'x',
        attribution: 'a',
        otherSources: OtherSources.keep,
      ),
      throwsA(isA<TilesException>()),
    );
  });

  test('a style for another schema is a warning, not a blank map', () {
    final result = const StyleConverter().convert(
      LoadedStyle(
        {
          'version': 8,
          'sources': {
            'protomaps': {'type': 'vector', 'url': 'https://x.json'},
          },
          'layers': [
            {
              'id': 'roads',
              'type': 'line',
              'source': 'protomaps',
              'source-layer': 'roads',
            },
          ],
        },
        Uri.parse('https://x/'),
        label: 'protomaps',
      ),
      id: 'x',
      attribution: 'a',
      vectorLayers: _omtLayers,
    );
    expect(result.warnings.single, contains('roads'));
  });

  test('a key anywhere but metadata is refused', () {
    expect(
      () => const StyleConverter().convert(
        LoadedStyle(
          {
            'version': 8,
            'sources': {
              'openmaptiles': {'type': 'vector', 'url': 'https://x.json'},
            },
            'sprite': 'https://x/sprite?key=abc',
            'layers': <Object>[],
          },
          Uri.parse('https://x/'),
          label: 's',
        ),
        id: 'x',
        attribution: 'a',
      ),
      throwsA(
        isA<TilesException>().having(
          (e) => e.message,
          'message',
          contains('key'),
        ),
      ),
    );
  });

  group('style forms', () {
    final pack = {
      'version': 8,
      'sources': {
        'openmaptiles': {'type': 'vector', 'url': 'pack://town.mbtiles'},
      },
      'sprite': 'pack://sprite',
      'glyphs': 'pack://fonts/{fontstack}/{range}.pbf',
      'layers': [
        {
          'id': 'bg',
          'type': 'background',
          'paint': {'background-color': '#fff'},
        },
      ],
    };

    test('tileserver form', () {
      final t = StyleForms.packToTileserver(pack, 'town');
      expect(
        ((t['sources']! as Map)['openmaptiles'] as Map)['url'],
        'mbtiles://{town}',
      );
      expect(t['sprite'], 'sprite');
      expect(t['glyphs'], '{fontstack}/{range}.pbf');
    });

    test('browser form round-trips, with localhost or 127.0.0.1', () {
      final base = Uri.parse('http://localhost:8080');
      final browser = StyleForms.packToBrowser(pack, 'town', base);
      expect(browser['sprite'], 'http://localhost:8080/styles/town/sprite');
      expect(StyleForms.browserToPack(browser, 'town', base), pack);

      final edited =
          jsonDecode(jsonEncode(browser).replaceAll('localhost', '127.0.0.1'))
              as Map<String, Object?>;
      edited['metadata'] = {'maputnik:renderer': 'mlgljs'};
      expect(StyleForms.browserToPack(edited, 'town', base), pack);
    });
  });

  test(
    'the OSM OpenMapTiles merge: header first, then by order, stably',
    () async {
      final repo = tempDir();
      void write(String path, Object json) {
        final file = File(p.joinAll([repo.path, ...path.split('/')]));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(json is String ? json : jsonEncode(json));
      }

      write('openmaptiles.yaml', '''
tileset:
  layers:
    - layers/water/water.yaml
    - file: layers/roads/roads.yaml
''');
      write('style/style-header.json', {
        'version': 8,
        'name': 'OSM OpenMapTiles',
        'sources': <String, Object>{},
        'layers': [
          {'id': 'Background', 'type': 'background'},
        ],
      });
      write('layers/water/style.json', {
        'layers': [
          {'id': 'lake', 'order': 20},
          {'id': 'river', 'order': 5},
        ],
      });
      write('layers/roads/style.json', {
        'layers': [
          {'id': 'road', 'order': 5},
          {'id': 'bridge', 'order': 30},
        ],
      });
      final merged = await OmtStyleBuilder(
        FakeFetcher(),
        tempDir(),
      ).merge(repo);
      final ids = [for (final l in merged['layers']! as List) (l as Map)['id']];
      expect(ids, ['Background', 'river', 'road', 'lake', 'bridge']);
      expect(
        (merged['layers']! as List).every(
          (l) => !(l as Map).containsKey('order'),
        ),
        isTrue,
      );
      expect(merged['name'], 'OSM OpenMapTiles');
    },
  );

  test('the loader caches fetched styles and resolves files', () async {
    final fetcher = FakeFetcher()
      ..putJson(StylePreset.positron.url.toString(), {
        'version': 8,
        'layers': <Object>[],
      });
    final cache = tempDir();
    final loader = StyleLoader(fetcher, cache);
    await loader.load('positron', cache);
    await loader.load('positron', cache);
    expect(fetcher.requests, hasLength(1));
    await loader.load('positron', cache, refresh: true);
    expect(fetcher.requests, hasLength(2));

    final dir = tempDir();
    File(
      p.join(dir.path, 'style.json'),
    ).writeAsStringSync('{"version": 8, "layers": []}');
    final local = await loader.load('style.json', dir);
    expect(local.isLocal, isTrue);
    expect(
      local.resolve('pack://sprite'),
      Uri.directory(dir.path).resolve('sprite'),
    );
    expect(
      () => loader.load('nope.json', dir),
      throwsA(
        isA<TilesException>().having(
          (e) => e.exitCode,
          'code',
          ExitCodes.missing,
        ),
      ),
    );
  });

  test('presets are found by id and alias', () {
    expect(StylePreset.find('bright'), StylePreset.osmBright);
    expect(StylePreset.find('OSM-OpenMapTiles'), StylePreset.osmOpenMapTiles);
    expect(StylePreset.find('style.json'), isNull);
    expect(StylePreset.values, hasLength(6));
  });

  test('glyph ranges of the pack format', () {
    expect(GlyphRange.containing(0x159)!.name, '256-511');
  });
}

const _omtLayers = {
  'water',
  'waterway',
  'landcover',
  'landuse',
  'mountain_peak',
  'park',
  'boundary',
  'aeroway',
  'transportation',
  'building',
  'water_name',
  'transportation_name',
  'place',
  'housenumber',
  'poi',
  'aerodrome_label',
};
