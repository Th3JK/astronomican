import 'dart:async';

import 'package:astronomican/astronomican.dart';
import 'package:astronomican_location/astronomican_location.dart';
import 'package:flutter_test/flutter_test.dart';

/// A device made of stream controllers and answers.
class FakePlatform implements DevicePlatform {
  bool service = true;
  DevicePermission permission = DevicePermission.granted;
  DevicePermission answer = DevicePermission.granted;
  int requests = 0;
  final StreamController<DevicePosition> gps = StreamController.broadcast();
  final StreamController<double> needle = StreamController.broadcast();

  @override
  Future<bool> isServiceEnabled() async => service;

  @override
  Future<DevicePermission> checkPermission() async => permission;

  @override
  Future<DevicePermission> requestPermission() async {
    requests++;
    return permission = answer;
  }

  @override
  Stream<DevicePosition> positions({
    required Duration interval,
    required double distanceFilter,
  }) => gps.stream;

  @override
  Stream<double> compass() => needle.stream;

  Future<void> close() async {
    await gps.close();
    await needle.close();
  }
}

void main() {
  late FakePlatform device;
  late DeviceLocationFeed feed;

  setUp(() {
    device = FakePlatform();
    feed = DeviceLocationFeed(platform: device);
  });

  tearDown(() async {
    await feed.dispose();
    await device.close();
  });

  test('says when location is switched off', () async {
    device.service = false;
    expect(await feed.start(), LocationAccess.serviceDisabled);
  });

  test('asks once when not yet granted, and reports the answer', () async {
    device.permission = DevicePermission.denied;
    device.answer = DevicePermission.denied;
    expect(await feed.start(), LocationAccess.denied);
    expect(device.requests, 1);

    device.answer = DevicePermission.granted;
    expect(await feed.start(), LocationAccess.granted);
    expect(device.requests, 2);
  });

  test('does not ask again after a refusal for good', () async {
    device.permission = DevicePermission.deniedForever;
    expect(await feed.start(), LocationAccess.deniedForever);
    expect(device.requests, 0);
  });

  test('reports fixes and compass headings', () async {
    final fixes = <LocationFix>[];
    final headings = <double>[];
    feed.fixes.listen(fixes.add);
    feed.headings.listen(headings.add);
    await feed.start();

    device.gps.add(
      const DevicePosition(latitude: 49.26, longitude: 13.9, accuracy: 6),
    );
    device.needle.add(271);
    await pumpEventQueue();
    expect(fixes.single.position, const GeoPosition(49.26, 13.9));
    expect(fixes.single.accuracy, 6);
    expect(headings, [271]);
  });

  test('without a compass, walks by the GPS course', () async {
    final headings = <double>[];
    feed.headings.listen(headings.add);
    await feed.start();
    device.needle.addError(StateError('no compass'));
    await pumpEventQueue();

    // Standing still: the course means nothing.
    device.gps.add(
      const DevicePosition(
        latitude: 49.26,
        longitude: 13.9,
        speed: 0.2,
        course: 80,
        courseAccuracy: 20,
      ),
    );
    // Walking: it does.
    device.gps.add(
      const DevicePosition(
        latitude: 49.2601,
        longitude: 13.9,
        speed: 1.4,
        course: 95,
        courseAccuracy: 15,
      ),
    );
    // Android's "no course".
    device.gps.add(
      const DevicePosition(
        latitude: 49.2602,
        longitude: 13.9,
        speed: 1.4,
        course: 0,
        courseAccuracy: 0,
      ),
    );
    await pumpEventQueue();
    expect(headings, [95]);
  });

  test('a working compass wins over the course', () async {
    final headings = <double>[];
    feed.headings.listen(headings.add);
    await feed.start();
    device.needle.add(10);
    device.gps.add(
      const DevicePosition(
        latitude: 49.26,
        longitude: 13.9,
        speed: 2,
        course: 180,
        courseAccuracy: 5,
      ),
    );
    await pumpEventQueue();
    expect(headings, [10]);
  });

  test('lets go of the GPS and compass when stopped', () async {
    var gpsListening = false;
    device.gps.onListen = () => gpsListening = true;
    device.gps.onCancel = () => gpsListening = false;
    await feed.start();
    expect(gpsListening, isTrue);
    await feed.stop();
    expect(gpsListening, isFalse);
    expect(feed.isRunning, isFalse);
  });
}
