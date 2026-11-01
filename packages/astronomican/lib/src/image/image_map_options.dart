import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// How an image map behaves. Every zoom here is relative to a fit: `1` is the
/// whole level just filling the screen, whatever its size in pixels.
@immutable
final class ImageMapOptions {
  /// The defaults suit a building plan on a phone.
  const ImageMapOptions({
    this.minZoom = 1,
    this.maxZoom = 4,
    this.overscroll = 0.04,
    this.doubleTapZoom = 2,
    this.levelTransition = const Duration(milliseconds: 320),
    this.transitionCurve = Curves.easeOutCubic,
    this.cameraDuration = const Duration(milliseconds: 350),
    this.rememberLevelView = false,
    this.backgroundColor,
    this.filterQuality = FilterQuality.medium,
    this.followZoom = 2,
  }) : assert(minZoom > 0, 'minZoom must be positive'),
       assert(maxZoom >= minZoom, 'maxZoom must not be below minZoom');

  /// How far out the map can be pulled. At the default of 1 zooming out stops
  /// at the fit itself: there is nothing past the edge of the picture to see.
  final double minZoom;

  /// How far in the map can be pushed.
  final double maxZoom;

  /// How far past the picture's edge it can be dragged before it is pulled
  /// back, as a fraction of its width. Enough that panning to a corner does not
  /// feel like hitting a wall.
  final double overscroll;

  /// How much a double tap zooms in by, about the tapped point. At [maxZoom] a
  /// double tap returns to the fit instead.
  ///
  /// 1 or less turns double tap off, which also makes single taps on the map
  /// report at once: while double tap is on, a tap is only a tap once the
  /// double-tap timeout has passed.
  final double doubleTapZoom;

  /// How long switching levels takes.
  final Duration levelTransition;

  /// The curve of the level transition.
  final Curve transitionCurve;

  /// How long a camera move from the controller takes by default.
  final Duration cameraDuration;

  /// Whether a level opens where it was left, rather than fitted again.
  final bool rememberLevelView;

  /// Painted behind the picture, where the screen is wider than the level.
  final Color? backgroundColor;

  /// How the picture is sampled when scaled. Plans are line drawings, which
  /// alias badly at [FilterQuality.low].
  final FilterQuality filterQuality;

  /// The zoom the map comes in to when it starts following the visitor from
  /// further out, so the dot has room to move on screen. Held within
  /// [minZoom] and [maxZoom].
  final double followZoom;
}
