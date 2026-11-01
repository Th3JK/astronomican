import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../cli/tiles_exception.dart';
import '../net/fetcher.dart';
import 'presets.dart';

/// A style document, with where its relative references are read from.
@immutable
final class LoadedStyle {
  /// [json], whose relative references resolve against [base].
  const LoadedStyle(this.json, this.base, {required this.label, this.sha256});

  /// The document.
  final Map<String, Object?> json;

  /// A folder (`file:` URI ending in `/`) or the URL the style came from.
  final Uri base;

  /// What it is, for messages: a preset name, a path or a URL.
  final String label;

  /// Its content hash, recorded in the build record.
  final String? sha256;

  /// Whether [base] is a folder on this machine.
  bool get isLocal => base.scheme == 'file';

  /// Where [reference] in the style points: a `file:` or `http(s):` URI, or
  /// null for what is not a file (an `mbtiles://` source, a template).
  ///
  /// `pack://x` and plain relative paths read from [base], so any pack folder
  /// is itself a valid style source.
  Uri? resolve(String reference) {
    if (reference.startsWith('pack://')) {
      return base.resolve(_escape(reference.substring('pack://'.length)));
    }
    final scheme = RegExp(
      r'^([a-zA-Z][a-zA-Z0-9+.-]*)://',
    ).firstMatch(reference);
    if (scheme != null) {
      final s = scheme.group(1)!.toLowerCase();
      if (s == 'http' || s == 'https' || s == 'file') {
        return Uri.parse(reference);
      }
      return null;
    }
    return base.resolve(_escape(reference));
  }

  static String _escape(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');
}

/// Loads the style a map.yaml names: a preset, a file or a URL.
class StyleLoader {
  /// A loader fetching with [fetcher] and caching under [cache].
  StyleLoader(this._fetcher, this._cache);

  final Fetcher _fetcher;
  final Directory _cache;

  /// The style [value], relative to [mapDirectory] when a path. With
  /// [refresh], a fetched style is fetched again rather than read from the
  /// cache. [buildOpenMapTiles] builds the OSM OpenMapTiles style when that
  /// preset is asked for.
  Future<LoadedStyle> load(
    String value,
    Directory mapDirectory, {
    bool refresh = false,
    Future<LoadedStyle> Function()? buildOpenMapTiles,
  }) async {
    final preset = StylePreset.find(value);
    if (preset != null) {
      if (preset == StylePreset.osmOpenMapTiles) {
        if (buildOpenMapTiles == null) {
          throw StateError('The OSM OpenMapTiles style has to be built.');
        }
        return buildOpenMapTiles();
      }
      return _fetch(preset.url!, label: preset.id, refresh: refresh);
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return _fetch(Uri.parse(value), label: value, refresh: refresh);
    }
    final file = File(p.normalize(p.join(mapDirectory.path, value)));
    if (!await file.exists()) {
      throw TilesException.missing(
        'No style at ${file.path}. Use a preset '
        '(${StylePreset.values.map((s) => s.id).join(', ')}), a path or a URL.',
      );
    }
    final text = await file.readAsString();
    return LoadedStyle(
      _decode(text, file.path),
      Uri.directory(file.parent.absolute.path),
      label: value,
      sha256: sha256.convert(utf8.encode(text)).toString(),
    );
  }

  Future<LoadedStyle> _fetch(
    Uri url, {
    required String label,
    required bool refresh,
  }) async {
    final key = sha1.convert(utf8.encode(url.toString())).toString();
    final cached = File(p.join(_cache.path, 'styles', '$key.json'));
    String text;
    if (!refresh && await cached.exists()) {
      text = await cached.readAsString();
    } else {
      final bytes = await _fetcher.get(url);
      if (bytes == null) throw TilesException.missing('No style at $url');
      text = utf8.decode(bytes);
      await cached.parent.create(recursive: true);
      await cached.writeAsString(text);
    }
    return LoadedStyle(
      _decode(text, url.toString()),
      url,
      label: label,
      sha256: sha256.convert(utf8.encode(text)).toString(),
    );
  }

  static Map<String, Object?> _decode(String text, String where) {
    final body = text.startsWith('﻿') ? text.substring(1) : text;
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      throw TilesException.config('$where is not JSON: ${e.message}');
    }
    if (json is! Map<String, Object?> || json['version'] != 8) {
      throw TilesException.config('$where is not a MapLibre style (version 8)');
    }
    return json;
  }
}
