import 'package:meta/meta.dart';

/// One file of a font's glyphs: 256 consecutive code points, `0-255`,
/// `256-511` and so on up to `65280-65535`.
///
/// MapLibre asks for a font stack's glyphs one range at a time, as
/// `{fontstack}/{range}.pbf`, and only for the ranges the labels on screen
/// need. A pack ships the ranges its labels use — and must ship every one of
/// them: MapLibre Native waits for a range that never arrives, and every label
/// in the tile waiting with it stays blank.
@immutable
final class GlyphRange implements Comparable<GlyphRange> {
  const GlyphRange._(this.start);

  /// Parses a range name such as `256-511`.
  ///
  /// Throws [FormatException] for anything that is not one of the 256 ranges.
  factory GlyphRange.parse(String name) {
    final match = RegExp(r'^(\d+)-(\d+)$').firstMatch(name.trim());
    if (match == null) {
      throw FormatException('"$name" is not a glyph range such as 0-255');
    }
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    if (start % 256 != 0 || end != start + 255 || start > 65280) {
      throw FormatException(
        '"$name" is not a glyph range: ranges are 256 code points starting at '
        'a multiple of 256, such as 0-255 or 256-511',
      );
    }
    return GlyphRange._(start);
  }

  /// The range holding [codePoint], or null outside the Basic Multilingual
  /// Plane, which MapLibre does not draw glyphs for.
  static GlyphRange? containing(int codePoint) {
    if (codePoint < 0 || codePoint > 0xFFFF) return null;
    return GlyphRange._(codePoint ~/ 256 * 256);
  }

  /// Every range, in order.
  static final List<GlyphRange> all = List.unmodifiable([
    for (var start = 0; start <= 65280; start += 256) GlyphRange._(start),
  ]);

  /// Latin, plus Latin-1 Supplement and Latin Extended-A — what most European
  /// place names need, Czech included.
  static final List<GlyphRange> latin = List.unmodifiable([
    const GlyphRange._(0),
    const GlyphRange._(256),
  ]);

  /// The first code point.
  final int start;

  /// The last code point.
  int get end => start + 255;

  /// The range's name, as its file is named: `0-255`.
  String get name => '$start-$end';

  /// Whether [codePoint] is in this range.
  bool contains(int codePoint) => codePoint >= start && codePoint <= end;

  @override
  int compareTo(GlyphRange other) => start.compareTo(other.start);

  @override
  bool operator ==(Object other) => other is GlyphRange && other.start == start;

  @override
  int get hashCode => start.hashCode;

  @override
  String toString() => name;
}
