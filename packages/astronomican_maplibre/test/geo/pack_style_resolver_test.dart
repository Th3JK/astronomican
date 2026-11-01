import 'dart:convert';
import 'dart:io';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/temp_root.dart';

void main() {
  late InstalledPack pack;

  setUp(() async {
    final root = await tempRoot();
    // A folder with a space in it, as iOS's Application Support has.
    final dir = Directory(p.join(root.path, 'Application Support', 'v000001'));
    Future<void> put(String path, String text) async {
      final file = File(p.joinAll([dir.path, ...path.split('/')]));
      await file.create(recursive: true);
      await file.writeAsString(text);
    }

    await put('town.mbtiles', 'tiles');
    await put('sprite.json', '{}');
    await put('sprite.png', 'png');
    await put('fonts/Noto Sans Regular/0-255.pbf', 'glyphs');
    pack = InstalledPack(
      manifest: const MapPackManifest(
        id: 'town',
        version: 1,
        files: [
          PackFileEntry(path: 'town.mbtiles', size: 5),
          PackFileEntry(path: 'sprite.json', size: 2),
        ],
      ),
      directory: dir,
      origin: PackOrigin.bundled,
    );
  });

  Map<String, Object?> resolve(
    Map<String, Object?> style, {
    Map<String, String> tokens = const {},
  }) =>
      jsonDecode(
            PackStyleResolver(
              pack,
              tokens: tokens,
            ).resolveDocument(jsonEncode(style)),
          )
          as Map<String, Object?>;

  test('points pack:// at the files on disk', () {
    final style = resolve({
      'version': 8,
      'sources': {
        'omt': {'type': 'vector', 'url': 'pack://town.mbtiles'},
      },
      'sprite': 'pack://sprite',
      'glyphs': 'pack://fonts/{fontstack}/{range}.pbf',
      'layers': <Object>[],
    });
    final source = (style['sources']! as Map)['omt'] as Map;
    expect(source['url'], 'mbtiles://${pack.path('town.mbtiles')}');
    expect(style['sprite'], 'file://${pack.path('sprite')}');
    expect(
      style['glyphs'],
      'file://${pack.path('fonts/{fontstack}/{range}.pbf')}',
    );
  });

  test('understands strakonice\'s placeholders', () {
    final style = resolve({
      'sources': {
        'omt': {'type': 'vector', 'url': '___MBTILES_URI___'},
      },
      'sprite': '___SPRITE_URI___',
      'glyphs': '___FONTS_URI___',
    });
    expect(
      ((style['sources']! as Map)['omt'] as Map)['url'],
      'mbtiles://${pack.path('town.mbtiles')}',
    );
    expect(style['sprite'], 'file://${pack.path('sprite')}');
  });

  test('applies extra tokens before rewriting', () {
    final style = resolve(
      {'sprite': '{{SPRITE}}'},
      tokens: {'{{SPRITE}}': 'pack://sprite'},
    );
    expect(style['sprite'], 'file://${pack.path('sprite')}');
  });

  test('rewrites sprite arrays and tile lists', () {
    final style = resolve({
      'sprite': [
        {'id': 'default', 'url': 'pack://sprite'},
      ],
      'sources': {
        'r': {
          'type': 'raster',
          'tiles': ['pack://tiles/{z}/{x}/{y}.png'],
        },
      },
    });
    expect(
      ((style['sprite']! as List).single as Map)['url'],
      'file://${pack.path('sprite')}',
    );
    expect(
      (((style['sources']! as Map)['r'] as Map)['tiles'] as List).single,
      'file://${pack.path('tiles/{z}/{x}/{y}.png')}',
    );
  });

  test('always hands MapLibre a document starting with {', () {
    final text = PackStyleResolver(pack).resolveDocument('﻿  {"version": 8}');
    expect(text.startsWith('{'), isTrue);
  });

  test('validate is happy with a complete pack', () async {
    final resolved = PackStyleResolver(pack).resolveDocument(
      jsonEncode({
        'sources': {
          'omt': {'type': 'vector', 'url': 'pack://town.mbtiles'},
        },
        'sprite': 'pack://sprite',
        'glyphs': 'pack://fonts/{fontstack}/{range}.pbf',
        'layers': [
          {
            'id': 'labels',
            'type': 'symbol',
            'layout': {
              'text-font': ['Noto Sans Regular'],
            },
          },
        ],
      }),
    );
    expect(await PackStyleResolver(pack).validate(resolved), isEmpty);
  });

  test('validate names what is missing', () async {
    final resolved = PackStyleResolver(pack).resolveDocument(
      jsonEncode({
        'sources': {
          'omt': {'type': 'vector', 'url': 'pack://other.mbtiles'},
        },
        'sprite': 'pack://icons',
        'glyphs': 'pack://fonts/{fontstack}/{range}.pbf',
        'layers': [
          {
            'id': 'labels',
            'type': 'symbol',
            'layout': {
              'text-font': [
                'literal',
                ['Noto Sans Bold'],
              ],
            },
          },
          {
            'id': 'x',
            'type': 'fill',
            'paint': {'fill-color': '___LEFT_OVER___'},
          },
        ],
      }),
    );
    final issues = await PackStyleResolver(pack).validate(resolved);
    expect(issues, hasLength(5));
    expect(issues.join('\n'), contains('other.mbtiles'));
    expect(issues.join('\n'), contains('Noto Sans Bold'));
    expect(issues.join('\n'), contains('___LEFT_OVER___'));
  });
}
