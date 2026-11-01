import 'dart:io';

import 'package:astronomican/astronomican.dart';
import 'package:astronomican_example/demo_data.dart';
import 'package:astronomican_example/demos/uc4_image_map_page.dart';
import 'package:astronomican_example/demos/uc5_floor_plans_page.dart';
import 'package:astronomican_example/main.dart';
import 'package:astronomican_example/support/demo_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MapPackManager packs;

  setUp(() {
    packs = MapPackManager(root: Directory.systemTemp.createTempSync('demo_'));
  });

  Widget app(Widget home) => DemoScope(
    packs: packs,
    child: MaterialApp(home: home),
  );

  void phone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  // The stops on screen: those drawn on their own, and those in the count of
  // a cluster.
  int stopsShown(WidgetTester tester) {
    var shown = 0;
    for (final stop in [...rymarovMuseum.stops, ...hedvaWorks.stops]) {
      if (find.byKey(ValueKey('${stop.id}')).evaluate().isNotEmpty) shown++;
    }
    final clusters = find.bySemanticsLabel(RegExp(r'^\d+ markers$'));
    for (var i = 0; i < clusters.evaluate().length; i++) {
      final label = tester.getSemantics(clusters.at(i)).label;
      shown += int.parse(label.split(' ').first);
    }
    return shown;
  }

  testWidgets('lists every demo', (tester) async {
    phone(tester);
    await tester.pumpWidget(AstronomicanDemo(packs: packs));
    for (final demo in demos) {
      await tester.scrollUntilVisible(find.text(demo.title), 200);
      expect(find.text(demo.title), findsOneWidget);
    }
    // And the choice of a simulated walk or the device's GPS, above them.
    await tester.scrollUntilVisible(find.text('Simulated walk'), -200);
    expect(find.text('Simulated walk'), findsOneWidget);
  });

  testWidgets('the image map shows the ground floor\'s stops', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const ImageMapPage()));
    await tester.pump();
    final onGround = hedvaWorks.stops.where((s) => s.floor == '1').length;
    expect(find.byType(MarkerIconView), findsNWidgets(onGround));

    await tester.tap(find.byType(MarkerIconView).first);
    await tester.pump();
    expect(find.text(hedvaWorks.stops.first.name), findsOneWidget);
  });

  testWidgets('floor plans switch floor from the selector and the list', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(const FloorPlansPage()));
    await tester.pump();
    int pins() => stopsShown(tester);
    expect(pins(), rymarovMuseum.stops.where((s) => s.floor == '1').length);

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(LevelSelector), matching: find.text('2')),
    );
    await tester.pumpAndSettle();
    expect(pins(), rymarovMuseum.stops.where((s) => s.floor == '2').length);

    // A stop on the third floor, picked from the list, brings its floor up.
    final third = rymarovMuseum.stops.firstWhere((s) => s.floor == '3');
    final chip = find.widgetWithText(
      ChoiceChip,
      '${rymarovMuseum.stops.indexOf(third) + 1}. ${third.name}',
    );
    await tester.scrollUntilVisible(
      chip,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    // Wholly on screen, so the tap lands on it.
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(pins(), rymarovMuseum.stops.where((s) => s.floor == '3').length);
  });

  testWidgets('floor plans dissolve to the other building', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const FloorPlansPage()));
    await tester.pump();
    await tester.tap(find.text('Hedva'));
    await tester.pumpAndSettle();
    expect(
      stopsShown(tester),
      hedvaWorks.stops.where((s) => s.floor == '1').length,
    );
  });

  testWidgets('floor plans group crowded stops, and can show them all', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(const FloorPlansPage()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(LevelSelector), matching: find.text('2')),
    );
    await tester.pumpAndSettle();
    final onSecond = rymarovMuseum.stops.where((s) => s.floor == '2').length;
    final clusters = find.bySemanticsLabel(RegExp(r'^\d+ markers$'));
    expect(clusters, findsWidgets);
    expect(stopsShown(tester), onSecond);

    await tester.tap(find.byTooltip('Show every stop'));
    await tester.pumpAndSettle();
    expect(clusters, findsNothing);
    expect(find.byType(MarkerIconView).evaluate().length, onSecond);
  });

  testWidgets('a walk through the rooms is followed on the plans', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(const FloorPlansPage()));
    await tester.pump();
    await tester.tap(find.byType(MyLocationButton));
    await tester.runAsync(pumpEventQueue);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Following the walk has zoomed in on the visitor.
    final map = tester.widget<ImageMap<RoomStop>>(
      find.byType(ImageMap<RoomStop>),
    );
    expect(map.controller!.zoom, greaterThan(1.5));
    // Leave the page, which stops the walk and its timers.
    await tester.pumpWidget(const SizedBox());
  });
}
