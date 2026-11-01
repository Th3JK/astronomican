import 'dart:ui';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_maplibre/astronomican_maplibre_testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MapLevel floor(String id) => MapLevel(
    id: id,
    label: id,
    image: MapImage.memory(transparentPng),
    size: const Size(100, 100),
  );

  test(
    'entering a building shows its floors; going outside leaves it',
    () async {
      final controller = GeoMapController(indoorMinZoom: 16);
      addTearDown(controller.dispose);
      final museum = MapBuilding(
        id: 'museum',
        name: 'Museum',
        levels: [floor('g'), floor('1'), floor('2')],
        position: const GeoPosition(49.26, 13.90),
        initialLevelId: '1',
      );

      var notified = 0;
      controller.addListener(() => notified++);
      // No map on screen: the floors change, the camera is left for later.
      await controller.enterBuilding(museum);
      expect(controller.activeBuilding, same(museum));
      expect(controller.levels.map((l) => l.id), ['g', '1', '2']);
      expect(controller.activeLevelId, '1');
      expect(notified, greaterThan(0));

      controller.showLevel('2');
      expect(controller.activeBuilding, same(museum));

      controller.leaveBuilding();
      expect(controller.activeBuilding, isNull);
      expect(controller.activeLevelId, isNull);

      await controller.enterBuilding(museum, levelId: 'g');
      expect(controller.activeLevelId, 'g');
      controller.clearLevel();
      expect(controller.activeBuilding, isNull);
    },
  );
}
