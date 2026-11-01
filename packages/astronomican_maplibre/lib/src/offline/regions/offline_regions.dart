import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';
import 'offline_area.dart';
import 'maplibre_offline_region_backend.dart';
import 'offline_region_backend.dart';

/// Areas of an online style kept for use without a connection, in MapLibre's
/// own offline database.
///
/// This is the other half of offline maps from packs: a pack is data the app
/// ships or fetches as files; an offline area is MapLibre fetching the tiles,
/// sprite and glyphs a style needs for an area and keeping them in its
/// database. A map showing that same style URL then draws the area with no
/// network — [setOffline] makes sure it does not even try.
///
/// ```dart
/// final regions = OfflineRegions();
/// final download = regions.download(OfflineAreaRequest(
///   styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
///   bounds: town,
///   minZoom: 12,
///   maxZoom: 16,
///   name: 'Town centre',
/// ));
/// download.progress.listen((p) => print(p.fraction));
/// await download.result;
/// ```
final class OfflineRegions {
  /// Areas in [backend], MapLibre's database by default.
  OfflineRegions({OfflineRegionBackend? backend})
    : _backend = backend ?? const MapLibreOfflineRegionBackend();

  /// The metadata key marking an area as downloaded through this class, so
  /// [list] can leave alone areas other code put in the shared database.
  static const String ownerKey = 'astronomican';

  final OfflineRegionBackend _backend;

  /// The areas downloaded through this class — or every area, with
  /// [onlyOwn] off.
  Future<List<OfflineArea>> list({bool onlyOwn = true}) async {
    final areas = await _backend.list();
    if (!onlyOwn) return areas;
    return [
      for (final area in areas)
        if (area.metadata[ownerKey] == true) area,
    ];
  }

  /// Starts downloading [request].
  ///
  /// An area already downloaded is refreshed rather than duplicated. A
  /// dropped connection pauses the download rather than failing it; MapLibre
  /// carries on when the network is back.
  OfflineDownload download(OfflineAreaRequest request) {
    final task = OfflineDownload._();
    final metadata = <String, Object?>{
      ...request.metadata,
      ownerKey: true,
      'name': ?request.name,
    };
    unawaited(
      _backend
          .download(request, metadata, task._onEvent)
          .then(task._started, onError: task._fail),
    );
    return task;
  }

  /// How far [area]'s download has got.
  Future<OfflineProgress> status(OfflineArea area) => _backend.status(area.id);

  /// Pauses [area]'s download.
  Future<void> pause(OfflineArea area) => _backend.pause(area.id);

  /// Resumes [area]'s download.
  Future<void> resume(OfflineArea area) => _backend.resume(area.id);

  /// Deletes [area]. Tiles it shares with other areas stay, as do tiles in the
  /// general cache unless [clearAmbientCache] is set.
  Future<void> delete(
    OfflineArea area, {
    bool clearAmbientCache = false,
  }) async {
    await _backend.delete(area.id);
    if (clearAmbientCache) await _backend.clearAmbientCache();
  }

  /// Caps how many tiles one area may hold. MapLibre's default is low enough
  /// that a town at street level can hit it.
  Future<void> setTileCountLimit(int limit) =>
      _backend.setTileCountLimit(limit);

  /// Stops every map in the app using the network, so it draws only what is
  /// stored — or lets it use the network again.
  Future<void> setOffline({required bool offline}) =>
      _backend.setOffline(offline: offline);

  /// About how many tiles one source of a style needs for [bounds] between
  /// [minZoom] and [maxZoom] — for warning before a download that will be
  /// large or hit the tile limit. A style with several sources needs this
  /// many for each.
  static int estimateTileCount(GeoBounds bounds, int minZoom, int maxZoom) {
    final nw = WebMercator.project(GeoPosition(bounds.north, bounds.west));
    final se = WebMercator.project(GeoPosition(bounds.south, bounds.east));
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final n = 1 << z;
      int tile(double v) => (v * n).floor().clamp(0, n - 1);
      final columns = tile(se.dx) - tile(nw.dx) + 1;
      final rows = tile(se.dy) - tile(nw.dy) + 1;
      total += math.max(0, columns) * math.max(0, rows);
    }
    return total;
  }
}

/// An area's download under way, from [OfflineRegions.download].
final class OfflineDownload {
  OfflineDownload._() {
    _result.future.ignore();
  }

  final StreamController<OfflineProgress> _progress =
      StreamController<OfflineProgress>.broadcast();
  final Completer<OfflineArea> _result = Completer<OfflineArea>();
  final Completer<OfflineArea> _area = Completer<OfflineArea>();
  OfflineArea? _created;
  OfflineProgress? _latest;
  bool _completedEarly = false;

  /// Reports as the download goes. Closes when it ends.
  Stream<OfflineProgress> get progress => _progress.stream;

  /// The most recent report.
  OfflineProgress? get latest => _latest;

  /// The area, as soon as it exists — to pause or delete it while it is
  /// still downloading.
  Future<OfflineArea> get area => _area.future;

  /// The area once everything is downloaded. Fails with an
  /// [OfflineRegionException].
  Future<OfflineArea> get result => _result.future;

  void _onEvent(OfflineRegionEvent event) {
    switch (event) {
      case OfflineRegionProgressed(:final progress):
        _latest = progress;
        if (!_progress.isClosed) _progress.add(progress);
      case OfflineRegionCompleted():
        final done = OfflineProgress(
          fraction: 1,
          completedResources: _latest?.completedResources ?? 0,
          requiredResources: _latest?.requiredResources ?? 0,
          completedBytes: _latest?.completedBytes ?? 0,
          isComplete: true,
        );
        _latest = done;
        if (!_progress.isClosed) _progress.add(done);
        final created = _created;
        if (created == null) {
          // Finished before MapLibre had told us the area's id: finish when
          // it does.
          _completedEarly = true;
        } else {
          _finish(created);
        }
      case OfflineRegionFailed(:final error):
        _fail(error, StackTrace.current);
    }
  }

  void _started(OfflineArea area) {
    _created = area;
    if (!_area.isCompleted) _area.complete(area);
    if (_completedEarly) _finish(area);
  }

  void _finish(OfflineArea area) {
    if (_result.isCompleted) return;
    _result.complete(area);
    unawaited(_progress.close());
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (!_area.isCompleted) {
      _area.completeError(error, stackTrace);
      _area.future.ignore();
    }
    if (_result.isCompleted) return;
    _result.completeError(error, stackTrace);
    unawaited(_progress.close());
  }

  /// Delivers [event] as MapLibre would, for tests of code built on this.
  @visibleForTesting
  void debugEvent(OfflineRegionEvent event) => _onEvent(event);
}
