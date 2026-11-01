import 'package:flutter/painting.dart';

/// Which point of a marker's picture stands on the marker's position.
///
/// A pin stands on its point, so it is [bottom]; a disc or a shield sits
/// centred on the spot, so it is [center]. The same value drives both engines:
/// an [Alignment] inside the icon for the image map, and MapLibre's
/// `icon-anchor` for the geo map.
enum MarkerAnchor {
  /// The middle of the icon.
  center(Alignment.center, 'center'),

  /// The middle of the top edge.
  top(Alignment.topCenter, 'top'),

  /// The middle of the bottom edge — the point of a pin.
  bottom(Alignment.bottomCenter, 'bottom'),

  /// The middle of the left edge.
  left(Alignment.centerLeft, 'left'),

  /// The middle of the right edge.
  right(Alignment.centerRight, 'right'),

  /// The top-left corner.
  topLeft(Alignment.topLeft, 'top-left'),

  /// The top-right corner.
  topRight(Alignment.topRight, 'top-right'),

  /// The bottom-left corner — a flag on a pole.
  bottomLeft(Alignment.bottomLeft, 'bottom-left'),

  /// The bottom-right corner.
  bottomRight(Alignment.bottomRight, 'bottom-right');

  const MarkerAnchor(this.alignment, this.maplibre);

  /// The anchor as an alignment inside the icon.
  final Alignment alignment;

  /// The anchor as MapLibre's `icon-anchor` names it.
  final String maplibre;

  /// Where the anchor falls inside an icon [size] across, from its top-left.
  Offset within(Size size) => alignment.alongSize(size);
}
