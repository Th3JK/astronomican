/// How a pack's style document names the pack's own files, and what can be
/// read out of a style without drawing it.
///
/// A style inside a pack cannot know where the pack will be installed — that
/// is an absolute path into the app's storage, decided on the device — so it
/// names its files relative to the pack:
///
/// ```json
/// "sources": { "openmaptiles": { "type": "vector", "url": "pack://town.mbtiles" } },
/// "sprite": "pack://sprite",
/// "glyphs": "pack://fonts/{fontstack}/{range}.pbf"
/// ```
///
/// The app rewrites these to the installed files; the tools that build packs
/// write them. Styles made for strakonice, with `___MBTILES_URI___`,
/// `___SPRITE_URI___` and `___FONTS_URI___` placeholders, map onto the same
/// thing through [legacyTokensFor].
abstract final class PackStyle {
  /// The scheme of a file inside the pack.
  static const String scheme = 'pack://';

  /// Where a pack's sprite is, by convention: `sprite.json`, `sprite.png` and
  /// their `@2x` twins at the top of the pack.
  static const String defaultSprite = 'pack://sprite';

  /// Where a pack's glyphs are, by convention: one folder per font stack under
  /// `fonts/`, one file per range.
  static const String defaultGlyphs = 'pack://fonts/{fontstack}/{range}.pbf';

  /// The font stack MapLibre falls back to for a label with no `text-font`.
  static const List<String> defaultFontStack = [
    'Open Sans Regular',
    'Arial Unicode MS Regular',
  ];

  /// A `___NAME___` placeholder left in a style.
  static final RegExp placeholderPattern = RegExp(r'___[A-Z0-9_]+___');

  /// The placeholders strakonice's style ships with, for a pack whose tileset
  /// is [mbtilesPath].
  static Map<String, String> legacyTokensFor(String? mbtilesPath) => {
    if (mbtilesPath != null) '___MBTILES_URI___': '$scheme$mbtilesPath',
    '___SPRITE_URI___': defaultSprite,
    '___FONTS_URI___': defaultGlyphs,
  };

  /// The path inside the pack that [uri] names, or null when it is not a
  /// `pack://` URI.
  static String? relativePath(String uri) =>
      uri.startsWith(scheme) ? uri.substring(scheme.length) : null;

  /// [node] with every string passed through [transform], the rest of the
  /// JSON structure kept.
  static Object? mapStrings(Object? node, String Function(String) transform) =>
      switch (node) {
        final String s => transform(s),
        final List<Object?> list => [
          for (final item in list) mapStrings(item, transform),
        ],
        final Map<String, Object?> map => {
          for (final MapEntry(:key, :value) in map.entries)
            key: mapStrings(value, transform),
        },
        _ => node,
      };

  /// Every string anywhere in [node].
  static Iterable<String> strings(Object? node) sync* {
    switch (node) {
      case final String s:
        yield s;
      case final List<Object?> list:
        for (final item in list) {
          yield* strings(item);
        }
      case final Map<String, Object?> map:
        for (final value in map.values) {
          yield* strings(value);
        }
    }
  }

  /// Every font stack [style]'s labels can ask for, as MapLibre asks for it:
  /// the fonts joined by commas, which is also the name of the stack's folder.
  ///
  /// Finds stacks written plainly, wrapped in `literal`, chosen by `step`,
  /// `case`, `match` and `coalesce` expressions, by legacy zoom `stops`, and
  /// in `format` overrides. With [includeDefault], a label layer that names no
  /// font adds MapLibre's own default stack, which it will then ask for.
  static Set<String> fontStacks(
    Map<String, Object?> style, {
    bool includeDefault = false,
  }) {
    final stacks = <String>{};
    final layers = style['layers'];
    if (layers is! List<Object?>) return stacks;
    for (final layer in layers) {
      if (layer is! Map<String, Object?>) continue;
      final layout = layer['layout'];
      if (layout is! Map<String, Object?>) continue;
      final font = layout['text-font'];
      if (font != null) {
        _collectFonts(font, stacks);
      } else if (includeDefault &&
          layer['type'] == 'symbol' &&
          layout['text-field'] != null) {
        stacks.add(defaultFontStack.join(','));
      }
      // Per-section font overrides inside a `format` expression.
      _collectFormatFonts(layout['text-field'], stacks);
    }
    return stacks;
  }

  static const Set<String> _operators = {
    'literal',
    'get',
    'has',
    'at',
    'in',
    'index-of',
    'slice',
    'concat',
    'to-string',
    'downcase',
    'upcase',
    'var',
    'let',
    'zoom',
    'feature-state',
    'geometry-type',
    'id',
    'properties',
    'accumulated',
    'line-progress',
    'image',
    'number-format',
    'resolved-locale',
    'collator',
    'coalesce',
    'step',
    'case',
    'match',
    'interpolate',
    'format',
    'global-state',
  };

  static void _collectFonts(Object? value, Set<String> stacks) {
    switch (value) {
      case final Map<String, Object?> function:
        // A legacy function: {"stops": [[zoom, ["Font"]], ...]}.
        final stops = function['stops'];
        if (stops is List<Object?>) {
          for (final stop in stops) {
            if (stop is List<Object?> && stop.length == 2) {
              _collectFonts(stop[1], stacks);
            }
          }
        }
      case final List<Object?> list when list.isNotEmpty:
        final head = list.first;
        if (head is String && _operators.contains(head)) {
          // An expression: only its outputs can be stacks. A match's labels
          // are string lists too, and `["get", "font"]` is no font.
          for (final output in _outputs(head, list)) {
            _collectFonts(output, stacks);
          }
        } else if (list.every((item) => item is String)) {
          stacks.add(list.cast<String>().join(','));
        }
      default:
        break;
    }
  }

  /// The arguments of expression [op] that are its possible results.
  static Iterable<Object?> _outputs(String op, List<Object?> e) sync* {
    final n = e.length;
    switch (op) {
      case 'literal':
        if (n == 2) yield e[1];
      case 'step':
        // ["step", input, output0, stop1, output1, ...]
        for (var i = 2; i < n; i += 2) {
          yield e[i];
        }
      case 'case':
        // ["case", cond1, output1, ..., fallback]
        for (var i = 2; i < n - 1; i += 2) {
          yield e[i];
        }
        if (n > 1) yield e[n - 1];
      case 'match':
        // ["match", input, labels1, output1, ..., fallback]
        for (var i = 3; i < n - 1; i += 2) {
          yield e[i];
        }
        if (n > 2) yield e[n - 1];
      case 'coalesce':
        yield* e.skip(1);
      case 'let':
        if (n > 1) yield e[n - 1];
    }
  }

  static void _collectFormatFonts(Object? node, Set<String> stacks) {
    switch (node) {
      case final List<Object?> list:
        for (final item in list) {
          _collectFormatFonts(item, stacks);
        }
      case final Map<String, Object?> map:
        final font = map['text-font'];
        if (font != null) _collectFonts(font, stacks);
      default:
        break;
    }
  }
}
