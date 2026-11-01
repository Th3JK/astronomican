import 'dart:convert';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';

/// One style in the three shapes it takes:
///
/// | | Pack form (what ships) | Tileserver form | Browser form (Maputnik) |
/// |---|---|---|---|
/// | tiles | `pack://<id>.mbtiles` | `mbtiles://{<id>}` | `<base>/data/<id>.json` |
/// | sprite | `pack://sprite` | `sprite` | `<base>/styles/<id>/sprite` |
/// | glyphs | `pack://fonts/{fontstack}/{range}.pbf` | `{fontstack}/{range}.pbf` | `<base>/fonts/{fontstack}/{range}.pbf` |
///
/// TileServer GL serves the pack's own files, so the preview draws exactly
/// what ships. Maputnik runs in a browser, which reaches the same files
/// through TileServer GL's URLs; an edited style comes back to the pack form
/// by [browserToPack].
abstract final class StyleForms {
  /// [style], from pack form to the form TileServer GL reads for pack [id].
  static Map<String, Object?> packToTileserver(
    Map<String, Object?> style,
    String id,
  ) => _map(style, (s) {
    if (s == 'pack://$id.mbtiles') return 'mbtiles://{$id}';
    if (s == PackStyle.defaultGlyphs) return '{fontstack}/{range}.pbf';
    final relative = PackStyle.relativePath(s);
    if (relative == null) return s;
    // Sprites resolve against TileServer GL's sprites path, the pack.
    return relative;
  });

  /// [style], from pack form to the form a browser loads through a TileServer
  /// GL at [base] serving pack [id].
  static Map<String, Object?> packToBrowser(
    Map<String, Object?> style,
    String id,
    Uri base,
  ) {
    final root = base.toString().replaceAll(RegExp(r'/+$'), '');
    return _map(style, (s) {
      if (s == 'pack://$id.mbtiles') return '$root/data/$id.json';
      if (s == PackStyle.defaultGlyphs) {
        return '$root/fonts/{fontstack}/{range}.pbf';
      }
      if (s == PackStyle.defaultSprite) return '$root/styles/$id/sprite';
      final relative = PackStyle.relativePath(s);
      if (relative != null && relative.startsWith('sprite-')) {
        return '$root/styles/$id/${relative.substring('sprite-'.length)}';
      }
      return s;
    });
  }

  /// [style], edited in a browser against a TileServer GL at [base], back to
  /// pack form for pack [id]. Drops the editor's own metadata.
  static Map<String, Object?> browserToPack(
    Map<String, Object?> style,
    String id,
    Uri base,
  ) {
    final roots = {
      base.toString().replaceAll(RegExp(r'/+$'), ''),
      base
          .replace(host: base.host == 'localhost' ? '127.0.0.1' : 'localhost')
          .toString()
          .replaceAll(RegExp(r'/+$'), ''),
    };
    final out = _map(style, (s) {
      for (final root in roots) {
        if (s == '$root/data/$id.json') return 'pack://$id.mbtiles';
        if (s == '$root/fonts/{fontstack}/{range}.pbf') {
          return PackStyle.defaultGlyphs;
        }
        if (s == '$root/styles/$id/sprite') return PackStyle.defaultSprite;
        if (s.startsWith('$root/styles/$id/')) {
          return 'pack://sprite-${s.substring('$root/styles/$id/'.length)}';
        }
      }
      return s;
    });
    final metadata = out['metadata'];
    if (metadata is Map<String, Object?>) {
      metadata.removeWhere((k, _) => k.startsWith('maputnik:'));
      if (metadata.isEmpty) out.remove('metadata');
    }
    return out;
  }

  static Map<String, Object?> _map(
    Map<String, Object?> style,
    String Function(String) transform,
  ) =>
      PackStyle.mapStrings(jsonDecode(jsonEncode(style)), transform)!
          as Map<String, Object?>;
}
