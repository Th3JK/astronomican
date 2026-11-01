# astronomican_tiles

Builds astronomican map packs from OpenStreetMap, and previews them, all
through Docker Compose:

- **Tiles:** [Planetiler](https://github.com/onthegomap/planetiler) generates
  OpenMapTiles-schema vector tiles (`.mbtiles`) for a Geofabrik area, clipped
  to your bounds.
- **Style:** any OpenMapTiles style is made fully offline. That covers all six
  on [openmaptiles.org](https://openmaptiles.org/#map-styles), and your own.
  The tool fetches the sprite, composites the fonts per font stack, and ships
  only the glyph ranges your labels need.
- **Pack:** everything is assembled into a pack folder with `pack.json`. It is
  validated, and published to your app's assets under a version guard.
- **Preview:** [TileServer GL](https://github.com/maptiler/tileserver-gl)
  serves exactly the files that ship, and [Maputnik](https://maplibre.org/maputnik/)
  edits the style against your tiles.

It runs anywhere Docker does (Windows, macOS, Linux; x86-64 and ARM). The
official openmaptiles `make` pipeline does not: it needs bash and make, and is
AMD64-only.

## Requirements

- **Docker** Desktop, or Docker Engine with the Compose plugin 2.17 or newer.
  `astronomican_tiles doctor` checks it.
- **Disk:** about 3 GB. The first build downloads about 1.5 GB of shared
  Planetiler inputs (water polygons, Natural Earth, lake centrelines) plus
  your area's extract. Every later map reuses them.
- **Memory:** Planetiler's heap (`planetiler.memory`, 2 GB by default) must fit
  in Docker's memory.
- **Dart 3.9 or newer.** No Flutter is needed.

## Quick start

```sh
# In an app, as a dev dependency:
#   dev_dependencies:
#     astronomican_tiles: { path: ../astronomican/packages/astronomican_tiles }
dart run astronomican_tiles init maps/town --area monaco --style positron --output assets/packs/town
dart run astronomican_tiles preview maps/town   # build into maps/town/.work and open http://localhost:8080
dart run astronomican_tiles build maps/town     # build and publish to assets/packs/town
```

Or install it once:

```sh
dart pub global activate --source path <repo>/packages/astronomican_tiles
astronomican_tiles doctor
```

`build` prints the pubspec asset lines the pack needs. Flutter's asset folders
are not recursive, so every font stack folder is listed. The app then installs
the pack with `MapPackManager.ensureBundled('assets/packs/town/pack.json')`.

## map.yaml

```yaml
id: strakonice                 # the pack's id
name: Strakonice
version: 1                     # installed apps recopy a pack only when this goes up
attribution: © OpenMapTiles © OpenStreetMap contributors

area: jihocesky                # Geofabrik id; or  osm: region.osm.pbf  or  tiles: made.mbtiles
bounds: [13.8748, 49.2435, 13.9309, 49.2749]   # west, south, east, north
minZoom: 0
maxZoom: 14                    # at most 15

style: osm-bright              # a preset, a path or a URL
# tilesSource: openmaptiles    # which style source the pack's tiles replace
# otherSources: drop           # or keep: other online sources stay online

glyphs:
  ranges: [0-255, 256-511]     # always shipped (0-255 is forced in)
  detect: true                 # add the ranges the tiles' labels need
  sources:                     # tried before the OpenMapTiles fonts
    - https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf

planetiler:
  memory: 2g
  languages: [cs, en]          # name:xx tags kept
  # excludeLayers: [housenumber]
  # args: [--threads=4]

output: ../../assets/packs/strakonice   # where build/pack publish
# split: 8                     # ship files over 8 MB in pieces
# assetPrefix: assets/packs/strakonice
# preview: { port: 8080, editorPort: 8888 }
# images: { planetiler: …, tileserver: … }   # override the pinned images
```

Unknown keys are errors, with a "did you mean" suggestion and the line and
column.

## Styles

| Preset | Fonts | Source |
|---|---|---|
| `osm-openmaptiles` | Open Sans + Noto Sans | built from openmaptiles v3.16: the style merged in Dart, the sprite made with spreet |
| `maptiler-basic` | Noto Sans | openmaptiles.github.io/maptiler-basic-gl-style |
| `osm-bright` | Noto Sans | openmaptiles.github.io/osm-bright-gl-style |
| `positron` | Metropolis + Noto Sans | openmaptiles.github.io/positron-gl-style |
| `dark-matter` | Metropolis + Noto Sans | openmaptiles.github.io/dark-matter-gl-style |
| `fiord-color` | Metropolis + Noto Sans | openmaptiles.github.io/fiord-color-gl-style |

Any other style for OpenMapTiles-schema tiles works too, as a file or a URL.
The conversion to the pack form works like this:

- **Tiles.** The tiles source becomes `pack://<id>.mbtiles`.
- **Sprite.** All four sprite files are fetched or copied, `@2x` included,
  and the sprite becomes `pack://sprite`.
- **Glyphs.** The glyphs become `pack://fonts/{fontstack}/{range}.pbf`.
- **Keys.** MapTiler URLs that need a key are never used, and a key or an
  unfilled `___PLACEHOLDER___` left anywhere is an error.
- **Other online sources** are dropped with their layers (`otherSources: drop`).
- **Wrong schema.** A style drawing layers the tiles don't have gets a warning
  instead of a blank map. That catches Protomaps or Shortbread styles pointed
  at OpenMapTiles tiles.

`style --eject` copies a preset and its sprite beside map.yaml so you can edit
it. `style --import <file>` brings back a style exported from Maputnik.

### Fonts and glyph ranges

MapLibre asks for a label's `text-font`, such as
`["Metropolis Regular", "Noto Sans Regular"]`, as one stack, from one folder:
`fonts/Metropolis Regular,Noto Sans Regular/0-255.pbf`. Servers composite these
on request; a pack has no server, so the tool composites them. The first font
that has a glyph wins it and the later fonts fill the gaps, the same rule as
TileServer GL and MapTiler.

Fonts are found in this order:

1. the style's own font folder;
2. `glyphs.sources`;
3. the style's public glyph URL;
4. the [OpenMapTiles fonts release](https://github.com/openmaptiles/fonts/releases),
   74 MB, downloaded once and checked by SHA-256.

**Every range a label needs must ship.** MapLibre Native waits forever for a
missing range file, and every label in the tile waits with it. So the tool
reads the tiles and adds the ranges of every character in their labels. It
reads the SQLite file with a pure-Dart reader, so no native library is needed.
A range none of a stack's fonts covers is written as a valid empty file.

## Commands

| Command | What it does |
|---|---|
| `init <dir>` | Writes a commented map.yaml. |
| `doctor` | Checks Docker, Compose, architecture, rootless and SELinux, cache, network. |
| `generate [<map>]` | Runs Planetiler. Skipped when its inputs have not changed. `--force`, `--refresh-osm`, `--dry-run`. |
| `style [<map>]` | Shows the stacks, sprite and warnings. `--list`, `--eject`, `--import <file>`, `--refresh`. |
| `pack [<map>]` | Assembles `.work/pack`, validates it and publishes it. `--no-publish`, `--out`, `--split`, `--bump`, `--force`. |
| `build [<map>]` | Runs `generate`, then `pack`. |
| `preview [<map>]` | Serves the pack until Ctrl+C. `--edit` adds Maputnik; `--open`, `--detach`/`--stop`, `--no-build`. |
| `validate <pack>` | Checks any pack folder, including ones assembled by hand. |
| `manifest <folder>` | Writes pack.json for a folder, as the old `pack_manifest` did; that executable remains an alias. |
| `clean [<map>]` | Runs `compose down` and removes `.work`. `--cache` also empties the shared cache. |

Global flags: `--verbose`, `--cache-dir` (or `ASTRONOMICAN_TILES_CACHE`),
`--docker`. Exit codes: 0 ok, 1 failed, 64 usage, 65 config, 66 missing
input, 69 Docker or network unavailable, 130 interrupted.

## Publishing and versions

An installed app recopies a bundled pack only when its version goes up, so
`pack` guards it:

| Output holds | Result |
|---|---|
| Nothing | Published. |
| The same content under the same version | Up to date; nothing copied. |
| Different content under the same version | Refused. `--bump` raises `version:` in map.yaml, keeping its comments, and publishes. |
| A higher version | Refused: installed apps would ignore it. |

`.work/pack` is always the whole, unsplit pack. Serve that folder for
`MapPackManager.download`.

## Preview and editing

`preview` serves `.work/pack` in TileServer GL (`maptiler/tileserver-gl-light`)
on `127.0.0.1:8080`:

- **The viewer:** `/styles/<id>/`.
- **The tile inspector:** `/data/<id>/`.

It serves the pack's own tiles, style and sprite files. Fonts are served per
member font and composited by TileServer GL with the same rule, so what you see
is what ships. The one difference is the renderer: MapLibre GL JS in the
browser, MapLibre Native in the app.

`preview --edit` also starts Maputnik on `127.0.0.1:8888`, on a copy of the
style that reads from the preview. When you stop the preview, your edits are
written back to the map's style file. Then `pack --bump` publishes them.
Maputnik is published for amd64 only: it runs under Rosetta on Apple silicon
and needs qemu/binfmt on arm64 Linux.

## Files

```text
maps/<id>/map.yaml
maps/<id>/.work/               ignored by git (it writes its own .gitignore)
  docker-compose.yml           generated on every run, runnable by hand
  tiles/<id>.mbtiles           Planetiler's output
  style-src/                   the OSM OpenMapTiles style and sprite, when built
  pack/                        the pack
  preview/  edit/              TileServer GL and Maputnik
  build.json                   what went in: style sha, images, stacks, ranges
<cache>/                       shared: Planetiler sources, fonts, styles, openmaptiles
```

The cache is `%LOCALAPPDATA%\astronomican_tiles\Cache` on Windows,
`~/Library/Caches/astronomican_tiles` on macOS and
`$XDG_CACHE_HOME/astronomican_tiles` on Linux.

## Pinned images

| Image | Role | Platforms |
|---|---|---|
| `ghcr.io/onthegomap/planetiler:0.10.2` | tiles (OpenMapTiles 3.16) | amd64, arm64 |
| `ghcr.io/flother/spreet:0.13.1` | the OSM OpenMapTiles sprite | amd64, arm64 |
| `maptiler/tileserver-gl-light:v5.6.0` | preview | amd64, arm64 |
| `ghcr.io/maplibre/maputnik@sha256:6abd34d5…` | editor | amd64 |

## Troubleshooting

- **Windows.** Paths in the compose file use forward slashes, which Docker
  Desktop accepts. Under Git Bash, Ctrl+C may not reach Docker; use PowerShell
  or Windows Terminal, or `preview --detach` and `preview --stop`.
- **Linux.** Containers run as your user, so their files belong to you. With
  rootless Docker they already do. Under SELinux, mounts get `:z`. Podman is not
  supported.
- **Port in use.** Set `preview.port` and `preview.editorPort`.
- **Proxies.** `HTTP_PROXY` and `HTTPS_PROXY` are honoured for the tool's own
  downloads. Docker has its own proxy settings.

## Licensing

- **The data.** OpenStreetMap data is ODbL. OpenMapTiles-schema tiles require
  the credit "© OpenMapTiles © OpenStreetMap contributors", which is the
  default `attribution`.
- **The fonts** are under the OFL or Apache 2.0.
- **The styles** are BSD (code) and CC-BY 4.0 (design); `style --list` shows
  each one's licence.
