import 'dart:math' as math;

import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ImageMapController controller;
  late PushLocationFeed feed;
  late MyLocationController me;

  // North-up plans: the top of the picture faces north.
  MapLevel floor(String id) => MapLevel(
    id: id,
    label: id,
    image: MapImage.memory(transparentPng),
    size: const Size(2000, 1000),
    bearing: 0,
  );

  setUp(() {
    controller = ImageMapController(levels: [floor('g'), floor('f')]);
    feed = PushLocationFeed(providesHeading: true);
    me = MyLocationController(feed: feed, pauseWhenHidden: false);
  });

  tearDown(() {
    me.dispose();
    controller.dispose();
    feed.dispose();
  });

  Future<void> pumpMap(WidgetTester tester, {ImageMapController? map}) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ImageMap<String>(
          controller: map ?? controller,
          myLocation: me,
          options: const ImageMapOptions(doubleTapZoom: 1),
        ),
      ),
    );
    await tester.runAsync(me.start);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void expectCentred(Offset? at) {
    expect(at, isNotNull);
    expect(at!.dx, closeTo(200, 1));
    expect(at.dy, closeTo(400, 1));
  }

  testWidgets('follows the visitor, zooming in to follow', (tester) async {
    await pumpMap(tester);
    feed.push(
      const LocationFix(position: ImagePosition(1700, 200), levelId: 'g'),
    );
    await tester.pump();
    me.setMode(MyLocationMode.follow);
    await settle(tester);

    // By the edge of the plan, and in the middle all the same.
    expectCentred(controller.imageToScreen(const ImagePosition(1700, 200)));
    expect(controller.zoom, closeTo(2, 0.01));

    feed.push(
      const LocationFix(position: ImagePosition(900, 600), levelId: 'g'),
    );
    await settle(tester);
    expectCentred(controller.imageToScreen(const ImagePosition(900, 600)));
  });

  testWidgets('faces the heading, keeping markers upright', (tester) async {
    await pumpMap(tester);
    feed
      ..push(const LocationFix(position: ImagePosition(1000, 500)))
      ..pushHeading(90);
    await tester.pump();
    me.setMode(MyLocationMode.heading);
    await settle(tester);

    // Facing east on a north-up plan: the map turns a quarter anticlockwise,
    // so east is up.
    expect(controller.rotation, closeTo(-math.pi / 2, 0.01));
    final here = controller.imageToScreen(const ImagePosition(1000, 500))!;
    final east = controller.imageToScreen(const ImagePosition(1100, 500))!;
    expect(east.dy, lessThan(here.dy - 10));
    expect((east.dx - here.dx).abs(), lessThan(1));
  });

  testWidgets('a drag stops following, and turns the plan upright again', (
    tester,
  ) async {
    await pumpMap(tester);
    feed
      ..push(const LocationFix(position: ImagePosition(1000, 500)))
      ..pushHeading(45);
    await tester.pump();
    me.setMode(MyLocationMode.heading);
    await settle(tester);
    expect(controller.rotation, isNot(closeTo(0, 0.01)));

    await tester.drag(find.byType(ImageMap<String>), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(me.mode, MyLocationMode.none);
    expect(controller.rotation, closeTo(0, 1e-6));
  });

  testWidgets('following a fix upstairs goes upstairs', (tester) async {
    await pumpMap(tester);
    feed.push(
      const LocationFix(position: ImagePosition(400, 400), levelId: 'g'),
    );
    await tester.pump();
    me.setMode(MyLocationMode.follow);
    await settle(tester);
    expect(controller.activeLevelId, 'g');

    feed.push(
      const LocationFix(position: ImagePosition(1200, 300), levelId: 'f'),
    );
    await tester.pump();
    expect(controller.activeLevelId, 'f');
    await settle(tester);
    expectCentred(controller.imageToScreen(const ImagePosition(1200, 300)));
  });

  testWidgets('a GPS fix lands through the georeference', (tester) async {
    final reference = ImageGeoreference.fromBounds(
      north: 49.262,
      south: 49.260,
      west: 13.900,
      east: 13.906,
      imageSize: const Size(2000, 1000),
    );
    final map = ImageMapController(
      levels: [
        MapLevel(
          id: 'site',
          label: 'site',
          image: MapImage.memory(transparentPng),
          size: const Size(2000, 1000),
          georeference: reference,
        ),
      ],
    );
    addTearDown(map.dispose);
    await pumpMap(tester, map: map);
    const gps = GeoPosition(49.261, 13.9045);
    feed.push(const LocationFix(position: gps, accuracy: 8));
    await tester.pump();
    me.setMode(MyLocationMode.follow);
    await settle(tester);
    expectCentred(map.imageToScreen(gps));
    // A georeferenced picture knows which way north is.
    expect(me.orientable, isTrue);
  });

  testWidgets('a plan with no bearing cannot face the heading', (tester) async {
    final plain = ImageMapController(levels: [sampleLevel('x')]);
    addTearDown(plain.dispose);
    await pumpMap(tester, map: plain);
    expect(me.orientable, isFalse);
    feed.push(const LocationFix(position: ImagePosition(10, 10)));
    await tester.pump();
    me
      ..setMode(MyLocationMode.follow)
      ..cycle();
    expect(me.mode, MyLocationMode.follow);
  });
}
