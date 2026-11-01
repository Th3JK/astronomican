import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import '../map_position.dart';
import '../marker/map_marker.dart';
import '../marker/marker_icon.dart';
import 'marker_clusterer.dart';

/// Draws markers that crowd each other as one, with a count.
///
/// Give it to a map's `clustering`. Markers closer than [radius] on screen
/// merge; zooming in splits them again, and a tap on a cluster zooms to where
/// it splits. Only markers showing together are clustered — those on the
/// active level and those on none — and a marker can stay out of it with
/// `MapMarker.clusterable`.
@immutable
final class MarkerClustering {
  /// Clustering within [radius] logical pixels, of at least [minPoints]
  /// markers, drawn with [icon] or a round badge with the count.
  const MarkerClustering({this.radius = 48, this.minPoints = 2, this.icon})
    : assert(radius > 0, 'radius must be positive'),
      assert(minPoints >= 2, 'a cluster is at least two markers');

  /// How close, in logical pixels, markers may come before they merge.
  final double radius;

  /// The fewest markers a cluster may hold.
  final int minPoints;

  /// Draws a cluster of [count] markers. Called with each count shown, and
  /// its icons are shared by key like any other.
  final MarkerIcon Function(int count)? icon;

  /// The icon for a cluster of [count].
  MarkerIcon iconFor(int count) => icon?.call(count) ?? defaultIcon(count);

  /// A navy badge with the count, a little larger for larger counts.
  static MarkerIcon defaultIcon(int count) => MarkerIcon.badge(
    count > 99 ? '99+' : '$count',
    diameter: count < 10 ? 34 : (count < 100 ? 40 : 46),
  );

  @override
  bool operator ==(Object other) =>
      other is MarkerClustering &&
      other.radius == radius &&
      other.minPoints == minPoints &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(radius, minPoints, icon);
}

/// Markers drawn as one because they crowd each other at the current zoom.
@immutable
final class MarkerCluster<T> {
  /// A cluster of [markers] drawn at [position].
  const MarkerCluster({
    required this.id,
    required this.markers,
    required this.position,
    this.levelId,
  });

  /// Stable while the same markers cluster the same way.
  final String id;

  /// The markers it stands for, in the order the map was given them.
  final List<MapMarker<T>> markers;

  /// Where it is drawn: the middle of its markers.
  final MapPosition position;

  /// The level its markers stand on, when any of them stands on one.
  final String? levelId;

  /// How many markers it stands for.
  int get count => markers.length;

  @override
  String toString() => 'MarkerCluster($id, $count markers)';
}

/// One thing a clustered map draws: a marker on its own, or a cluster.
///
/// The building blocks both engines draw clusters with, for an app that
/// draws markers some other way.
sealed class ClusterItem<T> {
  const ClusterItem(this.world);

  /// Where it is in the index's world frame.
  final Offset world;
}

/// A marker drawn on its own.
final class LoneMarker<T> extends ClusterItem<T> {
  /// [marker] at [world].
  const LoneMarker(this.marker, super.world);

  /// The marker.
  final MapMarker<T> marker;
}

/// A cluster, with the level at which it splits.
final class GroupedMarkers<T> extends ClusterItem<T> {
  /// [cluster] at [world], splitting at [expansionLevel].
  const GroupedMarkers(this.cluster, super.world, this.expansionLevel);

  /// The cluster.
  final MarkerCluster<T> cluster;

  /// The first level of the index at which it splits.
  final int expansionLevel;
}

/// A [ClusterIndex] over markers: what both engines draw from.
final class MarkerClusterSet<T> {
  /// [markers] at [world] positions — one each, in the same order — grouped
  /// over [scales] by [options]. [toPosition] turns a world point back into
  /// a position on the map.
  MarkerClusterSet({
    required this.markers,
    required List<Offset> world,
    required List<double> scales,
    required MarkerClustering options,
    required this.toPosition,
    this.idPrefix = 'cluster',
  }) : assert(world.length == markers.length, 'one world point per marker'),
       _world = world,
       index = ClusterIndex(
         [
           for (var i = 0; i < markers.length; i++)
             ClusterPoint(i, world[i].dx, world[i].dy),
         ],
         scales: scales,
         radius: options.radius,
         minPoints: options.minPoints,
       );

  /// The markers clustered, in the order given.
  final List<MapMarker<T>> markers;

  /// The grouping.
  final ClusterIndex index;

  /// Turns a world point into a map position.
  final MapPosition Function(Offset world) toPosition;

  /// Starts every cluster's id.
  final String idPrefix;

  final List<Offset> _world;
  final Map<int, List<ClusterItem<T>>> _items = {};

  /// What to draw at [level].
  List<ClusterItem<T>> itemsAt(int level) => _items.putIfAbsent(level, () {
    final out = <ClusterItem<T>>[];
    for (final node in index.nodesAt(level)) {
      final lone = node.pointIndex;
      if (lone != null) {
        out.add(LoneMarker(markers[lone], _world[lone]));
        continue;
      }
      final members = [for (final i in index.pointsOf(node)) markers[i]];
      final world = Offset(node.x, node.y);
      String? levelId;
      for (final m in members) {
        levelId ??= m.levelId;
      }
      out.add(
        GroupedMarkers(
          MarkerCluster<T>(
            id: '$idPrefix-${node.id}',
            markers: List.unmodifiable(members),
            position: toPosition(world),
            levelId: levelId,
          ),
          world,
          node.expansionLevel!,
        ),
      );
    }
    return List.unmodifiable(out);
  });

  /// Every distinct cluster size at any level, for drawing their icons ahead
  /// of time.
  Set<int> get counts => {
    for (var level = 0; level < index.levelCount; level++)
      for (final node in index.nodesAt(level))
        if (node.isCluster) node.count,
  };
}
