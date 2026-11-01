import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:path/path.dart' as p;

import '../cli/console.dart';
import '../cli/tiles_exception.dart';
import '../glyphs/font_providers.dart';
import '../glyphs/glyph_composer.dart';
import '../glyphs/glyph_pbf.dart';
import '../net/fetcher.dart';
import '../style/style_converter.dart';
import 'manifest_writer.dart';
import 'pack_validator.dart';

/// Assembles a complete pack folder: tiles, style, sprites, composited
/// glyphs and `pack.json`.
///
/// Built in a sibling `.next` folder and swapped in only once it validates,
/// so a failed build never leaves half a pack where the last good one was.
class PackAssembler {
  /// An assembler fetching with [fetcher], reporting to [console].
  PackAssembler(this._fetcher, this._console);

  final Fetcher _fetcher;
  final Console _console;

  /// Builds the pack [id] v[version] in [into].
  ///
  /// [memberFonts], when given, receives each member font's range files as
  /// TileServer GL wants them — it composites stacks itself — so the preview
  /// draws with exactly the glyphs the pack ships.
  Future<MapPackManifest> assemble({
    required Directory into,
    required String id,
    required int version,
    required File tiles,
    required StyleConversion style,
    required FontResolver fonts,
    required List<GlyphRange> ranges,
    String? name,
    String? attribution,
    List<double>? bounds,
    int? minZoom,
    int? maxZoom,
    Directory? memberFonts,
  }) async {
    final next = Directory('${into.path}.next');
    if (await next.exists()) await next.delete(recursive: true);
    await next.create(recursive: true);

    _console.detail('copying ${tiles.path}');
    await tiles.copy(p.join(next.path, '$id.mbtiles'));

    await File(p.join(next.path, 'style.json')).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(style.style)}\n',
    );

    for (final sprite in style.sprites) {
      for (final suffix in SpriteRef.suffixes) {
        final bytes = await _read(Uri.parse('${sprite.source}$suffix'));
        if (bytes == null) {
          throw TilesException.missing(
            'The sprite has no ${sprite.source}$suffix. MapLibre needs all '
            'four files (.json, .png and their @2x) to draw icons.',
          );
        }
        await File(
          p.join(next.path, '${sprite.name}$suffix'),
        ).writeAsBytes(bytes);
      }
    }

    for (final MapEntry(key: path, value: source) in style.extraFiles.entries) {
      final bytes = await _read(source);
      if (bytes == null) throw TilesException.missing('No file at $source');
      final file = File(p.joinAll([next.path, ...path.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }

    await fonts.check(style.fontStacks);
    final written = <String>{};
    for (final stack in style.fontStacks.toList()..sort()) {
      final members = stack.split(',');
      final folder = Directory(p.join(next.path, 'fonts', stack));
      await folder.create(recursive: true);
      for (final range in ranges) {
        final parts = <Uint8List?>[
          for (final font in members) await fonts.read(font, range),
        ];
        await File(
          p.join(folder.path, '${range.name}.pbf'),
        ).writeAsBytes(GlyphComposer.composite(stack, range, parts));
        if (memberFonts != null) {
          for (var i = 0; i < members.length; i++) {
            final key = '${members[i]}/${range.name}';
            if (!written.add(key)) continue;
            final file = File(
              p.join(memberFonts.path, members[i], '${range.name}.pbf'),
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
              parts[i] ?? GlyphPbf.empty(members[i], range.name),
            );
          }
        }
      }
    }
    _console.detail(
      '${style.fontStacks.length} font stacks × ${ranges.length} ranges',
    );

    final manifest = await const ManifestWriter().write(
      next,
      id: id,
      version: version,
      style: 'style.json',
      name: name,
      attribution: attribution,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    final report = await const PackValidator().validate(next);
    for (final warning in report.warnings) {
      _console.warn(warning);
    }
    if (!report.ok) {
      throw TilesException.config(
        'The assembled pack is not valid:\n'
        '${report.errors.map((e) => '  - $e').join('\n')}',
      );
    }

    if (await into.exists()) await into.delete(recursive: true);
    await next.rename(into.path);
    return manifest;
  }

  Future<Uint8List?> _read(Uri uri) async {
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      return await file.exists() ? file.readAsBytes() : null;
    }
    return _fetcher.get(uri);
  }
}
