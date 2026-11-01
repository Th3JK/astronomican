import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';
import 'geo_camera.dart';

/// What a [GeoFollower] moves: the map's camera, behind a seam so the
/// follower can be tested without a map.
@internal
abstract interface class FollowCamera {
  /// Where the camera is, or null before the map is up.
  GeoCamera? get camera;

  /// Moves the camera to [camera] over [duration].
  Future<void> move(GeoCamera camera, Duration duration);
}

/// Keeps a street map's camera on the visitor, and turned to their heading.
///
/// A GPS fix arrives about once a second and a compass reading many times a
/// second; each only updates the target. Camera moves go out at most once
/// per [interval], skip changes too small to see, and wait while a finger is
/// on the map — moving the camera under a finger interrupts the gesture —
/// then catch up when it lifts.
@internal
final class GeoFollower {
  /// A follower moving [camera], zooming in to [followZoom] when it starts
  /// following from further out than [nearZoom].
  GeoFollower({
    required this.camera,
    this.followZoom = 17,
    this.nearZoom = 15,
    this.interval = const Duration(milliseconds: 100),
  });

  /// The camera it moves.
  final FollowCamera camera;

  /// The zoom it comes in to on starting to follow.
  final double followZoom;

  /// Starting to follow from further out than this zooms in.
  final double nearZoom;

  /// The shortest time between two camera moves.
  final Duration interval;

  MyLocationMode _mode = MyLocationMode.none;
  GeoPosition? _target;
  double? _heading;
  bool _zoomIn = false;
  bool _newFix = false;
  bool _pending = false;
  int _pointers = 0;
  Timer? _cooling;

  /// What it is doing.
  MyLocationMode get mode => _mode;

  /// Follows in [mode]. [recentre] — a tap on the location button — puts the
  /// visitor back in the middle, zooming in if the map is far out.
  void setMode(MyLocationMode mode, {bool recentre = false}) {
    final was = _mode;
    _mode = mode;
    if (mode == MyLocationMode.none) {
      _pending = false;
      return;
    }
    if (was == MyLocationMode.none || recentre) _zoomIn = true;
    _request(newFix: true);
  }

  /// The visitor is now at [position].
  void setTarget(GeoPosition? position) {
    if (position == _target) return;
    _target = position;
    if (_mode != MyLocationMode.none) _request(newFix: true);
  }

  /// The visitor now faces [degrees] clockwise from north.
  void setHeading(double? degrees) {
    _heading = degrees;
    if (_mode == MyLocationMode.heading) _request(newFix: false);
  }

  /// A finger went down on the map.
  void pointerDown() => _pointers++;

  /// A finger lifted.
  void pointerUp() {
    if (_pointers > 0) _pointers--;
    if (_pointers == 0 && _pending) _request(newFix: true);
  }

  /// Stops for good.
  void dispose() {
    _cooling?.cancel();
    _cooling = null;
    _mode = MyLocationMode.none;
  }

  void _request({required bool newFix}) {
    _newFix = _newFix || newFix;
    if (_pointers > 0 || _cooling != null) {
      _pending = true;
      return;
    }
    _move();
  }

  void _move() {
    _pending = false;
    final target = _target;
    final now = camera.camera;
    if (_mode == MyLocationMode.none || target == null || now == null) return;

    var zoom = now.zoom;
    if (_zoomIn) {
      _zoomIn = false;
      if (zoom < nearZoom) zoom = followZoom;
    }
    final bearing = _mode == MyLocationMode.heading
        ? (_heading ?? now.bearing)
        : 0.0;
    final pixels =
        (WebMercator.project(target) - WebMercator.project(now.target))
            .distance *
        512 *
        math.pow(2, zoom);
    final turn = _turn(now.bearing, bearing).abs();
    if (pixels < 1 && turn < 2 && (zoom - now.zoom).abs() < 0.01) {
      _newFix = false;
      return;
    }

    // A fix glides; a turn of the compass is followed briskly. While facing
    // the heading both come often, so both are brisk.
    final duration = _newFix && _mode == MyLocationMode.follow
        ? const Duration(milliseconds: 900)
        : const Duration(milliseconds: 250);
    _newFix = false;
    unawaited(
      camera.move(
        GeoCamera(target: target, zoom: zoom, bearing: bearing, tilt: now.tilt),
        duration,
      ),
    );
    _cooling = Timer(interval, () {
      _cooling = null;
      if (_pending && _pointers == 0) _move();
    });
  }

  static double _turn(double from, double to) {
    final d = (to - from) % 360;
    return d > 180 ? d - 360 : d;
  }
}
