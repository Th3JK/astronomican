import 'dart:convert';
import 'dart:io';

import 'package:astronomican/astronomican.dart';

/// Points a pack's style document at the pack's files on disk.
///
/// A style inside a pack cannot know where the pack will be installed — that
/// is an absolute path into the app's storage, decided on the device. So it
/// names its files relative to the pack, with a `pack://` scheme:
///
/// ```json
/// "sources": { "openmaptiles": { "type": "vector", "url": "pack://town.mbtiles" } },
/// "sprite": "pack://sprite",
/// "glyphs": "pack://fonts/{fontstack}/{range}.pbf"
/// ```
///
/// and this rewrites them to what MapLibre opens: `mbtiles://` for a tileset,
/// which MapLibre's own SQLite source reads (TileJSON from the metadata table,
/// hence a `url` rather than a `tiles` template), and `file://` for anything
/// else. `{fontstack}` and `{range}` are left for MapLibre to fill in per label.
///
/// Styles written for strakonice, with `___MBTILES_URI___`, `___SPRITE_URI___`
/// and `___FONTS_URI___` placeholders, work unchanged: those are mapped onto
/// the pack's tileset, `sprite` and `fonts/` by default.
///
/// The rewrite walks the parsed document and re-encodes it, so no path — with
/// spaces, quotes or backslashes in it — can break the JSON. A broken style is
/// something MapLibre reports only as a blank map.
final class PackStyleResolver {
  /// A resolver for [pack], replacing each key of [tokens] with its value
  /// before `pack://` URIs are rewritten.
  const PackStyleResolver(this.pack, {this.tokens = const {}});

  /// The pack whose files the style names.
  final InstalledPack pack;

  /// Extra substitutions, applied to every string in the document.
  final Map<String, String> tokens;

  /// The placeholders strakonice's style ships with, and what they mean.
  static Map<String, String> get legacyTokens =>
      PackStyle.legacyTokensFor('{mbtiles}');

  /// Every substitution applied: the legacy ones, then [tokens].
  Map<String, String> get effectiveTokens => {
    ...PackStyle.legacyTokensFor(pack.manifest.mbtilesPath),
    ...tokens,
  };

  /// Reads [styleFile], or the pack's own style, and resolves it.
  Future<String> resolve([String? styleFile]) async {
    final path = styleFile ?? pack.manifest.stylePath;
    if (path == null) {
      throw StateError('The pack "${pack.id}" has no style document.');
    }
    return resolveDocument(await pack.file(path).readAsString());
  }

  /// [document], with every token and `pack://` URI resolved.
  String resolveDocument(String document) {
    final text = document.startsWith('﻿') ? document.substring(1) : document;
    final tokens = effectiveTokens;
    return jsonEncode(
      PackStyle.mapStrings(jsonDecode(text), (s) => _rewrite(s, tokens)),
    );
  }

  /// Problems with a resolved style: references left unresolved, files it
  /// names that are not on disk, and fonts with no glyphs. Empty when the
  /// style will draw.
  ///
  /// Worth running in a test against the real pack: every one of these shows
  /// up on a device only as a blank map or labels that never appear.
  Future<List<String>> validate(String resolved) async {
    final issues = <String>[];
    final Object? json;
    try {
      json = jsonDecode(resolved);
    } on FormatException catch (e) {
      return ['not JSON: ${e.message}'];
    }
    if (json is! Map<String, Object?>) return ['not a style document'];

    for (final value in PackStyle.strings(json)) {
      if (value.contains(PackStyle.scheme)) issues.add('unresolved: $value');
      if (PackStyle.placeholderPattern.hasMatch(value)) {
        issues.add('unreplaced placeholder: $value');
      }
    }

    final sources = json['sources'];
    if (sources is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in sources.entries) {
        if (value is! Map<String, Object?>) continue;
        final urls = [
          value['url'],
          value['data'],
          ...?(value['tiles'] as List<Object?>?),
        ];
        for (final url in urls.whereType<String>()) {
          final path = _localPath(url);
          if (path != null &&
              !path.contains('{') &&
              !await File(path).exists()) {
            issues.add('source "$key": no file at $path');
          }
        }
      }
    }

    final sprite = json['sprite'];
    final sprites = <String>[
      if (sprite is String) sprite,
      if (sprite is List<Object?>)
        for (final entry in sprite)
          if (entry is Map<String, Object?> && entry['url'] is String)
            entry['url']! as String,
    ];
    for (final url in sprites) {
      final path = _localPath(url);
      if (path == null) continue;
      for (final suffix in const ['.json', '.png']) {
        if (!await File('$path$suffix').exists()) {
          issues.add('sprite: no file at $path$suffix');
        }
      }
    }

    final glyphs = json['glyphs'];
    final glyphPath = glyphs is String ? _localPath(glyphs) : null;
    if (glyphPath != null) {
      for (final font in PackStyle.fontStacks(json)) {
        final path = glyphPath
            .replaceAll('{fontstack}', font)
            .replaceAll('{range}', '0-255');
        if (!await File(path).exists()) {
          issues.add('font "$font": no glyphs at $path');
        }
      }
    }
    return issues;
  }

  String _rewrite(String value, Map<String, String> tokens) {
    var result = value;
    tokens.forEach((token, replacement) {
      result = result.replaceAll(token, replacement);
    });
    final relative = PackStyle.relativePath(result);
    if (relative == null) return result;
    final absolute = pack.path(relative);
    final plain = relative.split('?').first;
    return plain.endsWith('.mbtiles')
        ? 'mbtiles://$absolute'
        : 'file://$absolute';
  }

  static String? _localPath(String url) {
    for (final scheme in const ['mbtiles://', 'file://']) {
      if (url.startsWith(scheme)) return url.substring(scheme.length);
    }
    return null;
  }
}
