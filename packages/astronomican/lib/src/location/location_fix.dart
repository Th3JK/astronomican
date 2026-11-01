import 'package:meta/meta.dart';

import '../core/map_position.dart';

/// Where the visitor is, as a [LocationFeed] reported it.
///
/// Outdoors a fix is a [GeoPosition] from the GPS. Indoors it can be an
/// [ImagePosition] on one floor — from a beacon, a scanned QR code, a tap on
/// "I am here" — with [levelId] naming the floor. Either kind is drawn on
/// either map: a GPS fix is carried onto a georeferenced picture, and a
/// floor-plan fix onto the streets through its floor's georeference.
///
/// The heading is not part of a fix. A compass reports many times a second
/// and a GPS about once, so they arrive on separate streams.
@immutable
final class LocationFix {
  /// A fix at [position].
  const LocationFix({
    required this.position,
    this.levelId,
    this.accuracy,
    this.course,
    this.timestamp,
  });

  /// Where the visitor is.
  final MapPosition position;

  /// The level an [ImagePosition] is read on. Ignored for a [GeoPosition].
  final String? levelId;

  /// How far off the position may be, in metres; the radius of the circle
  /// drawn around the dot. Null when the source cannot say.
  final double? accuracy;

  /// The direction of travel in degrees clockwise from true north, when the
  /// visitor is moving fast enough for it to mean anything. Which way the
  /// phone points is the feed's heading, not this.
  final double? course;

  /// When the fix was taken, if the source says.
  final DateTime? timestamp;

  @override
  bool operator ==(Object other) =>
      other is LocationFix &&
      other.position == position &&
      other.levelId == levelId &&
      other.accuracy == accuracy &&
      other.course == course &&
      other.timestamp == timestamp;

  @override
  int get hashCode =>
      Object.hash(position, levelId, accuracy, course, timestamp);

  @override
  String toString() =>
      'LocationFix($position${levelId == null ? '' : ' on $levelId'}'
      '${accuracy == null ? '' : ' ±${accuracy!.toStringAsFixed(0)} m'})';
}
