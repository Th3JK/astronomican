import 'package:flutter/foundation.dart';

import 'map_level.dart';

/// Something that shows one of several levels at a time.
///
/// Both engines implement it — `ImageMapController` switching whole pictures,
/// `GeoMapController` switching which floor is laid over the streets — so a
/// `LevelSelector` drives either without knowing which it has.
abstract interface class LevelController implements Listenable {
  /// Every level, from the lowest floor up.
  ///
  /// The order carries meaning: an image map slides a higher level in from
  /// above, and a `LevelSelector` stacks them like the buttons in a lift.
  List<MapLevel> get levels;

  /// The id of the level showing, or null when there are none.
  String? get activeLevelId;

  /// The level showing, or null when there are none.
  MapLevel? get activeLevel;

  /// Shows the level [id]. Ignores an id that is not among [levels].
  void showLevel(String id);
}
