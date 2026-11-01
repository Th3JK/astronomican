import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:test/test.dart';

Map<String, Object?> _style(List<Map<String, Object?>> layers) => {
  'version': 8,
  'layers': layers,
};

Map<String, Object?> _label(Object? font, {Object? field = '{name}'}) => {
  'id': 'l${font.hashCode}',
  'type': 'symbol',
  'layout': {'text-font': ?font, 'text-field': ?field},
};

void main() {
  group('fontStacks', () {
    test('finds plain and literal stacks, joined by commas', () {
      final stacks = PackStyle.fontStacks(
        _style([
          _label(['Noto Sans Regular']),
          _label([
            'literal',
            ['Metropolis Regular', 'Noto Sans Regular'],
          ]),
        ]),
      );
      expect(stacks, {
        'Noto Sans Regular',
        'Metropolis Regular,Noto Sans Regular',
      });
    });

    test('reads the outputs of step, case, match and coalesce only', () {
      final stacks = PackStyle.fontStacks(
        _style([
          _label([
            'step',
            ['zoom'],
            [
              'literal',
              ['A'],
            ],
            10,
            [
              'literal',
              ['B'],
            ],
          ]),
          _label([
            'match',
            ['get', 'class'],
            ['city', 'town'],
            [
              'literal',
              ['C'],
            ],
            [
              'literal',
              ['D'],
            ],
          ]),
          _label([
            'case',
            [
              '==',
              ['get', 'rank'],
              1,
            ],
            [
              'literal',
              ['E'],
            ],
            [
              'literal',
              ['F'],
            ],
          ]),
          _label([
            'coalesce',
            ['get', 'font'],
            [
              'literal',
              ['G'],
            ],
          ]),
        ]),
      );
      expect(stacks, {'A', 'B', 'C', 'D', 'E', 'F', 'G'});
    });

    test('reads legacy zoom stops', () {
      final stacks = PackStyle.fontStacks(
        _style([
          _label({
            'base': 1,
            'stops': [
              [
                8,
                ['Small'],
              ],
              [
                12,
                ['Large', 'Fallback'],
              ],
            ],
          }),
        ]),
      );
      expect(stacks, {'Small', 'Large,Fallback'});
    });

    test('reads format overrides', () {
      final stacks = PackStyle.fontStacks(
        _style([
          _label(
            ['Base'],
            field: [
              'format',
              ['get', 'name'],
              {
                'text-font': [
                  'literal',
                  ['Override'],
                ],
              },
            ],
          ),
        ]),
      );
      expect(stacks, {'Base', 'Override'});
    });

    test('adds MapLibre\'s default stack only when asked', () {
      final style = _style([_label(null)]);
      expect(PackStyle.fontStacks(style), isEmpty);
      expect(PackStyle.fontStacks(style, includeDefault: true), {
        'Open Sans Regular,Arial Unicode MS Regular',
      });
    });
  });

  test('legacy tokens map onto the pack conventions', () {
    expect(PackStyle.legacyTokensFor('town.mbtiles'), {
      '___MBTILES_URI___': 'pack://town.mbtiles',
      '___SPRITE_URI___': 'pack://sprite',
      '___FONTS_URI___': 'pack://fonts/{fontstack}/{range}.pbf',
    });
    expect(
      PackStyle.legacyTokensFor(null).containsKey('___MBTILES_URI___'),
      isFalse,
    );
  });

  test('mapStrings keeps the structure and rewrites every string', () {
    final out = PackStyle.mapStrings({
      'a': [
        'x',
        1,
        {'b': 'y'},
      ],
      'c': true,
    }, (s) => s.toUpperCase());
    expect(out, {
      'a': [
        'X',
        1,
        {'b': 'Y'},
      ],
      'c': true,
    });
    expect(PackStyle.strings(out).toList(), ['X', 'Y']);
  });

  test('relativePath and the placeholder pattern', () {
    expect(PackStyle.relativePath('pack://fonts/x'), 'fonts/x');
    expect(PackStyle.relativePath('file:///x'), isNull);
    expect(PackStyle.placeholderPattern.hasMatch('___SPRITE_URI___'), isTrue);
  });

  group('GlyphRange', () {
    test('parses only the 256 real ranges', () {
      expect(GlyphRange.parse('256-511').start, 256);
      for (final bad in ['0-256', '1-256', '65536-65791', 'x']) {
        expect(() => GlyphRange.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('finds the range of a code point', () {
      expect(GlyphRange.containing('č'.codeUnitAt(0))!.name, '256-511');
      expect(GlyphRange.containing('A'.codeUnitAt(0))!.name, '0-255');
      expect(GlyphRange.containing(0x1F600), isNull);
    });

    test('lists every range in order', () {
      expect(GlyphRange.all, hasLength(256));
      expect(GlyphRange.all.last.name, '65280-65535');
      expect(GlyphRange.latin.map((r) => r.name), ['0-255', '256-511']);
    });
  });
}
