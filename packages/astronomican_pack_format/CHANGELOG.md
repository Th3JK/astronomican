## 0.1.0

First release, split out of `astronomican` 0.1.0 so the tools that build packs
need no Flutter.

- `MapPackManifest` and `PackFileEntry`, unchanged, plus
  `MapPackManifest.isValidId`.
- The sealed `PackException` family, unchanged.
- `PackStyle`: the `pack://` conventions, the strakonice placeholders, a JSON
  string walk, and `fontStacks`. It finds stacks in plain lists, `literal`,
  the outputs of `step`/`case`/`match`/`coalesce`, legacy `stops` and `format`
  overrides, and optionally MapLibre's default stack.
- `GlyphRange`: the 256 glyph ranges, parsing, and the range holding a code
  point.
