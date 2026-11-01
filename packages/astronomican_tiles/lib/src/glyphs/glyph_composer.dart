import 'dart:typed_data';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';

import 'glyph_pbf.dart';

/// Builds the one range file MapLibre asks for when a label's `text-font`
/// names several fonts.
///
/// MapLibre Native asks for `["Metropolis Regular", "Noto Sans Regular"]` as
/// a single stack, `Metropolis Regular,Noto Sans Regular/0-255.pbf`, and draws
/// whatever glyphs that file holds. Servers composite those files on request;
/// a pack has no server, so they are composited here, the same way: the first
/// font that has a glyph wins it, and the later fonts fill the gaps.
abstract final class GlyphComposer {
  /// The range file for stack [stackName] and [range], from the range files of
  /// its fonts in stack order, null where a font lacks the range.
  ///
  /// A stack of one font is its font's file, unchanged. A range no font
  /// covers is a valid, empty file — MapLibre waits forever for a missing
  /// one, and every label in the tile waits with it.
  static Uint8List composite(
    String stackName,
    GlyphRange range,
    List<Uint8List?> members,
  ) {
    if (members.length == 1) {
      final only = members.single;
      if (only == null) return GlyphPbf.empty(stackName, range.name);
      if (!_gzipped(only)) return only;
    }
    final present = members.whereType<Uint8List>().toList();
    if (present.isEmpty) return GlyphPbf.empty(stackName, range.name);

    final byId = <int, Glyph>{};
    Uint8List? unknown;
    for (final member in present) {
      for (final stack in GlyphPbf.decode(member)) {
        unknown ??= stack.unknown;
        for (final glyph in stack.glyphs) {
          byId.putIfAbsent(glyph.id, () => glyph);
        }
      }
    }
    final glyphs = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return GlyphPbf.encode([
      GlyphStack(
        name: stackName,
        range: range.name,
        glyphs: glyphs,
        unknown: unknown,
      ),
    ]);
  }

  static bool _gzipped(Uint8List bytes) =>
      bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
}
