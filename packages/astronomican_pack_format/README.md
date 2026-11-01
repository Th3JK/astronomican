# astronomican_pack_format

The astronomican map pack format, in pure Dart. It's shared by the apps that
install packs (`astronomican`, which re-exports it) and the tools that build
them (`astronomican_tiles`, which runs without Flutter).

## A pack

A pack is a folder, described by `pack.json`:

```text
town/
  pack.json                      the manifest (MapPackManifest)
  town.mbtiles                   OpenMapTiles-schema vector tiles
  style.json                     the style, naming the pack's files with pack://
  sprite.json  sprite.png        the style's icons, and their @2x twins
  sprite@2x.json  sprite@2x.png
  fonts/<font stack>/<range>.pbf one folder per stack, one file per glyph range
```

### `pack.json`

```json
{
  "format": 1,
  "id": "town",
  "version": 3,
  "name": "Town",
  "style": "style.json",
  "bounds": [13.87, 49.24, 13.93, 49.27],
  "minZoom": 0,
  "maxZoom": 14,
  "attribution": "© OpenMapTiles © OpenStreetMap contributors",
  "files": [
    {"path": "town.mbtiles", "size": 1564672, "sha256": "…", "parts": ["town.mbtiles.000", "town.mbtiles.001"]},
    {"path": "style.json", "size": 114688, "sha256": "…"}
  ]
}
```

- **`id`** is lowercase letters, digits, `_`, `.` and `-`. It is also a folder
  name on the device.
- **`version`** is the "this is new" flag. An installed app recopies a bundled
  pack only when the version goes up. Bundled and downloaded packs share one
  version sequence.
- **`files[].path`** is relative, uses `/` between folders, and never contains
  `..`. `size` is checked on every install and `sha256` on every download.
- **`parts`** is used for bundling only. A large file ships in pieces so the
  installer holds one piece in memory at a time. Downloads fetch `path` whole.
- **`bounds`** is `[west, south, east, north]`, the same order as an mbtiles
  metadata table.

### `pack://` in the style

```json
"sources": { "openmaptiles": { "type": "vector", "url": "pack://town.mbtiles" } },
"sprite": "pack://sprite",
"glyphs": "pack://fonts/{fontstack}/{range}.pbf"
```

The app rewrites these to the installed files: `mbtiles://` for the tileset,
`file://` for everything else. Styles made for strakonice, with the
placeholders `___MBTILES_URI___`, `___SPRITE_URI___` and `___FONTS_URI___`,
mean the same thing (`PackStyle.legacyTokensFor`).

### Glyphs

- **One folder per font stack.** MapLibre asks for a stack as one folder, named
  by its fonts joined with commas: `fonts/Metropolis Regular,Noto Sans Regular/0-255.pbf`.
  A two-font stack's folder therefore holds the two fonts composited, the first
  font winning for each glyph. `PackStyle.fontStacks` finds every stack a style
  can ask for.
- **Every range the labels need must be there.** A range is 256 code points
  (`GlyphRange`). MapLibre Native waits for a missing range forever, and every
  label in the tile waiting with it stays blank. `0-255` and `256-511` cover
  Czech and most European names.
