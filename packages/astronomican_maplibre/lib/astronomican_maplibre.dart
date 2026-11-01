/// Real maps for astronomican, drawn natively by MapLibre.
///
/// * **`GeoMap`** draws an online style, raster tiles, or an offline `.mbtiles`
///   pack with its own style — with pictures pinned over it
///   (`GeoImageOverlay`) and indoor floors switched by a `LevelSelector`
///   (`GeoMapController` levels).
/// * **`OfflineRegions`** keeps areas of an online style for use without a
///   connection, in MapLibre's own offline database.
///
/// Re-exports all of `package:astronomican/astronomican.dart` — markers,
/// levels, georeferences, the image map and the pack installer — so an app
/// needs only this import.
///
/// ```dart
/// final packs = await MapPackManager.open();
///
/// GeoMap<Stop>(
///   source: GeoMapSource.bundledPack(packs, 'assets/packs/town/pack.json'),
///   markers: [
///     for (final stop in stops)
///       MapMarker(id: stop.id, position: GeoPosition(stop.lat, stop.lng)),
///   ],
///   onMarkerTap: (marker) => open(marker.data!),
/// );
/// ```
library;

export 'package:astronomican/astronomican.dart';

export 'src/geo/geo_camera.dart';
export 'src/geo/geo_image_overlay.dart';
export 'src/geo/geo_map.dart';
export 'src/geo/geo_map_controller.dart';
export 'src/geo/geo_map_source.dart';
export 'src/geo/maplibre_convert.dart';
export 'src/geo/style/blank_style.dart';
export 'src/geo/style/pack_style_resolver.dart';
export 'src/geo/style/raster_style.dart';
export 'src/offline/regions/maplibre_offline_region_backend.dart';
export 'src/offline/regions/offline_area.dart';
export 'src/offline/regions/offline_region_backend.dart';
export 'src/offline/regions/offline_regions.dart';
