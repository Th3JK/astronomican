import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cli/tiles_exception.dart';
import '../net/fetcher.dart';

/// Somewhere a font's glyph ranges can be found.
abstract interface class FontProvider {
  /// Where, for error messages.
  String get description;

  /// Whether this provider has [font] at all.
  Future<bool> hasFont(String font);

  /// [font]'s file for [range], or null when it does not cover the range.
  Future<Uint8List?> read(String font, GlyphRange range);
}

/// Fonts in a folder: `<folder>/<font>/<range>.pbf`, the layout of a pack's
/// `fonts/`, of the OpenMapTiles fonts and of TileServer GL.
class DirectoryFontProvider implements FontProvider {
  /// Fonts under [directory].
  DirectoryFontProvider(this.directory);

  /// The folder.
  final Directory directory;

  @override
  String get description => directory.path;

  @override
  Future<bool> hasFont(String font) =>
      Directory(p.join(directory.path, font)).exists();

  @override
  Future<Uint8List?> read(String font, GlyphRange range) async {
    final file = File(p.join(directory.path, font, '${range.name}.pbf'));
    return await file.exists() ? file.readAsBytes() : null;
  }
}

/// Fonts behind a URL template with `{fontstack}` and `{range}`, fetched
/// once and kept in the cache.
class UrlFontProvider implements FontProvider {
  /// Fonts at [template], cached under [cache].
  UrlFontProvider(this.template, this._fetcher, Directory cache)
    : _cache = Directory(p.join(cache.path, 'fonts', 'url', _hash(template)));

  /// The URL template.
  final String template;
  final Fetcher _fetcher;
  final Directory _cache;
  final Map<String, bool> _has = {};

  @override
  String get description => template;

  @override
  Future<bool> hasFont(String font) async =>
      _has[font] ??= await read(font, GlyphRange.all.first) != null;

  @override
  Future<Uint8List?> read(String font, GlyphRange range) async {
    final file = File(p.join(_cache.path, font, '${range.name}.pbf'));
    final missing = File('${file.path}.missing');
    if (await file.exists()) return file.readAsBytes();
    if (await missing.exists()) return null;
    final uri = Uri.parse(
      template
          .replaceAll('{fontstack}', Uri.encodeComponent(font))
          .replaceAll('{range}', range.name),
    );
    final bytes = await _fetcher.get(uri);
    await file.parent.create(recursive: true);
    if (bytes == null) {
      await missing.writeAsString('');
      return null;
    }
    await file.writeAsBytes(bytes);
    return bytes;
  }

  static String _hash(String s) =>
      sha1.convert(utf8.encode(s)).toString().substring(0, 16);
}

/// The OpenMapTiles fonts release: Noto Sans, Open Sans, Metropolis, PT Sans
/// and Roboto, every range — every font the OpenMapTiles styles name.
///
/// Downloaded once into the cache, the first time a font is not found
/// anywhere closer, and read one entry at a time without unpacking the rest.
class OpenMapTilesFontsProvider implements FontProvider {
  /// The release, cached as [zip] and fetched with [fetcher] when absent.
  OpenMapTilesFontsProvider(this.zip, this._fetcher, {this.onDownload});

  /// Where the release zip is kept.
  final File zip;
  final Fetcher _fetcher;

  /// Told before the one-time download starts.
  final void Function()? onDownload;

  /// The release.
  static final Uri url = Uri.parse(
    'https://github.com/openmaptiles/fonts/releases/download/v2.0/v2.0.zip',
  );

  /// Its SHA-256.
  static const String sha256 =
      '3a7a6c2dcd940a840aa6ffac8f39758252a667a0b329945b071fb44bf00e7f47';

  Map<String, ArchiveFile>? _entries;

  @override
  String get description => 'OpenMapTiles fonts v2.0 ($url)';

  @override
  Future<bool> hasFont(String font) async {
    final entries = await _index();
    return entries.containsKey('$font/0-255.pbf') ||
        entries.keys.any((k) => k.startsWith('$font/'));
  }

  @override
  Future<Uint8List?> read(String font, GlyphRange range) async {
    final entry = (await _index())['$font/${range.name}.pbf'];
    return entry?.readBytes();
  }

  Future<Map<String, ArchiveFile>> _index() async {
    final existing = _entries;
    if (existing != null) return existing;
    if (!await zip.exists()) {
      onDownload?.call();
      await _fetcher.download(url, zip, sha256: sha256);
    }
    final archive = ZipDecoder().decodeStream(InputFileStream(zip.path));
    final entries = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final parts = file.name.replaceAll(r'\', '/').split('/');
      if (parts.length < 2 || !parts.last.endsWith('.pbf')) continue;
      // Keyed by the last two segments, whatever folder the zip nests them in.
      entries['${parts[parts.length - 2]}/${parts.last}'] = file;
    }
    return _entries = entries;
  }
}

/// Finds each font in the first provider that has it.
class FontResolver {
  /// A resolver trying [providers] in order.
  FontResolver(this.providers);

  /// Where fonts are looked for, closest first.
  final List<FontProvider> providers;
  final Map<String, FontProvider?> _chosen = {};

  /// The provider for [font], or null when none has it.
  Future<FontProvider?> providerFor(String font) async {
    if (_chosen.containsKey(font)) return _chosen[font];
    for (final provider in providers) {
      if (await provider.hasFont(font)) return _chosen[font] = provider;
    }
    return _chosen[font] = null;
  }

  /// Throws unless every font of [stacks] can be found.
  Future<void> check(Iterable<String> stacks) async {
    final missing = <String>{};
    for (final stack in stacks) {
      for (final font in stack.split(',')) {
        if (await providerFor(font) == null) missing.add(font);
      }
    }
    if (missing.isEmpty) return;
    throw TilesException.config(
      'No glyphs for ${missing.map((f) => '"$f"').join(', ')}. Looked in:\n'
      '${providers.map((p) => '  - ${p.description}').join('\n')}\n'
      'Add a folder or a URL template with {fontstack} and {range} under '
      'glyphs.sources in map.yaml.',
    );
  }

  /// [font]'s file for [range], or null.
  Future<Uint8List?> read(String font, GlyphRange range) async =>
      (await providerFor(font))?.read(font, range);
}
