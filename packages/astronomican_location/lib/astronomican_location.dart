/// The visitor's position for astronomican maps, from the device itself.
///
/// [DeviceLocationFeed] reads the GPS through geolocator and a compass that
/// points to true north through compassx, asking for permission on the way.
/// Give it to a `MyLocationController`, and that to any map:
///
/// ```dart
/// final feed = DeviceLocationFeed();
/// final myLocation = MyLocationController(feed: feed);
///
/// ImageMap(controller: floors, myLocation: myLocation);  // or GeoMap
/// MyLocationButton(controller: myLocation);
/// ```
///
/// A separate package so an app that never shows the visitor's position does
/// not carry the GPS and compass plugins, or have to explain a location
/// permission it never asks for. Apps with their own positioning — beacons,
/// QR codes on the walls — use `PushLocationFeed` from `astronomican`
/// instead, and need nothing from here.
library;

export 'src/device_location_feed.dart';
export 'src/device_platform.dart';
