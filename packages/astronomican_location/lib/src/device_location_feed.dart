import 'dart:async';

import 'package:astronomican/astronomican.dart';

import 'device_platform.dart';

/// The device's own position and heading, as a [LocationFeed].
///
/// Starting it checks that location is switched on and asks for permission
/// when it has not been granted, and answers with a [LocationAccess] saying
/// how that went. Once granted it reports GPS fixes, and a compass heading
/// relative to true north.
///
/// A device without a compass — some cheap Android phones, the iOS
/// simulator — still gets a heading while the visitor walks: the GPS course,
/// used only when they move fast enough for it to mean something.
///
/// ```dart
/// final feed = DeviceLocationFeed();
/// final myLocation = MyLocationController(feed: feed);
/// // …
/// myLocation.dispose();
/// await feed.dispose();
/// ```
///
/// The heading is where the top of the phone points. Apps that let the screen
/// turn to landscape should lock the tour screens to portrait, or the map
/// will face a quarter turn off.
class DeviceLocationFeed extends LocationFeed {
  /// A feed reading the device through [platform], a fix at most every
  /// [interval] and after moving [distanceFilter] metres, and the compass
  /// unless [useCompass] is off.
  DeviceLocationFeed({
    DevicePlatform platform = const GeolocatorDevicePlatform(),
    this.interval = const Duration(seconds: 1),
    this.distanceFilter = 1,
    this.useCompass = true,
    this.minCourseSpeed = 1,
  }) : _platform = platform;

  final DevicePlatform _platform;

  /// The shortest time between two fixes.
  final Duration interval;

  /// How far, in metres, the visitor moves between two fixes.
  final double distanceFilter;

  /// Whether to read the compass. Off, the heading is the GPS course alone.
  final bool useCompass;

  /// The slowest walk, in metres a second, whose GPS course is taken as the
  /// heading when there is no compass.
  final double minCourseSpeed;

  StreamSubscription<DevicePosition>? _positions;
  StreamSubscription<double>? _compass;
  bool _compassWorks = false;

  /// The last error from the GPS stream, if any: the service switched off
  /// halfway, a platform failure.
  Object? lastError;

  @override
  bool get providesHeading => true;

  @override
  Future<LocationAccess> onStart() async {
    if (!await _platform.isServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    var permission = await _platform.checkPermission();
    if (permission == DevicePermission.denied) {
      permission = await _platform.requestPermission();
    }
    switch (permission) {
      case DevicePermission.denied:
        return LocationAccess.denied;
      case DevicePermission.deniedForever:
        return LocationAccess.deniedForever;
      case DevicePermission.unknown:
        return LocationAccess.unsupported;
      case DevicePermission.granted:
        break;
    }

    _compassWorks = false;
    _positions = _platform
        .positions(interval: interval, distanceFilter: distanceFilter)
        .listen(_onPosition, onError: (Object error) => lastError = error);
    if (useCompass) {
      _compass = _platform.compass().listen(
        _onCompass,
        onError: (Object _) {
          // No compass on this device: the course stands in for it.
          _compassWorks = false;
          unawaited(_compass?.cancel());
          _compass = null;
        },
        cancelOnError: true,
      );
    }
    return LocationAccess.granted;
  }

  @override
  Future<void> onStop() async {
    await _positions?.cancel();
    await _compass?.cancel();
    _positions = null;
    _compass = null;
  }

  void _onPosition(DevicePosition p) {
    final course = _course(p);
    addFix(
      LocationFix(
        position: GeoPosition(p.latitude, p.longitude),
        accuracy: p.accuracy,
        course: course,
        timestamp: p.timestamp,
      ),
    );
    if (!_compassWorks && course != null) addHeading(course);
  }

  void _onCompass(double heading) {
    _compassWorks = true;
    addHeading(heading);
  }

  /// The course, when the visitor moves fast enough and the platform says
  /// it knows one.
  double? _course(DevicePosition p) {
    final course = p.course;
    final speed = p.speed;
    if (course == null || speed == null || speed < minCourseSpeed) return null;
    if (course < 0) return null;
    final accuracy = p.courseAccuracy;
    // Android says 0 and iOS -1 for "no course".
    if (accuracy != null && accuracy <= 0 && course == 0) return null;
    return course;
  }
}
