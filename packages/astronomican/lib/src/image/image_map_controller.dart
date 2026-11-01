import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../core/level_controller.dart';
import '../core/map_level.dart';
import '../core/map_position.dart';
import 'image_map_options.dart';
import 'viewport_math.dart';

/// Drives an `ImageMap`: which level it shows, and where its camera looks.
///
/// Created and disposed by the app, like a `ScrollController`, so the screen
/// that owns the map can move it — open on the level a stop is on, fly to the
/// stop, zoom out to the whole building.
///
/// Camera methods need the map to be on screen. Called before it has been laid
/// out, they do nothing and read as null.
class ImageMapController extends ChangeNotifier implements LevelController {
  /// A controller over [levels], opening on [initialLevelId] or the first.
  ImageMapController({required List<MapLevel> levels, String? initialLevelId})
    : _levels = _checked(levels),
      _activeId = _pick(levels, initialLevelId);

  List<MapLevel> _levels;
  String? _activeId;
  int _generation = 0;
  int _direction = 0;
  double _rotation = 0;
  final Map<String, Matrix4> _views = {};
  ImageViewportHandle? _handle;
  final List<(String, Completer<void>)> _waiting = [];

  @override
  List<MapLevel> get levels => _levels;

  @override
  String? get activeLevelId => _activeId;

  @override
  MapLevel? get activeLevel {
    for (final level in _levels) {
      if (level.id == _activeId) return level;
    }
    return null;
  }

  /// Bumped by [replaceLevels], so the map can tell another building from
  /// another floor of the same one.
  @internal
  int get generation => _generation;

  /// Which way the last level change went through the list: 1 towards its end
  /// (up a building, since levels are listed from the lowest), -1 back towards
  /// its start, 0 for a change of building.
  @internal
  int get direction => _direction;

  @override
  void showLevel(String id) {
    if (id == _activeId) return;
    final to = _indexOf(id);
    if (to < 0) return;
    final from = _indexOf(_activeId);
    _direction = from < 0 ? 0 : (to > from ? 1 : -1);
    _activeId = id;
    notifyListeners();
  }

  /// Swaps in a different set of levels — another building — opening on
  /// [initialLevelId] or the first.
  ///
  /// Unlike [showLevel] this is not a step through a building, so the map
  /// dissolves between the two rather than sliding.
  void replaceLevels(List<MapLevel> levels, {String? initialLevelId}) {
    _levels = _checked(levels);
    _activeId = _pick(levels, initialLevelId);
    _generation++;
    _direction = 0;
    _views.clear();
    notifyListeners();
  }

  /// How far the map is turned, in radians clockwise: 0 unless it is facing
  /// the visitor's heading.
  double get rotation => _rotation;

  /// Called by the viewport on screen as its camera turns, so the next level
  /// to slide in arrives turned the same way.
  @internal
  void noteRotation(double radians) => _rotation = radians;

  /// The zoom relative to a fit: 1 when the level just fills the screen.
  double? get zoom {
    final handle = _handle;
    if (handle == null || handle.fitScale <= 0) return null;
    return ViewportMath.scaleOf(handle.matrix) / handle.fitScale;
  }

  /// The part of the active level on screen, in its logical frame.
  Rect? get visibleImageRect {
    final handle = _handle;
    if (handle == null) return null;
    return ViewportMath.visibleRect(handle.matrix, handle.viewport);
  }

  /// Where [position] on the active level is drawn, relative to the map's own
  /// box. Null when the map is not laid out, or the position cannot be placed
  /// on this level.
  Offset? imageToScreen(MapPosition position) {
    final handle = _handle;
    final point = handle?.level.locate(position);
    if (handle == null || point == null) return null;
    return ViewportMath.toScreen(handle.matrix, point.toOffset());
  }

  /// The point of the active level drawn at [screen], relative to the map's
  /// own box.
  ImagePosition? screenToImage(Offset screen) {
    final handle = _handle;
    if (handle == null) return null;
    return ImagePosition.fromOffset(
      ViewportMath.toContent(handle.matrix, screen),
    );
  }

  /// Moves the camera to put [position] in the middle, at [zoom] or the
  /// current zoom.
  ///
  /// With [levelId], switches to that level first and waits for it to be on
  /// screen — which is what "show me this stop" needs when the stop is on
  /// another floor.
  Future<void> animateTo(
    MapPosition position, {
    String? levelId,
    double? zoom,
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (levelId != null && levelId != _activeId) {
      showLevel(levelId);
      await _levelOnScreen(levelId);
    }
    final handle = _handle;
    final point = handle?.level.locate(position);
    if (handle == null || point == null) return;

    final scale = zoom == null
        ? ViewportMath.scaleOf(handle.matrix)
        : handle.clampScale(zoom * handle.fitScale);
    final target = ViewportMath.centreOn(
      point.toOffset(),
      scale,
      handle.viewport.center(Offset.zero),
      rotation: ViewportMath.rotationOf(handle.matrix),
    );
    await handle.animateMatrix(target, duration: duration, curve: curve);
  }

  /// Frames [rect] of the active level, as large as fits.
  Future<void> fitRect(
    Rect rect, {
    EdgeInsets? padding,
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    final handle = _handle;
    if (handle == null) return;
    final target = ViewportMath.fitRect(
      rect,
      viewport: handle.viewport,
      minScale: handle.fitScale * handle.options.minZoom,
      maxScale: handle.fitScale * handle.options.maxZoom,
      padding: padding ?? handle.fitPadding,
      rotation: ViewportMath.rotationOf(handle.matrix),
    );
    await handle.animateMatrix(target, duration: duration, curve: curve);
  }

  /// Frames the active level's focus, as it opened.
  Future<void> fitLevel({
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) {
    final level = _handle?.level;
    if (level == null) return Future.value();
    return fitRect(level.focusOrFrame, duration: duration, curve: curve);
  }

  /// Zooms by [factor] about [focal], or about the middle of the screen.
  Future<void> zoomBy(
    double factor, {
    Offset? focal,
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    final handle = _handle;
    if (handle == null) return;
    final scale = handle.clampScale(
      ViewportMath.scaleOf(handle.matrix) * factor,
    );
    final target = ViewportMath.zoomAbout(
      handle.matrix,
      focal ?? handle.viewport.center(Offset.zero),
      scale,
    );
    await handle.animateMatrix(target, duration: duration, curve: curve);
  }

  /// Called by the viewport that has just become the active one.
  @internal
  void attach(ImageViewportHandle handle) {
    _handle = handle;
    _waiting.removeWhere((entry) {
      if (entry.$1 != handle.level.id) return false;
      if (!entry.$2.isCompleted) entry.$2.complete();
      return true;
    });
  }

  /// Whether [handle] is the viewport on screen, as opposed to one sliding
  /// out.
  @internal
  bool isShowing(ImageViewportHandle handle) => identical(_handle, handle);

  /// Called by a viewport going away. Ignored unless it is the active one: the
  /// level sliding out must not unhook the level sliding in.
  @internal
  void detach(ImageViewportHandle handle) {
    if (identical(_handle, handle)) _handle = null;
  }

  /// Where the level [id] was left, when views are remembered.
  @internal
  Matrix4? savedView(String id) => _views[id];

  /// Keeps where the level [id] was left.
  @internal
  void saveView(String id, Matrix4 matrix) => _views[id] = matrix;

  Future<void> _levelOnScreen(String id) {
    if (_handle?.level.id == id) return Future.value();
    final completer = Completer<void>();
    _waiting.add((id, completer));
    // Not forever: a map that is never built must not hang the caller.
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }

  int _indexOf(String? id) => _levels.indexWhere((level) => level.id == id);

  static List<MapLevel> _checked(List<MapLevel> levels) {
    final ids = <String>{};
    for (final level in levels) {
      if (!ids.add(level.id)) {
        throw ArgumentError.value(level.id, 'levels', 'duplicate level id');
      }
    }
    return List.unmodifiable(levels);
  }

  static String? _pick(List<MapLevel> levels, String? id) {
    if (levels.isEmpty) return null;
    if (id != null && levels.any((level) => level.id == id)) return id;
    return levels.first.id;
  }

  @override
  void dispose() {
    for (final (_, completer) in _waiting) {
      if (!completer.isCompleted) completer.complete();
    }
    _waiting.clear();
    _handle = null;
    super.dispose();
  }
}

/// What the controller needs from the viewport showing the active level.
@internal
abstract interface class ImageViewportHandle {
  /// The level on screen.
  MapLevel get level;

  /// The size of the map's box.
  Size get viewport;

  /// The current camera.
  Matrix4 get matrix;

  /// The scale at which [level] just fits [viewport].
  double get fitScale;

  /// The padding the map fits within.
  EdgeInsets get fitPadding;

  /// The map's options.
  ImageMapOptions get options;

  /// [scale] held within the zoom limits.
  double clampScale(double scale);

  /// Moves the camera to [target], kept in bounds.
  Future<void> animateMatrix(Matrix4 target, {Duration? duration, Curve curve});
}
