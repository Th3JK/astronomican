# astronomican example

Every way astronomican draws a map, one page each.

| Page | Use case | Runs on |
|---|---|---|
| 1 · Online map | OpenFreeMap style, OpenStreetMap raster tiles, MapTiler with a key; clustered stops | Android, iOS |
| 2 · Offline pack | The Strakonice `.mbtiles` pack, copied out of the bundle once; clustering on and off | Android, iOS |
| 3 · Image overlay | A picture pinned over the town, on streets or on a blank background | Android, iOS |
| 4 · Image as the map | The Hedva ground floor, stops placed by x, y | everywhere |
| 5 · Floor plans | The Rýmařov museum's three floors and the Hedva works, with a level selector and clustering | everywhere |
| 6 · Indoor on the map | The museum as one marker in Strakonice: its floors over the streets, or its plans full screen | Android, iOS |

Every map has the location button: follow, then face the heading. The switch
at the top of the list picks where the position comes from:

- **Simulated walk** (the default): walks the Strakonice stops, so it works at
  a desk and on an emulator.
- **Device GPS**: the phone's GPS and compass, through `astronomican_location`.

The picture maps (4 and 5) have their own walk from room to room, as beacons
on each door would report it.
| Downloads | Version 2 of the pack from a server on the phone; an offline area of OpenFreeMap | Android, iOS (packs everywhere) |

```sh
flutter run                                    # a phone
flutter run -d windows                         # the image-map pages
flutter run --dart-define=MAPTILER_KEY=…       # adds MapTiler to page 1
```

## Assets

- `assets/packs/strakonice/`: the strakonice app's map (tileset, parchment
  style, sprite and glyphs). The style is switched to `pack://` URIs, and
  `pack.json` is written by `dart run astronomican_tiles manifest`.
- `assets/remote/strakonice/`: what the demo server offers as version 2. It is a
  "winter" recolouring of the style, and every other file is unchanged. The
  download fetches the style and reuses the rest.
- `assets/floors/`, `assets/markers/`: the rymarov app's floor plans and shield
  artwork, and strakonice's pin.

The floor-plan positions and the Strakonice coordinates are copied from the two
apps' content. The museum's placement in Strakonice on page 6 is made up; it is
there to show floors over real tiles.

## Tests

`flutter test` covers these:

- **The real bundled pack.** It installs, its resolved style validates, and a
  second launch copies nothing.
- **The two image-map pages.** They are driven through their markers, the level
  selector and the stop list.

## Rebuilding the Strakonice pack from OpenStreetMap

[`maps/strakonice/map.yaml`](maps/strakonice/map.yaml) describes the bundled
pack for [`astronomican_tiles`](../packages/astronomican_tiles):

- the Geofabrik South Bohemia extract, clipped to the town;
- Planetiler's OpenMapTiles tiles;
- the Parchment style, with its own sprite beside the map.yaml.

```sh
dart run astronomican_tiles doctor
dart run astronomican_tiles preview maps/strakonice   # http://localhost:8080
dart run astronomican_tiles preview maps/strakonice --edit   # + Maputnik on :8888
```

It never publishes over `assets/packs/strakonice` until you set `output:` and
raise `version:` past the downloads demo's v2. Try another look with
`style: positron`, `dark-matter` or any of the six OpenMapTiles presets.
