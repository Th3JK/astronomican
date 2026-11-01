/// The astronomican map pack format.
///
/// A pack is a folder of map data — an `.mbtiles` tileset, the style that
/// draws it, its sprite and its glyphs — described by a `pack.json`
/// [MapPackManifest]. The style names the pack's own files with `pack://`
/// URIs ([PackStyle]), and its glyphs are one folder per font stack holding
/// one file per [GlyphRange].
///
/// Pure Dart: the apps that install packs (`package:astronomican`) and the
/// tools that build them (`package:astronomican_tiles`) share this, and the
/// tools run without Flutter.
library;

export 'src/glyph_range.dart';
export 'src/map_pack_manifest.dart';
export 'src/pack_exceptions.dart';
export 'src/pack_style.dart';
