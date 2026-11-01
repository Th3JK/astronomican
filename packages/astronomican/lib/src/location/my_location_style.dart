import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import '../core/marker/marker_icon.dart';

/// How the visitor's position is drawn: a dot, a cone for the way they face,
/// and a circle for how sure the fix is.
///
/// Both map engines draw it from this, so a street map and a floor plan
/// opened over it show the same dot.
@immutable
final class MyLocationStyle {
  /// The familiar blue dot.
  const MyLocationStyle({
    this.color = const Color(0xFF1E88E5),
    this.borderColor = const Color(0xFFFFFFFF),
    this.dotDiameter = 18,
    this.borderWidth = 3,
    this.coneColor = const Color(0x801E88E5),
    this.coneLength = 44,
    this.coneSpread = 70,
    this.accuracyColor = const Color(0x1F1E88E5),
    this.accuracyBorderColor = const Color(0x661E88E5),
  });

  /// The dot's fill.
  final Color color;

  /// The ring around the dot.
  final Color borderColor;

  /// The dot's diameter, ring included, in logical pixels.
  final double dotDiameter;

  /// The ring's width.
  final double borderWidth;

  /// The cone's colour at the dot; it fades out towards its tip.
  final Color coneColor;

  /// How far the cone reaches from the dot's centre.
  final double coneLength;

  /// How wide the cone opens, in degrees.
  final double coneSpread;

  /// The fill of the accuracy circle.
  final Color accuracyColor;

  /// The edge of the accuracy circle.
  final Color accuracyBorderColor;

  /// The box the dot and its cone are drawn in, centred on the position.
  Size get puckSize => Size.square(coneLength * 2);

  /// Draws the dot in the middle of [size] and, with [cone], the cone
  /// pointing up — north, before the map turns it.
  void paintPuck(Canvas canvas, Size size, {required bool cone}) {
    final centre = size.center(Offset.zero);
    if (cone) {
      final half = coneSpread * math.pi / 360;
      final reach = Rect.fromCircle(center: centre, radius: coneLength);
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy)
          ..arcTo(reach, -math.pi / 2 - half, 2 * half, false)
          ..close(),
        Paint()
          ..shader = RadialGradient(
            colors: [coneColor, coneColor.withAlpha(0)],
          ).createShader(reach),
      );
    }
    final radius = dotDiameter / 2;
    canvas.drawCircle(
      centre.translate(0, 1),
      radius + 1,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(centre, radius, Paint()..color = borderColor);
    canvas.drawCircle(
      centre,
      math.max(0, radius - borderWidth),
      Paint()..color = color,
    );
  }

  /// Draws the accuracy circle of [radius] around [centre], its edge
  /// [strokeWidth] wide in the canvas's units.
  void paintAccuracy(
    Canvas canvas,
    Offset centre,
    double radius, {
    double strokeWidth = 1,
  }) {
    if (!(radius > 0)) return;
    canvas.drawCircle(centre, radius, Paint()..color = accuracyColor);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = accuracyBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  /// The dot as a marker icon, with or without its [cone], for engines that
  /// draw icons rather than widgets.
  MarkerIcon puckIcon({required bool cone}) => MarkerIcon.painted(
    'my-location-${hashCode.toUnsigned(32).toRadixString(16)}-'
    '${cone ? 'cone' : 'dot'}',
    size: puckSize,
    painter: (canvas, size) => paintPuck(canvas, size, cone: cone),
  );

  @override
  bool operator ==(Object other) =>
      other is MyLocationStyle &&
      other.color == color &&
      other.borderColor == borderColor &&
      other.dotDiameter == dotDiameter &&
      other.borderWidth == borderWidth &&
      other.coneColor == coneColor &&
      other.coneLength == coneLength &&
      other.coneSpread == coneSpread &&
      other.accuracyColor == accuracyColor &&
      other.accuracyBorderColor == accuracyBorderColor;

  @override
  int get hashCode => Object.hash(
    color,
    borderColor,
    dotDiameter,
    borderWidth,
    coneColor,
    coneLength,
    coneSpread,
    accuracyColor,
    accuracyBorderColor,
  );
}
