import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _dot = MarkerIcon.dot(diameter: 16);

void main() {
  late ImageMapController controller;

  setUp(() {
    controller = ImageMapController(levels: [sampleLevel('a')]);
  });

  tearDown(() => controller.dispose());

  // A 2000 by 1000 plan fits a 400 wide screen at 0.2: these three, 100
  // units apart, sit 20 px apart at the fit — crowded — and 160 px apart at
  // the 8× the map allows.
  final crowd = [
    for (var i = 0; i < 3; i++)
      MapMarker<String>(
        id: 'c$i',
        position: ImagePosition(800.0 + 100 * i, 500),
        icon: _dot,
      ),
  ];

  Future<void> pumpMap(
    WidgetTester tester, {
    required List<MapMarker<String>> markers,
    void Function(MarkerCluster<String>)? onClusterTap,
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
          clustering: const MarkerClustering(radius: 40),
          onClusterTap: onClusterTap,
          options: const ImageMapOptions(doubleTapZoom: 1, maxZoom: 8),
        ),
      ),
    );
  }

  Finder cluster(int count) => find.bySemanticsLabel('$count markers');

  testWidgets('crowded markers merge, and split as the map zooms in', (
    tester,
  ) async {
    await pumpMap(tester, markers: crowd);
    expect(cluster(3), findsOneWidget);
    expect(find.byKey(const ValueKey('c0')), findsNothing);

    await controller.zoomBy(8, duration: Duration.zero);
    await tester.pump();
    expect(cluster(3), findsNothing);
    for (final m in crowd) {
      expect(find.byKey(ValueKey(m.id)), findsOneWidget);
    }
  });

  testWidgets('a tap on a cluster zooms in until it splits', (tester) async {
    await pumpMap(tester, markers: crowd);
    final before = controller.zoom!;
    await tester.tap(cluster(3));
    await tester.pumpAndSettle();
    expect(controller.zoom!, greaterThan(before));
    expect(cluster(3), findsNothing);
    // Centred on where the cluster was.
    final middle = controller.imageToScreen(const ImagePosition(900, 500))!;
    expect(middle.dx, closeTo(200, 1));
  });

  testWidgets('the app can take the tap instead', (tester) async {
    final tapped = <MarkerCluster<String>>[];
    await pumpMap(tester, markers: crowd, onClusterTap: tapped.add);
    await tester.tap(cluster(3));
    await tester.pumpAndSettle();
    expect(tapped.single.markers.map((m) => m.id), ['c0', 'c1', 'c2']);
    expect(controller.zoom, closeTo(1, 1e-9));
  });

  testWidgets('a marker that is not clusterable stands on its own', (
    tester,
  ) async {
    await pumpMap(
      tester,
      markers: [
        ...crowd,
        const MapMarker<String>(
          id: 'open',
          position: ImagePosition(850, 500),
          icon: _dot,
          clusterable: false,
        ),
      ],
    );
    expect(cluster(3), findsOneWidget);
    expect(find.byKey(const ValueKey('open')), findsOneWidget);
  });

  testWidgets('markers far apart are left alone', (tester) async {
    await pumpMap(
      tester,
      markers: const [
        MapMarker(id: 'l', position: ImagePosition(100, 100), icon: _dot),
        MapMarker(id: 'r', position: ImagePosition(1900, 900), icon: _dot),
      ],
    );
    expect(find.bySemanticsLabel(RegExp('markers')), findsNothing);
    expect(find.byKey(const ValueKey('l')), findsOneWidget);
  });
}
