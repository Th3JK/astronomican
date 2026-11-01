import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../core/geo_bounds.dart';
import 'package:astronomican_pack_format/astronomican_pack_format.dart';

/// Where an installed pack came from.
enum PackOrigin {
  /// Copied out of the app's bundle.
  bundled,

  /// Fetched from a server.
  downloaded,
}

/// A map pack on disk, ready to draw.
///
/// Each version is installed in a folder of its own and never changed once
/// installed, so a map holding one open is never pulled out from under by an
/// update: the update lands beside it, and the old folder is only removed on a
/// later launch.
@immutable
final class InstalledPack {
  /// [manifest]'s files, installed in [directory].
  const InstalledPack({
    required this.manifest,
    required this.directory,
    required this.origin,
    this.installedAt,
  });

  /// What the pack holds.
  final MapPackManifest manifest;

  /// The folder holding this version.
  final Directory directory;

  /// Whether it came from the bundle or a download.
  final PackOrigin origin;

  /// When it was installed, if recorded.
  final DateTime? installedAt;

  /// The pack's id.
  String get id => manifest.id;

  /// The installed version.
  int get version => manifest.version;

  /// The absolute path of [relative], a path inside the pack written with `/`.
  String path(String relative) =>
      p.joinAll([directory.path, ...relative.split('/')]);

  /// The file [relative] inside the pack.
  File file(String relative) => File(path(relative));

  /// The area the pack covers, when its manifest says.
  GeoBounds? get bounds {
    final b = manifest.bounds;
    if (b == null) return null;
    return GeoBounds(west: b[0], south: b[1], east: b[2], north: b[3]);
  }

  @override
  bool operator ==(Object other) =>
      other is InstalledPack &&
      other.manifest == manifest &&
      other.directory.path == directory.path &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(manifest, directory.path, origin);

  @override
  String toString() =>
      'InstalledPack($id v$version, ${origin.name}, '
      '${directory.path})';
}
