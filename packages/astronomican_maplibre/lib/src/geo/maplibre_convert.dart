import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'package:astronomican/astronomican.dart';

/// [GeoPosition] as MapLibre's type.
extension GeoPositionToMapLibre on GeoPosition {
  /// This point as a MapLibre `LatLng`.
  ml.LatLng toLatLng() => ml.LatLng(latitude, longitude);
}

/// MapLibre's `LatLng` as a [GeoPosition].
extension LatLngToGeoPosition on ml.LatLng {
  /// This point as a [GeoPosition].
  GeoPosition toGeoPosition() => GeoPosition(latitude, longitude);
}

/// [GeoBounds] as MapLibre's type.
extension GeoBoundsToMapLibre on GeoBounds {
  /// These bounds as MapLibre `LatLngBounds`.
  ml.LatLngBounds toLatLngBounds() => ml.LatLngBounds(
    southwest: southwest.toLatLng(),
    northeast: northeast.toLatLng(),
  );
}

/// MapLibre's `LatLngBounds` as [GeoBounds].
extension LatLngBoundsToGeoBounds on ml.LatLngBounds {
  /// These bounds as [GeoBounds].
  GeoBounds toGeoBounds() => GeoBounds(
    south: southwest.latitude,
    west: southwest.longitude,
    north: northeast.latitude,
    east: northeast.longitude,
  );
}

/// [GeoQuad] as MapLibre's type.
extension GeoQuadToMapLibre on GeoQuad {
  /// This quad as a MapLibre `LatLngQuad`.
  ml.LatLngQuad toLatLngQuad() => ml.LatLngQuad(
    topLeft: topLeft.toLatLng(),
    topRight: topRight.toLatLng(),
    bottomRight: bottomRight.toLatLng(),
    bottomLeft: bottomLeft.toLatLng(),
  );
}
