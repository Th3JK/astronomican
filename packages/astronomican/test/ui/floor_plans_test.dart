import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reference = ImageGeoreference.fromBounds(
    north: 49.2620,
    south: 49.2610,
    west: 13.9030,
    east: 13.9050,
    imageSize: const Size(2000, 1000),
  );

  MapLevel floor(String id, {bool pinned = true}) => MapLevel(
    id: id,
    label: id,
    image: MapImage.memory(transparentPng),
    size: const Size(2000, 1000),
    georeference: pinned ? reference : null,
  );

  group('MapBuilding', () {
    test('stands in the middle of its floors, unless told otherwise', () {
      final museum = MapBuilding(
        id: 'museum',
        name: 'Museum',
        levels: [floor('1'), floor('2')],
        initialLevelId: '2',
      );
      expect(museum.position!.latitude, closeTo(49.2615, 1e-6));
      expect(museum.position!.longitude, closeTo(13.9040, 1e-6));
      expect(museum.footprint!.north, closeTo(49.2620, 1e-9));
      expect(museum.initialLevel.id, '2');
      expect(museum.icon, const MarkerIcon.building());

      final placed = MapBuilding(
        id: 'hall',
        name: 'Hall',
        levels: [floor('g', pinned: false)],
        position: const GeoPosition(50, 14),
      );
      expect(placed.footprint, isNull);
      expect(placed.position, const GeoPosition(50, 14));
    });
  });

  group('showFloorPlans', () {
    testWidgets('opens the floors with a selector and their markers', (
      tester,
    ) async {
      final museum = MapBuilding(
        id: 'museum',
        name: 'Museum',
        levels: [floor('1'), floor('2')],
      );
      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFloorPlans<String>(
                context,
                building: museum,
                markers: const [
                  MapMarker(
                    id: 'she-wolf',
                    position: ImagePosition(1000, 500),
                    levelId: '1',
                    data: 'she-wolf',
                  ),
                ],
                onMarkerTap: (m) => tapped.add(m.data!),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Museum'), findsOneWidget);
      expect(find.byType(LevelSelector), findsOneWidget);
      expect(find.byType(MyLocationButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('she-wolf')));
      expect(tapped, ['she-wolf']);

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Museum'), findsNothing);
    });

    testWidgets('reads the street map\'s feed without starting it twice', (
      tester,
    ) async {
      final feed = PushLocationFeed();
      addTearDown(feed.dispose);
      final outside = MyLocationController(feed: feed, pauseWhenHidden: false);
      addTearDown(outside.dispose);
      await tester.runAsync(outside.start);
      feed.push(const LocationFix(position: GeoPosition(49.2615, 13.904)));
      await tester.pump();

      final museum = MapBuilding(
        id: 'museum',
        name: 'Museum',
        levels: [floor('1')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BuildingFloorPlans<String>(
            building: museum,
            myLocation: outside,
          ),
        ),
      );
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(find.byType(MyLocationButton), findsOneWidget);
      expect(feed.isRunning, isTrue);

      // Following on the plans leaves the street map alone.
      await tester.tap(find.byType(MyLocationButton));
      await tester.pump();
      expect(outside.mode, MyLocationMode.none);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(pumpEventQueue);
      // Still held by the street map.
      expect(feed.isRunning, isTrue);
    });
  });
}
