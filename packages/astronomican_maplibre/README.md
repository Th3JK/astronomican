# astronomican_maplibre

Real maps for [astronomican](../astronomican), drawn natively by MapLibre:

- **`GeoMap`** draws an online style, raster tiles, or an offline `.mbtiles`
  pack with its own style. Pictures can be pinned over it (`GeoImageOverlay`),
  and a building's floors are laid over the streets and switched with a
  `LevelSelector`.
- **`OfflineRegions`** keeps areas of an online style for use without a
  connection, in MapLibre's own offline database.

It re-exports all of `package:astronomican/astronomican.dart`, so the markers,
levels, georeferences, image map and pack installer come with the one import.
The same `MapMarker` list draws here and on an `ImageMap`.

## Getting started

```yaml
dependencies:
  astronomican_maplibre:
    path: ../astronomican/packages/astronomican_maplibre
```

```dart
import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_maplibre/astronomican_maplibre_testing.dart';
```

`GeoMap` needs MapLibre's native setup: Android `minSdk` 21 or higher, and iOS
13 or higher. Online maps also need the `INTERNET` permission in the main
Android manifest.

## Four of the six ways to draw a map

| | What | How |
|---|---|---|
| 1 | Normal map, online provider | `GeoMap(source: GeoMapSource.styleUrl(…))` or `.rasterTiles(…)` |
| 2 | Normal map, offline mbtiles + custom style | `GeoMap(source: GeoMapSource.bundledPack(packs, 'assets/packs/town/pack.json'))` |
| 3 | Normal map + image overlay | `GeoMap(overlays: [GeoImageOverlay(…)])` |
| 6 | Offline map with indoor floor plans | `GeoMap(buildings: [MapBuilding(…)])`: a tap lays the floors over the streets (`enterBuilding`) or opens them as plans (`showFloorPlans`); `LevelSelector` switches floors |

The other two (an image as the map, several floor plans) are `ImageMap`, in the
core.

## 1. The geo map

```dart
GeoMap<Stop>(
  source: const GeoMapSource.styleUrl('https://tiles.openfreemap.org/styles/liberty'),
  controller: controller,          // camera moves, indoor levels
  markers: markers,
  overlays: [GeoImageOverlay(id: 'plan', image: …, georeference: …, imageSize: …)],
  cameraBounds: town,              // keep the camera over the data
  attribution: MapAttribution.hidden, // then credit the data yourself
  onMarkerTap: (m) => open(m.data!),
);
```

- **Marker layer.** All markers go into one GeoJSON source drawn by symbol
  layers, so hundreds of them cost one update.
- **Style reloads.** MapLibre forgets everything added at runtime whenever its
  style reloads. That happens on a change of source, and on Android when the
  activity is recreated. The map therefore reinstalls markers, overlays and
  floors by itself after every style load.
- **Indoor floors.** They are the controller's levels. Set `indoorMinZoom` to
  hide them from across town, and call `clearLevel()` to go back outdoors.
- **Platforms.** It runs on Android and iOS. On the web it draws online sources
  and markers, but not pictures or packs. Elsewhere it shows
  `unsupportedBuilder`.

## 2. Offline packs on the map

Packs are installed by `MapPackManager`, in the core. `GeoMapSource.bundledPack`
installs a bundled pack on first use and draws it; `GeoMapSource.pack` draws an
installed one. `PackStyleResolver` points the pack's `pack://` URIs at the files
on disk.

To build a pack from OpenStreetMap, use
[`astronomican_tiles`](../astronomican_tiles).

Worth a test in every app that ships a pack:

```dart
// flutter test
final pack = await MapPackManager(root: temp, bundle: rootBundle)
    .ensureBundled('assets/packs/town/pack.json');
final resolver = PackStyleResolver(pack);
expect(await resolver.validate(await resolver.resolve()), isEmpty);
```

This catches the problems that show up on a device only as a blank map: a
missing file, a leftover placeholder, a font with no glyphs.


## 3. Offline areas of an online style

```dart
final regions = OfflineRegions();
final download = regions.download(OfflineAreaRequest(
  styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
  bounds: town, minZoom: 12, maxZoom: 16, name: 'Town',
));
await download.result;
await regions.setOffline(offline: true); // draw only what is stored
```

`OfflineRegions.estimateTileCount` warns before a large download, and
`setTileCountLimit` raises MapLibre's cap.

Mind the provider's terms: OpenStreetMap's own tile servers forbid bulk
downloading, while OpenFreeMap and paid providers allow it.


## 4. Clusters, buildings and the visitor

```dart
GeoMap<Stop>(
  source: …,
  controller: controller,
  markers: stops,
  clustering: const MarkerClustering(),        // crowded stops merge
  buildings: [museum],                         // one marker each
  onBuildingTap: (b) => showFloorPlans(context, building: b),
  myLocation: myLocation,                      // the dot, followed
);
```

- **Clusters** are worked out in Dart for each whole zoom level up to
  `clusterMaxZoom` (16), not by MapLibre: its clusters would count markers on
  hidden floors, and need glyphs for their counts that a blank style lacks.
- **Buildings** stand as one marker while outdoors. Without `onBuildingTap`, a
  tap calls `controller.enterBuilding`, which lays the floors over the streets
  and frames them at `indoorMinZoom` or closer. Zooming out past it, or
  `leaveBuilding()`, brings the marker back.
- **The visitor** is drawn as map layers — the accuracy circle under the
  markers, the dot and its cone over them — and followed by the camera: the
  button's `follow` keeps them in the middle, `heading` turns the map to face
  the way they do. The camera never moves while a finger is on the map.

## Notes

- **Attribution.** With `MapAttribution.hidden`, credit the data in your own UI.
  OpenStreetMap-derived tiles are under the ODbL; OpenMapTiles-schema tiles ask
  for "© OpenMapTiles © OpenStreetMap contributors".
- **Picture size.** Keep floor plans and overlays at most 4096 px per side for
  MapLibre's textures. The logical frame can be any size.
