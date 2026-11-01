import 'package:compassx/compassx.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Whether the app may read the device's position.
enum DevicePermission {
  /// Not granted; asking may help.
  denied,

  /// Not granted, and asking will not help.
  deniedForever,

  /// Granted while the app is in use, or always.
  granted,

  /// The platform cannot say.
  unknown,
}

/// A GPS reading, in the feed's own terms.
@immutable
final class DevicePosition {
  /// A reading at [latitude], [longitude].
  const DevicePosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.course,
    this.courseAccuracy,
    this.timestamp,
  });

  /// Degrees north.
  final double latitude;

  /// Degrees east.
  final double longitude;

  /// How far off it may be, in metres.
  final double? accuracy;

  /// Metres a second.
  final double? speed;

  /// The direction of travel, in degrees clockwise from north.
  final double? course;

  /// How far off [course] may be, in degrees. Android reports 0 and iOS -1
  /// when there is no course to speak of.
  final double? courseAccuracy;

  /// When it was taken.
  final DateTime? timestamp;
}

/// What the device feed needs from the platform: the location service, its
/// permission, the GPS and the compass.
///
/// The seam tests put a fake behind; [GeolocatorDevicePlatform] is the real
/// thing.
abstract interface class DevicePlatform {
  /// Whether location is switched on for the device.
  Future<bool> isServiceEnabled();

  /// What the app has been granted.
  Future<DevicePermission> checkPermission();

  /// Asks the visitor, and returns what they chose.
  Future<DevicePermission> requestPermission();

  /// GPS readings at most every [interval], and only after moving
  /// [distanceFilter] metres.
  Stream<DevicePosition> positions({
    required Duration interval,
    required double distanceFilter,
  });

  /// Headings relative to true north, as often as the compass reports. An
  /// error on it means the device has no compass.
  Stream<double> compass();
}

/// [DevicePlatform] through geolocator and compassx.
final class GeolocatorDevicePlatform implements DevicePlatform {
  /// The device's own location service and compass.
  const GeolocatorDevicePlatform();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<DevicePermission> checkPermission() async =>
      _permission(await Geolocator.checkPermission());

  @override
  Future<DevicePermission> requestPermission() async =>
      _permission(await Geolocator.requestPermission());

  @override
  Stream<DevicePosition> positions({
    required Duration interval,
    required double distanceFilter,
  }) {
    final distance = distanceFilter.round();
    final LocationSettings settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distance,
        intervalDuration: interval,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: LocationAccuracy.best,
        // On foot: iOS tunes its filtering for walking, and must not pause
        // updates while the visitor stands reading a panel.
        activityType: ActivityType.fitness,
        distanceFilter: distance,
        pauseLocationUpdatesAutomatically: false,
      ),
      _ => LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distance,
      ),
    };
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => DevicePosition(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        speed: p.speed,
        course: p.heading,
        courseAccuracy: p.headingAccuracy,
        timestamp: p.timestamp,
      ),
    );
  }

  @override
  Stream<double> compass() => CompassX.events.map((event) => event.heading);

  static DevicePermission _permission(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.denied => DevicePermission.denied,
        LocationPermission.deniedForever => DevicePermission.deniedForever,
        LocationPermission.whileInUse ||
        LocationPermission.always => DevicePermission.granted,
        LocationPermission.unableToDetermine => DevicePermission.unknown,
      };
}
