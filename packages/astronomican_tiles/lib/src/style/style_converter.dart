import 'dart:convert';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:meta/meta.dart';

import '../cli/tiles_exception.dart';
import '../config/map_config.dart';
import 'style_source.dart';

/// A sprite the pack ships: its four files, fetched or copied from [source].
@immutable
final class SpriteRef {
  /// The sprite [id] of the style, shipped as [name] (`sprite`, or
  /// `sprite-<id>` in a sprite array) from [source].
  const SpriteRef({required this.id, required this.name, required this.source});

  /// Its id in a sprite array; `default` for a plain sprite.
  final String id;

  /// The file stem inside the pack.
  final String name;

  /// The sprite URL without extension, as MapLibre would append to it.
  final Uri source;

  /// The four files MapLibre reads, `@2x` on high-density screens.
  static const List<String> suffixes = ['.json', '.png', '@2x.json', '@2x.png'];
}

/// A style made ready for a pack, and what the pack needs to go with it.
@immutable
final class StyleConversion {
  /// The result of [StyleConverter.convert].
  const StyleConversion({
    required this.style,
    required this.sprites,
    required this.fontStacks,
    required this.fontSources,
    required this.extraFiles,
    required this.textKeys,
    required this.warnings,
  });

  /// The style in pack form: tiles, sprite and glyphs all `pack://`.
  final Map<String, Object?> style;

  /// The sprites to ship.
  final List<SpriteRef> sprites;

  /// Every font stack its labels can ask for.
  final Set<String> fontStacks;

  /// Where the style itself kept its fonts, usable as providers: folders
  /// (`file:`) and public URL templates.
  final List<String> fontSources;

  /// Other files the style names, by their path in the pack.
  final Map<String, Uri> extraFiles;

  /// The feature properties its labels show, such as `name:latin`.
  final Set<String> textKeys;

  /// What was changed or left out, for the user.
  final List<String> warnings;
}

/// Turns any MapLibre style for OpenMapTiles-schema tiles into the pack form.
///
/// * The tiles source (`tilesSource`, else `openmaptiles`, else the only
///   vector source) becomes `pack://<id>.mbtiles`.
/// * An attribution-only source, as OSM OpenMapTiles has, is removed —
///   MapLibre Native rejects a vector source with no tiles.
/// * Other online sources, with their layers, are dropped (or kept, with a
///   warning, when asked; never with a key in the URL).
/// * The sprite becomes `pack://sprite`, the glyphs
///   `pack://fonts/{fontstack}/{range}.pbf`.
/// * Nothing may be left that carries a key, a token or an unfilled
///   `___PLACEHOLDER___`.
class StyleConverter {
  /// A converter.
  const StyleConverter();

  static final RegExp _secret = RegExp(
    r'([?&](key|access_token|api_key|apikey)=)',
  );

  /// [loaded] in pack form for pack [id].
  ///
  /// [vectorLayers], the tiles' layer names when known, turns a style drawn
  /// for another schema into a warning rather than a blank map.
  StyleConversion convert(
    LoadedStyle loaded, {
    required String id,
    required String attribution,
    String? tilesSource,
    OtherSources otherSources = OtherSources.drop,
    Set<String>? vectorLayers,
  }) {
    final warnings = <String>[];
    final tiles = 'pack://$id.mbtiles';
    var style =
        PackStyle.mapStrings(
              jsonDecode(jsonEncode(loaded.json)),
              (s) => _replaceAll(s, PackStyle.legacyTokensFor('$id.mbtiles')),
            )!
            as Map<String, Object?>;

    // Sources.
    final sources = (style['sources'] as Map<String, Object?>?) ?? {};
    final tilesKey = _tilesSource(sources, tilesSource, loaded.label);
    final kept = <String, Object?>{};
    final dropped = <String>{};
    final extraFiles = <String, Uri>{};
    for (final MapEntry(:key, :value) in sources.entries) {
      final source = value is Map<String, Object?>
          ? value
          : <String, Object?>{};
      if (key == tilesKey) {
        kept[key] = {
          'type': 'vector',
          'url': tiles,
          'attribution': attribution,
        };
        continue;
      }
      final urls = [
        if (source['url'] is String) source['url']! as String,
        if (source['data'] is String) source['data']! as String,
        ...?(source['tiles'] as List<Object?>?)?.whereType<String>(),
      ];
      if (urls.isEmpty) {
        if (source['type'] == 'vector' || source['type'] == 'raster') {
          // An attribution holder with no tiles: MapLibre Native refuses it.
          dropped.add(key);
          continue;
        }
        kept[key] = source; // inline GeoJSON
        continue;
      }
      final remote = urls.any(
        (u) => u.startsWith('http://') || u.startsWith('https://'),
      );
      if (remote) {
        if (otherSources == OtherSources.keep) {
          if (urls.any(_secret.hasMatch)) {
            throw TilesException.config(
              'The source "$key" of ${loaded.label} needs a key '
              '(${urls.first}); it cannot be kept. Leave otherSources: drop.',
            );
          }
          warnings.add('source "$key" stays online: ${urls.first}');
          kept[key] = source;
        } else {
          warnings.add(
            'dropped online source "$key" and its layers (${urls.first})',
          );
          dropped.add(key);
        }
        continue;
      }
      if (source['type'] == 'geojson' && source['data'] is String) {
        final from = loaded.resolve(source['data']! as String);
        if (from == null) {
          throw TilesException.config(
            'Cannot read the GeoJSON of source "$key"',
          );
        }
        final name = 'data/$key.geojson';
        extraFiles[name] = from;
        kept[key] = {...source, 'data': 'pack://$name'};
        continue;
      }
      throw TilesException.config(
        'The source "$key" of ${loaded.label} is a local ${source['type']} '
        'source; only the tiles source and GeoJSON files can be packed.',
      );
    }
    style['sources'] = kept;

    // Layers of dropped sources go with them.
    final layers = <Object?>[];
    for (final layer in (style['layers'] as List<Object?>?) ?? const []) {
      if (layer is! Map<String, Object?>) continue;
      final source = layer['source'];
      if (source is String) {
        if (dropped.contains(source)) continue;
        if (!kept.containsKey(source)) {
          throw TilesException.config(
            'The layer "${layer['id']}" of ${loaded.label} draws the unknown '
            'source "$source"',
          );
        }
      }
      layers.add(layer);
    }
    style['layers'] = layers;

    // Sprite.
    final sprites = <SpriteRef>[];
    final sprite = style['sprite'];
    if (sprite is String) {
      sprites.add(_sprite('default', 'sprite', sprite, loaded));
      style['sprite'] = PackStyle.defaultSprite;
    } else if (sprite is List<Object?>) {
      final rewritten = <Object?>[];
      for (final entry in sprite) {
        if (entry is! Map<String, Object?>) continue;
        final spriteId = '${entry['id']}';
        final name = spriteId == 'default' ? 'sprite' : 'sprite-$spriteId';
        sprites.add(_sprite(spriteId, name, '${entry['url']}', loaded));
        rewritten.add({...entry, 'url': 'pack://$name'});
      }
      style['sprite'] = rewritten;
    }

    // Glyphs.
    final fontStacks = PackStyle.fontStacks(style, includeDefault: true);
    final fontSources = <String>[];
    final glyphs = style['glyphs'];
    if (glyphs is String) {
      final source = _glyphSource(glyphs, loaded);
      if (source != null) fontSources.add(source);
    }
    if (fontStacks.isNotEmpty || glyphs != null) {
      style['glyphs'] = PackStyle.defaultGlyphs;
    }

    // Nothing secret, nothing unfilled.
    final problems = <String>[];
    // `metadata` is for editors and never fetched; presets keep MapTiler
    // URLs there.
    for (final s in PackStyle.strings(_withoutMetadata(style))) {
      if (_secret.hasMatch(s)) problems.add('a key or token: $s');
      if (PackStyle.placeholderPattern.hasMatch(s)) {
        problems.add('an unfilled placeholder: $s');
      }
    }
    if (problems.isNotEmpty) {
      throw TilesException.config(
        '${loaded.label} still has ${problems.join('; ')}',
      );
    }

    // Drawn for these tiles?
    if (vectorLayers != null && vectorLayers.isNotEmpty) {
      final missing = <String>{
        for (final layer in layers.cast<Map<String, Object?>>())
          if (layer['source'] == tilesKey &&
              layer['source-layer'] is String &&
              !vectorLayers.contains(layer['source-layer']))
            layer['source-layer']! as String,
      };
      if (missing.isNotEmpty) {
        warnings.add(
          'the style draws layers the tiles do not have: '
          '${(missing.toList()..sort()).join(', ')} — is it made for another '
          'schema than OpenMapTiles?',
        );
      }
    }

    style = _withoutRendererMetadata(style);
    return StyleConversion(
      style: style,
      sprites: sprites,
      fontStacks: fontStacks,
      fontSources: fontSources,
      extraFiles: extraFiles,
      textKeys: textKeys(style),
      warnings: warnings,
    );
  }

  /// The feature properties [style]'s labels show: `{name:latin}` tokens and
  /// `["get", "name"]` expressions in `text-field`.
  static Set<String> textKeys(Map<String, Object?> style) {
    final keys = <String>{};
    void visit(Object? node) {
      switch (node) {
        case final String s:
          for (final m in RegExp(r'\{([^{}]+)\}').allMatches(s)) {
            keys.add(m.group(1)!);
          }
        case final List<Object?> list:
          if (list.length == 2 && list[0] == 'get' && list[1] is String) {
            keys.add(list[1]! as String);
          }
          list.forEach(visit);
        case final Map<String, Object?> map:
          map.values.forEach(visit);
      }
    }

    for (final layer in (style['layers'] as List<Object?>?) ?? const []) {
      if (layer is Map<String, Object?>) {
        visit((layer['layout'] as Map<String, Object?>?)?['text-field']);
      }
    }
    return keys;
  }

  String _tilesSource(
    Map<String, Object?> sources,
    String? configured,
    String label,
  ) {
    if (configured != null) {
      if (!sources.containsKey(configured)) {
        throw TilesException.config(
          'tilesSource "$configured" is not a source of $label '
          '(${sources.keys.join(', ')})',
        );
      }
      return configured;
    }
    bool isVector(Object? s) =>
        s is Map<String, Object?> &&
        s['type'] == 'vector' &&
        (s['url'] != null || s['tiles'] != null);
    if (isVector(sources['openmaptiles'])) return 'openmaptiles';
    final vectors = [
      for (final MapEntry(:key, :value) in sources.entries)
        if (isVector(value)) key,
    ];
    if (vectors.length == 1) return vectors.single;
    throw TilesException.config(
      vectors.isEmpty
          ? '$label has no vector source to draw the pack\'s tiles with'
          : '$label has several vector sources (${vectors.join(', ')}); say '
                'which one is the pack\'s tiles with tilesSource in map.yaml',
    );
  }

  SpriteRef _sprite(String id, String name, String value, LoadedStyle loaded) {
    if (_secret.hasMatch(value)) {
      throw TilesException.config(
        'The sprite of ${loaded.label} needs a key ($value); use a public one '
        'or a copy beside map.yaml.',
      );
    }
    final source = loaded.resolve(value);
    if (source == null) {
      throw TilesException.config(
        'Cannot find the sprite "$value" of ${loaded.label}',
      );
    }
    return SpriteRef(id: id, name: name, source: source);
  }

  /// A usable font source from the style's own glyph template: a folder for
  /// a local one, the template for a public URL; never one with a key, nor
  /// MapTiler's, which always needs one.
  String? _glyphSource(String template, LoadedStyle loaded) {
    if (!template.endsWith('{fontstack}/{range}.pbf')) return null;
    final head = template.substring(
      0,
      template.length - '{fontstack}/{range}.pbf'.length,
    );
    if (head.startsWith('http://') || head.startsWith('https://')) {
      if (_secret.hasMatch(template) || template.contains('api.maptiler.com')) {
        return null;
      }
      return template;
    }
    if (!loaded.isLocal) {
      // A relative template in a fetched style: under the style's URL.
      return '${loaded.base.resolve('.')}$head{fontstack}/{range}.pbf';
    }
    final relative = head.startsWith('pack://') ? head.substring(7) : head;
    final folder = loaded.base.resolve(
      relative.isEmpty
          ? '.'
          : relative.split('/').map(Uri.encodeComponent).join('/'),
    );
    return folder.toFilePath();
  }

  static String _replaceAll(String s, Map<String, String> tokens) {
    var out = s;
    tokens.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  static Object? _withoutMetadata(Object? node) => switch (node) {
    final Map<String, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key != 'metadata') key: _withoutMetadata(value),
    },
    final List<Object?> list => [
      for (final item in list) _withoutMetadata(item),
    ],
    _ => node,
  };

  static Map<String, Object?> _withoutRendererMetadata(
    Map<String, Object?> style,
  ) {
    final metadata = style['metadata'];
    if (metadata is Map<String, Object?>) {
      metadata.removeWhere((k, _) => k.startsWith('maputnik:'));
    }
    return style;
  }
}
