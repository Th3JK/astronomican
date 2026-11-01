import '../offline/regions/offline_area.dart';
import '../offline/regions/offline_region_backend.dart';

/// MapLibre's offline database, in memory.
///
/// Downloads start and stay at 0% until the test moves them along with
/// [progress], [complete] or [fail] — so a download screen can be tested at
/// every stage.
class FakeOfflineRegionBackend implements OfflineRegionBackend {
  /// An empty database.
  FakeOfflineRegionBackend();

  final Map<int, OfflineArea> _areas = {};
  final Map<int, void Function(OfflineRegionEvent)> _listeners = {};
  final Map<int, OfflineProgress> _status = {};
  int _nextId = 1;

  /// Areas paused and not resumed.
  final Set<int> paused = {};

  /// The tile limit last set.
  int? tileCountLimit;

  /// Whether the maps were last set offline.
  bool offline = false;

  /// How many times the ambient cache was cleared.
  int ambientCacheClears = 0;

  /// Every area in the database.
  Iterable<OfflineArea> get areas => _areas.values;

  /// Reports area [id] at [fraction].
  void progress(int id, double fraction, {int required = 100}) {
    final p = OfflineProgress(
      fraction: fraction,
      completedResources: (required * fraction).round(),
      requiredResources: required,
      completedBytes: (required * fraction * 1000).round(),
    );
    _status[id] = p;
    _listeners[id]?.call(OfflineRegionProgressed(p));
  }

  /// Finishes area [id].
  void complete(int id) {
    final last = _status[id];
    _status[id] = OfflineProgress(
      fraction: 1,
      completedResources: last?.requiredResources ?? 0,
      requiredResources: last?.requiredResources ?? 0,
      isComplete: true,
    );
    _listeners.remove(id)?.call(const OfflineRegionCompleted());
  }

  /// Fails area [id] with MapLibre's error [code].
  void fail(int id, String code, [String? message]) {
    _listeners
        .remove(id)
        ?.call(OfflineRegionFailed(OfflineRegionException(code, message)));
  }

  @override
  Future<List<OfflineArea>> list() async => _areas.values.toList();

  @override
  Future<OfflineArea> download(
    OfflineAreaRequest request,
    Map<String, Object?> metadata,
    void Function(OfflineRegionEvent event) onEvent,
  ) async {
    final id = _nextId++;
    final area = OfflineArea(
      id: id,
      styleUrl: request.styleUrl,
      bounds: request.bounds,
      minZoom: request.minZoom,
      maxZoom: request.maxZoom,
      name: request.name,
      metadata: metadata,
    );
    _areas[id] = area;
    _listeners[id] = onEvent;
    _status[id] = const OfflineProgress(fraction: 0);
    return area;
  }

  @override
  Future<OfflineProgress> status(int id) async =>
      _status[id] ?? const OfflineProgress(fraction: 0);

  @override
  Future<void> pause(int id) async => paused.add(id);

  @override
  Future<void> resume(int id) async => paused.remove(id);

  @override
  Future<void> delete(int id) async {
    _areas.remove(id);
    _listeners.remove(id);
    _status.remove(id);
  }

  @override
  Future<void> clearAmbientCache() async => ambientCacheClears++;

  @override
  Future<void> setTileCountLimit(int limit) async => tileCountLimit = limit;

  @override
  Future<void> setOffline({required bool offline}) async =>
      this.offline = offline;
}
