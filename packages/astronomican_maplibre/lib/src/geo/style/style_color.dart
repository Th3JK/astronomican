import 'dart:ui' show Color;

import 'package:meta/meta.dart';

/// [color] as a CSS colour string, which is how MapLibre styles take colours.
@internal
String cssColor(Color color) {
  final argb = color.toARGB32();
  final a = (argb >> 24) & 0xFF;
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  if (a == 0xFF) return '#$rgb';
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 'rgba($r,$g,$b,${(a / 255).toStringAsFixed(3)})';
}
