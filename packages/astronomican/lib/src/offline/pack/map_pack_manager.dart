import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'installed_pack.dart';
import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'pack_download.dart';
import 'pack_progress.dart';
import 'pack_store.dart';
import 'pack_transport.dart';

/// Installs map packs into the app's storage, and keeps them up to date.
///
/// MapLibre draws natively and cannot read the Flutter bundle: it opens files
/// on disk. So a tileset shipped with the app has to be copied out of the
/// bundle before the map can use it — and copied **once**, not on every
/// launch, since a tileset can be hundreds of megabytes.
///
/// [ensureBundled] does exactly that. On the first launch it copies the pack
/// out; on every later launch it reads the bundled `pack.json`, sees the
/// installed version is as new, and returns straight away. It copies again only
/// when an app update ships a manifest with a higher version — the flag that
/// the pack is new.
///
/// [download] fetches a newer version from a server into the same place, and
/// the same version sequence decides between them: a downloaded v5 stays
/// active when the app still bundles v4.
///
/// ```dart
/// final packs = await MapPackManager.open(transport: IoPackTransport());
/// final pack = await packs.ensureBundled('assets/packs/town/pack.json');
/// // pack.file('town.mbtiles') is on disk.
/// ```
///
/// One manager per app is enough; it serialises work on each pack.
final class MapPackManager {
  /// A manager keeping packs under [root].
  ///
  /// [bundle] is where bundled packs are read from, [transport] how downloads
  /// are fetched. Packs in a manifest format above [supportedFormat] are
  /// refused rather than half understood.
  MapPackManager({
    required Directory root,
    AssetBundle? bundle,
    PackTransport? transport,
    this.supportedFormat = MapPackManifest.currentFormat,
  }) : _store = PackStore(root),
       _bundle = bundle,
       _transport = transport;

  /// A manager rooted at [defaultRoot].
  static Future<MapPackManager> open({
    AssetBundle? bundle,
    PackTransport? transport,
  }) async => MapPackManager(
    root: await defaultRoot(),
    bundle: bundle,
    transport: transport,
  );

  /// `<application support>/astronomican/packs`.
  ///
  /// Application support rather than a cache or temporary folder: a map that
  /// has to work with no connection cannot live somewhere the system may
  /// reclaim between launches.
  static Future<Directory> defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'astronomican', 'packs'));
  }

  /// The newest manifest format this app reads.
  final int supportedFormat;

  final PackStore _store;
  final AssetBundle? _bundle;
  final PackTransport? _transport;

  final Map<String, Future<void>> _locks = {};
  final Map<String, Future<InstalledPack>> _bundledInFlight = {};
  final Set<String> _downloading = {};

  /// Install folders handed to the app during this run. Never pruned while
  /// the app is running: a map may have the tileset in one of them open.
  final Set<String> _handedOut = {};

  final StreamController<InstalledPack> _changes =
      StreamController<InstalledPack>.broadcast();

  /// Where the packs live.
  Directory get root => _store.root;

  AssetBundle get _assets => _bundle ?? rootBundle;

  /// Announces every version installed from now on, from the bundle or a
  /// download — for a map to switch to it.
  Stream<InstalledPack> get changes => _changes.stream;

  /// Makes sure the pack whose manifest is the asset [manifestAsset] is
  /// installed, at least at the bundled version, and returns what is active.
  ///
  /// The files are read relative to the manifest: a manifest at
  /// `assets/packs/town/pack.json` listing `town.mbtiles` reads
  /// `assets/packs/town/town.mbtiles`.
  ///
  /// Cheap when there is nothing to do, so it is meant to be called on every
  /// launch — from a splash screen, or lazily by the first map. With [prune]
  /// it also clears versions older than the active one that no map in this run
  /// has been given.
  ///
  /// Concurrent calls for the same manifest share one install. A failure
  /// leaves the previous version active and is not remembered, so the next
  /// call tries again.
  Future<InstalledPack> ensureBundled(
    String manifestAsset, {
    void Function(PackProgress progress)? onProgress,
    bool prune = true,
  }) {
    final existing = _bundledInFlight[manifestAsset];
    if (existing != null) return existing;
    final pending = _ensureBundled(manifestAsset, onProgress, prune);
    _bundledInFlight[manifestAsset] = pending;
    return pending.whenComplete(() {
      if (identical(_bundledInFlight[manifestAsset], pending)) {
        _bundledInFlight.remove(manifestAsset);
      }
    });
  }

  /// The bundled manifest at [manifestAsset], without installing anything.
  Future<MapPackManifest> readBundledManifest(String manifestAsset) async {
    final String text;
    try {
      text = await _assets.loadString(manifestAsset, cache: false);
    } catch (_) {
      throw PackMissingAssetException(manifestAsset);
    }
    final manifest = MapPackManifest.parse(text);
    _checkFormat(manifest);
    return manifest;
  }

  /// The active version of [id], or null when none is installed.
  Future<InstalledPack?> installed(String id) async {
    final active = await _withLock(id, () => _store.resolveActive(id));
    return active == null ? null : _handOut(active);
  }

  /// The active version of every installed pack.
  Future<List<InstalledPack>> list() async {
    final found = <InstalledPack>[];
    for (final id in await _store.ids()) {
      final active = await installed(id);
      if (active != null) found.add(active);
    }
    return found;
  }

  /// Removes every version of [id], downloads in progress included.
  ///
  /// A map still drawing it keeps working on Android and iOS, which keep a
  /// deleted file readable while it is open, but the pack is gone next launch.
  Future<void> remove(String id) => _withLock(id, () async {
    MapPackManifest.checkPath(id);
    for (final install in await _store.installs(id)) {
      await _store.demote(install.directory);
    }
    final dir = _store.packDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// The manifest at [manifestUrl] if it is newer than what is installed,
  /// otherwise null.
  Future<MapPackManifest?> checkForUpdate(Uri manifestUrl) async {
    final remote = await _fetchManifest(manifestUrl);
    final active = await installed(remote.$1.id);
    if (active != null && active.version >= remote.$1.version) return null;
    return remote.$1;
  }

  /// Downloads the pack whose manifest is at [manifestUrl], if it is newer
  /// than what is installed — or regardless, with [force].
  ///
  /// Files are fetched relative to the manifest's URL. Unchanged files — same
  /// path and SHA-256 as the installed version — are copied locally instead of
  /// fetched. An interrupted or cancelled download resumes where it stopped
  /// the next time the same version is downloaded, using HTTP ranges within a
  /// file.
  ///
  /// The new version is announced on [changes] and becomes active for the
  /// next map that asks. The version it replaces is removed on a later launch,
  /// not now, since a map may be drawing from it.
  PackDownload download(Uri manifestUrl, {bool force = false}) {
    final task = PackDownload(manifestUrl);
    unawaited(_download(task, force: force));
    return task;
  }

  /// Stops announcing [changes]. Installs still work.
  Future<void> dispose() => _changes.close();

  // Bundled installs.

  Future<InstalledPack> _ensureBundled(
    String asset,
    void Function(PackProgress progress)? onProgress,
    bool prune,
  ) async {
    final manifest = await readBundledManifest(asset);
    final id = manifest.id;
    return _withLock(id, () async {
      onProgress?.call(
        PackProgress(
          packId: id,
          version: manifest.version,
          phase: PackPhase.checking,
        ),
      );
      await _sweepBundleStaging(id);
      final active = await _store.resolveActive(id);
      if (active != null && active.version >= manifest.version) {
        if (prune) await _prune(active);
        onProgress?.call(
          PackProgress(
            packId: id,
            version: active.version,
            phase: PackPhase.upToDate,
          ),
        );
        return _handOut(active);
      }

      final installed = await _copyBundled(asset, manifest, onProgress);
      if (prune) await _prune(installed);
      if (!_changes.isClosed) _changes.add(installed);
      onProgress?.call(
        PackProgress(
          packId: id,
          version: installed.version,
          phase: PackPhase.done,
          bytesDone: manifest.totalBytes,
          bytesTotal: manifest.totalBytes,
        ),
      );
      return _handOut(installed);
    });
  }

  Future<InstalledPack> _copyBundled(
    String asset,
    MapPackManifest manifest,
    void Function(PackProgress progress)? onProgress,
  ) async {
    final base = p.posix.dirname(asset);
    final staging = _store.stagingDir(manifest.id, 'bundle', manifest.version);
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    final total = manifest.totalBytes;
    var done = 0;
    try {
      for (final entry in manifest.files) {
        final target = File(_join(staging.path, entry.path));
        await target.parent.create(recursive: true);
        final sink = await target.open(mode: FileMode.write);
        try {
          // One piece at a time: rootBundle can only read an asset whole, so
          // a split tileset keeps peak memory to one piece.
          for (final piece in entry.parts ?? [entry.path]) {
            final key = p.posix.normalize(p.posix.join(base, piece));
            final ByteData data;
            try {
              data = await _assets.load(key);
            } catch (_) {
              throw PackMissingAssetException(key);
            }
            await sink.writeFrom(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
            done += data.lengthInBytes;
            onProgress?.call(
              PackProgress(
                packId: manifest.id,
                version: manifest.version,
                phase: PackPhase.copying,
                bytesDone: done,
                bytesTotal: total,
                file: entry.path,
              ),
            );
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        final length = await target.length();
        if (length != entry.size) {
          throw PackIntegrityException(
            entry.path,
            '"${entry.path}" is $length bytes in the bundle; the manifest '
            'says ${entry.size}. Regenerate pack.json.',
          );
        }
      }
      return await _store.commit(staging, manifest, PackOrigin.bundled);
    } catch (_) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _sweepBundleStaging(String id) async {
    for (final (dir, kind, _) in await _store.stagingDirs(id)) {
      if (kind == 'bundle') {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Clears versions below [active] that nobody in this run was given, and
  /// downloads in progress that [active] has made pointless.
  Future<void> _prune(InstalledPack active) async {
    for (final install in await _store.installs(active.id)) {
      if (install.version < active.version &&
          !_handedOut.contains(install.directory.path)) {
        await _store.demote(install.directory);
      }
    }
    for (final (dir, kind, version) in await _store.stagingDirs(active.id)) {
      if (kind == 'remote' && version <= active.version) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  // Downloads.

  Future<(MapPackManifest, String)> _fetchManifest(Uri url) async {
    final transport = _transport;
    if (transport == null) {
      throw StateError('MapPackManager needs a PackTransport to download.');
    }
    final text = utf8.decode(await transport.fetch(url));
    final manifest = MapPackManifest.parse(text);
    _checkFormat(manifest);
    return (manifest, text);
  }

  Future<void> _download(PackDownload task, {required bool force}) async {
    try {
      final (remote, text) = await _fetchManifest(task.url);
      task.checkCancelled();
      final id = remote.id;
      task.report(
        PackProgress(
          packId: id,
          version: remote.version,
          phase: PackPhase.checking,
        ),
      );
      InstalledPack? upToDate(InstalledPack? active) {
        if (force || active == null || active.version < remote.version) {
          return null;
        }
        task.report(
          PackProgress(
            packId: id,
            version: active.version,
            phase: PackPhase.upToDate,
          ),
        );
        return _handOut(active);
      }

      final active = await _withLock(id, () => _store.resolveActive(id));
      final current = upToDate(active);
      if (current != null) {
        task.complete(current);
        return;
      }

      // The files are fetched without holding the pack's lock: a download can
      // take minutes, and a map opening meanwhile must not wait for it. Only
      // one download per pack at a time, though — they would share a staging
      // folder.
      if (!_downloading.add(id)) {
        throw StateError('The pack "$id" is already downloading.');
      }
      try {
        final staging = await _fetchFiles(task, remote, text, active);
        task.checkCancelled();
        final pack = await _withLock(id, () async {
          // A newer version may have been installed while this one arrived.
          final latest = upToDate(await _store.resolveActive(id));
          if (latest != null) {
            await staging.delete(recursive: true);
            return latest;
          }
          final installed = await _store.commit(
            staging,
            remote,
            PackOrigin.downloaded,
          );
          if (!_changes.isClosed) _changes.add(installed);
          task.report(
            PackProgress(
              packId: id,
              version: installed.version,
              phase: PackPhase.done,
              bytesDone: remote.totalBytes,
              bytesTotal: remote.totalBytes,
            ),
          );
          return installed;
        });
        task.complete(pack);
      } finally {
        _downloading.remove(id);
      }
    } catch (error, stackTrace) {
      task.fail(error, stackTrace);
    }
  }

  /// Fetches every file of [remote] into its staging folder, and returns the
  /// folder.
  Future<Directory> _fetchFiles(
    PackDownload task,
    MapPackManifest remote,
    String manifestText,
    InstalledPack? active,
  ) async {
    final transport = _transport!;
    final staging = _store.stagingDir(remote.id, 'remote', remote.version);
    await _prepareRemoteStaging(staging, manifestText);

    final total = remote.totalBytes;
    var done = 0;
    void report(String file) => task.report(
      PackProgress(
        packId: remote.id,
        version: remote.version,
        phase: PackPhase.downloading,
        bytesDone: done,
        bytesTotal: total,
        file: file,
      ),
    );

    for (final entry in remote.files) {
      task.checkCancelled();
      final target = File(_join(staging.path, entry.path));
      await target.parent.create(recursive: true);

      if (await _isValid(target, entry)) {
        done += entry.size;
        report(entry.path);
        continue;
      }

      final previous = active?.manifest.file(entry.path);
      if (active != null &&
          entry.sha256 != null &&
          previous?.sha256 == entry.sha256 &&
          previous?.size == entry.size) {
        final source = active.file(entry.path);
        if (await source.exists()) {
          await source.copy(target.path);
          if (await _isValid(target, entry)) {
            done += entry.size;
            report(entry.path);
            continue;
          }
        }
      }

      final base = done;
      await _fetchFile(
        task,
        transport,
        task.url.resolve(
          entry.path.split('/').map(Uri.encodeComponent).join('/'),
        ),
        target,
        entry,
        (received) {
          done = base + received;
          report(entry.path);
        },
      );
      done = base + entry.size;
    }
    return staging;
  }

  /// Keeps a download in progress only if it was downloading this very
  /// manifest; anything else is started over.
  Future<void> _prepareRemoteStaging(Directory staging, String text) async {
    final saved = File(p.join(staging.path, PackStore.remoteManifestName));
    if (await staging.exists()) {
      final same = await saved.exists() && await saved.readAsString() == text;
      if (!same) await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);
    await saved.writeAsString(text, flush: true);
  }

  Future<void> _fetchFile(
    PackDownload task,
    PackTransport transport,
    Uri uri,
    File target,
    PackFileEntry entry,
    void Function(int received) onBytes,
  ) async {
    final part = File('${target.path}.part');
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > entry.size) {
      await part.delete();
      offset = 0;
    }

    var hasher = entry.sha256 == null ? null : _Sha256();
    if (hasher != null && offset > 0) {
      await for (final chunk in part.openRead()) {
        hasher.add(chunk);
      }
    }

    if (offset < entry.size) {
      final response = await transport.open(uri, offset: offset);
      task.checkCancelled();
      if (response.start != offset) {
        // The server sent the whole file instead of the rest of it.
        offset = 0;
        hasher = entry.sha256 == null ? null : _Sha256();
      }
      final sink = await part.open(
        mode: offset == 0 ? FileMode.write : FileMode.append,
      );
      var received = offset;
      onBytes(received);
      try {
        await _drain(task, response.body, (chunk) async {
          await sink.writeFrom(chunk);
          hasher?.add(chunk);
          received += chunk.length;
          onBytes(received);
        });
        await sink.flush();
      } finally {
        await sink.close();
      }
    }

    final length = await part.length();
    if (length < entry.size) {
      // Kept: the next attempt resumes from here.
      throw PackIntegrityException(
        entry.path,
        '"${entry.path}" stopped at $length of ${entry.size} bytes',
      );
    }
    if (length > entry.size) {
      await part.delete();
      throw PackIntegrityException(
        entry.path,
        '"${entry.path}" is $length bytes; the manifest says ${entry.size}',
      );
    }
    final digest = hasher?.close();
    if (digest != null && digest != entry.sha256) {
      await part.delete();
      throw PackIntegrityException(
        entry.path,
        '"${entry.path}" does not match its checksum',
      );
    }
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
  }

  /// Feeds [body] through [write] one chunk at a time, stoppable by the task's
  /// cancel even while the connection is silent.
  Future<void> _drain(
    PackDownload task,
    Stream<List<int>> body,
    Future<void> Function(List<int> chunk) write,
  ) {
    final done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    void finish([Object? error, StackTrace? stackTrace]) {
      task.abort = null;
      if (done.isCompleted) return;
      if (error == null) {
        done.complete();
      } else {
        done.completeError(error, stackTrace);
      }
    }

    subscription = body.listen(
      (chunk) {
        subscription.pause();
        write(chunk).then(
          (_) => subscription.resume(),
          onError: (Object error, StackTrace stackTrace) {
            unawaited(subscription.cancel());
            finish(error, stackTrace);
          },
        );
      },
      onError: finish,
      onDone: finish,
      cancelOnError: true,
    );
    task.abort = () {
      unawaited(subscription.cancel());
      finish(const PackCancelledException(), StackTrace.current);
    };
    return done.future;
  }

  static Future<bool> _isValid(File file, PackFileEntry entry) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size != entry.size) {
      return false;
    }
    final expected = entry.sha256;
    if (expected == null) return true;
    final hasher = _Sha256();
    await for (final chunk in file.openRead()) {
      hasher.add(chunk);
    }
    return hasher.close() == expected;
  }

  // Shared.

  void _checkFormat(MapPackManifest manifest) {
    if (manifest.format > supportedFormat) {
      throw PackIncompatibleException(
        format: manifest.format,
        supported: supportedFormat,
      );
    }
  }

  InstalledPack _handOut(InstalledPack pack) {
    _handedOut.add(pack.directory.path);
    return pack;
  }

  /// Runs [body] with every other operation on pack [id] waiting its turn.
  Future<T> _withLock<T>(String id, Future<T> Function() body) async {
    final previous = _locks[id];
    final mine = Completer<void>();
    _locks[id] = mine.future;
    try {
      if (previous != null) await previous;
      return await body();
    } finally {
      mine.complete();
      if (identical(_locks[id], mine.future)) _locks.remove(id)?.ignore();
    }
  }

  static String _join(String root, String relative) =>
      p.joinAll([root, ...relative.split('/')]);
}

/// SHA-256 over a stream of chunks, as lowercase hex.
final class _Sha256 {
  _Sha256() {
    _input = sha256.startChunkedConversion(_output);
  }

  // Closed in close(), which every caller reaches.
  // ignore: close_sinks
  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  void add(List<int> chunk) => _input.add(chunk);

  String close() {
    _input.close();
    return _output.value.toString();
  }
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
