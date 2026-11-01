import 'package:meta/meta.dart';

/// Steadies a compass that jitters by a degree or two with every reading.
///
/// A low-pass filter on an angle has to go the short way round: from 359° to
/// 1° is two degrees, not three hundred and fifty-eight, and averaging the
/// plain numbers would spin the map through south to get there.
@internal
final class HeadingSmoother {
  /// A smoother moving [factor] of the way to each new reading.
  HeadingSmoother({this.factor = 0.35})
    : assert(factor > 0 && factor <= 1, 'factor must be in (0, 1]');

  /// How far towards each reading the value moves: 1 follows the compass
  /// exactly, smaller values lag it and steady it.
  final double factor;

  double? _value;

  /// The smoothed heading, or null before the first reading.
  double? get value => _value;

  /// Takes a reading of [degrees] and returns the smoothed heading.
  double add(double degrees) {
    final reading = normalize(degrees);
    final current = _value;
    if (current == null) return _value = reading;
    return _value = normalize(current + factor * difference(current, reading));
  }

  /// Forgets the value, so the next reading is taken as it is.
  void reset() => _value = null;

  /// [degrees] within [0, 360).
  static double normalize(double degrees) {
    final wrapped = degrees % 360;
    return wrapped < 0 ? wrapped + 360 : wrapped;
  }

  /// The turn from [from] to [to] the short way round, in (-180, 180].
  static double difference(double from, double to) {
    final d = normalize(to - from);
    return d > 180 ? d - 360 : d;
  }
}
