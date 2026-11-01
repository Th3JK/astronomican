import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import 'heading_smoother.dart';
import 'location_feed.dart';
import 'location_fix.dart';

/// Where a [MyLocationController] stands.
enum MyLocationStatus {
  /// Not started.
  off,

  /// Started, waiting for the first fix.
  searching,

  /// Delivering fixes.
  active,

  /// The visitor refused access; asking again may work.
  denied,

  /// The visitor refused access for good; only the settings can change it.
  deniedForever,

  /// Location is switched off for the whole device.
  serviceDisabled,

  /// The device cannot be located.
  unsupported;

  /// Whether this is a reason the position cannot be shown, which the app
  /// may want to explain or send the visitor to the settings for.
  bool get isProblem => switch (this) {
    off || searching || active => false,
    denied || deniedForever || serviceDisabled || unsupported => true,
  };
}

/// What the map does with the visitor's position.
enum MyLocationMode {
  /// Draws it, and leaves the camera to the visitor.
  none,

  /// Keeps it in the middle as the visitor walks.
  follow,

  /// Keeps it in the middle and turns the map to face the way the visitor
  /// does.
  heading,
}

/// The visitor's position on a map: whether it is known, and whether the map
/// follows it.
///
/// Give one to a map's `myLocation` and put a `MyLocationButton` next to it.
/// The button cycles like the one in every map app: the first tap starts
/// the feed and follows, the next turns the map to face the way the visitor
/// does, the next goes back to following; dragging the map stops following.
///
/// ```dart
/// final myLocation = MyLocationController(feed: DeviceLocationFeed());
///
/// Stack(children: [
///   GeoMap(source: …, myLocation: myLocation),
///   Positioned(right: 16, bottom: 16,
///       child: MyLocationButton(controller: myLocation)),
/// ]);
/// ```
///
/// Listeners hear about the status, the mode and every fix. The heading
/// changes many times a second and is on its own listenable, [heading], so a
/// compass does not rebuild everything that listens here.
class MyLocationController extends ChangeNotifier {
  /// A controller reading [feed], which it does not own: several controllers
  /// may share one feed, and the app disposes it.
  ///
  /// [headingInterval] and [headingDeadband] bound how often [heading]
  /// changes: at most once per interval, and only by at least the deadband.
  /// With [pauseWhenHidden] the feed is released while the app is in the
  /// background, and taken again when it returns.
  MyLocationController({
    required this.feed,
    this.headingInterval = const Duration(milliseconds: 66),
    this.headingDeadband = 1,
    this.pauseWhenHidden = true,
  });

  /// Where positions come from.
  final LocationFeed feed;

  /// The shortest time between two changes of [heading].
  final Duration headingInterval;

  /// The smallest change of [heading], in degrees, worth reporting.
  final double headingDeadband;

  /// Whether the feed is released while the app is hidden.
  final bool pauseWhenHidden;

  final ValueNotifier<double?> _heading = ValueNotifier<double?>(null);
  final HeadingSmoother _smoother = HeadingSmoother();

  MyLocationStatus _status = MyLocationStatus.off;
  MyLocationMode _mode = MyLocationMode.none;
  LocationFix? _fix;
  int _centreRequests = 0;
  bool _orientable = true;

  bool _wanted = false;
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  Future<MyLocationStatus>? _starting;
  StreamSubscription<LocationFix>? _fixSubscription;
  StreamSubscription<double>? _headingSubscription;
  AppLifecycleListener? _lifecycle;
  Timer? _headingTimer;
  double? _pendingHeading;

  /// Whether the position is known, and if not, why.
  MyLocationStatus get status => _status;

  /// What the map does with the position.
  MyLocationMode get mode => _mode;

  /// The latest fix, or null before the first.
  LocationFix? get fix => _fix;

  /// Which way the visitor faces, in degrees clockwise from true north,
  /// smoothed; null until the feed reports one.
  ValueListenable<double?> get heading => _heading;

  /// Whether [MyLocationMode.heading] is on offer: the feed has a heading,
  /// and the map showing it knows which way north is.
  bool get canFaceHeading => feed.providesHeading && _orientable;

  /// Bumped each time the visitor asks to be put back in the middle, so a
  /// map re-centres even when the mode did not change.
  int get centreRequests => _centreRequests;

  /// Whether the map showing this position knows which way north is on it.
  /// Maps set this: a street map always does, a picture only when it is
  /// georeferenced or has a bearing.
  bool get orientable => _orientable;
  set orientable(bool value) {
    if (value == _orientable) return;
    _orientable = value;
    if (!value && _mode == MyLocationMode.heading) {
      _mode = MyLocationMode.follow;
    }
    _notify();
  }

  /// Starts the feed. Returns what came of it; on
  /// [MyLocationStatus.searching] the first fix is on its way.
  Future<MyLocationStatus> start() {
    if (_disposed) throw StateError('The controller has been disposed.');
    _wanted = true;
    _paused = false;
    if (pauseWhenHidden) {
      _lifecycle ??= AppLifecycleListener(onHide: _pause, onShow: _resume);
    }
    return _starting ??= _open().whenComplete(() => _starting = null);
  }

  /// Stops the feed and forgets the mode. The last fix stays, for a map that
  /// wants to show where the visitor was.
  Future<void> stop() async {
    _wanted = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    await _close();
    _mode = MyLocationMode.none;
    _status = MyLocationStatus.off;
    _notify();
  }

  /// What the location button does: starts the feed and follows when it is
  /// off, and otherwise steps none → follow → heading → follow.
  void cycle() {
    if (_status == MyLocationStatus.searching ||
        _status == MyLocationStatus.active) {
      setMode(switch (_mode) {
        MyLocationMode.none => MyLocationMode.follow,
        MyLocationMode.follow =>
          canFaceHeading ? MyLocationMode.heading : MyLocationMode.follow,
        MyLocationMode.heading => MyLocationMode.follow,
      });
      return;
    }
    setMode(MyLocationMode.follow);
    unawaited(
      start().then((status) {
        if (status.isProblem && !_disposed) setMode(MyLocationMode.none);
      }),
    );
  }

  /// Switches to [mode]. Heading falls back to following when it is not on
  /// offer. Switching to following, even from following, puts the visitor
  /// back in the middle.
  void setMode(MyLocationMode mode) {
    final next = mode == MyLocationMode.heading && !canFaceHeading
        ? MyLocationMode.follow
        : mode;
    if (next != MyLocationMode.none) _centreRequests++;
    _mode = next;
    _notify();
  }

  /// Leaves the camera to the visitor: what a map does when it is dragged.
  void stopFollowing() {
    if (_mode == MyLocationMode.none) return;
    _mode = MyLocationMode.none;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _wanted = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    _headingTimer?.cancel();
    unawaited(_close());
    _heading.dispose();
    super.dispose();
  }

  Future<MyLocationStatus> _open() async {
    if (_running) return _status;
    if (_fix == null || _status != MyLocationStatus.active) {
      _setStatus(MyLocationStatus.searching);
    }
    final access = await feed.start();
    if (_disposed || !_wanted || _paused) {
      if (access == LocationAccess.granted) await feed.stop();
      return _status;
    }
    if (access != LocationAccess.granted) {
      _setStatus(_statusFor(access));
      return _status;
    }
    _running = true;
    _fixSubscription = feed.fixes.listen(_onFix);
    _headingSubscription = feed.headings.listen(_onHeading);
    final last = feed.lastFix;
    if (last != null) _onFix(last);
    final heading = feed.lastHeading;
    if (heading != null) _onHeading(heading);
    return _status;
  }

  Future<void> _close() async {
    if (!_running) return;
    _running = false;
    _headingTimer?.cancel();
    _headingTimer = null;
    await _fixSubscription?.cancel();
    await _headingSubscription?.cancel();
    _fixSubscription = null;
    _headingSubscription = null;
    await feed.stop();
  }

  void _pause() {
    if (!_wanted || _paused) return;
    _paused = true;
    unawaited(_close());
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    if (_wanted && !_disposed) unawaited(start());
  }

  void _onFix(LocationFix fix) {
    if (_disposed) return;
    _fix = fix;
    _status = MyLocationStatus.active;
    _notify();
  }

  void _onHeading(double degrees) {
    if (_disposed) return;
    _pendingHeading = _smoother.add(degrees);
    if (_headingTimer == null) _flushHeading();
  }

  void _flushHeading() {
    final pending = _pendingHeading;
    final current = _heading.value;
    if (pending == null || _disposed) return;
    if (current != null &&
        HeadingSmoother.difference(current, pending).abs() < headingDeadband) {
      return;
    }
    _heading.value = pending;
    _headingTimer = Timer(headingInterval, () {
      _headingTimer = null;
      _flushHeading();
    });
  }

  void _setStatus(MyLocationStatus status) {
    if (status == _status) return;
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static MyLocationStatus _statusFor(LocationAccess access) => switch (access) {
    LocationAccess.granted => MyLocationStatus.active,
    LocationAccess.denied => MyLocationStatus.denied,
    LocationAccess.deniedForever => MyLocationStatus.deniedForever,
    LocationAccess.serviceDisabled => MyLocationStatus.serviceDisabled,
    LocationAccess.unsupported => MyLocationStatus.unsupported,
  };
}
