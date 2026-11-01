import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../core/map_level.dart';
import '../location/level_location.dart';
import '../location/my_location_controller.dart';
import '../location/my_location_style.dart';
import 'viewport_math.dart';

/// Paints the visitor's position on a level, inside the zoomed picture.
///
/// The accuracy circle is drawn in the picture's own units, so it grows and
/// shrinks with the zoom like the rooms do. The dot and its cone are drawn
/// back down by the camera's scale, so they stay one size on the glass.
///
/// It repaints on the camera, the fix and the heading — a painter's
/// `repaint`, not a rebuild — so a compass turning many times a second costs
/// a repaint of this one layer and nothing else.
@internal
class MyLocationPainter extends CustomPainter {
  /// Paints [controller]'s fix on [level] under [transform], in [style].
  MyLocationPainter({
    required this.transform,
    required this.controller,
    required this.level,
    required this.style,
  }) : super(
         repaint: Listenable.merge([transform, controller, controller.heading]),
       );

  /// The camera.
  final TransformationController transform;

  /// The position.
  final MyLocationController controller;

  /// The level being painted.
  final MapLevel level;

  /// How it looks.
  final MyLocationStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final fix = controller.fix;
    if (fix == null || controller.status == MyLocationStatus.off) return;
    final at = LevelLocation.place(fix, level);
    if (at == null) return;
    final scale = ViewportMath.scaleOf(transform.value);
    if (scale <= 0) return;

    final accuracy = fix.accuracy;
    final unitsPerMetre = LevelLocation.unitsPerMetre(level, at);
    if (accuracy != null && unitsPerMetre != null) {
      style.paintAccuracy(
        canvas,
        at,
        accuracy * unitsPerMetre,
        strokeWidth: 1 / scale,
      );
    }

    final north = LevelLocation.north(level, at);
    final heading = controller.heading.value;
    final cone = north != null && heading != null;
    final puck = style.puckSize;
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(1 / scale);
    if (cone) canvas.rotate(north + heading * math.pi / 180);
    canvas.translate(-puck.width / 2, -puck.height / 2);
    style.paintPuck(canvas, puck, cone: cone);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MyLocationPainter oldDelegate) =>
      oldDelegate.transform != transform ||
      oldDelegate.controller != controller ||
      oldDelegate.level != level ||
      oldDelegate.style != style;
}
