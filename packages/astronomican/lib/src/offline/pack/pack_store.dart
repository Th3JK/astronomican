import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'installed_pack.dart';
import 'package:astronomican_pack_format/astronomican_pack_format.dart';

/// The packs' layout on disk, and the few operations that change it.
///
/// ```text
/// <root>/<id>/v000003/            a complete install; .pack.json written last
/// <root>/<id>/v000004/            a newer one
/// <root>/<id>/.stage-bundle-v000005/   a copy in progress, or abandoned
/// <root>/<id>/.stage-remote-v000006/   a download in progress, kept to resume
/// ```
///
/// There is no "current" pointer to keep in step. The active version is simply
/// the highest one whose folder is complete, and a folder only becomes a
/// version folder by being renamed into place once everything in it has been
/// written and checked. So whatever moment the app is killed at, the next
/// launch sees either the old version or the new one — never half of one.
@internal
final class PackStore {
  /// A store rooted at [root].
  PackStore(this.root);

  /// Where every pack lives.
  final Directory root;

  /// The marker that makes a folder a complete install.
  static const String markerName = '.pack.json';

  /// The copy of a remote manifest kept beside a download in progress.
  static const String remoteManifestName = '.remote.json';

  static final RegExp _versionName = RegExp(r'^v(\d{6,})$');

  /// The folder holding every version of [id].
  Directory packDir(String id) => Directory(p.join(root.path, id));

  /// The folder name of [version].
  static String versionName(int version) =>
      'v${version.toString().padLeft(6, '0')}';

  /// The folder of [version] of [id].
  Directory versionDir(String id, int version) =>
      Directory(p.join(packDir(id).path, versionName(version)));

  /// The staging folder for [version] of [id], for a copy of [kind].
  Directory stagingDir(String id, String kind, int version) => Directory(
    p.join(packDir(id).path, '.stage-$kind-${versionName(version)}'),
  );

  /// The id of every pack with a folder.
  Future<List<String>> ids() async {
    if (!await root.exists()) return const [];
    return [
      await for (final entity in root.list())
        if (entity is Directory) p.basename(entity.path),
    ]..sort();
  }

  /// Every complete install of [id], newest first. Intactness is not checked.
  Future<List<InstalledPack>> installs(String id) async {
    final dir = packDir(id);
    if (!await dir.exists()) return const [];
    final found = <InstalledPack>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final match = _versionName.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      final install = await readInstall(entity);
      if (install != null &&
          install.id == id &&
          install.version == int.parse(match.group(1)!)) {
        found.add(install);
      }
    }
    found.sort((a, b) => b.version.compareTo(a.version));
    return found;
  }

  /// The install in [dir], or null when it has no readable marker.
  Future<InstalledPack?> readInstall(Directory dir) async {
    final marker = File(p.join(dir.path, markerName));
    try {
      final json = jsonDecode(await marker.readAsString());
      if (json is! Map<String, Object?>) return null;
      final manifest = json['manifest'];
      if (manifest is! Map<String, Object?>) return null;
      final installedAt = json['installedAt'];
      return InstalledPack(
        manifest: MapPackManifest.fromJson(manifest),
        directory: dir,
        origin: json['origin'] == PackOrigin.downloaded.name
            ? PackOrigin.downloaded
            : PackOrigin.bundled,
        installedAt: installedAt is String
            ? DateTime.tryParse(installedAt)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether every file of [install] is on disk at its declared size.
  ///
  /// Sizes only, not checksums: this runs on every launch, and hashing a
  /// tileset each time the app opens would cost seconds for a failure that
  /// storage essentially never produces. A file that has gone missing or been
  /// truncated — a cleaner app, a full disk — is caught.
  Future<bool> isIntact(InstalledPack install) async {
    for (final entry in install.manifest.files) {
      final stat = await install.file(entry.path).stat();
      if (stat.type != FileSystemEntityType.file || stat.size != entry.size) {
        return false;
      }
    }
    return true;
  }

  /// The newest intact install of [id], demoting any broken ones above it.
  Future<InstalledPack?> resolveActive(String id) async {
    for (final install in await installs(id)) {
      if (await isIntact(install)) return install;
      await demote(install.directory);
    }
    return null;
  }

  /// Removes an install: its marker first, so a removal interrupted halfway
  /// leaves a folder nothing will take for a complete version.
  Future<void> demote(Directory dir) async {
    try {
      final marker = File(p.join(dir.path, markerName));
      if (await marker.exists()) await marker.delete();
    } catch (_) {}
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // A file held open elsewhere; the marker is gone, so it is inert, and a
      // later launch will clear it.
    }
  }

  /// Every staging folder of [id], with its kind and version.
  Future<List<(Directory, String, int)>> stagingDirs(String id) async {
    final dir = packDir(id);
    if (!await dir.exists()) return const [];
    final pattern = RegExp(r'^\.stage-([a-z]+)-v(\d{6,})$');
    return [
      await for (final entity in dir.list())
        if (entity is Directory)
          if (pattern.firstMatch(p.basename(entity.path)) case final m?)
            (entity, m.group(1)!, int.parse(m.group(2)!)),
    ];
  }

  /// Makes [staging] the install of [manifest]: writes its marker, then
  /// renames it into place.
  Future<InstalledPack> commit(
    Directory staging,
    MapPackManifest manifest,
    PackOrigin origin,
  ) async {
    final remote = File(p.join(staging.path, remoteManifestName));
    if (await remote.exists()) await remote.delete();

    final now = DateTime.now().toUtc();
    final marker = File(p.join(staging.path, markerName));
    final temp = File('${marker.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'origin': origin.name,
        'installedAt': now.toIso8601String(),
        'manifest': manifest.toJson(),
      }),
      flush: true,
    );
    await temp.rename(marker.path);

    final target = versionDir(manifest.id, manifest.version);
    if (await target.exists()) await demote(target);
    final moved = await staging.rename(target.path);
    return InstalledPack(
      manifest: manifest,
      directory: moved,
      origin: origin,
      installedAt: now,
    );
  }
}
