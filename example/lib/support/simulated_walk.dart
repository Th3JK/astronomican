import 'dart:async';
import 'dart:math' as math;

import 'package:astronomican/astronomican.dart';

import '../demo_data.dart';

/// A visitor walking the town, for trying the location button at a desk.
///
/// Walks [route] round and round at [speed] metres a second, reporting a fix
/// every second like a GPS, and a heading several times a second like a
/// compass — facing the way they walk, give or take the swing of a hand.
class SimulatedWalk extends PushLocationFeed {
  /// A walk along [route].
  SimulatedWalk(
    this.route, {
    this.speed = 1.4,
    this.accuracy = 8,
    this.tick = const Duration(milliseconds: 200),
  }) : assert(route.length >= 2, 'a walk goes somewhere'),
       super(providesHeading: true);

  /// The Strakonice walk, stop by stop.
  factory SimulatedWalk.strakonice() =>
      SimulatedWalk([for (final stop in strakoniceStops) stop.position]);

  /// Where it goes, back to the start at the end.
  final List<GeoPosition> route;

  /// Metres a second.
  final double speed;

  /// How far off each fix claims to be, in metres.
  final double accuracy;

  /// How often the heading is reported.
  final Duration tick;

  Timer? _timer;
  double _walked = 0;
  int _ticks = 0;

  @override
  Future<LocationAccess> onStart() async {
    _timer ??= Timer.periodic(tick, (_) => _step());
    _step();
    return LocationAccess.granted;
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await super.dispose();
  }

  void _step() {
    _walked += speed * tick.inMicroseconds / 1e6;
    final (at, bearing) = _along(_walked);
    // A fix a second, like a phone's GPS.
    if (_ticks % (1000 ~/ tick.inMilliseconds) == 0) {
      push(LocationFix(position: at, accuracy: accuracy, course: bearing));
    }
    pushHeading(bearing + 12 * math.sin(_ticks / 6));
    _ticks++;
  }

  /// Where the walk is after [metres], and which way it is going.
  (GeoPosition, double) _along(double metres) {
    final legs = [
      for (var i = 0; i < route.length; i++)
        (route[i], route[(i + 1) % route.length]),
    ];
    final lengths = [for (final (a, b) in legs) _metres(a, b)];
    final total = lengths.fold<double>(0, (sum, l) => sum + l);
    var left = metres % total;
    for (var i = 0; i < legs.length; i++) {
      final (a, b) = legs[i];
      if (left <= lengths[i] || i == legs.length - 1) {
        final t = lengths[i] == 0 ? 0.0 : left / lengths[i];
        return (
          GeoPosition(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
          _bearing(a, b),
        );
      }
      left -= lengths[i];
    }
    return (route.first, 0);
  }

  static (double, double) _offset(GeoPosition a, GeoPosition b) {
    final east =
        (b.longitude - a.longitude) *
        111320 *
        math.cos(a.latitude * math.pi / 180);
    final north = (b.latitude - a.latitude) * 110540;
    return (east, north);
  }

  static double _metres(GeoPosition a, GeoPosition b) {
    final (east, north) = _offset(a, b);
    return math.sqrt(east * east + north * north);
  }

  static double _bearing(GeoPosition a, GeoPosition b) {
    final (east, north) = _offset(a, b);
    return (math.atan2(east, north) * 180 / math.pi) % 360;
  }
}

/// A visitor walking from room to room of a building, for trying the
/// location button on floor plans: what a beacon or a QR code on each door
/// would report.
///
/// Reports positions on the plans with the floor they are on, taking the
/// stairs when the next stop is upstairs, and a heading along the way they
/// walk, turned by [planBearing] — which way the top of the plans faces.
class SimulatedRoomWalk extends PushLocationFeed {
  /// A walk through [stops], [speed] plan units a second.
  SimulatedRoomWalk(
    this.stops, {
    this.speed = 140,
    this.planBearing = 0,
    this.tick = const Duration(milliseconds: 200),
  }) : assert(stops.length >= 2, 'a walk goes somewhere'),
       super(providesHeading: true);

  /// The rooms, in the order walked.
  final List<RoomStop> stops;

  /// Plan units a second.
  final double speed;

  /// The compass bearing the top of the plans faces.
  final double planBearing;

  /// How often it reports.
  final Duration tick;

  Timer? _timer;
  int _leg = 0;
  double _along = 0;
  int _ticks = 0;
  double _heading = 0;

  @override
  Future<LocationAccess> onStart() async {
    _timer ??= Timer.periodic(tick, (_) => _step());
    _step();
    return LocationAccess.granted;
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await super.dispose();
  }

  void _step() {
    final from = stops[_leg % stops.length];
    final to = stops[(_leg + 1) % stops.length];
    final ImagePosition at;
    String floor;
    if (from.floor != to.floor) {
      // Up or down the stairs: arrive at the next room.
      at = to.position;
      floor = to.floor;
      _leg++;
      _along = 0;
    } else {
      final dx = to.x - from.x;
      final dy = to.y - from.y;
      final length = math.sqrt(dx * dx + dy * dy);
      _along += speed * tick.inMicroseconds / 1e6;
      final t = length == 0 ? 1.0 : math.min(1.0, _along / length);
      at = ImagePosition(from.x + dx * t, from.y + dy * t);
      floor = from.floor;
      if (length > 0) {
        _heading = math.atan2(dx, -dy) * 180 / math.pi + planBearing;
      }
      if (t >= 1) {
        _leg++;
        _along = 0;
      }
    }
    if (_ticks % 5 == 0) push(LocationFix(position: at, levelId: floor));
    pushHeading(_heading + 8 * math.sin(_ticks / 5));
    _ticks++;
  }
}
