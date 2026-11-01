import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';

/// Turns markers, clusters and buildings into the GeoJSON the marker layers
/// draw.
///
/// Each feature carries a top-level string `id` — Android reports taps by it,
/// and ignores `promoteId` — and the properties the layers read: what kind of
/// thing it is, which icon, which anchor, the level it stands on, its paint
/// order and whether it is tappable. Taps are routed by the layer they land
/// on, never by the id, so a marker may be called anything.
@internal
abstract final class MarkerFeatures {
  /// A marker the app gave.
  static const String marker = 'marker';

  /// Markers drawn as one.
  static const String cluster = 'cluster';

  /// A building with floors to open.
  static const String building = 'building';

  /// The name an icon is registered under.
  static String iconName(String key) => 'astro:$key';

  /// Where [position] on [levelId] stands on the Earth, or null when it
  /// cannot be placed: an image position whose level is unknown or not
  /// georeferenced.
  static GeoPosition? place(
    MapPosition position,
    String? levelId,
    Map<String, MapLevel> levels,
  ) {
    return switch (position) {
      final GeoPosition g => g,
      final ImagePosition i => levels[levelId]?.georeference?.toGeo(i),
    };
  }

  /// Where [marker] stands on the Earth, or null when it cannot be placed.
  static GeoPosition? locate<T>(
    MapMarker<T> marker,
    Map<String, MapLevel> levels,
  ) => place(marker.position, marker.levelId, levels);

  /// One marker as a feature at [at].
  static Map<String, Object?> feature<T>(MapMarker<T> marker, GeoPosition at) =>
      _point(marker.id, at, {
        'kind': MarkerFeatures.marker,
        'icon': iconName(marker.icon.key),
        'anchor': marker.icon.anchor.maplibre,
        'z': marker.zIndex,
        'tappable': marker.tappable,
        'level': ?marker.levelId,
      });

  /// A cluster as a feature, drawn with [icon].
  static Map<String, Object?> clusterFeature<T>(
    MarkerCluster<T> cluster,
    GeoPosition at,
    MarkerIcon icon,
  ) => _point(cluster.id, at, {
    'kind': MarkerFeatures.cluster,
    'icon': iconName(icon.key),
    'anchor': icon.anchor.maplibre,
    'z': cluster.count,
    'tappable': true,
    'level': ?cluster.levelId,
  });

  /// A building's marker as a feature.
  static Map<String, Object?> buildingFeature(
    MapBuilding building,
    GeoPosition at,
  ) => _point(building.id, at, {
    'kind': MarkerFeatures.building,
    'icon': iconName(building.icon.key),
    'anchor': building.icon.anchor.maplibre,
    'z': 0,
    'tappable': true,
  });

  /// A collection of [features].
  static Map<String, Object?> collection(List<Map<String, Object?>> features) =>
      {'type': 'FeatureCollection', 'features': features};

  /// What a marker layer shows while [activeLevel] is showing: markers on
  /// every level, and those on the active one. With no active level, only
  /// markers on every level.
  static List<Object> levelFilter(String? activeLevel) => activeLevel == null
      ? [
          '!',
          ['has', 'level'],
        ]
      : [
          'any',
          [
            '!',
            ['has', 'level'],
          ],
          [
            '==',
            ['get', 'level'],
            activeLevel,
          ],
        ];

  /// The whole filter of the tappable marker layer, or of the other one.
  static List<Object> layerFilter(
    String? activeLevel, {
    required bool tappable,
  }) => [
    'all',
    _kind(MarkerFeatures.marker),
    [
      '==',
      ['get', 'tappable'],
      tappable,
    ],
    levelFilter(activeLevel),
  ];

  /// The filter of the cluster layer.
  static List<Object> clusterFilter(String? activeLevel) => [
    'all',
    _kind(MarkerFeatures.cluster),
    levelFilter(activeLevel),
  ];

  /// The filter of the building layer, leaving out [hidden] — the building
  /// whose floors are showing.
  static List<Object> buildingFilter(String? hidden) => hidden == null
      ? _kind(MarkerFeatures.building)
      : [
          'all',
          _kind(MarkerFeatures.building),
          [
            '!=',
            ['get', 'id'],
            hidden,
          ],
        ];

  static List<Object> _kind(String kind) => [
    '==',
    ['get', 'kind'],
    kind,
  ];

  static Map<String, Object?> _point(
    String id,
    GeoPosition at,
    Map<String, Object?> properties,
  ) => {
    'type': 'Feature',
    'id': id,
    'geometry': {
      'type': 'Point',
      'coordinates': [at.longitude, at.latitude],
    },
    'properties': {'id': id, ...properties},
  };
}
