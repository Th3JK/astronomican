import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The arithmetic behind an image map's camera, kept free of widgets so every
/// case can be tested on its own.
///
/// A camera here is the [Matrix4] an `InteractiveViewer` applies to a picture
/// laid out at its logical size: a uniform scale, a rotation — only while the
/// map turns to face the visitor's heading — and a translation.
/// "Content" coordinates are the picture's logical frame; "screen"
/// coordinates are the viewer's own box.
///
/// Scales are absolute ratios — screen pixels per content unit — because that
/// is what the matrix holds. A plan thousands of units across fits a phone at
/// a scale of about 0.15, so zoom limits are always written relative to
/// [fitScale], never as plain numbers.
abstract final class ViewportMath {
  /// The scale at which [content] just fits [viewport], less [padding].
  ///
  /// Zero when either is empty, which callers treat as "not laid out yet".
  static double fitScale(
    Size viewport,
    Size content, [
    EdgeInsets padding = EdgeInsets.zero,
  ]) {
    final area = _area(viewport, padding);
    if (area.isEmpty || content.isEmpty) return 0;
    return math.min(area.width / content.width, area.height / content.height);
  }

  /// The camera that shows [rect] of the content as large as fits in
  /// [viewport] less [padding], its scale held between [minScale] and
  /// [maxScale], and its middle in the middle of the padded area.
  ///
  /// Turned by [rotation], it fits the box the turned rectangle takes up.
  static Matrix4 fitRect(
    Rect rect, {
    required Size viewport,
    required double minScale,
    required double maxScale,
    EdgeInsets padding = EdgeInsets.zero,
    double rotation = 0,
  }) {
    final area = _area(viewport, padding);
    final c = math.cos(rotation).abs();
    final s = math.sin(rotation).abs();
    final width = rect.width * c + rect.height * s;
    final height = rect.width * s + rect.height * c;
    final raw = rect.isEmpty || area.isEmpty
        ? minScale
        : math.min(area.width / width, area.height / height);
    final scale = raw.clamp(minScale, math.max(minScale, maxScale)).toDouble();
    final centre = Offset(
      padding.left + area.width / 2,
      padding.top + area.height / 2,
    );
    return centreOn(rect.center, scale, centre, rotation: rotation);
  }

  /// The camera at [scale], turned [rotation] radians clockwise, that puts
  /// [content] at [screen].
  static Matrix4 centreOn(
    Offset content,
    double scale,
    Offset screen, {
    double rotation = 0,
  }) {
    if (rotation == 0) {
      return Matrix4.identity()
        ..translateByDouble(
          screen.dx - content.dx * scale,
          screen.dy - content.dy * scale,
          0,
          1,
        )
        // All three axes: InteractiveViewer reads the scale back with
        // getMaxScaleOnAxis, and an unscaled z axis would read as 1.
        ..scaleByDouble(scale, scale, scale, 1);
    }
    return Matrix4.identity()
      ..translateByDouble(screen.dx, screen.dy, 0, 1)
      ..rotateZ(rotation)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(-content.dx, -content.dy, 0, 1);
  }

  /// The scale [matrix] draws at.
  static double scaleOf(Matrix4 matrix) => matrix.getMaxScaleOnAxis();

  /// How far [matrix] turns the picture, in radians clockwise on screen.
  static double rotationOf(Matrix4 matrix) =>
      math.atan2(matrix.entry(1, 0), matrix.entry(0, 0));

  /// Where the content point [content] is drawn under [matrix].
  static Offset toScreen(Matrix4 matrix, Offset content) =>
      MatrixUtils.transformPoint(matrix, content);

  /// Which content point is drawn at [screen] under [matrix].
  static Offset toContent(Matrix4 matrix, Offset screen) =>
      MatrixUtils.transformPoint(Matrix4.inverted(matrix), screen);

  /// The part of the content showing through [viewport] under [matrix].
  ///
  /// On a turned map, the box around the turned screen.
  static Rect visibleRect(Matrix4 matrix, Size viewport) {
    final inverse = Matrix4.inverted(matrix);
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final corner in [
      Offset.zero,
      viewport.topRight(Offset.zero),
      viewport.bottomRight(Offset.zero),
      viewport.bottomLeft(Offset.zero),
    ]) {
      final p = MatrixUtils.transformPoint(inverse, corner);
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// [matrix] rescaled to [scale] about the screen point [focal], so whatever
  /// is under [focal] stays under it — what a pinch or a double tap does. It
  /// stays turned as it was.
  static Matrix4 zoomAbout(Matrix4 matrix, Offset focal, double scale) =>
      centreOn(
        toContent(matrix, focal),
        scale,
        focal,
        rotation: rotationOf(matrix),
      );

  /// [matrix] turned to [rotation] about the screen point [focal], keeping
  /// its scale.
  static Matrix4 rotateAbout(Matrix4 matrix, Offset focal, double rotation) =>
      centreOn(
        toContent(matrix, focal),
        scaleOf(matrix),
        focal,
        rotation: rotation,
      );

  /// [matrix] carried from a viewport [from] to one [to]: the same content
  /// point stays in the middle, and the zoom relative to a fit stays the same.
  ///
  /// Refitting on every resize would throw away where the visitor had panned
  /// to the moment they turned the phone.
  static Matrix4 resize(
    Matrix4 matrix, {
    required Size from,
    required Size to,
    required double fromFit,
    required double toFit,
  }) {
    if (fromFit <= 0 || toFit <= 0) return matrix;
    final relative = scaleOf(matrix) / fromFit;
    final centre = toContent(matrix, from.center(Offset.zero));
    return centreOn(
      centre,
      relative * toFit,
      to.center(Offset.zero),
      rotation: rotationOf(matrix),
    );
  }

  /// [matrix] pulled back so the content stays in view, or the very same
  /// instance when it already is.
  ///
  /// Along an axis where the drawn content is larger than [viewport], the
  /// visible window is kept inside the content's edges, give or take
  /// [overscroll] of the content's width. Along an axis where it is smaller
  /// there is nothing to scroll through, so the content is set with [rest] —
  /// usually the middle of the level's focus — in the middle, as far as that
  /// still keeps the whole content on screen.
  ///
  /// Returning the same instance lets a listener tell "nothing to do" from a
  /// correction without comparing matrices.
  ///
  /// A turned map has no edges that line up with the screen's, so there it
  /// is held by [clampCentre] instead.
  static Matrix4 clamp(
    Matrix4 matrix, {
    required Size viewport,
    required Size content,
    required double overscroll,
    required Offset rest,
  }) {
    final scale = scaleOf(matrix);
    if (scale <= 0 || viewport.isEmpty || content.isEmpty) return matrix;
    if (rotationOf(matrix).abs() > 1e-9) {
      return clampCentre(matrix, viewport: viewport, content: content);
    }

    final drawing = content * scale;
    final slack = content.width * overscroll * scale;
    final translation = matrix.getTranslation();
    final x = clampAxis(
      translation.x,
      drawing.width,
      viewport.width,
      slack,
      viewport.width / 2 - rest.dx * scale,
    );
    final y = clampAxis(
      translation.y,
      drawing.height,
      viewport.height,
      slack,
      viewport.height / 2 - rest.dy * scale,
    );

    if ((x - translation.x).abs() < 0.5 && (y - translation.y).abs() < 0.5) {
      return matrix;
    }
    return matrix.clone()..setTranslationRaw(x, y, translation.z);
  }

  /// [matrix] moved so the point of the content in the middle of the screen
  /// lies on the content, or the very same instance when it already does.
  ///
  /// Looser than [clamp]: the picture may leave part of the screen empty, so
  /// any point of it can be brought to the middle. That is what following
  /// the visitor needs — they may stand by the edge of the plan — and what a
  /// turned map, whose edges run across the screen, is held by.
  static Matrix4 clampCentre(
    Matrix4 matrix, {
    required Size viewport,
    required Size content,
  }) {
    final scale = scaleOf(matrix);
    if (scale <= 0 || viewport.isEmpty || content.isEmpty) return matrix;
    final middle = viewport.center(Offset.zero);
    final centre = toContent(matrix, middle);
    final inside = Offset(
      centre.dx.clamp(0.0, content.width),
      centre.dy.clamp(0.0, content.height),
    );
    if ((inside - centre).distance * scale < 0.5) return matrix;
    return centreOn(inside, scale, middle, rotation: rotationOf(matrix));
  }

  /// Where the content's leading edge may sit along one axis.
  ///
  /// [offset] is where it sits now, [drawing] and [viewport] the lengths of the
  /// drawn content and of the screen, [slack] the allowed overscroll, and
  /// [rest] where it would sit to centre the content's focus.
  static double clampAxis(
    double offset,
    double drawing,
    double viewport,
    double slack,
    double rest,
  ) {
    if (drawing <= viewport) return rest.clamp(0.0, viewport - drawing);
    // Trailing edge no further in than the viewport's, leading edge no further
    // out than its own — with a little give at both ends.
    return offset.clamp(viewport - drawing - slack, slack);
  }

  static Size _area(Size viewport, EdgeInsets padding) {
    final area = padding.deflateSize(viewport);
    if (area.width <= 0 || area.height <= 0) return viewport;
    return area;
  }
}
