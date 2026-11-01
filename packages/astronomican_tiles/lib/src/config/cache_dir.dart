import 'dart:io';

import 'package:path/path.dart' as p;

/// The shared cache: the fonts release, the openmaptiles sources, fetched
/// styles and sprites, and Planetiler's inputs — about 1.5 GB after a first
/// build, reused by every map.
///
/// `ASTRONOMICAN_TILES_CACHE` overrides the platform's usual place:
/// `%LOCALAPPDATA%\astronomican_tiles\Cache` on Windows,
/// `~/Library/Caches/astronomican_tiles` on macOS, and
/// `$XDG_CACHE_HOME/astronomican_tiles` (or `~/.cache/…`) elsewhere.
Directory defaultCacheDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final override = env['ASTRONOMICAN_TILES_CACHE'];
  if (override != null && override.isNotEmpty) return Directory(override);
  switch (os) {
    case 'windows':
      final local =
          env['LOCALAPPDATA'] ??
          p.join(env['USERPROFILE'] ?? '.', 'AppData', 'Local');
      return Directory(p.join(local, 'astronomican_tiles', 'Cache'));
    case 'macos':
      return Directory(
        p.join(env['HOME'] ?? '.', 'Library', 'Caches', 'astronomican_tiles'),
      );
    default:
      final xdg = env['XDG_CACHE_HOME'];
      final base = xdg != null && xdg.isNotEmpty
          ? xdg
          : p.join(env['HOME'] ?? '.', '.cache');
      return Directory(p.join(base, 'astronomican_tiles'));
  }
}
