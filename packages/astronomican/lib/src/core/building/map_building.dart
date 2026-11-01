import 'package:meta/meta.dart';

import '../geo_bounds.dart';
import '../map_level.dart';
import '../map_position.dart';
import '../marker/marker_icon.dart';

/// A building with floors to look inside: a museum on the town walk, the
/// works on the edge of town.
///
/// On a street map it stands as one marker, set apart from the stops around
/// it. Tapping it can lay its floors over the streets, or open them as floor
/// plans on their own; which is up to the app.
@immutable
final class MapBuilding {
  /// Building [id], called [name], with [levels] from the lowest up.
  ///
  /// Its marker stands at [position], or else in the middle of the area its
  /// georeferenced floors cover.
  MapBuilding({
    required this.id,
    required this.name,
    required List<MapLevel> levels,
    GeoPosition? position,
    this.icon = const MarkerIcon.building(),
    this.initialLevelId,
  }) : assert(levels.isNotEmpty, 'a building has at least one floor'),
       assert(
         levels.map((level) => level.id).toSet().length == levels.length,
         'floor ids must be unique within a building',
       ),
       levels = List.unmodifiable(levels),
       _position = position;

  /// Unique among the buildings on one map.
  final String id;

  /// What the visitor calls it.
  final String name;

  /// Its floors, from the lowest up.
  final List<MapLevel> levels;

  /// How its marker is drawn.
  final MarkerIcon icon;

  /// The floor it opens on, or the first.
  final String? initialLevelId;

  final GeoPosition? _position;

  /// The area its georeferenced floors cover on the Earth, or null when none
  /// of them is georeferenced.
  GeoBounds? get footprint {
    GeoBounds? bounds;
    for (final level in levels) {
      final reference = level.georeference;
      if (reference == null) continue;
      final quad = GeoBounds.around(reference.quad(level.size).corners);
      bounds = bounds == null ? quad : bounds.union(quad);
    }
    return bounds;
  }

  /// Where its marker stands, or null when it has neither a position nor a
  /// georeferenced floor.
  GeoPosition? get position => _position ?? footprint?.center;

  /// The floor it opens on.
  MapLevel get initialLevel => levels.firstWhere(
    (level) => level.id == initialLevelId,
    orElse: () => levels.first,
  );

  @override
  bool operator ==(Object other) =>
      other is MapBuilding &&
      other.id == id &&
      other.name == name &&
      _listEquals(other.levels, levels) &&
      other._position == _position &&
      other.icon == icon &&
      other.initialLevelId == initialLevelId;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(levels),
    _position,
    icon,
    initialLevelId,
  );

  @override
  String toString() => 'MapBuilding($id, ${levels.length} floors)';

  static bool _listEquals(List<MapLevel> a, List<MapLevel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
