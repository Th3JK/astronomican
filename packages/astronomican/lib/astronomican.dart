/// Maps for tour apps that need no street map: pictures used as the map, the
/// floors of a building, markers, levels and versioned offline packs — all in
/// plain Flutter, without MapLibre.
///
/// * [ImageMap] uses a picture as the map: an illustrated site map, or the
///   floor plans of a building, with markers placed by their position on the
///   picture, constant-size at every zoom, and a [LevelSelector] to switch
///   floors.
/// * A [MapMarker] stands at a [GeoPosition] or an [ImagePosition], on one
///   [MapLevel] or on all of them. A level with an [ImageGeoreference] is
///   pinned to the Earth, so a GPS position lands on a floor plan.
/// * [MapPackManager] installs versioned packs of map data: a pack bundled in
///   the assets is copied into the app's storage once, and again only when a
///   pack with a higher version ships; newer packs download resumably.
///
/// For real maps drawn by MapLibre — online styles, offline `.mbtiles` packs,
/// overlays and indoor floors over the streets — depend on
/// `astronomican_maplibre` instead. It re-exports everything here, so an app
/// using both imports only that.
///
/// ```dart
/// final controller = ImageMapController(levels: floors);
///
/// ImageMap<Stop>(
///   controller: controller,
///   markers: [
///     for (final stop in stops)
///       MapMarker(
///         id: stop.id,
///         position: ImagePosition(stop.x, stop.y),
///         levelId: stop.floor,
///       ),
///   ],
///   onMarkerTap: (marker) => open(marker.data!),
/// );
/// ```
library;

export 'package:astronomican_pack_format/astronomican_pack_format.dart';
export 'src/core/building/map_building.dart';
export 'src/core/cluster/marker_clusterer.dart';
export 'src/core/cluster/marker_clustering.dart';
export 'src/core/geo_bounds.dart';
export 'src/core/image_georeference.dart';
export 'src/core/level_controller.dart';
export 'src/core/map_image.dart';
export 'src/core/map_level.dart';
export 'src/core/map_position.dart';
export 'src/core/marker/map_marker.dart';
export 'src/core/marker/marker_anchor.dart';
export 'src/core/marker/marker_icon.dart';
export 'src/core/marker/marker_rasterizer.dart';
export 'src/core/web_mercator.dart';
export 'src/image/image_map.dart';
export 'src/image/image_map_controller.dart' show ImageMapController;
export 'src/image/image_map_options.dart';
export 'src/image/level_viewport.dart'
    show ImageClusterBuilder, ImageMarkerBuilder;
export 'src/image/viewport_math.dart';
export 'src/location/location_feed.dart';
export 'src/location/location_fix.dart';
export 'src/location/my_location_controller.dart';
export 'src/location/my_location_style.dart';
export 'src/offline/pack/installed_pack.dart';
export 'src/offline/pack/io_pack_transport.dart';
export 'src/offline/pack/map_pack_manager.dart';
export 'src/offline/pack/pack_download.dart';
export 'src/offline/pack/pack_progress.dart';
export 'src/offline/pack/pack_transport.dart';
export 'src/ui/floor_plans_dialog.dart';
export 'src/ui/level_selector.dart';
export 'src/ui/level_selector_theme.dart';
export 'src/ui/marker_icon_view.dart';
export 'src/ui/my_location_button.dart';
