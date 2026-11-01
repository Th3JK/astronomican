import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import 'marker_anchor.dart';

/// Paints a marker's picture onto [canvas], filling [size] logical pixels.
typedef MarkerPainter = void Function(Canvas canvas, Size size);

/// The picture a marker is drawn with, on either engine.
///
/// The image map could draw any widget, but MapLibre draws only pictures that
/// have been registered with the style. An icon is therefore something both can
/// render: a bitmap for MapLibre (see `MarkerRasterizer`) and a widget for the
/// image map. An image map that wants a full widget per marker can still pass a
/// `markerBuilder`; the icon then only supplies its [size] and [anchor].
///
/// Icons are shared by [key]. MapLibre registers each key once per style, so
/// a hundred markers with the same pin cost one image, and a marker whose icon
/// changes — say, to a selected variant — only swaps which key it points at.
@immutable
sealed class MarkerIcon {
  const MarkerIcon();

  /// A bundled picture drawn at [size], standing on [anchor].
  const factory MarkerIcon.asset(
    String asset, {
    required Size size,
    MarkerAnchor anchor,
    String? package,
  }) = AssetMarkerIcon;

  /// An encoded picture already in memory, registered under [key].
  const factory MarkerIcon.bytes(
    String key,
    Uint8List bytes, {
    required Size size,
    MarkerAnchor anchor,
  }) = BytesMarkerIcon;

  /// A picture drawn by [painter], registered under [key].
  ///
  /// The key stands in for the painter, which cannot be compared: two icons
  /// with the same key must paint the same picture.
  const factory MarkerIcon.painted(
    String key, {
    required Size size,
    required MarkerPainter painter,
    MarkerAnchor anchor,
  }) = PaintedMarkerIcon;

  /// A drop-shaped pin in [color], with an optional short [label] in its head.
  const factory MarkerIcon.pin({
    Color color,
    String? label,
    Color labelColor,
    double height,
  }) = PinMarkerIcon;

  /// A filled circle with a ring, such as a "you are here" dot.
  const factory MarkerIcon.dot({
    Color color,
    double diameter,
    Color borderColor,
    double borderWidth,
  }) = DotMarkerIcon;

  /// A round badge with a short [text] — the count on a cluster of markers.
  const factory MarkerIcon.badge(
    String text, {
    Color color,
    Color textColor,
    double diameter,
    Color borderColor,
    double borderWidth,
  }) = BadgeMarkerIcon;

  /// A tag with a building drawn on it, standing on its point: a building
  /// whose floors can be opened, set apart from the stops around it.
  const factory MarkerIcon.building({
    Color color,
    Color symbolColor,
    double height,
  }) = BuildingMarkerIcon;

  /// Identifies the picture. Equal keys must mean equal pictures.
  String get key;

  /// How big the picture is drawn on screen, in logical pixels. It stays this
  /// size at every zoom.
  Size get size;

  /// Which point of the picture stands on the marker's position.
  MarkerAnchor get anchor;
}

/// A bundled picture.
final class AssetMarkerIcon extends MarkerIcon {
  /// The [asset] drawn at [size].
  const AssetMarkerIcon(
    this.asset, {
    required this.size,
    this.anchor = MarkerAnchor.center,
    this.package,
  });

  /// The asset key, as listed in the pubspec.
  final String asset;

  /// The package the asset ships in, when it is not the app's own.
  final String? package;

  @override
  final Size size;

  @override
  final MarkerAnchor anchor;

  /// The key the asset is loaded by.
  String get assetKey => package == null ? asset : 'packages/$package/$asset';

  @override
  String get key => 'asset:$assetKey@${_n(size.width)}x${_n(size.height)}';

  @override
  bool operator ==(Object other) =>
      other is AssetMarkerIcon &&
      other.asset == asset &&
      other.package == package &&
      other.size == size &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(asset, package, size, anchor);
}

/// An encoded picture in memory.
final class BytesMarkerIcon extends MarkerIcon {
  /// The picture in [bytes], known as [key].
  const BytesMarkerIcon(
    this.id,
    this.bytes, {
    required this.size,
    this.anchor = MarkerAnchor.center,
  });

  /// The caller's name for the picture.
  final String id;

  /// The encoded picture.
  final Uint8List bytes;

  @override
  final Size size;

  @override
  final MarkerAnchor anchor;

  @override
  String get key => 'bytes:$id';

  @override
  bool operator ==(Object other) =>
      other is BytesMarkerIcon &&
      other.id == id &&
      other.size == size &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(id, size, anchor);
}

/// A picture drawn in code.
///
/// Sealed rather than open: both engines have to know how to draw every kind
/// of icon, so new kinds are added here, not by subclassing elsewhere.
sealed class CanvasMarkerIcon extends MarkerIcon {
  const CanvasMarkerIcon();

  /// Draws the icon onto [canvas], which is [size] logical pixels across.
  void paint(Canvas canvas, Size size);
}

/// A picture drawn by a caller's painter.
final class PaintedMarkerIcon extends CanvasMarkerIcon {
  /// The picture [painter] draws, known as [id].
  const PaintedMarkerIcon(
    this.id, {
    required this.size,
    required this.painter,
    this.anchor = MarkerAnchor.center,
  });

  /// The caller's name for the picture.
  final String id;

  /// Draws the picture.
  final MarkerPainter painter;

  @override
  final Size size;

  @override
  final MarkerAnchor anchor;

  @override
  String get key => 'painted:$id@${_n(size.width)}x${_n(size.height)}';

  @override
  void paint(Canvas canvas, Size size) => painter(canvas, size);

  @override
  bool operator ==(Object other) =>
      other is PaintedMarkerIcon &&
      other.id == id &&
      other.size == size &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(id, size, anchor);
}

/// The default marker: a drop that stands on its point.
final class PinMarkerIcon extends CanvasMarkerIcon {
  /// A pin [height] tall in [color], with [label] in its head.
  const PinMarkerIcon({
    this.color = const Color(0xFFD32F2F),
    this.label,
    this.labelColor = const Color(0xFFFFFFFF),
    this.height = 40,
  });

  /// The drop's colour.
  final Color color;

  /// A short text in the head — a stop number, a letter. Kept to a few
  /// characters; it is drawn to fit the head, not wrapped.
  final String? label;

  /// The colour of [label], and of the dot drawn in its place when there is
  /// none.
  final Color labelColor;

  /// How tall the drop is, in logical pixels.
  final double height;

  @override
  Size get size => Size(height * 0.72, height);

  @override
  MarkerAnchor get anchor => MarkerAnchor.bottom;

  @override
  String get key =>
      'pin:${_hex(color)}:${label ?? ''}:${_hex(labelColor)}:${_n(height)}';

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final centre = Offset(size.width / 2, r);
    final tip = Offset(size.width / 2, size.height);
    final d = tip.dy - centre.dy;
    // Where the two straight sides of the drop touch the round head: the
    // points from which the head's edge runs square to the line to the tip.
    final beta = math.acos((r / d).clamp(-1.0, 1.0));

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(centre.dx + r * math.sin(beta), centre.dy + r * math.cos(beta))
      ..arcTo(
        Rect.fromCircle(center: centre, radius: r),
        math.pi / 2 - beta,
        -(2 * math.pi - 2 * beta),
        false,
      )
      ..close();

    // A soft outline in white keeps the pin readable on dark tiles as well as
    // light ones.
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xE6FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, height / 28),
    );

    final label = this.label;
    if (label == null || label.isEmpty) {
      canvas.drawCircle(centre, r * 0.36, Paint()..color = labelColor);
      return;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: r * (label.length > 2 ? 0.8 : 1.0),
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // Squeezed rather than clipped when a label runs wider than the head.
    final fit = math.min(1.0, r * 1.6 / painter.width);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(fit);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    painter.dispose();
  }

  @override
  bool operator ==(Object other) =>
      other is PinMarkerIcon &&
      other.color == color &&
      other.label == label &&
      other.labelColor == labelColor &&
      other.height == height;

  @override
  int get hashCode => Object.hash(color, label, labelColor, height);
}

/// A dot with a ring around it, centred on its position.
final class DotMarkerIcon extends CanvasMarkerIcon {
  /// A dot [diameter] across in [color], ringed with [borderColor].
  const DotMarkerIcon({
    this.color = const Color(0xFF1E88E5),
    this.diameter = 18,
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderWidth = 3,
  });

  /// The fill.
  final Color color;

  /// Outer diameter, ring included, in logical pixels.
  final double diameter;

  /// The ring's colour.
  final Color borderColor;

  /// The ring's width, in logical pixels.
  final double borderWidth;

  @override
  Size get size => Size.square(diameter);

  @override
  MarkerAnchor get anchor => MarkerAnchor.center;

  @override
  String get key =>
      'dot:${_hex(color)}:${_n(diameter)}:${_hex(borderColor)}:${_n(borderWidth)}';

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(centre, radius, Paint()..color = borderColor);
    canvas.drawCircle(
      centre,
      math.max(0, radius - borderWidth),
      Paint()..color = color,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DotMarkerIcon &&
      other.color == color &&
      other.diameter == diameter &&
      other.borderColor == borderColor &&
      other.borderWidth == borderWidth;

  @override
  int get hashCode => Object.hash(color, diameter, borderColor, borderWidth);
}

/// A round badge with a short text, centred on its position.
final class BadgeMarkerIcon extends CanvasMarkerIcon {
  /// A badge [diameter] across in [color], with [text] in [textColor].
  const BadgeMarkerIcon(
    this.text, {
    this.color = const Color(0xFF1F2A44),
    this.textColor = const Color(0xFFFFFFFF),
    this.diameter = 36,
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderWidth = 2.5,
  });

  /// The text: a few characters, squeezed to fit rather than wrapped.
  final String text;

  /// The fill.
  final Color color;

  /// The colour of [text].
  final Color textColor;

  /// Outer diameter, ring included, in logical pixels.
  final double diameter;

  /// The ring's colour.
  final Color borderColor;

  /// The ring's width.
  final double borderWidth;

  @override
  Size get size => Size.square(diameter);

  @override
  MarkerAnchor get anchor => MarkerAnchor.center;

  @override
  String get key =>
      'badge:$text:${_hex(color)}:${_hex(textColor)}:${_n(diameter)}:'
      '${_hex(borderColor)}:${_n(borderWidth)}';

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      centre.translate(0, 1),
      radius - 1,
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawCircle(centre, radius - 1, Paint()..color = borderColor);
    canvas.drawCircle(
      centre,
      math.max(0, radius - 1 - borderWidth),
      Paint()..color = color,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final fit = math.min(1.0, (radius - borderWidth) * 1.5 / painter.width);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(fit);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    painter.dispose();
  }

  @override
  bool operator ==(Object other) =>
      other is BadgeMarkerIcon &&
      other.text == text &&
      other.color == color &&
      other.textColor == textColor &&
      other.diameter == diameter &&
      other.borderColor == borderColor &&
      other.borderWidth == borderWidth;

  @override
  int get hashCode =>
      Object.hash(text, color, textColor, diameter, borderColor, borderWidth);
}

/// A rounded tag with a building drawn on it, standing on the point below it.
final class BuildingMarkerIcon extends CanvasMarkerIcon {
  /// A tag [height] tall in [color], with the building in [symbolColor].
  const BuildingMarkerIcon({
    this.color = const Color(0xFF00695C),
    this.symbolColor = const Color(0xFFFFFFFF),
    this.height = 50,
  });

  /// The tag's fill.
  final Color color;

  /// The building's colour.
  final Color symbolColor;

  /// How tall the tag is, point included, in logical pixels.
  final double height;

  @override
  Size get size => Size(height * 0.84, height);

  @override
  MarkerAnchor get anchor => MarkerAnchor.bottom;

  @override
  String get key =>
      'building:${_hex(color)}:${_hex(symbolColor)}:${_n(height)}';

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final point = size.height * 0.16;
    final body = Rect.fromLTWH(1, 1, w - 2, size.height - point - 2);
    final radius = Radius.circular(w * 0.22);
    final tag = Path()
      ..addRRect(RRect.fromRectAndRadius(body, radius))
      ..moveTo(w / 2 - point * 0.8, body.bottom - 1)
      ..lineTo(w / 2, size.height)
      ..lineTo(w / 2 + point * 0.8, body.bottom - 1)
      ..close();
    canvas.drawPath(tag, Paint()..color = color);
    canvas.drawPath(
      tag,
      Paint()
        ..color = const Color(0xE6FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.height / 28),
    );

    // A classical front — pediment, columns, steps — reads as "a building to
    // go into" at any size, and needs no font.
    final s = body.deflate(body.width * 0.2);
    final ink = Paint()..color = symbolColor;
    final roof = s.height * 0.28;
    canvas.drawPath(
      Path()
        ..moveTo(s.left, s.top + roof)
        ..lineTo(s.center.dx, s.top)
        ..lineTo(s.right, s.top + roof)
        ..close(),
      ink,
    );
    final base = s.height * 0.14;
    final gap = s.height * 0.08;
    final columnTop = s.top + roof + gap;
    final columnBottom = s.bottom - base - gap;
    final column = s.width * 0.14;
    for (var i = 0; i < 3; i++) {
      final x = s.left + s.width * (0.17 + 0.33 * i) - column / 2;
      canvas.drawRect(
        Rect.fromLTRB(x, columnTop, x + column, columnBottom),
        ink,
      );
    }
    canvas.drawRect(
      Rect.fromLTRB(s.left, s.bottom - base, s.right, s.bottom),
      ink,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BuildingMarkerIcon &&
      other.color == color &&
      other.symbolColor == symbolColor &&
      other.height == height;

  @override
  int get hashCode => Object.hash(color, symbolColor, height);
}

String _hex(Color color) => color.toARGB32().toRadixString(16).padLeft(8, '0');

/// A number as it appears in a key: no trailing `.0`, so `40` and `40.0` agree.
String _n(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
