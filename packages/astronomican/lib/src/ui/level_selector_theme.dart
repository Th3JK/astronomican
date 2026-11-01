import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Colours and measurements of a [LevelSelector]. Anything left null is taken
/// from the app's [ColorScheme].
@immutable
class LevelSelectorThemeData {
  /// A theme; every field optional.
  const LevelSelectorThemeData({
    this.backgroundColor,
    this.activeColor,
    this.activeLabelColor,
    this.labelColor,
    this.labelStyle,
    this.tileSize = 44,
    this.inset = 6,
    this.frameRadius = const BorderRadius.all(Radius.circular(18)),
    this.tileRadius = const BorderRadius.all(Radius.circular(12)),
    this.elevation = 4,
    this.shadowColor = const Color(0x66000000),
  });

  /// The frame around the tiles. Defaults to the scheme's primary.
  final Color? backgroundColor;

  /// The tile of the level showing. Defaults to the scheme's on-primary.
  final Color? activeColor;

  /// The label on [activeColor]. Defaults to the scheme's primary.
  final Color? activeLabelColor;

  /// Labels of the other levels, and the chevron. Defaults to on-primary.
  final Color? labelColor;

  /// The label text style, before its colour is applied.
  final TextStyle? labelStyle;

  /// Side of one level's tile.
  final double tileSize;

  /// Frame around the tiles.
  final double inset;

  /// Corners of the frame.
  final BorderRadius frameRadius;

  /// Corners of a tile.
  final BorderRadius tileRadius;

  /// Shadow depth.
  final double elevation;

  /// Shadow colour.
  final Color shadowColor;
}
