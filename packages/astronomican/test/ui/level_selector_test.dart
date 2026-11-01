import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, LevelController controller) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: LevelSelector(controller: controller),
            ),
          ),
        ),
      );

  testWidgets('lists the levels highest first and switches on a tap', (
    tester,
  ) async {
    final controller = ImageMapController(
      levels: [
        sampleLevel('g', label: 'G'),
        sampleLevel('1', label: '1'),
        sampleLevel('2', label: '2'),
      ],
    );
    addTearDown(controller.dispose);
    await pump(tester, controller);

    // Closed: only the level showing.
    expect(find.text('G'), findsOneWidget);
    expect(find.text('2'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.text('2')).dy;
    final bottom = tester.getTopLeft(find.text('G')).dy;
    expect(top, lessThan(bottom));

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(controller.activeLevelId, '1');
    expect(find.text('2'), findsNothing);
  });

  testWidgets('steps aside when there is nothing to choose', (tester) async {
    final controller = ImageMapController(levels: [sampleLevel('only')]);
    addTearDown(controller.dispose);
    await pump(tester, controller);
    final ignore = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(LevelSelector),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignore.ignoring, isTrue);
  });

  testWidgets('close() shuts an open selector', (tester) async {
    final key = GlobalKey<LevelSelectorState>();
    final controller = ImageMapController(
      levels: [sampleLevel('a'), sampleLevel('b')],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LevelSelector(key: key, controller: controller),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    expect(key.currentState!.isOpen, isTrue);
    key.currentState!.close();
    await tester.pumpAndSettle();
    expect(key.currentState!.isOpen, isFalse);
  });
}
