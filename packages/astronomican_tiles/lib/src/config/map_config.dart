import 'dart:io';
import 'dart:math' as math;

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../cli/tiles_exception.dart';
import '../docker/images.dart';

/// Where a map's tiles come from.
@immutable
sealed class TilesInput {
  const TilesInput();
}

/// A Geofabrik extract, downloaded by Planetiler.
final class AreaInput extends TilesInput {
  /// The extract with Geofabrik id [area], such as `jihocesky`.
  const AreaInput(this.area);

  /// The Geofabrik id.
  final String area;
}

/// A local OpenStreetMap extract.
final class OsmInput extends TilesInput {
  /// The `.osm.pbf` at [file].
  const OsmInput(this.file);

  /// The extract.
  final File file;
}

/// Tiles made elsewhere — tilemaker, a download — used as they are.
final class ExistingTilesInput extends TilesInput {
  /// The `.mbtiles` at [file].
  const ExistingTilesInput(this.file);

  /// The tiles.
  final File file;
}

/// What happens to a style's sources other than the pack's tiles.
enum OtherSources {
  /// Removed, with the layers drawing them. The pack stays fully offline.
  drop,

  /// Kept online, with a warning. Refused for a URL carrying a key.
  keep,
}

/// A map's `map.yaml`: everything that makes one pack.
@immutable
final class MapConfig {
  /// A config; see [load].
  const MapConfig({
    required this.file,
    required this.id,
    required this.version,
    required this.input,
    required this.style,
    this.name,
    this.attribution = Upstream.attribution,
    this.bounds,
    this.minZoom = 0,
    this.maxZoom = 14,
    this.tilesSource,
    this.otherSources = OtherSources.drop,
    this.glyphRanges = const [],
    this.detectGlyphRanges = true,
    this.glyphSources = const [],
    this.memory = '2g',
    this.languages = const [],
    this.excludeLayers = const [],
    this.planetilerArgs = const [],
    this.output,
    this.splitMegabytes,
    this.assetPrefix,
    this.previewPort = 8080,
    this.editorPort = 8888,
    this.images = const Images(),
  });

  /// The map.yaml this came from.
  final File file;

  /// The folder of [file]; relative paths are read from here.
  Directory get directory => file.parent;

  /// Where generated files go: `.work` beside map.yaml.
  Directory get workDirectory => Directory(p.join(directory.path, '.work'));

  /// The pack's id.
  final String id;

  /// A human name.
  final String? name;

  /// The pack's version: the "this is new" flag installed apps read.
  final int version;

  /// The credit the data asks for.
  final String attribution;

  /// Where the tiles come from.
  final TilesInput input;

  /// `[west, south, east, north]`, or null for the whole input.
  final List<double>? bounds;

  /// The lowest zoom generated.
  final int minZoom;

  /// The highest zoom generated; MapLibre overzooms past it.
  final int maxZoom;

  /// A preset name, a path relative to map.yaml, or a URL.
  final String style;

  /// Which of the style's sources becomes the pack's tiles.
  final String? tilesSource;

  /// What happens to the style's other sources.
  final OtherSources otherSources;

  /// The glyph ranges always shipped; `0-255` is always among them.
  final List<GlyphRange> glyphRanges;

  /// Whether the ranges the tiles' labels need are added.
  final bool detectGlyphRanges;

  /// Extra places fonts are looked for: folders or URL templates.
  final List<String> glyphSources;

  /// Planetiler's Java heap, such as `2g`.
  final String memory;

  /// Planetiler `--languages`: the `name:xx` tags kept.
  final List<String> languages;

  /// Planetiler `--exclude_layers`.
  final List<String> excludeLayers;

  /// More Planetiler arguments, passed as they are.
  final List<String> planetilerArgs;

  /// Where `pack` publishes the pack, such as an app's `assets/packs/<id>`.
  final Directory? output;

  /// Files larger than this many megabytes are published in pieces.
  final int? splitMegabytes;

  /// The output's asset path, for the pubspec lines printed.
  final String? assetPrefix;

  /// The preview's port on 127.0.0.1.
  final int previewPort;

  /// Maputnik's port on 127.0.0.1.
  final int editorPort;

  /// The images run.
  final Images images;

  /// Every glyph range to ship, before detection.
  List<GlyphRange> get baseGlyphRanges {
    final ranges = {...GlyphRange.latin.take(1), ...glyphRanges};
    return ranges.toList()..sort();
  }

  static const Set<String> _keys = {
    'id',
    'name',
    'version',
    'attribution',
    'area',
    'osm',
    'tiles',
    'bounds',
    'minZoom',
    'maxZoom',
    'style',
    'tilesSource',
    'otherSources',
    'glyphs',
    'planetiler',
    'output',
    'split',
    'assetPrefix',
    'preview',
    'images',
  };

  /// Reads and checks [file], a map.yaml or the folder holding one.
  ///
  /// Throws [TilesException] naming the line and column of what is wrong.
  static MapConfig load(String path) {
    var file = File(path);
    if (FileSystemEntity.isDirectorySync(path)) {
      file = File(p.join(path, 'map.yaml'));
    }
    if (!file.existsSync()) {
      throw TilesException.missing(
        'No map.yaml at ${file.path}. Create one with '
        '`astronomican_tiles init <folder>`.',
      );
    }
    final YamlNode root;
    try {
      root = loadYamlNode(
        file.readAsStringSync(),
        sourceUrl: file.absolute.uri,
      );
    } on YamlException catch (e) {
      throw TilesException.config(e.toString());
    }
    return _Parser(file.absolute).parse(root);
  }
}

class _Parser {
  _Parser(this.file);

  final File file;

  Never fail(YamlNode node, String message) {
    final at = node.span.start;
    throw TilesException.config(
      '${file.path}:${at.line + 1}:${at.column + 1}: $message',
    );
  }

  MapConfig parse(YamlNode root) {
    if (root is! YamlMap) fail(root, 'map.yaml must be a mapping of keys');
    for (final key in root.nodes.keys) {
      final name = (key as YamlNode).value;
      if (name is! String || !MapConfig._keys.contains(name)) {
        final hint = name is String ? _closest(name, MapConfig._keys) : null;
        fail(
          key,
          'unknown key "$name"${hint == null ? '' : ' — did you mean "$hint"?'}',
        );
      }
    }

    final id = _string(root, 'id', required: true)!;
    if (!MapPackManifest.isValidId(id)) {
      fail(
        root.nodes['id']!,
        '"$id" is not a valid pack id: lowercase letters, digits, _ . and -',
      );
    }
    final version = _int(root, 'version', required: true)!;
    if (version < 1) fail(root.nodes['version']!, 'version must be 1 or more');

    final inputs = [
      for (final k in const ['area', 'osm', 'tiles'])
        if (root.containsKey(k)) k,
    ];
    if (inputs.length != 1) {
      fail(
        root,
        inputs.isEmpty
            ? 'say where the tiles come from: area (a Geofabrik id), osm (an '
                  '.osm.pbf file) or tiles (an .mbtiles file)'
            : 'give only one of area, osm and tiles',
      );
    }
    final TilesInput input = switch (inputs.single) {
      'area' => AreaInput(_area(root)),
      'osm' => OsmInput(_file(root, 'osm', '.osm.pbf')),
      _ => ExistingTilesInput(_file(root, 'tiles', '.mbtiles')),
    };

    final bounds = _bounds(root);
    if (input is OsmInput && bounds == null) {
      fail(
        root.nodes['osm']!,
        'with osm, give bounds: [west, south, east, north]',
      );
    }
    final minZoom = _int(root, 'minZoom') ?? 0;
    final maxZoom = _int(root, 'maxZoom') ?? 14;
    if (minZoom < 0 || maxZoom > 15 || minZoom > maxZoom) {
      fail(
        root.nodes['maxZoom'] ?? root.nodes['minZoom'] ?? root,
        'zooms must be 0 ≤ minZoom ≤ maxZoom ≤ 15 (OpenMapTiles stops at 15)',
      );
    }

    final glyphs = _map(root, 'glyphs', const {'ranges', 'detect', 'sources'});
    final planetiler = _map(root, 'planetiler', const {
      'memory',
      'languages',
      'excludeLayers',
      'args',
    });
    final preview = _map(root, 'preview', const {'port', 'editorPort'});
    final images = _map(root, 'images', const {
      'planetiler',
      'spreet',
      'tileserver',
      'maputnik',
    });

    final output = _string(root, 'output');
    final other = _string(root, 'otherSources') ?? 'drop';
    if (!const {'drop', 'keep'}.contains(other)) {
      fail(root.nodes['otherSources']!, 'otherSources is drop or keep');
    }

    return MapConfig(
      file: file,
      id: id,
      name: _string(root, 'name'),
      version: version,
      attribution: _string(root, 'attribution') ?? Upstream.attribution,
      input: input,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      style: _string(root, 'style') ?? 'osm-bright',
      tilesSource: _string(root, 'tilesSource'),
      otherSources: other == 'keep' ? OtherSources.keep : OtherSources.drop,
      glyphRanges: glyphs == null ? GlyphRange.latin : _ranges(glyphs),
      detectGlyphRanges: glyphs == null
          ? true
          : (_bool(glyphs, 'detect') ?? true),
      glyphSources: glyphs == null
          ? const []
          : [
              for (final s in _strings(glyphs, 'sources'))
                s.contains('://') || p.isAbsolute(s)
                    ? s
                    : p.normalize(p.join(file.parent.path, s)),
            ],
      memory: planetiler == null
          ? '2g'
          : (_string(planetiler, 'memory') ?? '2g'),
      languages: planetiler == null
          ? const []
          : _strings(planetiler, 'languages'),
      excludeLayers: planetiler == null
          ? const []
          : _strings(planetiler, 'excludeLayers'),
      planetilerArgs: planetiler == null
          ? const []
          : _strings(planetiler, 'args'),
      output: output == null
          ? null
          : Directory(p.normalize(p.join(file.parent.path, output))),
      splitMegabytes: _int(root, 'split'),
      assetPrefix: _string(root, 'assetPrefix'),
      previewPort: preview == null ? 8080 : (_int(preview, 'port') ?? 8080),
      editorPort: preview == null
          ? 8888
          : (_int(preview, 'editorPort') ?? 8888),
      images: Images(
        planetiler: _string(images, 'planetiler') ?? Images.defaultPlanetiler,
        spreet: _string(images, 'spreet') ?? Images.defaultSpreet,
        tileserver: _string(images, 'tileserver') ?? Images.defaultTileserver,
        maputnik: _string(images, 'maputnik') ?? Images.defaultMaputnik,
      ),
    );
  }

  String _area(YamlMap root) {
    final raw = _string(root, 'area', required: true)!;
    // "europe/czech-republic/jihocesky" names the same extract as "jihocesky";
    // Planetiler matches Geofabrik ids, not paths.
    final area = raw.split('/').where((s) => s.isNotEmpty).last;
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(area)) {
      fail(
        root.nodes['area']!,
        '"$raw" is not a Geofabrik id such as jihocesky',
      );
    }
    return area;
  }

  File _file(YamlMap root, String key, String extension) {
    final value = _string(root, key, required: true)!;
    final path = p.normalize(p.join(file.parent.path, value));
    if (!value.toLowerCase().endsWith(extension)) {
      fail(root.nodes[key]!, '$key must be a $extension file');
    }
    return File(path);
  }

  List<double>? _bounds(YamlMap root) {
    final node = root.nodes['bounds'];
    if (node == null || node.value == null) return null;
    if (node is! YamlList ||
        node.length != 4 ||
        node.nodes.any((n) => n.value is! num)) {
      fail(node, 'bounds is [west, south, east, north] in degrees');
    }
    final b = [for (final n in node.nodes) (n.value as num).toDouble()];
    if (b[0] >= b[2] ||
        b[1] >= b[3] ||
        b[0] < -180 ||
        b[2] > 180 ||
        b[1] < -85.06 ||
        b[3] > 85.06) {
      fail(
        node,
        'bounds is [west, south, east, north]: west < east, south < north, '
        'within ±180 and ±85',
      );
    }
    return b;
  }

  List<GlyphRange> _ranges(YamlMap glyphs) {
    final node = glyphs.nodes['ranges'];
    if (node == null) return GlyphRange.latin;
    if (node.value == 'all') return GlyphRange.all;
    if (node is! YamlList) {
      fail(node, 'ranges is a list such as [0-255, 256-511], or all');
    }
    return [
      for (final n in node.nodes)
        () {
          try {
            return GlyphRange.parse('${n.value}');
          } on FormatException catch (e) {
            fail(n, e.message);
          }
        }(),
    ];
  }

  YamlMap? _map(YamlMap root, String key, Set<String> keys) {
    final node = root.nodes[key];
    if (node == null || node.value == null) return null;
    if (node is! YamlMap) fail(node, '$key is a mapping');
    for (final k in node.nodes.keys) {
      final name = (k as YamlNode).value;
      if (!keys.contains(name)) {
        final hint = name is String ? _closest(name, keys) : null;
        fail(
          k,
          'unknown key "$key.$name"${hint == null ? '' : ' — did you mean "$key.$hint"?'}',
        );
      }
    }
    return node;
  }

  String? _string(YamlMap? map, String key, {bool required = false}) {
    final node = map?.nodes[key];
    if (node == null || node.value == null) {
      if (required) fail(map!, 'missing "$key"');
      return null;
    }
    final value = node.value;
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    fail(node, '$key must be text');
  }

  int? _int(YamlMap map, String key, {bool required = false}) {
    final node = map.nodes[key];
    if (node == null || node.value == null) {
      if (required) fail(map, 'missing "$key"');
      return null;
    }
    if (node.value is! int) fail(node, '$key must be a whole number');
    return node.value as int;
  }

  bool? _bool(YamlMap map, String key) {
    final node = map.nodes[key];
    if (node == null || node.value == null) return null;
    if (node.value is! bool) fail(node, '$key is true or false');
    return node.value as bool;
  }

  List<String> _strings(YamlMap map, String key) {
    final node = map.nodes[key];
    if (node == null || node.value == null) return const [];
    if (node is! YamlList) fail(node, '$key is a list');
    return [for (final n in node.nodes) '${n.value}'];
  }

  static String? _closest(String name, Set<String> options) {
    String? best;
    var bestDistance = 3;
    for (final option in options) {
      final d = _distance(name.toLowerCase(), option.toLowerCase());
      if (d < bestDistance) {
        best = option;
        bestDistance = d;
      }
    }
    return best;
  }

  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = [i, ...List<int>.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
      previous = current;
    }
    return previous[b.length];
  }
}
