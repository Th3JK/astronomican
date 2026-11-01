import 'dart:convert';

/// The `config.json` TileServer GL previews a pack with.
///
/// The pack folder is mounted at `/pack` and served as it is: its tiles, its
/// sprite files. Fonts come from `/data/fonts`, one folder per member font —
/// TileServer GL composites a comma stack itself, first font first, exactly
/// as the pack's own composited folders were made.
abstract final class TileserverConfig {
  /// The config for pack [id], with [bounds] framing the viewer.
  static String render({required String id, List<double>? bounds}) =>
      const JsonEncoder.withIndent('  ').convert({
        'options': {
          'paths': {
            'root': '/data',
            'styles': '/data/styles',
            'fonts': '/data/fonts',
            'sprites': '/pack',
            'mbtiles': '/pack',
            'pmtiles': '/pack',
            'files': '/pack',
          },
          'serveAllFonts': false,
          'serveAllStyles': false,
        },
        'styles': {
          id: {
            'style': '$id.json',
            if (bounds != null) 'tilejson': {'bounds': bounds},
          },
        },
        'data': {
          id: {'mbtiles': '$id.mbtiles'},
        },
      });
}
