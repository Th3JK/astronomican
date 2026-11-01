import 'dart:async';

import 'package:astronomican/astronomican.dart';
import 'package:astronomican/src/location/heading_smoother.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A feed that counts its starts and stops and answers with [answer].
class CountingFeed extends LocationFeed {
  CountingFeed({this.answer = LocationAccess.granted, this.heading = true});

  LocationAccess answer;
  final bool heading;
  int starts = 0;
  int stops = 0;

  @override
  bool get providesHeading => heading;

  void fix(double lat, double lng) =>
      addFix(LocationFix(position: GeoPosition(lat, lng)));

  void face(double degrees) => addHeading(degrees);

  @override
  Future<LocationAccess> onStart() async {
    starts++;
    return answer;
  }

  @override
  Future<void> onStop() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationFeed', () {
    test(
      'runs once for any number of users, and stops with the last',
      () async {
        final feed = CountingFeed();
        addTearDown(feed.dispose);

        expect(await feed.start(), LocationAccess.granted);
        expect(await feed.start(), LocationAccess.granted);
        expect(feed.starts, 1);
        expect(feed.isRunning, isTrue);

        await feed.stop();
        expect(feed.stops, 0);
        await feed.stop();
        expect(feed.stops, 1);
        expect(feed.isRunning, isFalse);

        await feed.start();
        expect(feed.starts, 2);
      },
    );

    test('a refused start does not count, and can be tried again', () async {
      final feed = CountingFeed(answer: LocationAccess.denied);
      addTearDown(feed.dispose);

      expect(await feed.start(), LocationAccess.denied);
      expect(feed.isRunning, isFalse);
      await feed.stop();
      expect(feed.stops, 0);

      feed.answer = LocationAccess.granted;
      expect(await feed.start(), LocationAccess.granted);
      expect(feed.starts, 2);
    });

    test('keeps the last fix and heading, and closes on dispose', () async {
      final feed = CountingFeed();
      var closed = false;
      feed.fixes.listen(null, onDone: () => closed = true);
      feed
        ..fix(49.26, 13.90)
        ..face(-90);
      expect(feed.lastFix!.position, const GeoPosition(49.26, 13.90));
      expect(feed.lastHeading, 270);

      await feed.start();
      await feed.dispose();
      expect(feed.stops, 1);
      expect(closed, isTrue);
    });

    test('a stream feed forwards what its streams carry', () async {
      final fixes = StreamController<LocationFix>();
      final headings = StreamController<double>();
      addTearDown(fixes.close);
      addTearDown(headings.close);
      final feed = StreamLocationFeed(
        fixes: fixes.stream,
        headings: headings.stream,
      );
      addTearDown(feed.dispose);
      expect(feed.providesHeading, isTrue);

      final seen = <LocationFix>[];
      feed.fixes.listen(seen.add);
      await feed.start();
      fixes.add(const LocationFix(position: ImagePosition(1, 2), levelId: 'g'));
      headings.add(12);
      await pumpEventQueue();
      expect(seen.single.levelId, 'g');
      expect(feed.lastHeading, 12);
    });
  });

  group('HeadingSmoother', () {
    test('goes the short way round north', () {
      expect(HeadingSmoother.difference(350, 10), 20);
      expect(HeadingSmoother.difference(10, 350), -20);
      expect(HeadingSmoother.normalize(-30), 330);

      final smoother = HeadingSmoother(factor: 0.5);
      expect(smoother.add(350), 350);
      // Halfway from 350 to 10 is 0, not 180.
      expect(smoother.add(10), closeTo(0, 1e-9));
    });
  });

  group('MyLocationController', () {
    MyLocationController controller(LocationFeed feed) {
      final c = MyLocationController(feed: feed, pauseWhenHidden: false);
      addTearDown(c.dispose);
      return c;
    }

    test('searches until the first fix, then is active', () async {
      final feed = CountingFeed();
      addTearDown(feed.dispose);
      final c = controller(feed);

      expect(c.status, MyLocationStatus.off);
      expect(await c.start(), MyLocationStatus.searching);
      feed.fix(49.26, 13.90);
      await pumpEventQueue();
      expect(c.status, MyLocationStatus.active);
      expect(c.fix!.position, const GeoPosition(49.26, 13.90));
    });

    test('takes the feed\'s last fix at once', () async {
      final feed = CountingFeed()..fix(1, 2);
      addTearDown(feed.dispose);
      final c = controller(feed);
      expect(await c.start(), MyLocationStatus.active);
    });

    test('reports why the position cannot be had', () async {
      for (final (access, status) in [
        (LocationAccess.denied, MyLocationStatus.denied),
        (LocationAccess.deniedForever, MyLocationStatus.deniedForever),
        (LocationAccess.serviceDisabled, MyLocationStatus.serviceDisabled),
        (LocationAccess.unsupported, MyLocationStatus.unsupported),
      ]) {
        final feed = CountingFeed(answer: access);
        addTearDown(feed.dispose);
        final c = controller(feed);
        expect(await c.start(), status);
        expect(status.isProblem, isTrue);
      }
    });

    test('cycles none, follow, heading, follow', () async {
      final feed = CountingFeed()..fix(1, 2);
      addTearDown(feed.dispose);
      final c = controller(feed);

      c.cycle();
      expect(c.mode, MyLocationMode.follow);
      await pumpEventQueue();
      expect(c.status, MyLocationStatus.active);

      final requests = c.centreRequests;
      c.cycle();
      expect(c.mode, MyLocationMode.heading);
      c.cycle();
      expect(c.mode, MyLocationMode.follow);
      expect(c.centreRequests, requests + 2);

      c.stopFollowing();
      expect(c.mode, MyLocationMode.none);
      c.cycle();
      expect(c.mode, MyLocationMode.follow);
    });

    test('skips heading when there is none, or the map cannot turn', () async {
      final feed = CountingFeed(heading: false)..fix(1, 2);
      addTearDown(feed.dispose);
      final c = controller(feed);
      await c.start();
      c
        ..setMode(MyLocationMode.follow)
        ..cycle();
      expect(c.mode, MyLocationMode.follow);

      final compass = CountingFeed()..fix(1, 2);
      addTearDown(compass.dispose);
      final d = controller(compass);
      await d.start();
      d.setMode(MyLocationMode.heading);
      expect(d.mode, MyLocationMode.heading);
      d.orientable = false;
      expect(d.mode, MyLocationMode.follow);
      d.cycle();
      expect(d.mode, MyLocationMode.follow);
    });

    test('a refused start drops the follow the button asked for', () async {
      final feed = CountingFeed(answer: LocationAccess.denied);
      addTearDown(feed.dispose);
      final c = controller(feed);
      c.cycle();
      await pumpEventQueue();
      expect(c.status, MyLocationStatus.denied);
      expect(c.mode, MyLocationMode.none);
    });

    test('two controllers share one feed', () async {
      final feed = CountingFeed();
      addTearDown(feed.dispose);
      final a = controller(feed);
      final b = controller(feed);
      await a.start();
      await b.start();
      expect(feed.starts, 1);
      await a.stop();
      expect(feed.isRunning, isTrue);
      await b.stop();
      expect(feed.stops, 1);
    });

    test('smooths the heading and reports it at a bounded rate', () {
      fakeAsync((async) {
        final feed = CountingFeed();
        final c = MyLocationController(
          feed: feed,
          pauseWhenHidden: false,
          headingInterval: const Duration(milliseconds: 100),
        );
        c.start();
        async.flushMicrotasks();

        final seen = <double?>[];
        c.heading.addListener(() => seen.add(c.heading.value));
        for (var i = 0; i < 20; i++) {
          feed.face(90);
          async.elapse(const Duration(milliseconds: 10));
        }
        // 200 ms of readings: the first at once, then one per 100 ms.
        expect(seen.length, lessThanOrEqualTo(3));
        async.elapse(const Duration(seconds: 1));
        expect(c.heading.value, closeTo(90, 1));

        // Jitter under the deadband is not reported.
        final count = seen.length;
        feed.face(90.2);
        async.elapse(const Duration(seconds: 1));
        expect(seen.length, count);

        c.dispose();
        feed.dispose();
        async.flushMicrotasks();
      });
    });

    testWidgets('lets go of the feed while the app is hidden', (tester) async {
      final feed = CountingFeed();
      addTearDown(feed.dispose);
      final c = MyLocationController(feed: feed);
      addTearDown(c.dispose);
      await tester.runAsync(c.start);
      expect(feed.isRunning, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.runAsync(pumpEventQueue);
      expect(feed.isRunning, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(pumpEventQueue);
      expect(feed.isRunning, isTrue);
      expect(feed.starts, 2);
    });
  });

  group('MyLocationButton', () {
    Future<void> pump(WidgetTester tester, Widget button) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: button)),
      ),
    );

    testWidgets('steps through the modes, and says which', (tester) async {
      final feed = CountingFeed()..fix(1, 2);
      addTearDown(feed.dispose);
      final c = MyLocationController(feed: feed, pauseWhenHidden: false);
      addTearDown(c.dispose);
      await pump(tester, MyLocationButton(controller: c));
      expect(find.byIcon(Icons.location_searching), findsOneWidget);

      await tester.tap(find.byType(MyLocationButton));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(c.mode, MyLocationMode.follow);
      expect(find.byIcon(Icons.my_location), findsOneWidget);

      await tester.tap(find.byType(MyLocationButton));
      await tester.pump();
      expect(find.byIcon(Icons.navigation), findsOneWidget);
    });

    testWidgets('hands a refusal to the app', (tester) async {
      final feed = CountingFeed(answer: LocationAccess.deniedForever);
      addTearDown(feed.dispose);
      final c = MyLocationController(feed: feed, pauseWhenHidden: false);
      addTearDown(c.dispose);
      await tester.runAsync(c.start);
      final problems = <MyLocationStatus>[];
      await pump(
        tester,
        MyLocationButton(controller: c, onAccessProblem: problems.add),
      );
      expect(find.byIcon(Icons.location_disabled), findsOneWidget);

      await tester.tap(find.byType(MyLocationButton));
      await tester.pump();
      expect(problems, [MyLocationStatus.deniedForever]);
      // Asking again cannot help; the feed was not tried a second time.
      expect(feed.starts, 1);
    });
  });
}
