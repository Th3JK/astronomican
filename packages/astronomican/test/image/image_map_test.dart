import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _dot = MarkerIcon.dot(diameter: 20);

void main() {
  late ImageMapController controller;

  setUp(() {
    controller = ImageMapController(
      levels: [sampleLevel('a'), sampleLevel('b')],
    );
  });

  tearDown(() => controller.dispose());

  Future<void> pumpMap(
    WidgetTester tester, {
    List<MapMarker<String>> markers = const [],
    ImageMapOptions options = const ImageMapOptions(doubleTapZoom: 1),
    void Function(MapMarker<String>)? onMarkerTap,
    void Function(ImagePosition)? onBackgroundTap,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ImageMap<String>(
          controller: controller,
          markers: markers,
          options: options,
          onMarkerTap: onMarkerTap,
          onBackgroundTap: onBackgroundTap,
        ),
      ),
    );
  }

  testWidgets('opens fitted on the very first frame', (tester) async {
    await pumpMap(tester);
    expect(controller.zoom, closeTo(1, 1e-9));
    final middle = controller.imageToScreen(const ImagePosition(1000, 500))!;
    expect(middle.dx, closeTo(200, 1e-6));
    expect(middle.dy, closeTo(400, 1e-6));
  });

  testWidgets('draws a marker on its point, at its own size', (tester) async {
    await pumpMap(
      tester,
      markers: const [
        MapMarker(id: 'm', position: ImagePosition(1500, 250), icon: _dot),
      ],
    );
    final expected = controller.imageToScreen(const ImagePosition(1500, 250))!;
    final rect = tester.getRect(find.byType(MarkerIconView));
    expect(rect.center.dx, closeTo(expected.dx, 0.01));
    expect(rect.center.dy, closeTo(expected.dy, 0.01));
    expect(rect.width, closeTo(20, 0.01));
  });

  testWidgets('keeps markers the same size on screen at any zoom', (
    tester,
  ) async {
    await pumpMap(
      tester,
      markers: const [
        MapMarker(id: 'm', position: ImagePosition(1000, 500), icon: _dot),
      ],
    );
    await controller.zoomBy(3, duration: Duration.zero);
    await tester.pump();
    expect(controller.zoom, closeTo(3, 1e-9));
    final rect = tester.getRect(find.byType(MarkerIconView));
    expect(rect.width, closeTo(20, 0.01));
    expect(rect.center.dx, closeTo(200, 0.01));
  });

  testWidgets('a pin stands on its point', (tester) async {
    const pin = MarkerIcon.pin(height: 40);
    await pumpMap(
      tester,
      markers: const [
        MapMarker(id: 'p', position: ImagePosition(1000, 500), icon: pin),
      ],
    );
    final rect = tester.getRect(find.byType(MarkerIconView));
    expect(rect.bottomCenter.dx, closeTo(200, 0.01));
    expect(rect.bottomCenter.dy, closeTo(400, 0.01));
  });

  testWidgets('reports marker taps and background taps', (tester) async {
    MapMarker<String>? tapped;
    ImagePosition? background;
    await pumpMap(
      tester,
      markers: const [
        MapMarker(
          id: 'm',
          position: ImagePosition(1000, 500),
          icon: _dot,
          data: 'stop',
        ),
      ],
      onMarkerTap: (m) => tapped = m,
      onBackgroundTap: (p) => background = p,
    );

    await tester.tap(find.byType(MarkerIconView));
    expect(tapped?.data, 'stop');
    expect(background, isNull);

    await tester.tapAt(const Offset(100, 400));
    expect(background!.x, closeTo(500, 0.01));
    expect(background!.y, closeTo(500, 0.01));
  });

  testWidgets('a marker that only marks lets the tap through', (tester) async {
    var tapped = false;
    ImagePosition? background;
    await pumpMap(
      tester,
      markers: const [
        MapMarker(
          id: 'here',
          position: ImagePosition(1000, 500),
          icon: _dot,
          tappable: false,
        ),
      ],
      onMarkerTap: (_) => tapped = true,
      onBackgroundTap: (p) => background = p,
    );
    await tester.tapAt(const Offset(200, 400));
    expect(tapped, isFalse);
    expect(background, isNotNull);
  });

  testWidgets('double tap zooms in about the tapped point', (tester) async {
    await pumpMap(tester, options: const ImageMapOptions());
    const at = Offset(300, 400);
    final before = controller.screenToImage(at)!;

    await tester.tapAt(at);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(at);
    await tester.pumpAndSettle();

    expect(controller.zoom, closeTo(2, 1e-6));
    final after = controller.screenToImage(at)!;
    expect(after.x, closeTo(before.x, 0.5));
  });

  testWidgets('stays inside the picture when dragged away', (tester) async {
    await pumpMap(tester);
    await controller.zoomBy(4, duration: Duration.zero);
    await tester.pump();
    await tester.fling(
      find.byType(InteractiveViewer),
      const Offset(3000, 0),
      4000,
    );
    await tester.pumpAndSettle();
    final visible = controller.visibleImageRect!;
    // At most the overscroll's worth of blank past the left edge.
    expect(visible.left, greaterThanOrEqualTo(-2000 * 0.04 - 1));
  });

  testWidgets('switching levels shows only that level\'s markers', (
    tester,
  ) async {
    await pumpMap(
      tester,
      markers: const [
        MapMarker(id: 'a1', position: ImagePosition(10, 10), levelId: 'a'),
        MapMarker(id: 'b1', position: ImagePosition(10, 10), levelId: 'b'),
        MapMarker(id: 'all', position: ImagePosition(20, 20)),
      ],
    );
    expect(find.byKey(const ValueKey('a1')), findsOneWidget);
    expect(find.byKey(const ValueKey('b1')), findsNothing);

    controller.showLevel('b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-slide both levels are on screen.
    expect(find.byKey(const ValueKey('a1')), findsOneWidget);
    expect(find.byKey(const ValueKey('b1')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('a1')), findsNothing);
    expect(find.byKey(const ValueKey('b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('all')), findsOneWidget);
    expect(controller.activeLevelId, 'b');
  });

  testWidgets('animateTo with a level switches first, then flies', (
    tester,
  ) async {
    await pumpMap(tester);
    final done = controller.animateTo(
      const ImagePosition(1500, 250),
      levelId: 'b',
      zoom: 2,
    );
    await tester.pumpAndSettle();
    await done;
    expect(controller.activeLevelId, 'b');
    expect(controller.zoom, closeTo(2, 1e-6));
    final centre = controller.screenToImage(const Offset(200, 400))!;
    expect(centre.x, closeTo(1500, 0.5));
    // At twice the fit the plan is still shorter than the screen, so there is
    // nothing to scroll through vertically and it stays centred.
    expect(centre.y, closeTo(500, 0.5));
  });

  testWidgets('places a GPS position through the level\'s georeference', (
    tester,
  ) async {
    final ref = ImageGeoreference.fromBounds(
      north: 49.262,
      south: 49.258,
      east: 13.906,
      west: 13.900,
      imageSize: const Size(2000, 1000),
    );
    controller.replaceLevels([
      MapLevel(
        id: 'geo',
        label: 'G',
        image: MapImage.memory(transparentPng),
        size: const Size(2000, 1000),
        georeference: ref,
      ),
    ]);
    final here = ref.toGeo(const ImagePosition(500, 250));
    await pumpMap(
      tester,
      markers: [MapMarker(id: 'here', position: here, icon: _dot)],
    );
    final expected = controller.imageToScreen(const ImagePosition(500, 250))!;
    final rect = tester.getRect(find.byType(MarkerIconView));
    expect(rect.center.dx, closeTo(expected.dx, 0.01));
    expect(rect.center.dy, closeTo(expected.dy, 0.01));
  });

  testWidgets('ImageMap.single needs no controller', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ImageMap<void>.single(
          level: sampleLevel('only'),
          markers: const [MapMarker(id: 'x', position: ImagePosition(1, 1))],
        ),
      ),
    );
    expect(find.byType(MarkerIconView), findsOneWidget);
  });
}
