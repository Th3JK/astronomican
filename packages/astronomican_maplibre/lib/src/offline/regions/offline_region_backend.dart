import 'offline_area.dart';

/// What happened to a download, as MapLibre reports it.
sealed class OfflineRegionEvent {
  const OfflineRegionEvent();
}

/// The download moved on.
final class OfflineRegionProgressed extends OfflineRegionEvent {
  /// Now at [progress].
  const OfflineRegionProgressed(this.progress);

  /// Where it is.
  final OfflineProgress progress;
}

/// The download finished.
final class OfflineRegionCompleted extends OfflineRegionEvent {
  /// Finished.
  const OfflineRegionCompleted();
}

/// The download stopped with [error].
final class OfflineRegionFailed extends OfflineRegionEvent {
  /// Stopped by [error].
  const OfflineRegionFailed(this.error);

  /// Why.
  final OfflineRegionException error;
}

/// MapLibre's offline database, behind an interface so apps and tests can
/// stand in for it.
abstract interface class OfflineRegionBackend {
  /// Every area in the database.
  Future<List<OfflineArea>> list();

  /// Starts downloading [request], tagged with [metadata], reporting to
  /// [onEvent]. Completes once the area exists, before it has downloaded.
  Future<OfflineArea> download(
    OfflineAreaRequest request,
    Map<String, Object?> metadata,
    void Function(OfflineRegionEvent event) onEvent,
  );

  /// How far area [id] has got.
  Future<OfflineProgress> status(int id);

  /// Pauses area [id]'s download.
  Future<void> pause(int id);

  /// Resumes area [id]'s download.
  Future<void> resume(int id);

  /// Deletes area [id].
  Future<void> delete(int id);

  /// Clears cached tiles that belong to no area.
  Future<void> clearAmbientCache();

  /// Caps how many tiles one area may hold.
  Future<void> setTileCountLimit(int limit);

  /// Stops MapLibre using the network, or lets it again.
  Future<void> setOffline({required bool offline});
}
