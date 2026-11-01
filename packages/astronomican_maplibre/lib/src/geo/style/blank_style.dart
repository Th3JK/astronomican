import 'dart:convert';
import 'dart:ui' show Color;

import 'style_color.dart';

/// A style with nothing in it but a background colour.
///
/// The base for a map that is all overlay — a historic drawing pinned to the
/// town, with the stops on it — where streets underneath would only compete
/// with the picture. No sources, so nothing is fetched and nothing needs
/// staging.
abstract final class BlankStyle {
  /// The style document, painted [background].
  static String build({Color background = const Color(0xFFF0E0C6)}) =>
      jsonEncode({
        'version': 8,
        'name': 'Blank',
        'sources': <String, Object?>{},
        'layers': [
          {
            'id': 'background',
            'type': 'background',
            'paint': {'background-color': cssColor(background)},
          },
        ],
      });
}
