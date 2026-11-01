## 0.3.0

**Clustering**

- `MarkerClustering` on `ImageMap` merges markers that crowd each other into a
  badge with the count, and splits them as the map zooms in. A tap zooms in to
  where a cluster splits, or goes to `onClusterTap`; `clusterBuilder` draws
  clusters as any widget.
- `MapMarker.clusterable` keeps a marker on its own: the open stop, the way
  into a building.
- `ClusterIndex` and `MarkerClusterSet` are the pure clustering both engines
  share, in the supercluster style: grouped once per zoom level, the same
  every time for the same markers.
- `MarkerIcon.badge`, the default cluster icon.

**The visitor's position**

- `LocationFeed` is where positions come from. `PushLocationFeed` is filled by
  the app — beacons, QR codes, a simulation — and `StreamLocationFeed` wraps
  streams it already has. A feed runs once however many maps read it. GPS and
  compass are in the new `astronomican_location`.
- `MyLocationController` draws the position on a map and follows it: `follow`
  keeps it in the middle, `heading` also turns the map to face the way the
  visitor does. Dragging stops following; a pinch does not. It lets go of the
  feed while the app is in the background.
- `MyLocationButton` cycles through them like the one in every map app, and
  hands a refused permission to the app.
- `ImageMap(myLocation:)` draws a GPS fix through the level's georeference, or
  a floor-plan fix on its floor, and switches floor to follow it. The accuracy
  circle scales with the plan; the dot does not.
- Picture maps can turn: the camera carries a rotation, markers stay upright,
  and a level sliding in arrives turned. `MapLevel.bearing` says which way a
  plan faces when it has no georeference. `ImageMapController.rotation` reads
  the turn.
- `ViewportMath` gains `rotationOf`, `rotateAbout`, `clampCentre` and a
  `rotation` on `centreOn` and `fitRect`; `visibleRect` covers a turned
  screen. Unturned, everything behaves as before.

**Buildings**

- `MapBuilding` is a building with floors, standing on a street map as one
  marker (`MarkerIcon.building`).
- `showFloorPlans` opens a building's floors full screen, with a level
  selector and the visitor's position read from the street map's feed;
  `BuildingFloorPlans` is the same as a widget.

## 0.2.0

**Split into a family of packages.** This package is now the MapLibre-free
core: an app that only draws pictures no longer carries the native map SDK.

- `GeoMap` and everything around it, and `OfflineRegions`, moved to
  `astronomican_maplibre`. That package re-exports this one, so a MapLibre app
  changes one import.
- The pack format (`MapPackManifest`, `PackFileEntry`, the pack exceptions)
  moved to the pure-Dart `astronomican_pack_format`. This package re-exports
  it, so nothing changes for apps.
- `dart run astronomican:pack_manifest` is replaced by
  `dart run astronomican_tiles manifest`, with the same flags. That package
  also builds whole packs from OpenStreetMap.
- `maplibre_gl` is no longer a dependency. A test in this package resolves a
  scratch app to prove it (`tool/check_dependency_isolation.dart core`).

## 0.1.0

First release: the map code of strakonice (MapLibre, offline mbtiles) and
rymarov (floor plans on an `InteractiveViewer`), made into one package with one
set of models.

**Models**

- `MapMarker` stands at a `GeoPosition` or an `ImagePosition`, on one
  `MapLevel` or on all of them, drawn with a `MarkerIcon` (pin, dot, asset,
  bytes or painted) that both engines can render.
- `MapLevel` is a picture with a logical frame independent of its pixels, and
  an optional focus to open on.
- `ImageGeoreference` pins a picture to the Earth, affine in Web Mercator, from
  three or more control points, four edges, or four corners that form a
  parallelogram. It carries floor-plan positions onto the streets and GPS
  positions onto floor plans.

**Image map**

- `ImageMap`, generalised from rymarov's `IllustratedMapView`: opens framed on
  the level's focus from the first frame, keeps the picture in view, zooms from
  a fit, double-taps to zoom about a point, and slides between floors or
  dissolves between buildings.
- Markers stay the same size on screen at any zoom. They are painted through a
  counter-scaled `Flow`, so a pinch costs a repaint rather than a rebuild, and a
  pinch that starts on a marker still zooms.
- `ImageMapController` switches levels, flies to a point (on another level
  first, if need be), fits a rectangle and converts between screen and picture
  coordinates.
- `LevelSelector`, generalised from rymarov's `FloorSelector`, drives either
  engine.

**Geo map**

- `GeoMap` over `maplibre_gl` 0.27. Its base comes from a style URL, style JSON,
  raster tiles, an installed or bundled pack, or a plain background.
- Markers go into one GeoJSON source drawn by two symbol layers, one tappable
  and one not. After every style load, markers, overlays and indoor floors are
  installed again from scratch, so an Android activity recreation or a change
  of source loses nothing.
- `GeoImageOverlay` pins pictures over the map. Indoor floors are
  `GeoMapController` levels, drawn only while active and hidden below
  `indoorMinZoom`.
- The opening camera is computed in Dart from the markers, the bounds or the
  pack's area, so there is no jump on the first frame.

**Offline**

- `MapPackManager` copies a bundled pack out once, and again only when its
  `pack.json` version goes up. The copy is crash-safe and repairs itself;
  split tilesets are assembled one piece at a time; and versions a running map
  was given are never deleted from under it.
- Downloads of newer packs from any static server resume within a file, verify
  SHA-256, and reuse unchanged files from the installed version. Bundled and
  downloaded packs share one version sequence.
- `PackStyleResolver` rewrites `pack://` URIs, and strakonice's placeholders, to
  the files on disk, and `validate()` reports what would draw a blank map.
- `OfflineRegions` wraps MapLibre's offline database: download with progress,
  pause, resume, delete, tile estimates and offline mode.
- `dart run astronomican:pack_manifest` writes `pack.json`, splits large files,
  and prints the pubspec asset lines.
