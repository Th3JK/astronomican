# astronomican

Maps for Flutter tour apps that need no street map: a picture used as the map,
the floors of a building, markers, levels, and versioned offline packs. All in
plain Flutter, with no MapLibre and no native map SDK.

- **`ImageMap`** uses a picture as the map: an illustrated site map, or the
  floors of a building. Markers are placed by their x, y on the picture and stay
  the same size at any zoom. A `LevelSelector` switches floors.
- **`MapMarker`, `MapLevel`, `ImageGeoreference`** are the models the whole
  family shares. A marker placed on a floor plan also draws on a street map in
  `astronomican_maplibre`, and a GPS position lands on a georeferenced plan.
- **`MapPackManager`** installs **versioned packs** of map data. A pack bundled
  with the app is copied into its storage once, and copied again only when a
  pack with a higher version ships. Newer packs download resumably from any
  static file server.

For real maps drawn by MapLibre (online styles, offline `.mbtiles`, overlays,
indoor floors over the streets), depend on
[`astronomican_maplibre`](../astronomican_maplibre) instead. It re-exports
everything here.

## Getting started

```yaml
dependencies:
  astronomican:
    path: ../astronomican/packages/astronomican
```

```dart
import 'package:astronomican/astronomican.dart';
import 'package:astronomican/astronomican_testing.dart'; // fakes, for your tests
```

Nothing to set up natively: `ImageMap` runs everywhere Flutter does.

## 1. Markers, positions and levels

```dart
MapMarker<Stop>(
  id: '12',
  position: const GeoPosition(49.2577, 13.9078),  // on the Earth
  icon: const MarkerIcon.pin(label: '12'),
  data: stop,                                     // handed back on a tap
);

MapMarker<Stop>(
  id: '203',
  position: const ImagePosition(870, 1585),       // on a floor plan
  levelId: 'ground',                              // shows on that level only
  icon: MarkerIcon.asset('assets/marker.webp', size: const Size.square(46)),
);
```

- **Visibility.** A marker without a `levelId` shows on every level. A marker
  with one shows only while that level is active.
- **Size.** Markers stay the same size on screen at every zoom.
- **Icons.** `MarkerIcon` comes as `pin`, `dot`, `asset`, `bytes` or `painted`.
  Both engines can draw every kind: MapLibre registers it as a bitmap, and the
  image map draws it as a widget.
- **Custom widgets.** An image map can instead take any widget through
  `markerBuilder`.

A `MapLevel` is one picture: a floor or a site map. Its `size` is a **logical
frame**, independent of the image file's pixels. Positions are written against
the frame and the picture is stretched to fill it, so a plan can be re-exported
smaller without moving a marker. `focus` is the part worth opening on.

```dart
MapLevel(
  id: 'ground',
  label: '1',
  image: const MapImage.asset('assets/floors/ground.webp'),
  size: const Size(2664, 2048),
  focus: const Rect.fromLTWH(120, 150, 2390, 1480),
  georeference: reference, // optional: pins the plan to the Earth
)
```

## 2. Pinning a picture to the Earth

An `ImageGeoreference` maps points on a picture to places and back. It is
**affine in Web Mercator**: the picture may be moved, scaled, rotated and
sheared. MapLibre draws an image as two triangles, so anything richer would put
the markers in one place and the picture in another. The picture's corners are
always derived from the reference, so the picture and the markers agree by
construction.

```dart
// Three or more points: a corner of the building on the plan, and where it is.
ImageGeoreference.fromControlPoints([
  (const ImagePosition(120, 150), const GeoPosition(49.26170, 13.90362)),
  (const ImagePosition(2510, 150), const GeoPosition(49.26182, 13.90452)),
  (const ImagePosition(120, 1630), const GeoPosition(49.26118, 13.90371)),
]);

// A north-up picture between four edges.
ImageGeoreference.fromBounds(north: …, south: …, east: …, west: …, imageSize: size);
```

With a reference, a level draws on a `GeoMap` (in `astronomican_maplibre`), and its `ImagePosition` markers
are carried onto the streets. In the other direction, a GPS `GeoPosition` marker
lands on the floor plan in an `ImageMap`.

## 3. The image map

```dart
final controller = ImageMapController(levels: floors);

Stack(children: [
  ImageMap<Stop>(
    controller: controller,
    markers: markers,
    onMarkerTap: (m) => open(m.data!),
    onBackgroundTap: (p) => debugPrint('x ${p.x}, y ${p.y}'), // authoring aid
  ),
  Positioned(top: 12, right: 12, child: LevelSelector(controller: controller)),
]);

await controller.animateTo(stop.position, levelId: stop.floor, zoom: 2.5);
controller.replaceLevels(otherBuilding.floors); // another building: dissolves
```

- **Zoom.** Pinch, pan and double tap all work. Zoom is counted from a fit, so
  `1` is the whole level on screen. `ImageMapOptions` sets the limits and the
  overscroll.
- **Bounds.** The picture is held in view. On an axis where it is smaller than
  the screen, it is centred on its focus.
- **Levels.** Levels are listed from the lowest floor up. A higher floor slides
  in from above, and another building dissolves in. `LevelSelector` stacks them
  like the buttons in a lift.

## 4. Clustering

```dart
ImageMap<Stop>(
  controller: controller,
  markers: markers,
  clustering: const MarkerClustering(radius: 48),
  onClusterTap: null, // default: zoom in until it splits
);
```

- **What merges.** Markers closer than `radius` logical pixels on screen, among
  those showing together: the active level's and those on no level.
- **Zooming.** Clusters are worked out once per half-step of zoom, with a
  little give either side, so a pinch resting on a boundary does not flicker.
  At the deepest zoom every marker stands on its own, even markers on the same
  spot.
- **Opting out.** `MapMarker(clusterable: false)` keeps a marker apart — the
  open stop, say.
- **Drawing.** A badge with the count by default; `MarkerClustering(icon:)` or
  `clusterBuilder` for your own.

## 5. The visitor's position

A `LocationFeed` says where the visitor is; a `MyLocationController` draws it
on a map and follows it; a `MyLocationButton` cycles the modes.

```dart
final feed = PushLocationFeed(providesHeading: true); // or DeviceLocationFeed()
final myLocation = MyLocationController(feed: feed);

Stack(children: [
  ImageMap(controller: floors, myLocation: myLocation),
  Positioned(right: 16, bottom: 16,
      child: MyLocationButton(controller: myLocation)),
]);

// Indoors, the app says where the visitor is:
feed.push(LocationFix(position: ImagePosition(870, 1585), levelId: '1'));
feed.pushHeading(135);
```

- **Where it comes from.** GPS and the compass are in `astronomican_location`
  (`DeviceLocationFeed`), so an app without them carries neither plugin.
  Beacons, QR codes or a tap on "I am here" go through `PushLocationFeed`.
- **Where it lands.** A GPS fix is carried onto a picture through the level's
  georeference; a floor-plan fix stands on its `levelId`. While following, a
  fix on another floor switches to it.
- **Modes.** `follow` keeps the dot in the middle, zooming in to
  `ImageMapOptions.followZoom` first. `heading` also turns the plan so the
  visitor faces up. That needs to know which way north is on the plan: its
  georeference, or `MapLevel.bearing`. A one-finger drag stops following; a
  pinch keeps it.
- **Sharing.** Several controllers can read one feed — a street map and a
  floor-plan dialog over it — and the GPS still runs once.

## 6. Buildings

A `MapBuilding` groups a building's floors. On a street map it stands as one
marker (see `astronomican_maplibre`); anywhere, its floors open as floor plans
of their own:

```dart
final museum = MapBuilding(id: 'museum', name: 'Museum', levels: floors);
await showFloorPlans(context, building: museum, markers: stops,
    myLocation: myLocation);
```

## 7. Offline packs

A pack is a folder: a tileset, the style that draws it, its sprite and glyphs,
and a `pack.json` listing every file with its size and checksum. The style names
its files relative to the pack:

```json
"sources": { "openmaptiles": { "type": "vector", "url": "pack://town.mbtiles" } },
"sprite": "pack://sprite",
"glyphs": "pack://fonts/{fontstack}/{range}.pbf"
```

Styles written for strakonice, with `___MBTILES_URI___`, `___SPRITE_URI___` and
`___FONTS_URI___`, work unchanged.

To build a whole pack from OpenStreetMap — tiles, any OpenMapTiles style, sprite
and glyphs — use `astronomican_tiles build` (see its README). For a folder you
assembled yourself, generate just the manifest. It also prints the pubspec lines
the folder needs, since Flutter's asset folders are not recursive:

```sh
dart run astronomican:pack_manifest assets/packs/town --id town --version 1 \
    --style style.json --attribution "© OpenStreetMap contributors" \
    --bounds 13.87,49.24,13.93,49.27 --max-zoom 14
```

Install it:

```dart
final packs = await MapPackManager.open(transport: IoPackTransport());
final pack = await packs.ensureBundled('assets/packs/town/pack.json');
```

**The version is the "this is new" flag.** `ensureBundled` works like this:

- On first launch it copies the pack out.
- On every later launch it reads `pack.json`, sees the installed version is as
  new, and returns. That costs one small asset read and a few file checks.
- It copies again only when an app update ships a higher version.

Bump `--version` whenever anything in the pack changes. Other guarantees:

- **Crash-safe.** A copy goes into a staging folder and is renamed into place
  only once complete. A copy interrupted halfway is redone on the next launch.
- **Self-repairing.** An install with a missing or truncated file is put back.
- **Large tilesets.** `--split <MB>` ships a large tileset in pieces, so the copy
  holds one piece in memory at a time.

### Downloading a newer pack

Serve the pack's folder from any static file server, then:

```dart
final newer = await packs.checkForUpdate(url);       // null when up to date
final download = packs.download(url);
download.progress.listen((p) => bar.value = p.fraction);
final pack = await download.result;                  // or download.cancel()
```

- **Reuse.** Files whose checksum is unchanged are copied from the installed
  version instead of fetched.
- **Resume.** An interrupted or cancelled download resumes where it stopped,
  including partway through a file.
- **One version sequence.** Bundled and downloaded packs share one sequence, so
  a downloaded v5 stays active while the app still bundles v4.
- **Switching over.** Maps pick up the new version through `packs.changes`, or
  on their next resolve with `GeoMapSource.bundledPack`.
- **Cleanup.** The old version is removed on a later launch, never while a map
  might be reading it.

## 8. Testing

`package:astronomican/astronomican_testing.dart` has:

- `sampleLevel` and `transparentPng`: levels that draw without assets.
- `MemoryAssetBundle`: a bundle that counts its loads, to prove a relaunch
  copies nothing.
- `FakePackTransport`: a pack server in memory, with ranges, dropped
  connections and stalls.

## Notes

- **iOS storage.** Packs live in Application Support, which iOS backs up. Large
  re-downloadable packs may want excluding from backup.
