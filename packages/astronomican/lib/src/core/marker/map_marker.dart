import 'package:meta/meta.dart';

import '../map_position.dart';
import 'marker_icon.dart';

/// Something drawn at a place on a map, which the visitor can tap.
///
/// The same marker works on both engines. Where it appears depends on its
/// [position] and [levelId] together:
///
/// * With no [levelId] it shows on every level, and on the base map.
/// * With a [levelId] it shows only while that level is the active one.
/// * An [ImagePosition] is read in that level's logical frame. On a `GeoMap`
///   it is carried onto the streets through the level's georeference, which is
///   how one list of floor-plan markers serves both an image map and an indoor
///   map.
///
/// [data] carries whatever the app needs back when the marker is tapped —
/// typically the stop it stands for.
@immutable
final class MapMarker<T> {
  /// A marker named [id], standing at [position].
  const MapMarker({
    required this.id,
    required this.position,
    this.levelId,
    this.icon = const MarkerIcon.pin(),
    this.data,
    this.semanticLabel,
    this.tappable = true,
    this.zIndex = 0,
    this.clusterable = true,
  });

  /// Unique within one map. Taps are reported by it, and a map diffs its
  /// markers by it between rebuilds.
  final String id;

  /// Where the marker stands.
  final MapPosition position;

  /// The level the marker stands on, or null for all of them.
  final String? levelId;

  /// How the marker is drawn.
  final MarkerIcon icon;

  /// Whatever the app wants handed back on a tap.
  final T? data;

  /// Read out by screen readers in place of the picture.
  final String? semanticLabel;

  /// Whether a tap on the marker is reported. Off for markers that only mark
  /// something, such as the visitor's own position, so a tap goes through to
  /// the map underneath.
  final bool tappable;

  /// Markers with a higher index are drawn above lower ones, and win a tap
  /// where they overlap.
  final int zIndex;

  /// Whether the marker may merge with others when the map clusters them.
  /// Off for markers that must always stand on their own — the stop that is
  /// open, the way into a building.
  final bool clusterable;

  /// A copy with the given fields replaced.
  MapMarker<T> copyWith({
    MapPosition? position,
    String? levelId,
    MarkerIcon? icon,
    T? data,
    String? semanticLabel,
    bool? tappable,
    int? zIndex,
    bool? clusterable,
  }) => MapMarker<T>(
    id: id,
    position: position ?? this.position,
    levelId: levelId ?? this.levelId,
    icon: icon ?? this.icon,
    data: data ?? this.data,
    semanticLabel: semanticLabel ?? this.semanticLabel,
    tappable: tappable ?? this.tappable,
    zIndex: zIndex ?? this.zIndex,
    clusterable: clusterable ?? this.clusterable,
  );

  @override
  bool operator ==(Object other) =>
      other is MapMarker<T> &&
      other.id == id &&
      other.position == position &&
      other.levelId == levelId &&
      other.icon == icon &&
      other.data == data &&
      other.semanticLabel == semanticLabel &&
      other.tappable == tappable &&
      other.zIndex == zIndex &&
      other.clusterable == clusterable;

  @override
  int get hashCode => Object.hash(
    id,
    position,
    levelId,
    icon,
    data,
    semanticLabel,
    tappable,
    zIndex,
    clusterable,
  );

  @override
  String toString() => 'MapMarker($id at $position on ${levelId ?? 'any'})';
}
