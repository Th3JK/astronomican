import 'package:path/path.dart' as p;

import '../config/map_config.dart';

/// Planetiler's command line for a map.
///
/// Planetiler's default profile is the OpenMapTiles schema, so its tiles draw
/// with every OpenMapTiles style. Its inputs besides the OpenStreetMap extract
/// — water polygons, Natural Earth, lake centrelines, about 1.45 GB — are
/// downloaded once into the shared cache (`/sources`) and reused by every map.
abstract final class Planetiler {
  /// The arguments for [config], with the paths inside the container.
  static List<String> arguments(MapConfig config) {
    final input = config.input;
    final bounds = config.bounds;
    return [
      '--download',
      '--download_dir=/sources',
      // Temporary files stay inside the container, off the bind mount.
      '--tmpdir=/tmp/planetiler',
      if (input is AreaInput) '--area=${input.area}',
      if (input is OsmInput) '--osm_path=/osm/${p.basename(input.file.path)}',
      if (bounds != null) '--bounds=${bounds.join(',')}',
      '--minzoom=${config.minZoom}',
      '--maxzoom=${config.maxZoom}',
      if (config.languages.isNotEmpty)
        '--languages=${config.languages.join(',')}',
      if (config.excludeLayers.isNotEmpty)
        '--exclude_layers=${config.excludeLayers.join(',')}',
      '--output=/output/${config.id}.mbtiles',
      '--force',
      ...config.planetilerArgs,
    ];
  }
}
