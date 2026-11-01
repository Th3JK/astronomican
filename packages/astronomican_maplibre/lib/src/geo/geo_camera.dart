import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';

/// Where a `GeoMap` looks from.
@immutable
final class GeoCamera {
  /// A camera over [target] at [zoom].
  const GeoCamera({
    required this.target,
    this.zoom = 14,
    this.bearing = 0,
    this.tilt = 0,
  });

  /// The point in the middle of the map.
  final GeoPosition target;

  /// The zoom level: 0 shows the world in one 512-pixel square, and every
  /// step doubles the scale.
  final double zoom;

  /// Degrees clockwise from north that the map is turned.
  final double bearing;

  /// Degrees the map is tilted away from straight down.
  final double tilt;

  /// The camera that shows all of [bounds] in a [viewport], less [padding].
  ///
  /// Worked out in Dart rather than asked of the map, so the map can be
  /// created already looking at the right place: fitting after it is up shows
  /// as a jump on its first frame.
  ///
  /// MapLibre's zoom counts 512-pixel tiles, so at zoom `z` the world is
  /// `512 · 2^z` logical pixels across.
  static GeoCamera fit(
    GeoBounds bounds,
    Size viewport, {
    EdgeInsets padding = EdgeInsets.zero,
    double minZoom = 0,
    double maxZoom = 20,
  }) {
    const tileSize = 512.0;
    final sw = WebMercator.project(bounds.southwest);
    final ne = WebMercator.project(bounds.northeast);
    final width = (ne.dx - sw.dx).abs();
    final height = (sw.dy - ne.dy).abs();

    var area = padding.deflateSize(viewport);
    if (area.width <= 0 || area.height <= 0) area = viewport;

    double zoom;
    if (width <= 0 && height <= 0) {
      zoom = maxZoom;
    } else {
      final zx = width > 0
          ? _log2(area.width / (width * tileSize))
          : double.infinity;
      final zy = height > 0
          ? _log2(area.height / (height * tileSize))
          : double.infinity;
      zoom = math.min(zx, zy);
    }
    zoom = zoom.clamp(minZoom, math.max(minZoom, maxZoom)).toDouble();

    // The padded area's middle is off the screen's by half the difference in
    // padding; the camera's target sits under the screen's middle, so it moves
    // the other way by as much.
    final world = tileSize * math.pow(2, zoom);
    final shift = Offset(
      (padding.right - padding.left) / 2 / world,
      (padding.bottom - padding.top) / 2 / world,
    );
    final middle = Offset((sw.dx + ne.dx) / 2, (sw.dy + ne.dy) / 2);
    return GeoCamera(target: WebMercator.unproject(middle + shift), zoom: zoom);
  }

  static double _log2(double x) => math.log(x) / math.ln2;

  @override
  bool operator ==(Object other) =>
      other is GeoCamera &&
      other.target == target &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(target, zoom, bearing, tilt);

  @override
  String toString() => 'GeoCamera($target, z$zoom)';
}
