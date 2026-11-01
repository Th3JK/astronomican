## 0.3.0

- **Clustering.** `GeoMap(clustering:)` merges crowded markers into a count,
  worked out in Dart for each whole zoom level up to `clusterMaxZoom`, and
  splits them as the map zooms in. A tap zooms to where a cluster splits, or
  goes to `onClusterTap`. Only markers on the floor showing are clustered.
- **Buildings.** `GeoMap(buildings:)` draws each `MapBuilding` as one marker.
  A tap enters it by default — `GeoMapController.enterBuilding` lays its
  floors over the streets and frames it — or does what `onBuildingTap` says,
  such as `showFloorPlans`. The marker gives way to the floors, and comes back
  on `leaveBuilding`, `clearLevel`, or zooming out past `indoorMinZoom`, where
  the floors' markers now hide with the floors. Markers on a building's floors
  are placed through them whether it was entered or not.
- **The visitor's position.** `GeoMap(myLocation:)` draws the dot, its
  accuracy circle and its heading as map layers, and follows it: centred,
  or turned to the heading. Camera moves are throttled, skip what cannot be
  seen, and wait while a finger is on the map; a one-finger drag stops
  following. The compass shows while a position is shown.
- Taps are routed by layer, so a marker may be called anything.

## 0.2.0

First release as its own package. Everything MapLibre moved here from
`astronomican` 0.1.0, so an app that only draws pictures no longer carries the
native map SDK. Nothing changed in behaviour.

- `GeoMap`, `GeoMapController`, `GeoMapSource`, `GeoCamera`,
  `GeoImageOverlay`, `RasterStyle`, `BlankStyle` and `PackStyleResolver`.
  `PackStyleResolver` now builds on `PackStyle` from `astronomican_pack_format`.
- `OfflineRegions` and its backend. The MapLibre implementation,
  `MapLibreOfflineRegionBackend`, has its own file, so the interface and
  `FakeOfflineRegionBackend` no longer import MapLibre.
- `astronomican_maplibre.dart` re-exports `package:astronomican/astronomican.dart`,
  so an app needs one import. `astronomican_maplibre_testing.dart` does the same
  for the fakes.
