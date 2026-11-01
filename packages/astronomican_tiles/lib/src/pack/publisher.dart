import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:path/path.dart' as p;

import '../cli/tiles_exception.dart';
import 'manifest_writer.dart';

/// What publishing did.
enum PublishOutcome {
  /// Copied to the output.
  published,

  /// The output already holds this very pack.
  upToDate,
}

/// The output holds the same version with different content. Installed apps
/// would never pick the change up, so it is refused until the version goes
/// up.
final class VersionConflict extends TilesException {
  /// A conflict with [published], the version already in the output.
  VersionConflict(this.published, String message) : super.config(message);

  /// The version in the output.
  final int published;
}

/// Copies a built pack to its output — typically an app's
/// `assets/packs/<id>` — guarding the version.
///
/// An installed app recopies a bundled pack only when its version goes up.
/// So the publisher refuses to overwrite the output with different content
/// under the same version, and refuses a lower version outright; the same
/// content under the same version is simply up to date.
class Publisher {
  /// A publisher.
  const Publisher();

  /// Publishes the unsplit pack in [pack] to [output], splitting files
  /// larger than [splitBytes]. With [force], an output that is not a pack of
  /// the same id is replaced anyway.
  Future<(PublishOutcome, MapPackManifest)> publish({
    required Directory pack,
    required Directory output,
    int? splitBytes,
    bool force = false,
  }) async {
    final built = MapPackManifest.parse(
      await File(p.join(pack.path, 'pack.json')).readAsString(),
    );
    final existingFile = File(p.join(output.path, 'pack.json'));
    if (await existingFile.exists()) {
      final existing = MapPackManifest.parse(await existingFile.readAsString());
      if (existing.id != built.id && !force) {
        throw TilesException.config(
          '${output.path} holds the pack "${existing.id}", not "${built.id}". '
          'Pass --force to replace it.',
        );
      }
      if (existing.id == built.id) {
        if (built.version < existing.version) {
          throw TilesException.config(
            '${output.path} already has "${built.id}" v${existing.version}; '
            'v${built.version} would go backwards and installed apps would '
            'ignore it. Set version: ${existing.version + 1} in map.yaml.',
          );
        }
        if (built.version == existing.version) {
          if (_sameContent(built, existing)) {
            return (PublishOutcome.upToDate, existing);
          }
          throw VersionConflict(
            existing.version,
            '${output.path} already has "${built.id}" v${existing.version} '
            'with different content. Installed apps only recopy a pack when '
            'its version goes up: set version: ${existing.version + 1} in '
            'map.yaml, or pass --bump.',
          );
        }
      }
    } else if (await output.exists() &&
        await output.list().isEmpty == false &&
        !force) {
      throw TilesException.config(
        '${output.path} is not empty and holds no pack.json. Pass --force to '
        'replace what is there.',
      );
    }

    if (await output.exists()) await output.delete(recursive: true);
    await output.create(recursive: true);
    await for (final entity in pack.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: pack.path);
      if (relative == 'pack.json') continue;
      final target = File(p.join(output.path, relative));
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    }
    final published = await const ManifestWriter().write(
      output,
      id: built.id,
      version: built.version,
      style: built.style,
      name: built.name,
      attribution: built.attribution,
      bounds: built.bounds,
      minZoom: built.minZoom,
      maxZoom: built.maxZoom,
      splitBytes: splitBytes,
    );
    return (PublishOutcome.published, published);
  }

  static bool _sameContent(MapPackManifest a, MapPackManifest b) {
    String key(PackFileEntry e) => '${e.path}|${e.size}|${e.sha256}';
    final left = {for (final e in a.files) key(e)};
    final right = {for (final e in b.files) key(e)};
    return left.length == right.length && left.containsAll(right);
  }
}
