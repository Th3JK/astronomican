# astronomican

Maps for Flutter tour apps. A stop is a marker that stands at a place on the
Earth or at a point on a floor plan. The same marker draws on a real map, on a
picture used as the map, or on a building's floors laid over the streets.
Offline map data comes in versioned packs, which are built from OpenStreetMap
by a command-line tool.

## Which package

| Package | For | Depends on |
|---|---|---|
| [`astronomican`](packages/astronomican) | Apps without a street map: pictures as the map, floor plans, markers, levels, offline packs | Flutter, **no MapLibre** |
| [`astronomican_maplibre`](packages/astronomican_maplibre) | Real maps: online styles, offline `.mbtiles` packs, overlays, indoor floors, offline regions. Re-exports the core | `astronomican`, `maplibre_gl` |
| [`astronomican_location`](packages/astronomican_location) | The visitor's position from the device: GPS (geolocator) and a true-north compass (compassx), for the location button on either map | `astronomican`, `geolocator`, `compassx` |
| [`astronomican_tiles`](packages/astronomican_tiles) | The CLI that builds packs: Planetiler tiles, any OpenMapTiles style made offline, preview in TileServer GL and Maputnik, all in Docker | pure Dart |
| [`astronomican_pack_format`](packages/astronomican_pack_format) | The pack format shared by apps and tools | pure Dart |

An app that only draws pictures depends on `astronomican` and never carries
MapLibre's native SDK. An app with a street map depends on
`astronomican_maplibre` and imports only that. An app that shows the visitor's
GPS position adds `astronomican_location`; one that places them by beacons or
QR codes needs nothing more than the core's `PushLocationFeed`.

```yaml
dependencies:
  astronomican:                  # rymarov-style: floor plans only
    path: ../astronomican/packages/astronomican
  # or
  astronomican_maplibre:         # strakonice-style: a real map
    path: ../astronomican/packages/astronomican_maplibre
dev_dependencies:
  astronomican_tiles:            # dart run astronomican_tiles build maps/town
    path: ../astronomican/packages/astronomican_tiles
```

## The six ways to draw a map

| | What | Package |
|---|---|---|
| 1 | Normal map, online provider | maplibre: `GeoMap(source: GeoMapSource.styleUrl(…))` |
| 2 | Normal map, offline mbtiles + custom style | maplibre: `GeoMap(source: GeoMapSource.bundledPack(…))`, pack built by `astronomican_tiles` |
| 3 | Normal map + image overlay | maplibre: `GeoMap(overlays: [GeoImageOverlay(…)])` |
| 4 | An image as the map, markers at x, y | core: `ImageMap.single(level: …)` |
| 5 | Several floor plans | core: `ImageMap` + `LevelSelector` |
| 6 | Offline map with indoor floor plans | maplibre: `GeoMap(buildings: […])` — floors over the streets, or `showFloorPlans` |

On every map: markers cluster (`clustering:`), and the visitor's position is
drawn and followed, north-up or turned to their heading (`myLocation:` and a
`MyLocationButton`).

The [example app](example) has one page for each, plus downloads. Its
[`maps/strakonice`](example/maps/strakonice) rebuilds the bundled Strakonice
pack from OpenStreetMap.

## Layout

```text
packages/
  astronomican_pack_format/   pure Dart
  astronomican/               Flutter core
  astronomican_maplibre/      Flutter + MapLibre
  astronomican_location/      Flutter + GPS and compass
  astronomican_tiles/         pure Dart CLI
example/                      the demo app
tool/check_dependency_isolation.dart
```

The packages are plain packages linked by path, not a pub workspace. Apps
outside this repository depend on them by path too, and pub refuses path
dependencies on workspace members from outside the workspace.

## Development

```sh
cd packages/astronomican_pack_format && dart test
cd packages/astronomican && flutter test          # includes the isolation check
cd packages/astronomican_maplibre && flutter test
cd packages/astronomican_location && flutter test
cd packages/astronomican_tiles && dart test
cd example && flutter test
dart run tool/check_dependency_isolation.dart     # from the repo root
```

The isolation script resolves a scratch app against each package, as a
consumer would. It fails if MapLibre reaches the core, or Flutter reaches the
pure-Dart packages.
