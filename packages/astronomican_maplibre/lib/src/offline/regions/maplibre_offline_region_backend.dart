import 'package:astronomican/astronomican.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'offline_area.dart';
import 'offline_region_backend.dart';

/// [OfflineRegionBackend] on MapLibre's own offline database.
final class MapLibreOfflineRegionBackend implements OfflineRegionBackend {
  /// The database shared by every map in the app.
  const MapLibreOfflineRegionBackend();

  @override
  Future<List<OfflineArea>> list() async => [
    for (final region in await ml.getListOfRegions()) _area(region),
  ];

  @override
  Future<OfflineArea> download(
    OfflineAreaRequest request,
    Map<String, Object?> metadata,
    void Function(OfflineRegionEvent event) onEvent,
  ) async {
    final region = await ml.downloadOfflineRegion(
      ml.OfflineRegionDefinition(
        bounds: ml.LatLngBounds(
          southwest: ml.LatLng(request.bounds.south, request.bounds.west),
          northeast: ml.LatLng(request.bounds.north, request.bounds.east),
        ),
        mapStyleUrl: request.styleUrl,
        minZoom: request.minZoom,
        maxZoom: request.maxZoom,
        includeIdeographs: request.includeIdeographs,
      ),
      metadata: metadata,
      onEvent: (event) {
        switch (event) {
          case ml.InProgress():
            onEvent(
              OfflineRegionProgressed(
                OfflineProgress(
                  // MapLibre reports a percentage.
                  fraction: (event.progress / 100).clamp(0, 1).toDouble(),
                  completedResources: event.completedResourceCount,
                  requiredResources: event.requiredResourceCount,
                  completedBytes: event.completedResourceSize,
                ),
              ),
            );
          case ml.Success():
            onEvent(const OfflineRegionCompleted());
          case ml.Error():
            onEvent(OfflineRegionFailed(_exception(event.cause)));
        }
      },
    );
    return _area(region);
  }

  @override
  Future<OfflineProgress> status(int id) async {
    final status = await ml.getOfflineRegionStatus(id);
    return OfflineProgress(
      fraction: (status.downloadProgress / 100).clamp(0, 1).toDouble(),
      completedResources: status.completedResourceCount,
      requiredResources: status.requiredResourceCount,
      completedBytes: status.completedResourceSize,
      isComplete: status.isComplete,
    );
  }

  @override
  Future<void> pause(int id) => ml.pauseOfflineRegionDownload(id);

  @override
  Future<void> resume(int id) => ml.resumeOfflineRegionDownload(id);

  @override
  Future<void> delete(int id) async => ml.deleteOfflineRegion(id);

  @override
  Future<void> clearAmbientCache() => ml.clearAmbientCache();

  @override
  Future<void> setTileCountLimit(int limit) async =>
      ml.setOfflineTileCountLimit(limit);

  @override
  Future<void> setOffline({required bool offline}) async =>
      ml.setOffline(offline);

  static OfflineArea _area(ml.OfflineRegion region) {
    final d = region.definition;
    final metadata = Map<String, Object?>.from(region.metadata);
    return OfflineArea(
      id: region.id,
      styleUrl: d.mapStyleUrl,
      bounds: GeoBounds(
        south: d.bounds.southwest.latitude,
        west: d.bounds.southwest.longitude,
        north: d.bounds.northeast.latitude,
        east: d.bounds.northeast.longitude,
      ),
      minZoom: d.minZoom,
      maxZoom: d.maxZoom,
      name: metadata['name'] as String?,
      metadata: metadata,
    );
  }

  static OfflineRegionException _exception(PlatformException cause) =>
      OfflineRegionException(cause.code, cause.message);
}
