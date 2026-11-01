import 'dart:convert' show utf8;
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One glyph of a signed-distance-field font range.
@immutable
final class Glyph {
  /// A glyph for code point [id].
  const Glyph({
    required this.id,
    this.bitmap,
    this.width = 0,
    this.height = 0,
    this.left = 0,
    this.top = 0,
    this.advance = 0,
    this.unknown,
  });

  /// The code point.
  final int id;

  /// The SDF bitmap; absent for a glyph with nothing to draw, such as a space.
  final Uint8List? bitmap;

  /// Bitmap width, without the buffer.
  final int width;

  /// Bitmap height, without the buffer.
  final int height;

  /// Horizontal bearing.
  final int left;

  /// Vertical bearing.
  final int top;

  /// Horizontal advance.
  final int advance;

  /// Fields this reader does not know, kept as they came.
  final Uint8List? unknown;
}

/// The glyphs of one font stack for one range.
@immutable
final class GlyphStack {
  /// [glyphs] of stack [name] for range [range].
  const GlyphStack({
    required this.name,
    required this.range,
    required this.glyphs,
    this.unknown,
  });

  /// The font stack's name, as MapLibre asked for it.
  final String name;

  /// The range, such as `0-255`.
  final String range;

  /// The glyphs.
  final List<Glyph> glyphs;

  /// Fields this reader does not know — newer generators add ascender and
  /// descender — kept as they came.
  final Uint8List? unknown;
}

/// Reads and writes the glyph range files MapLibre loads (`{range}.pbf`):
///
/// ```proto
/// message glyphs { repeated fontstack stacks = 1; extensions 16 to 8191; }
/// message fontstack { required string name = 1; required string range = 2; repeated glyph glyphs = 3; }
/// message glyph { required uint32 id = 1; optional bytes bitmap = 2; required uint32 width = 3;
///                 required uint32 height = 4; required sint32 left = 5; required sint32 top = 6;
///                 required uint32 advance = 7; }
/// ```
///
/// A hand-written protobuf subset — varints, zigzag, length-delimited fields
/// — rather than a generated one, to keep the tool dependency-light. Fields it
/// does not know are carried through untouched. Re-encoding keeps the content
/// but not necessarily the bytes: generators differ in field order (fontnik
/// writes 1–7, Protomaps' fonts write 3, 4, 5, 1, 6, 7), and MapLibre reads
/// either.
abstract final class GlyphPbf {
  /// Decodes [bytes], gunzipping first if they are gzipped (some servers
  /// store the ranges compressed).
  static List<GlyphStack> decode(Uint8List bytes) {
    final data = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        ? Uint8List.fromList(gzip.decode(bytes))
        : bytes;
    final reader = _Reader(data);
    final stacks = <GlyphStack>[];
    while (!reader.done) {
      final start = reader.pos;
      final tag = reader.varint();
      if (tag >> 3 == 1 && tag & 7 == 2) {
        stacks.add(_stack(_Reader(reader.lengthDelimited())));
      } else {
        reader.skip(tag & 7);
        // Top-level extensions carry nothing a composite needs; dropped.
        assert(reader.pos > start);
      }
    }
    return stacks;
  }

  /// Encodes [stacks] as a range file.
  static Uint8List encode(List<GlyphStack> stacks) {
    final out = _Writer();
    for (final stack in stacks) {
      out.message(1, _encodeStack(stack));
    }
    return out.bytes;
  }

  /// A valid range file with no glyphs, for a range none of a stack's fonts
  /// covers. MapLibre accepts it and draws nothing for those characters —
  /// where a missing file would make it wait forever.
  static Uint8List empty(String name, String range) =>
      encode([GlyphStack(name: name, range: range, glyphs: const [])]);

  static GlyphStack _stack(_Reader r) {
    var name = '';
    var range = '';
    final glyphs = <Glyph>[];
    final unknown = BytesBuilder(copy: false);
    while (!r.done) {
      final start = r.pos;
      final tag = r.varint();
      switch ((tag >> 3, tag & 7)) {
        case (1, 2):
          name = r.string();
        case (2, 2):
          range = r.string();
        case (3, 2):
          glyphs.add(_glyph(_Reader(r.lengthDelimited())));
        default:
          r.skip(tag & 7);
          unknown.add(r.bytes.sublist(start, r.pos));
      }
    }
    return GlyphStack(
      name: name,
      range: range,
      glyphs: glyphs,
      unknown: unknown.isEmpty ? null : unknown.takeBytes(),
    );
  }

  static Glyph _glyph(_Reader r) {
    var id = 0, width = 0, height = 0, left = 0, top = 0, advance = 0;
    Uint8List? bitmap;
    final unknown = BytesBuilder(copy: false);
    while (!r.done) {
      final start = r.pos;
      final tag = r.varint();
      switch ((tag >> 3, tag & 7)) {
        case (1, 0):
          id = r.varint();
        case (2, 2):
          bitmap = r.lengthDelimited();
        case (3, 0):
          width = r.varint();
        case (4, 0):
          height = r.varint();
        case (5, 0):
          left = _unzigzag(r.varint());
        case (6, 0):
          top = _unzigzag(r.varint());
        case (7, 0):
          advance = r.varint();
        default:
          r.skip(tag & 7);
          unknown.add(r.bytes.sublist(start, r.pos));
      }
    }
    return Glyph(
      id: id,
      bitmap: bitmap,
      width: width,
      height: height,
      left: left,
      top: top,
      advance: advance,
      unknown: unknown.isEmpty ? null : unknown.takeBytes(),
    );
  }

  static Uint8List _encodeStack(GlyphStack stack) {
    final out = _Writer()
      ..string(1, stack.name)
      ..string(2, stack.range);
    for (final glyph in stack.glyphs) {
      out.message(3, _encodeGlyph(glyph));
    }
    if (stack.unknown case final unknown?) out.raw(unknown);
    return out.bytes;
  }

  static Uint8List _encodeGlyph(Glyph glyph) {
    final out = _Writer()..uint(1, glyph.id);
    if (glyph.bitmap case final bitmap?) out.message(2, bitmap);
    out
      ..uint(3, glyph.width)
      ..uint(4, glyph.height)
      ..uint(5, _zigzag(glyph.left))
      ..uint(6, _zigzag(glyph.top))
      ..uint(7, glyph.advance);
    if (glyph.unknown case final unknown?) out.raw(unknown);
    return out.bytes;
  }

  static int _zigzag(int n) => ((n << 1) ^ (n >> 31)) & 0xFFFFFFFF;

  static int _unzigzag(int n) => (n >>> 1) ^ -(n & 1);
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int pos = 0;

  bool get done => pos >= bytes.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (pos >= bytes.length) {
        throw const FormatException('Truncated protobuf varint');
      }
      final b = bytes[pos++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('Protobuf varint too long');
    }
  }

  Uint8List lengthDelimited() {
    final length = varint();
    if (pos + length > bytes.length) {
      throw const FormatException('Truncated protobuf field');
    }
    final value = Uint8List.sublistView(bytes, pos, pos + length);
    pos += length;
    return value;
  }

  String string() => utf8.decode(lengthDelimited());

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        varint();
      case 1:
        pos += 8;
      case 2:
        lengthDelimited();
      case 5:
        pos += 4;
      default:
        throw FormatException('Unsupported protobuf wire type $wireType');
    }
    if (pos > bytes.length) throw const FormatException('Truncated protobuf');
  }
}

class _Writer {
  final BytesBuilder _out = BytesBuilder(copy: false);

  Uint8List get bytes => _out.takeBytes();

  void _varint(int value) {
    var v = value;
    while (v >= 0x80 || v < 0) {
      _out.addByte((v & 0x7f) | 0x80);
      v >>>= 7;
    }
    _out.addByte(v);
  }

  void uint(int field, int value) {
    _varint(field << 3);
    _varint(value);
  }

  void message(int field, Uint8List value) {
    _varint(field << 3 | 2);
    _varint(value.length);
    _out.add(value);
  }

  void string(int field, String value) => message(field, utf8.encode(value));

  void raw(Uint8List bytes) => _out.add(bytes);
}
