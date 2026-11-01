import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'viewport_math.dart';

/// A camera as the three things a person sees change: the point of the
/// picture in the middle of the screen, the zoom, and the turn.
///
/// Easing between two cameras through these, rather than entry by entry of
/// their matrices, keeps the middle on a straight line, the zoom even, and
/// the turn the short way round.
@internal
@immutable
final class CameraPose {
  /// [centre] of the picture in the middle, at [scale], turned [rotation]
  /// radians clockwise.
  const CameraPose(this.centre, this.scale, this.rotation);

  /// The pose of [matrix] on a screen [viewport] across.
  factory CameraPose.of(Matrix4 matrix, Size viewport) => CameraPose(
    ViewportMath.toContent(matrix, viewport.center(Offset.zero)),
    ViewportMath.scaleOf(matrix),
    ViewportMath.rotationOf(matrix),
  );

  /// The point of the picture in the middle of the screen.
  final Offset centre;

  /// Screen pixels per unit of the picture.
  final double scale;

  /// The turn, in radians clockwise.
  final double rotation;

  /// This pose as a camera on a screen [viewport] across.
  Matrix4 matrix(Size viewport) => ViewportMath.centreOn(
    centre,
    scale,
    viewport.center(Offset.zero),
    rotation: rotation,
  );

  /// The pose [t] of the way from [a] to [b].
  static CameraPose lerp(CameraPose a, CameraPose b, double t) => CameraPose(
    Offset.lerp(a.centre, b.centre, t)!,
    math.exp(_lerp(math.log(a.scale), math.log(b.scale), t)),
    a.rotation + turn(a.rotation, b.rotation) * t,
  );

  /// One frame [dt] long of easing towards [target]: each part closes the
  /// same share of its gap in the same time, however far it has to go.
  CameraPose towards(CameraPose target, Duration dt) {
    final seconds = dt.inMicroseconds / 1e6;
    double share(double timeConstant) => 1 - math.exp(-seconds / timeConstant);
    final move = share(0.35);
    final spin = share(0.2);
    return CameraPose(
      Offset.lerp(centre, target.centre, move)!,
      math.exp(_lerp(math.log(scale), math.log(target.scale), move)),
      rotation + turn(rotation, target.rotation) * spin,
    );
  }

  /// Whether the two are too close to tell apart on screen.
  bool isCloseTo(CameraPose other) =>
      (centre - other.centre).distance * scale < 0.3 &&
      (math.log(scale) - math.log(other.scale)).abs() < 1e-3 &&
      turn(rotation, other.rotation).abs() < 2e-3;

  /// The turn from [from] to [to] the short way round, in (-π, π].
  static double turn(double from, double to) {
    final d = (to - from) % (2 * math.pi);
    return d > math.pi ? d - 2 * math.pi : d;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Keeps a picture map's camera on the visitor while they walk.
///
/// A new fix, a turn of the compass, a request to zoom in: each only moves
/// the target, and every frame the camera closes part of the gap. So a fix
/// that lands in the middle of a turn does not interrupt it, and nothing ever
/// jumps. It stands aside while [blocked] says so — a finger on the map,
/// another camera move running — and catches up afterwards.
@internal
final class ImageFollower {
  /// A follower ticking on [vsync], reading and writing the camera through
  /// [read] and [write].
  ImageFollower({
    required TickerProvider vsync,
    required this.read,
    required this.write,
    required this.blocked,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  /// The camera now, or null before there is one.
  final CameraPose? Function() read;

  /// Moves the camera.
  final void Function(CameraPose pose) write;

  /// Whether to hold still this frame.
  final bool Function() blocked;

  late final Ticker _ticker;
  Duration? _last;
  Offset? _centre;
  double? _scale;
  double _rotation = 0;

  /// Whether it has somewhere to take the camera.
  bool get isFollowing => _centre != null;

  /// Takes the camera to [centre], turned [rotation], and — once — to
  /// [scale], after which the visitor's own zoom is left alone.
  void follow({
    required Offset centre,
    required double rotation,
    double? scale,
  }) {
    _centre = centre;
    _rotation = rotation;
    if (scale != null) _scale = scale;
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  /// Leaves the camera where it is.
  void stop() {
    _centre = null;
    _scale = null;
    if (_ticker.isActive) _ticker.stop();
  }

  /// Stops for good.
  void dispose() => _ticker.dispose();

  void _tick(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    final centre = _centre;
    if (centre == null) {
      _ticker.stop();
      return;
    }
    if (blocked()) return;
    final current = read();
    if (current == null) return;
    final dt = last == null ? const Duration(milliseconds: 16) : elapsed - last;
    final target = CameraPose(centre, _scale ?? current.scale, _rotation);
    final next = current.towards(target, dt);
    if (next.isCloseTo(target)) {
      write(target);
      _scale = null;
      _ticker.stop();
      return;
    }
    write(next);
  }
}
