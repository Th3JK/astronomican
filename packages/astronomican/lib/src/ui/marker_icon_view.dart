import 'package:flutter/widgets.dart';

import '../core/marker/marker_icon.dart';

/// A [MarkerIcon] as a widget, at the icon's own size.
///
/// What an image map draws for a marker by default, and a starting point for a
/// `markerBuilder` that wants the same picture with something added — a
/// selection pop, a badge.
class MarkerIconView extends StatelessWidget {
  /// Draws [icon].
  const MarkerIconView(this.icon, {super.key});

  /// The icon to draw.
  final MarkerIcon icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final size = icon.size;
    return switch (icon) {
      AssetMarkerIcon() => Image.asset(
        icon.asset,
        package: icon.package,
        width: size.width,
        height: size.height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
      BytesMarkerIcon() => Image.memory(
        icon.bytes,
        width: size.width,
        height: size.height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
      CanvasMarkerIcon() => CustomPaint(
        size: size,
        painter: _IconPainter(icon),
      ),
    };
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon);

  final CanvasMarkerIcon icon;

  @override
  void paint(Canvas canvas, Size size) => icon.paint(canvas, size);

  @override
  bool shouldRepaint(_IconPainter oldDelegate) => oldDelegate.icon != icon;
}
