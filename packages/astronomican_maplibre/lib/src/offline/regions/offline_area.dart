import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';

/// An area of an online style to keep for offline use.
@immutable
final class OfflineAreaRequest {
  /// Everything [styleUrl] draws inside [bounds], from [minZoom] to
  /// [maxZoom].
  ///
  /// Mind the provider's terms: bulk downloading is exactly what many free
  /// tile servers forbid (OpenStreetMap's own among them). OpenFreeMap and
  /// paid providers allow it.
  const OfflineAreaRequest({
    required this.styleUrl,
    required this.bounds,
    this.minZoom = 0,
    this.maxZoom = 16,
    this.name,
    this.includeIdeographs = false,
    this.metadata = const {},
  });

  /// The style whose sources, sprite and glyphs are downloaded. A URL — the
  /// offline database keys everything by it, so a map using the same URL
  /// later finds the tiles.
  final String styleUrl;

  /// The area.
  final GeoBounds bounds;

  /// The lowest zoom downloaded.
  final double minZoom;

  /// The highest zoom downloaded. Each step up roughly quadruples the tiles.
  final double maxZoom;

  /// A name for a download screen.
  final String? name;

  /// Whether glyphs for Chinese, Japanese and Korean are downloaded too.
  final bool includeIdeographs;

  /// Anything else to keep with the area.
  final Map<String, Object?> metadata;
}

/// An area in MapLibre's offline database.
@immutable
final class OfflineArea {
  /// The area MapLibre knows as [id].
  const OfflineArea({
    required this.id,
    required this.styleUrl,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    this.name,
    this.metadata = const {},
  });

  /// MapLibre's id for the area.
  final int id;

  /// The style it was downloaded for.
  final String styleUrl;

  /// The area.
  final GeoBounds bounds;

  /// The lowest zoom downloaded.
  final double minZoom;

  /// The highest zoom downloaded.
  final double maxZoom;

  /// Its name, if it was given one.
  final String? name;

  /// What was kept with it.
  final Map<String, Object?> metadata;

  @override
  bool operator ==(Object other) => other is OfflineArea && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'OfflineArea($id, ${name ?? styleUrl})';
}

/// How far an area's download has got.
@immutable
final class OfflineProgress {
  /// [completedResources] of [requiredResources] done.
  const OfflineProgress({
    required this.fraction,
    this.completedResources = 0,
    this.requiredResources = 0,
    this.completedBytes = 0,
    this.isComplete = false,
  });

  /// From 0 to 1.
  final double fraction;

  /// Tiles, glyphs and sprites fetched.
  final int completedResources;

  /// Tiles, glyphs and sprites needed. Grows at first, as MapLibre discovers
  /// what the style needs.
  final int requiredResources;

  /// Bytes fetched.
  final int completedBytes;

  /// Whether everything is there.
  final bool isComplete;

  @override
  String toString() =>
      'OfflineProgress(${(fraction * 100).toStringAsFixed(1)}%, '
      '$completedResources/$requiredResources, $completedBytes B)';
}

/// An offline download that did not finish.
final class OfflineRegionException implements Exception {
  /// A failure MapLibre reported as [code].
  const OfflineRegionException(this.code, this.message);

  /// MapLibre's error code.
  final String code;

  /// What it said.
  final String? message;

  /// Whether the area needed more tiles than the offline database allows.
  /// Raise the limit with `OfflineRegions.setTileCountLimit`, or ask for less.
  bool get isTileLimit =>
      code == 'tileCountLimitExceeded' ||
      code == 'mapboxTileCountLimitExceeded';

  @override
  String toString() => 'OfflineRegionException($code: $message)';
}
