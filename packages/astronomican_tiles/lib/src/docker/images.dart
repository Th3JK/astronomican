import 'package:meta/meta.dart';

/// The container images the tool runs, pinned so a build today and a build
/// next year produce the same thing. Each can be overridden under `images:`
/// in map.yaml.
@immutable
final class Images {
  /// Images, defaulting to the pinned ones.
  const Images({
    this.planetiler = defaultPlanetiler,
    this.spreet = defaultSpreet,
    this.tileserver = defaultTileserver,
    this.maputnik = defaultMaputnik,
  });

  /// Planetiler: OpenStreetMap to OpenMapTiles-schema vector tiles. Its
  /// default profile is OpenMapTiles 3.16. Multi-arch.
  static const String defaultPlanetiler =
      'ghcr.io/onthegomap/planetiler:0.10.2';

  /// spreet: SVG icons to a MapLibre sprite, as the openmaptiles Makefile
  /// builds its own. Multi-arch.
  static const String defaultSpreet = 'ghcr.io/flother/spreet:0.13.1';

  /// TileServer GL, without server-side rendering: serves the pack's tiles,
  /// style, sprite and fonts to a browser viewer. Multi-arch.
  static const String defaultTileserver = 'maptiler/tileserver-gl-light:v5.6.0';

  /// Maputnik, the MapLibre style editor. Published for amd64 only, and
  /// without version tags, so pinned by digest.
  static const String defaultMaputnik =
      'ghcr.io/maplibre/maputnik@sha256:'
      '6abd34d5760e612a387f278b3a8fbbdfe497afd31af595efbb13333ceff89b22';

  /// The Planetiler image.
  final String planetiler;

  /// The spreet image.
  final String spreet;

  /// The TileServer GL image.
  final String tileserver;

  /// The Maputnik image.
  final String maputnik;
}

/// Other pinned inputs.
abstract final class Upstream {
  /// The openmaptiles release the OSM OpenMapTiles style is built from; the
  /// same schema version Planetiler generates.
  static const String openmaptilesTag = 'v3.16';

  /// Its source archive.
  static final Uri openmaptilesZip = Uri.parse(
    'https://codeload.github.com/openmaptiles/openmaptiles/zip/refs/tags/v3.16',
  );

  /// What OpenMapTiles-schema tiles ask to be credited with.
  static const String attribution =
      '© OpenMapTiles © OpenStreetMap contributors';
}
