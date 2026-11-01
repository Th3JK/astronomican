/// The OpenMapTiles styles, as listed on openmaptiles.org.
///
/// Five are published as `style-cdn.json` on GitHub Pages, with a public
/// sprite beside them. Their tiles and glyphs point at MapTiler with a key;
/// the tool replaces both. The sixth, OSM OpenMapTiles, the official style,
/// is built from the openmaptiles repository itself.
enum StylePreset {
  /// The official OpenMapTiles style: shows every layer of the schema.
  osmOpenMapTiles(
    'osm-openmaptiles',
    ['openmaptiles', 'osm'],
    null,
    'CC-BY 4.0 (design), OpenMapTiles',
  ),

  /// A quiet basemap that stays in the background.
  maptilerBasic(
    'maptiler-basic',
    ['basic'],
    'maptiler-basic-gl-style',
    'BSD 3-Clause (code), CC-BY 4.0 (design)',
  ),

  /// A general-purpose basemap with OpenStreetMap's detail. The base of
  /// strakonice's "Parchment".
  osmBright(
    'osm-bright',
    ['bright'],
    'osm-bright-gl-style',
    'BSD 3-Clause (code), CC-BY 4.0 (design)',
  ),

  /// A light, unobtrusive basemap for data on top.
  positron(
    'positron',
    [],
    'positron-gl-style',
    'BSD 3-Clause (code), CC-BY 4.0 (design)',
  ),

  /// A dark basemap.
  darkMatter(
    'dark-matter',
    ['dark'],
    'dark-matter-gl-style',
    'BSD 3-Clause (code), CC-BY 4.0 (design)',
  ),

  /// A blue-toned basemap for data visualisation.
  fiordColor(
    'fiord-color',
    ['fiord'],
    'fiord-color-gl-style',
    'BSD 3-Clause (code), CC-BY 4.0 (design)',
  );

  const StylePreset(this.id, this.aliases, this.repository, this.license);

  /// The name map.yaml uses.
  final String id;

  /// Other accepted names.
  final List<String> aliases;

  /// The GitHub repository under `openmaptiles/`, when published there.
  final String? repository;

  /// The style's licence, for the credit an app must give.
  final String license;

  /// Where the published style is, or null for one built from source.
  Uri? get url => repository == null
      ? null
      : Uri.parse('https://openmaptiles.github.io/$repository/style-cdn.json');

  /// The preset named [name], by id or alias, or null.
  static StylePreset? find(String name) {
    final key = name.trim().toLowerCase();
    for (final preset in values) {
      if (preset.id == key || preset.aliases.contains(key)) return preset;
    }
    return null;
  }
}
