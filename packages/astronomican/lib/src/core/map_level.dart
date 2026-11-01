import 'package:flutter/widgets.dart';

import 'image_georeference.dart';
import 'map_image.dart';
import 'map_position.dart';

/// One picture a map can show: a floor of a building, or the one illustrated
/// map of a site.
///
/// On an image map a level *is* the map; several of them are floors to switch
/// between. On a `GeoMap` a level is laid over the streets through its
/// [georeference], and switching levels swaps which floor is drawn there.
///
/// ### The logical frame
///
/// [size] is the level's coordinate frame, and it is deliberately independent
/// of the image file. Positions on the level are authored against this frame,
/// and the picture is stretched to fill it. So a plan can be re-exported
/// smaller, or swapped for a redrawn one, without moving a single marker — as
/// long as the new drawing covers the same frame.
@immutable
class MapLevel {
  /// A level named [id], drawing [image] stretched over a frame [size] across.
  const MapLevel({
    required this.id,
    required this.label,
    required this.image,
    required this.size,
    this.focus,
    this.georeference,
    this.bearing,
  });

  /// Unique among the levels shown together. Markers name the level they stand
  /// on by this.
  final String id;

  /// What a level selector shows for this level, such as `1` or `GF`.
  final String label;

  /// The picture.
  final MapImage image;

  /// The logical frame positions on this level are written in.
  final Size size;

  /// The part of the picture worth opening on.
  ///
  /// Plans are often drawn in one corner of a large sheet, or with a wide
  /// border of nothing around the building. An image map opens framed on this
  /// rather than on the whole sheet, and centres it when the sheet is smaller
  /// than the screen. Null, empty or negative means the whole frame.
  final Rect? focus;

  /// Where the picture is on the Earth, when it is anywhere.
  ///
  /// Required for the level to be drawn on a `GeoMap`, and for markers placed
  /// by [GeoPosition] to appear on it on an image map.
  final ImageGeoreference? georeference;

  /// The compass bearing the top of the picture faces, in degrees clockwise
  /// from north, for a picture with no [georeference] — a floor plan whose
  /// top wall faces east has a bearing of 90.
  ///
  /// It is what lets the map turn to face the visitor's heading. A level with
  /// a [georeference] takes its bearing from that, and this is ignored.
  final double? bearing;

  /// The whole frame, from the origin.
  Rect get frame => Offset.zero & size;

  /// [focus] if it describes an area, otherwise [frame].
  Rect get focusOrFrame {
    final focus = this.focus;
    if (focus == null || focus.width <= 0 || focus.height <= 0) return frame;
    return focus;
  }

  /// Whether [position] lies on the picture.
  bool contains(ImagePosition position) => frame.contains(position.toOffset());

  /// Where [position] stands on this level, or null when it cannot be placed
  /// here: a [GeoPosition] on a level with no [georeference].
  ImagePosition? locate(MapPosition position) => switch (position) {
    ImagePosition() => position,
    GeoPosition() => georeference?.toImage(position),
  };

  /// Starts decoding the picture, so the first frame that shows the level does
  /// not show it blank. Worth calling for every level from a splash screen.
  Future<void> precache(BuildContext context, {AssetBundle? bundle}) =>
      precacheImage(image.provider(bundle: bundle), context);

  @override
  bool operator ==(Object other) =>
      other is MapLevel &&
      other.id == id &&
      other.label == label &&
      other.image == image &&
      other.size == size &&
      other.focus == focus &&
      other.georeference == georeference &&
      other.bearing == bearing;

  @override
  int get hashCode =>
      Object.hash(id, label, image, size, focus, georeference, bearing);

  @override
  String toString() => 'MapLevel($id, $label, $size)';
}
