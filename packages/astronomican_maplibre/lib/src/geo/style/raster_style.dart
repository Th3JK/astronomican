import 'dart:convert';
import 'dart:ui' show Color;

import 'style_color.dart';

/// A style that draws one layer of raster tiles, such as OpenStreetMap's.
///
/// For a provider that serves plain `{z}/{x}/{y}` pictures rather than a
/// style document of its own. Mind the provider's terms: OpenStreetMap's own
/// tile servers ask for a real user agent and visible attribution, and forbid
/// bulk downloading — so they are fine to browse and not to take offline.
abstract final class RasterStyle {
  /// The style document for tiles at [urlTemplate].
  ///
  /// The template uses `{z}`, `{x}` and `{y}`. A `{s}` in it is expanded over
  /// [subdomains], spreading requests across the provider's hosts.
  static String build({
    required String urlTemplate,
    int tileSize = 256,
    int minZoom = 0,
    int maxZoom = 19,
    String? attribution,
    List<String> subdomains = const ['a', 'b', 'c'],
    Color background = const Color(0xFFF2EFE9),
  }) {
    final tiles = urlTemplate.contains('{s}')
        ? [for (final s in subdomains) urlTemplate.replaceAll('{s}', s)]
        : [urlTemplate];
    return jsonEncode({
      'version': 8,
      'name': 'Raster',
      'sources': {
        'raster': {
          'type': 'raster',
          'tiles': tiles,
          'tileSize': tileSize,
          'minzoom': minZoom,
          'maxzoom': maxZoom,
          'attribution': ?attribution,
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': cssColor(background)},
        },
        {'id': 'raster', 'type': 'raster', 'source': 'raster'},
      ],
    });
  }
}
