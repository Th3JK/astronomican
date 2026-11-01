import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A point to cluster: its [index] in the caller's list, and where it is in
/// the caller's world frame — Mercator for a street map, the level's logical
/// frame for a picture.
@immutable
final class ClusterPoint {
  /// Point [index] at [x], [y].
  const ClusterPoint(this.index, this.x, this.y);

  /// Which of the caller's items this is.
  final int index;

  /// Across the world frame.
  final double x;

  /// Down the world frame.
  final double y;
}

/// A cluster, or a lone point, at one level of a [ClusterIndex].
@immutable
final class ClusterNode {
  const ClusterNode._({
    required this.id,
    required this.x,
    required this.y,
    required this.count,
    required this.expansionLevel,
    required List<int> children,
    int? index,
  }) : _children = children,
       _index = index;

  /// Unique within the index. A node that passes unchanged to a coarser
  /// level keeps its id there, so a map can tell it is the same one.
  final int id;

  /// Across the world frame: the point itself, or the mean of a cluster's
  /// points.
  final double x;

  /// Down the world frame.
  final double y;

  /// How many points it stands for: 1 for a lone point.
  final int count;

  /// The first level at which a cluster breaks up, which is where a tap on
  /// it should zoom to. Null for a lone point.
  final int? expansionLevel;

  final List<int> _children;
  final int? _index;

  /// Whether this stands for more than one point.
  bool get isCluster => count > 1;

  /// The caller's index of a lone point; null for a cluster.
  int? get pointIndex => _index;
}

/// Markers grouped at each of a list of scales, so a map at any zoom can ask
/// which of them overlap there and draw those as one.
///
/// Built the way supercluster builds it: from the finest level up, each
/// level groups the previous level's nodes that lie within [radius] screen
/// pixels of one another at that level's scale. Grouping greedily in input
/// order makes the result the same every time for the same markers, so
/// clusters do not reshuffle when nothing moved.
///
/// [scales] are screen pixels per world unit, from the coarsest level to
/// the finest. The finest level is never clustered: at the deepest zoom
/// every marker can be reached, even markers standing on the same spot.
final class ClusterIndex {
  /// An index of [points] over [scales].
  ClusterIndex(
    List<ClusterPoint> points, {
    required List<double> scales,
    this.radius = 48,
    this.minPoints = 2,
  }) : assert(scales.isNotEmpty, 'at least one level is needed'),
       assert(minPoints >= 2, 'a cluster is at least two points'),
       scales = List.unmodifiable(scales) {
    _build(points);
  }

  /// Screen pixels per world unit at each level, coarsest first.
  final List<double> scales;

  /// How close, in screen pixels, two markers may come before they are
  /// drawn as one.
  final double radius;

  /// The fewest points a cluster may hold.
  final int minPoints;

  final Map<int, ClusterNode> _nodes = {};
  late final List<List<ClusterNode>> _levels;
  final Map<int, List<int>> _leaves = {};

  /// How many levels there are.
  int get levelCount => _levels.length;

  /// Every cluster and lone point at [level], coarsest being 0.
  List<ClusterNode> nodesAt(int level) =>
      _levels[level.clamp(0, _levels.length - 1)];

  /// The level to draw at a map scale of [scale] screen pixels per world
  /// unit: the finest level no finer than the map.
  int levelFor(double scale) {
    var level = 0;
    for (var i = 0; i < scales.length; i++) {
      if (scales[i] <= scale * (1 + 1e-9)) level = i;
    }
    return level;
  }

  /// The node [id].
  ClusterNode? node(int id) => _nodes[id];

  /// The caller's indices of every point [node] stands for, in input order.
  List<int> pointsOf(ClusterNode node) => _leaves.putIfAbsent(node.id, () {
    final out = <int>[];
    void walk(ClusterNode n) {
      final index = n._index;
      if (index != null) {
        out.add(index);
        return;
      }
      for (final child in n._children) {
        walk(_nodes[child]!);
      }
    }

    walk(node);
    return out..sort();
  });

  void _build(List<ClusterPoint> points) {
    var nextId = 0;
    for (final p in points) {
      nextId = math.max(nextId, p.index + 1);
    }
    var current = [
      for (final p in points)
        ClusterNode._(
          id: p.index,
          x: p.x,
          y: p.y,
          count: 1,
          expansionLevel: null,
          children: const [],
          index: p.index,
        ),
    ];
    for (final n in current) {
      _nodes[n.id] = n;
    }

    final levels = List<List<ClusterNode>>.filled(scales.length, const []);
    levels[scales.length - 1] = List.unmodifiable(current);
    for (var level = scales.length - 2; level >= 0; level--) {
      final r = radius / scales[level];
      final grid = <(int, int), List<int>>{};
      (int, int) cell(ClusterNode n) => ((n.x / r).floor(), (n.y / r).floor());
      for (var i = 0; i < current.length; i++) {
        grid.putIfAbsent(cell(current[i]), () => []).add(i);
      }

      final taken = List<bool>.filled(current.length, false);
      final next = <ClusterNode>[];
      for (var i = 0; i < current.length; i++) {
        if (taken[i]) continue;
        final p = current[i];
        taken[i] = true;
        final (cx, cy) = cell(p);
        final near = <int>[];
        for (var gx = cx - 1; gx <= cx + 1; gx++) {
          for (var gy = cy - 1; gy <= cy + 1; gy++) {
            for (final j in grid[(gx, gy)] ?? const <int>[]) {
              if (taken[j]) continue;
              final q = current[j];
              final dx = q.x - p.x, dy = q.y - p.y;
              if (dx * dx + dy * dy <= r * r) near.add(j);
            }
          }
        }
        var count = p.count;
        for (final j in near) {
          count += current[j].count;
        }
        if (near.isEmpty || count < minPoints) {
          next.add(p);
          continue;
        }
        var sx = p.x * p.count, sy = p.y * p.count;
        final children = [p.id];
        for (final j in near) {
          taken[j] = true;
          final q = current[j];
          sx += q.x * q.count;
          sy += q.y * q.count;
          children.add(q.id);
        }
        final cluster = ClusterNode._(
          id: nextId++,
          x: sx / count,
          y: sy / count,
          count: count,
          expansionLevel: level + 1,
          children: children,
        );
        _nodes[cluster.id] = cluster;
        next.add(cluster);
      }
      levels[level] = List.unmodifiable(next);
      current = next;
    }
    _levels = levels;
  }
}
