import 'dart:math' as math;

import 'package:astronomican/astronomican.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Levels a factor of two apart: at level i one world unit is 2^i pixels.
  final scales = [for (var i = 0; i < 8; i++) math.pow(2, i).toDouble()];

  List<ClusterPoint> scatter(int n, {int seed = 7, double size = 400}) {
    final random = math.Random(seed);
    return [
      for (var i = 0; i < n; i++)
        ClusterPoint(i, random.nextDouble() * size, random.nextDouble() * size),
    ];
  }

  test('every point is in exactly one node at every level', () {
    final points = scatter(200);
    final index = ClusterIndex(points, scales: scales, radius: 40);
    for (var level = 0; level < index.levelCount; level++) {
      final seen = <int>[];
      for (final node in index.nodesAt(level)) {
        final members = index.pointsOf(node);
        expect(members, hasLength(node.count));
        seen.addAll(members);
      }
      seen.sort();
      expect(seen, [for (var i = 0; i < 200; i++) i]);
    }
    // Coarser levels hold fewer nodes, and the finest holds every point.
    expect(index.nodesAt(0).length, lessThan(index.nodesAt(7).length));
    expect(index.nodesAt(7), hasLength(200));
  });

  test('close points merge when zoomed out and split where promised', () {
    // 10 units apart: 10 px at level 0 — merged — and 1280 px at level 7.
    final index = ClusterIndex(
      const [ClusterPoint(0, 100, 100), ClusterPoint(1, 110, 100)],
      scales: scales,
      radius: 40,
    );
    final top = index.nodesAt(0).single;
    expect(top.isCluster, isTrue);
    expect(top.count, 2);
    expect(top.x, closeTo(105, 1e-9));

    final split = top.expansionLevel!;
    expect(index.nodesAt(split), hasLength(2));
    expect(index.nodesAt(split - 1), hasLength(1));
    // 10 units at 2^split pixels each is beyond the 40 px radius.
    expect(10 * scales[split], greaterThan(40));
  });

  test('points far apart never merge', () {
    final index = ClusterIndex(
      const [ClusterPoint(0, 0, 0), ClusterPoint(1, 1000, 1000)],
      scales: scales,
      radius: 40,
    );
    expect(index.nodesAt(0), hasLength(2));
    // A lone point keeps its own index as its id at every level.
    expect(index.nodesAt(0).map((n) => n.pointIndex), containsAll([0, 1]));
  });

  test('points on the same spot still come apart at the deepest level', () {
    final index = ClusterIndex(const [
      ClusterPoint(0, 50, 50),
      ClusterPoint(1, 50, 50),
      ClusterPoint(2, 50, 50),
    ], scales: scales);
    expect(index.nodesAt(6).single.count, 3);
    expect(index.nodesAt(7), hasLength(3));
  });

  test('minPoints holds small groups apart', () {
    final index = ClusterIndex(
      const [ClusterPoint(0, 100, 100), ClusterPoint(1, 101, 100)],
      scales: scales,
      minPoints: 3,
    );
    expect(index.nodesAt(0), hasLength(2));
  });

  test('levelFor picks the finest level no finer than the map', () {
    final index = ClusterIndex(const [], scales: scales);
    expect(index.levelFor(0.1), 0);
    expect(index.levelFor(1), 0);
    expect(index.levelFor(3.9), 1);
    expect(index.levelFor(4), 2);
    expect(index.levelFor(1e9), 7);
  });

  test('the same markers cluster the same way every time', () {
    final a = ClusterIndex(scatter(80), scales: scales, radius: 40);
    final b = ClusterIndex(scatter(80), scales: scales, radius: 40);
    for (var level = 0; level < 8; level++) {
      expect(
        a.nodesAt(level).map((n) => n.id).toList(),
        b.nodesAt(level).map((n) => n.id).toList(),
      );
    }
  });

  test('a marker set hands back markers and clusters', () {
    final markers = [
      for (var i = 0; i < 3; i++)
        MapMarker<int>(
          id: 'm$i',
          position: ImagePosition(100.0 + i, 100),
          levelId: i == 0 ? null : 'g',
          data: i,
        ),
      const MapMarker<int>(id: 'far', position: ImagePosition(900, 900)),
    ];
    final set = MarkerClusterSet<int>(
      markers: markers,
      world: [
        for (final m in markers) (m.position as ImagePosition).toOffset(),
      ],
      scales: scales,
      options: const MarkerClustering(),
      toPosition: ImagePosition.fromOffset,
    );
    final items = set.itemsAt(0);
    final group = items.whereType<GroupedMarkers<int>>().single;
    expect(group.cluster.markers.map((m) => m.id), ['m0', 'm1', 'm2']);
    expect(group.cluster.levelId, 'g');
    expect(group.cluster.id, startsWith('cluster-'));
    expect((group.cluster.position as ImagePosition).x, closeTo(101, 1e-9));
    expect(items.whereType<LoneMarker<int>>().single.marker.id, 'far');
    // Three at the top; finer down, two of them are still together.
    expect(set.counts, {3, 2});
    expect(identical(set.itemsAt(0), items), isTrue);
  });

  test('the default icon is a badge that stops counting at 99', () {
    final icon = MarkerClustering.defaultIcon(250) as BadgeMarkerIcon;
    expect(icon.text, '99+');
    expect(MarkerClustering.defaultIcon(3).size, const Size.square(34));
  });
}
