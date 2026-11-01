import 'dart:async';

import 'package:meta/meta.dart';

import 'location_fix.dart';

/// Whether a feed may deliver positions.
enum LocationAccess {
  /// It may, and is running.
  granted,

  /// The visitor said no, and may still be asked again.
  denied,

  /// The visitor said no for good; only the system settings can change it.
  deniedForever,

  /// Location is switched off for the whole device.
  serviceDisabled,

  /// There is no way to locate this device.
  unsupported,
}

/// Where the visitor's position comes from: the device's GPS and compass,
/// beacons, a simulated walk.
///
/// A feed is shared. The street map and a floor-plan dialog opened over it
/// each have their own `MyLocationController`, and both read one feed, so the
/// GPS runs once. It runs while any [start] is outstanding: every [start] that
/// was granted is matched by a [stop], and the last [stop] switches it off.
///
/// Subclasses implement [onStart] and [onStop] and report through [addFix]
/// and [addHeading]; this class does the counting and the streams.
abstract class LocationFeed {
  /// A feed with nothing reported yet.
  LocationFeed();

  final StreamController<LocationFix> _fixes =
      StreamController<LocationFix>.broadcast();
  final StreamController<double> _headings =
      StreamController<double>.broadcast();

  int _users = 0;
  Future<LocationAccess>? _opening;
  LocationAccess? _access;
  LocationFix? _lastFix;
  double? _lastHeading;
  bool _disposed = false;

  /// Every fix, as it arrives.
  Stream<LocationFix> get fixes => _fixes.stream;

  /// Which way the device points, in degrees clockwise from true north, as
  /// often as the source reports it.
  Stream<double> get headings => _headings.stream;

  /// Whether [headings] will say anything. Without a heading a map cannot
  /// turn to face the way the visitor does.
  bool get providesHeading;

  /// The last fix reported, so a map opened later draws the dot at once.
  LocationFix? get lastFix => _lastFix;

  /// The last heading reported.
  double? get lastHeading => _lastHeading;

  /// What the last [start] was told, or null before the first.
  LocationAccess? get access => _access;

  /// Whether the feed is delivering.
  bool get isRunning => _users > 0 && _access == LocationAccess.granted;

  /// Starts delivering, asking for access where the platform needs it.
  ///
  /// Only a start that comes back [LocationAccess.granted] counts, and needs
  /// a [stop]; one that does not can simply be tried again later.
  Future<LocationAccess> start() async {
    if (_disposed) throw StateError('The feed has been disposed.');
    _users++;
    final opening = _opening ??= _open();
    final access = await opening;
    if (access != LocationAccess.granted) {
      _users--;
      if (identical(_opening, opening)) _opening = null;
    }
    return access;
  }

  /// Ends one [start]. The last one switches the feed off.
  Future<void> stop() async {
    if (_users == 0) return;
    _users--;
    if (_users > 0) return;
    final opening = _opening;
    _opening = null;
    if (opening == null) return;
    if (await opening == LocationAccess.granted && _users == 0) {
      await onStop();
    }
  }

  /// Stops the feed whatever is outstanding and closes its streams.
  @mustCallSuper
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final running = _opening != null;
    _users = 0;
    _opening = null;
    if (running) await onStop();
    await _fixes.close();
    await _headings.close();
  }

  /// Starts the source. Called when the first user starts the feed.
  @protected
  Future<LocationAccess> onStart();

  /// Stops the source. Called when the last user stops the feed.
  @protected
  Future<void> onStop();

  /// Reports [fix] to every listener.
  @protected
  void addFix(LocationFix fix) {
    if (_disposed) return;
    _lastFix = fix;
    _fixes.add(fix);
  }

  /// Reports a heading of [degrees] clockwise from true north.
  @protected
  void addHeading(double degrees) {
    if (_disposed || !degrees.isFinite) return;
    final normal = degrees % 360;
    _lastHeading = normal;
    _headings.add(normal);
  }

  Future<LocationAccess> _open() async {
    final access = await onStart();
    _access = access;
    return access;
  }
}

/// A feed the app fills itself: a beacon SDK, a scanned QR code, a tap on
/// "I am here", a simulation.
///
/// ```dart
/// final feed = PushLocationFeed();
/// beacons.onRoom((room) => feed.push(LocationFix(
///   position: ImagePosition(room.x, room.y),
///   levelId: room.floor,
/// )));
/// ```
class PushLocationFeed extends LocationFeed {
  /// A feed that also carries headings when [providesHeading] is set.
  PushLocationFeed({this.providesHeading = false});

  @override
  final bool providesHeading;

  /// Reports [fix].
  void push(LocationFix fix) => addFix(fix);

  /// Reports a heading of [degrees] clockwise from true north.
  void pushHeading(double degrees) => addHeading(degrees);

  @override
  Future<LocationAccess> onStart() async => LocationAccess.granted;

  @override
  Future<void> onStop() async {}
}

/// A feed over streams the app already has — from its own location plugin,
/// say.
class StreamLocationFeed extends LocationFeed {
  /// A feed reading [fixes], and [headings] when there are any.
  StreamLocationFeed({
    required Stream<LocationFix> fixes,
    Stream<double>? headings,
  }) : _fixSource = fixes,
       _headingSource = headings;

  final Stream<LocationFix> _fixSource;
  final Stream<double>? _headingSource;
  StreamSubscription<LocationFix>? _fixSubscription;
  StreamSubscription<double>? _headingSubscription;

  @override
  bool get providesHeading => _headingSource != null;

  @override
  Future<LocationAccess> onStart() async {
    _fixSubscription = _fixSource.listen(addFix);
    _headingSubscription = _headingSource?.listen(addHeading);
    return LocationAccess.granted;
  }

  @override
  Future<void> onStop() async {
    await _fixSubscription?.cancel();
    await _headingSubscription?.cancel();
    _fixSubscription = null;
    _headingSubscription = null;
  }
}
