import 'package:astronomican/astronomican.dart';
import 'package:flutter/material.dart';

/// Brand-ish colours for the demos.
abstract final class DemoColors {
  /// The strakonice red.
  static const Color red = Color(0xFFC62828);

  /// A navy for everything not selected.
  static const Color navy = Color(0xFF1F2A44);

  /// The gold the rymarov app uses on navy.
  static const Color gold = Color(0xFFE0B04B);
}

/// A numbered pin, red while [selected].
MarkerIcon numberedPin(int number, {bool selected = false}) => MarkerIcon.pin(
  color: selected ? DemoColors.red : DemoColors.navy,
  label: '$number',
  height: selected ? 46 : 40,
);

/// How a stop is doing, for the rymarov shields.
enum ShieldState {
  /// Not visited.
  plain,

  /// Done.
  done,

  /// Open in a sheet.
  selected,
}

/// The rymarov app's shield for [state].
MarkerIcon shield(ShieldState state) => MarkerIcon.asset(switch (state) {
  ShieldState.plain => 'assets/markers/marker.webp',
  ShieldState.done => 'assets/markers/marker_done.webp',
  ShieldState.selected => 'assets/markers/marker_selected.webp',
}, size: const Size.square(46));

/// The visitor's own position.
const MarkerIcon hereDot = MarkerIcon.dot(color: Color(0xFF1E88E5));

/// A small square marking a corner, for checking an overlay's alignment.
MarkerIcon cornerMark(String label) => MarkerIcon.painted(
  'corner',
  size: const Size.square(14),
  painter: (canvas, size) {
    final rect = Offset.zero & size;
    canvas
      ..drawRect(rect, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(rect.deflate(3), Paint()..color = const Color(0xFF00897B));
  },
);
