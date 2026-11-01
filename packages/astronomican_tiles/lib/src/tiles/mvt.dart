import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// Reads the label text out of Mapbox Vector Tiles.
///
/// Only as much of the format as finding the strings a style will draw needs:
/// each layer's keys, its string values, and which features pair which key
/// with which value.
abstract final class MvtStrings {
  /// Adds to [into] every string value in [tile] whose key [isLabelKey]
  /// accepts. [tile] may be gzipped, as tiles in an mbtiles file usually are.
  static void collect(
    Uint8List tile,
    bool Function(String key) isLabelKey,
    Set<String> into,
  ) {
    final data = tile.length > 2 && tile[0] == 0x1f && tile[1] == 0x8b
        ? Uint8List.fromList(gzip.decode(tile))
        : tile;
    final r = _Reader(data);
    while (!r.done) {
      final tag = r.varint();
      if (tag == (3 << 3 | 2)) {
        _layer(_Reader(r.bytes()), isLabelKey, into);
      } else {
        r.skip(tag & 7);
      }
    }
  }

  static void _layer(
    _Reader r,
    bool Function(String key) isLabelKey,
    Set<String> into,
  ) {
    final keys = <String>[];
    final values = <String?>[];
    final features = <Uint8List>[];
    while (!r.done) {
      final tag = r.varint();
      switch (tag) {
        case 0x12: // field 2, length-delimited
          features.add(r.bytes());
        case 0x1a: // field 3
          keys.add(utf8.decode(r.bytes(), allowMalformed: true));
        case 0x22: // field 4
          values.add(_stringValue(_Reader(r.bytes())));
        default:
          r.skip(tag & 7);
      }
    }
    final wanted = {
      for (var i = 0; i < keys.length; i++)
        if (isLabelKey(keys[i])) i,
    };
    if (wanted.isEmpty) return;
    for (final feature in features) {
      final tags = _tags(_Reader(feature));
      for (var i = 0; i + 1 < tags.length; i += 2) {
        if (!wanted.contains(tags[i])) continue;
        final value = tags[i + 1] < values.length ? values[tags[i + 1]] : null;
        if (value != null && value.isNotEmpty) into.add(value);
      }
    }
  }

  static String? _stringValue(_Reader r) {
    while (!r.done) {
      final tag = r.varint();
      if (tag == (1 << 3 | 2)) {
        return utf8.decode(r.bytes(), allowMalformed: true);
      }
      r.skip(tag & 7);
    }
    return null;
  }

  static List<int> _tags(_Reader r) {
    final tags = <int>[];
    while (!r.done) {
      final tag = r.varint();
      if (tag == (2 << 3 | 2)) {
        final packed = _Reader(r.bytes());
        while (!packed.done) {
          tags.add(packed.varint());
        }
      } else if (tag == (2 << 3 | 0)) {
        tags.add(r.varint());
      } else {
        r.skip(tag & 7);
      }
    }
    return tags;
  }
}

class _Reader {
  _Reader(this._b);

  final Uint8List _b;
  int _pos = 0;

  bool get done => _pos >= _b.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = _b[_pos++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  Uint8List bytes() {
    final length = varint();
    final value = Uint8List.sublistView(_b, _pos, _pos + length);
    _pos += length;
    return value;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        varint();
      case 1:
        _pos += 8;
      case 2:
        bytes();
      case 5:
        _pos += 4;
      default:
        throw FormatException('Unsupported protobuf wire type $wireType');
    }
  }
}
