import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_maplibre/src/geo/geo_follower.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera that goes where it is told at once, and remembers each move.
class FakeCamera implements FollowCamera {
  FakeCamera(this.camera);

  @override
  GeoCamera? camera;

  final List<(GeoCamera, Duration)> moves = [];

  @override
  Future<void> move(GeoCamera camera, Duration duration) async {
    moves.add((camera, duration));
    this.camera = camera;
  }
}

void main() {
  const here = GeoPosition(49.2613, 13.9030);
  const there = GeoPosition(49.2620, 13.9040);

  test('comes in close when it starts following from far out', () {
    fakeAsync((async) {
      final camera = FakeCamera(
        const GeoCamera(target: GeoPosition(49, 13), zoom: 12),
      );
      final follower = GeoFollower(camera: camera)
        ..setTarget(here)
        ..setMode(MyLocationMode.follow);
      expect(camera.moves.single.$1.target, here);
      expect(camera.moves.single.$1.zoom, 17);
      expect(camera.moves.single.$1.bearing, 0);

      // Zoomed out by the visitor since: the next fix keeps their zoom.
      camera.camera = const GeoCamera(target: here, zoom: 14);
      async.elapse(const Duration(seconds: 1));
      follower.setTarget(there);
      expect(camera.moves.last.$1.zoom, 14);
      follower.dispose();
    });
  });

  test('moves at most once an interval, and catches up', () {
    fakeAsync((async) {
      final camera = FakeCamera(const GeoCamera(target: here, zoom: 17));
      final follower = GeoFollower(camera: camera)
        ..setTarget(here)
        ..setMode(MyLocationMode.heading);
      final before = camera.moves.length;
      for (var i = 0; i < 10; i++) {
        follower.setHeading(10.0 * i);
      }
      // All ten in one interval: at most one move now, one to catch up.
      expect(camera.moves.length - before, lessThanOrEqualTo(1));
      async.elapse(const Duration(milliseconds: 150));
      expect(camera.moves.last.$1.bearing, 90);
      follower.dispose();
    });
  });

  test('faces the heading, and north again when only following', () {
    fakeAsync((async) {
      final camera = FakeCamera(const GeoCamera(target: here, zoom: 17));
      final follower = GeoFollower(camera: camera)
        ..setTarget(here)
        ..setHeading(120)
        ..setMode(MyLocationMode.heading);
      expect(camera.moves.last.$1.bearing, 120);

      async.elapse(const Duration(milliseconds: 200));
      follower.setMode(MyLocationMode.follow);
      expect(camera.moves.last.$1.bearing, 0);
      follower.dispose();
    });
  });

  test('keeps its hands off while a finger is down', () {
    fakeAsync((async) {
      final camera = FakeCamera(const GeoCamera(target: here, zoom: 17));
      final follower = GeoFollower(camera: camera)
        ..setTarget(here)
        ..setMode(MyLocationMode.follow);
      async.elapse(const Duration(milliseconds: 200));
      final before = camera.moves.length;

      follower
        ..pointerDown()
        ..pointerDown()
        ..setTarget(there);
      async.elapse(const Duration(seconds: 1));
      expect(camera.moves, hasLength(before));

      follower.pointerUp();
      expect(camera.moves, hasLength(before));
      follower.pointerUp();
      expect(camera.moves.last.$1.target, there);
      follower.dispose();
    });
  });

  test('does nothing for a move too small to see, or when not following', () {
    fakeAsync((async) {
      final camera = FakeCamera(const GeoCamera(target: here, zoom: 17));
      final follower = GeoFollower(camera: camera)
        ..setTarget(here)
        ..setMode(MyLocationMode.follow);
      async.elapse(const Duration(milliseconds: 200));
      // Already there, north up: nothing to do.
      expect(camera.moves, isEmpty);

      follower
        ..setMode(MyLocationMode.none)
        ..setTarget(there);
      async.elapse(const Duration(milliseconds: 200));
      expect(camera.moves, isEmpty);
      follower.dispose();
    });
  });
}
