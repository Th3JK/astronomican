## 0.1.0

First release.

**Tiles**

- Runs Planetiler 0.10.2 (OpenMapTiles 3.16) through a generated Docker Compose
  file, for a Geofabrik area, a local extract, or tiles made elsewhere.
- The inputs shared by every map are downloaded once into a cache, and a
  fingerprint skips generation when nothing changed.
- Runs on Windows, macOS and Linux, on x86-64 and ARM. Containers run as the
  user; SELinux mounts are relabelled; rootless Docker is detected.

**Styles**

- All six OpenMapTiles styles are presets. OSM OpenMapTiles is built from the
  openmaptiles v3.16 sources: the style merged in Dart, the sprite made with
  spreet.
- Custom styles work as files or URLs, and the Strakonice placeholders are
  understood.
- Conversion to the pack form swaps keyed MapTiler URLs for the pack's own
  tiles, sprite and glyphs. It refuses any key left behind, drops or keeps
  other online sources, and warns about a style made for another schema.
- `style --eject` copies a preset out for editing; `style --import` brings
  back a style exported from Maputnik.

**Glyphs**

- Multi-font stacks are composited offline, first font winning, through a
  small protobuf codec.
- Fonts come from the style, from configured folders or URLs, or from the
  OpenMapTiles fonts release, which is SHA-256 pinned.
- The glyph ranges the labels need are found by reading the tiles with a
  pure-Dart SQLite and MVT reader. No range file is ever missing.

**Packs**

- Assembled in a staging folder, validated, and swapped in.
- Published with a version guard: `--bump` raises the version in map.yaml,
  keeping its comments.
- Large files can be split for bundling; the asset lines the pubspec needs
  are printed.
- `validate` checks any pack. `manifest` replaces `astronomican:pack_manifest`,
  which stays as an alias executable.

**Preview**

- TileServer GL serves the pack exactly as it ships.
- Maputnik edits the style against the same tiles, and the edits are written
  back when the preview stops.
