import 'dart:math' as math;

import 'package:astronomican/astronomican.dart';
import 'package:flutter/painting.dart';

/// The Strakonice pack as the app bundles it.
const String strakonicePack = 'assets/packs/strakonice/pack.json';

/// The area the Strakonice tileset covers.
const GeoBounds strakoniceBounds = GeoBounds(
  south: 49.243512,
  west: 13.874796,
  north: 49.274931,
  east: 13.930929,
);

/// A stop on the Strakonice town walk.
class TownStop {
  /// Stop [number], [name], at [position].
  const TownStop(this.number, this.name, this.position);

  /// Its place in the walk.
  final int number;

  /// Its name.
  final String name;

  /// Where it is.
  final GeoPosition position;
}

/// The fifteen stops of the Strakonice walk, from the strakonice app.
const List<TownStop> strakoniceStops = [
  TownStop(1, 'Velké náměstí', GeoPosition(49.2610, 13.9032)),
  TownStop(2, 'Radnice', GeoPosition(49.2616, 13.9027)),
  TownStop(3, 'Kostel svaté Markéty', GeoPosition(49.2624, 13.9021)),
  TownStop(4, 'Rennerovy sady', GeoPosition(49.2634, 13.9018)),
  TownStop(5, 'Sokolovská ulice', GeoPosition(49.2629, 13.9051)),
  TownStop(6, 'Hrnčířská ulice', GeoPosition(49.2618, 13.9046)),
  TownStop(7, 'Palackého náměstí', GeoPosition(49.2603, 13.9030)),
  TownStop(8, 'Bavorova ulice', GeoPosition(49.2592, 13.9042)),
  TownStop(9, 'Nábřeží Otavy', GeoPosition(49.2594, 13.9066)),
  TownStop(10, 'Podskalí', GeoPosition(49.2585, 13.9049)),
  TownStop(11, 'Ostrov', GeoPosition(49.2580, 13.9060)),
  TownStop(12, 'Papírenská lávka', GeoPosition(49.2577, 13.9078)),
  TownStop(13, 'Jelenka', GeoPosition(49.2573, 13.9050)),
  TownStop(14, 'Most Jana Palacha', GeoPosition(49.2580, 13.9041)),
  TownStop(15, 'Strakonický hrad', GeoPosition(49.2588, 13.9021)),
];

/// A stop inside a building, placed on a floor plan.
class RoomStop {
  /// Stop [id], [name], on floor [floor] at [x], [y] in the plan's frame.
  const RoomStop(this.id, this.name, this.floor, this.x, this.y);

  /// Its id.
  final int id;

  /// Its name.
  final String name;

  /// The floor's level id.
  final String floor;

  /// Units from the plan's left edge.
  final double x;

  /// Units from the plan's top edge.
  final double y;

  /// Where it stands.
  ImagePosition get position => ImagePosition(x, y);
}

/// A building with its floors and the stops on them.
class Building {
  /// [name], with [floors] from the ground up and [stops] on them.
  const Building(this.id, this.name, this.floors, this.stops);

  /// Its id.
  final String id;

  /// Its name.
  final String name;

  /// Its floors, from the ground up.
  final List<MapLevel> floors;

  /// Its stops.
  final List<RoomStop> stops;
}

MapLevel _floor(
  String id,
  String label,
  String asset,
  double width,
  double height,
  Rect focus, {
  ImageGeoreference? georeference,
}) => MapLevel(
  id: id,
  label: label,
  image: MapImage.asset(asset),
  size: Size(width, height),
  focus: focus,
  georeference: georeference,
  // For the demo the plans are taken as drawn north-up, so the floor plans
  // can turn to face the visitor's heading.
  bearing: 0,
);

/// The Rýmařov museum, from the rymarov app: sizes, focus and stops as its
/// content declares them.
final Building rymarovMuseum = Building(
  'museum',
  'Rýmařov Museum',
  [
    _floor(
      '1',
      '1',
      'assets/floors/rymarov_0.webp',
      2664,
      2048,
      const Rect.fromLTWH(120, 150, 2390, 1480),
    ),
    _floor(
      '2',
      '2',
      'assets/floors/rymarov_1.webp',
      2628,
      2048,
      const Rect.fromLTWH(120, 140, 2370, 1740),
    ),
    _floor(
      '3',
      '3',
      'assets/floors/rymarov_2.webp',
      2664,
      2048,
      const Rect.fromLTWH(270, 340, 1900, 1590),
    ),
  ],
  const [
    RoomStop(101, 'The Rýmařov she-wolf', '1', 528, 885),
    RoomStop(102, 'The name Rýmařov', '1', 942, 885),
    RoomStop(103, 'The German museum', '2', 445, 415),
    RoomStop(104, 'The Czech museum', '2', 895, 415),
    RoomStop(105, "The museum's collections", '2', 445, 725),
    RoomStop(106, 'The earliest finds', '2', 1608, 415),
    RoomStop(107, 'Hrádek', '2', 2122, 415),
    RoomStop(108, 'The medieval town', '2', 1608, 725),
    RoomStop(109, 'The Renaissance town', '2', 445, 1195),
    RoomStop(110, 'The Baroque town', '2', 895, 1195),
    RoomStop(111, 'St Michael the Archangel', '2', 445, 1545),
    RoomStop(112, 'Rýmařov in the 19th century', '2', 1608, 1195),
    RoomStop(113, 'The First World War', '2', 2122, 1195),
    RoomStop(114, 'The Second World War', '2', 1608, 1545),
    RoomStop(115, 'The second half of the 20th century', '2', 2122, 1545),
    RoomStop(116, 'The Flemmich textile factory', '3', 825, 683),
    RoomStop(117, "The Schiel brothers' textile factory", '3', 1635, 683),
    RoomStop(118, 'Mining in the Rýmařov region', '3', 825, 1130),
    RoomStop(119, 'The geology of the Jeseníky region', '3', 1635, 1130),
    RoomStop(120, 'Information centre', '3', 825, 1577),
  ],
);

/// The Hedva textile works, from the rymarov app.
final Building hedvaWorks = Building(
  'hedva',
  'Hedva Český Brokát',
  [
    _floor(
      '1',
      '1',
      'assets/floors/hedva_0.webp',
      2851,
      2048,
      const Rect.fromLTWH(130, 250, 2570, 1640),
    ),
    _floor(
      '2',
      '2',
      'assets/floors/hedva_1.webp',
      2851,
      2048,
      const Rect.fromLTWH(1250, 1490, 1230, 400),
    ),
  ],
  const [
    RoomStop(200, 'Introduction', '1', 350, 1585),
    RoomStop(202, 'The Janovice linen manufactory', '1', 610, 1585),
    RoomStop(203, "The Schiel brothers' textile works", '1', 870, 1585),
    RoomStop(204, 'Hedva', '1', 350, 1755),
    RoomStop(205, 'Hall II', '1', 1950, 500),
    RoomStop(206, 'Fabric', '1', 1717, 1038),
    RoomStop(207, 'The Jacquard loom', '1', 2030, 1038),
    RoomStop(208, 'Brocade', '1', 2343, 1038),
    RoomStop(209, 'Silk', '1', 1717, 1312),
    RoomStop(210, 'A unique shop', '1', 2068, 1730),
    RoomStop(211, 'The necktie', '1', 2302, 1730),
    RoomStop(212, 'The brocade room', '2', 1668, 1690),
    RoomStop(213, 'Fabric samples', '2', 2102, 1690),
  ],
);

/// A made-up placement for use case 6: the Rýmařov museum's plans pinned
/// beside Strakonice's town square, about 70 m across and turned a little —
/// the museum is really a long way away, but this shows floors on the
/// streets with real tiles around them.
///
/// Built from three control points, the way a real plan is calibrated: find
/// three corners of the building on the plan and on a satellite view.
ImageGeoreference demoMuseumGeoreference(Size planSize) {
  const centre = GeoPosition(49.26135, 13.90405);
  const widthMetres = 70.0;
  const turnDegrees = 12.0;

  final metresPerUnit = widthMetres / planSize.width;
  final turn = turnDegrees * math.pi / 180;
  GeoPosition at(double u, double v) {
    // Plan units to metres east and north of the centre, turned.
    final dx = (u - planSize.width / 2) * metresPerUnit;
    final dy = -(v - planSize.height / 2) * metresPerUnit;
    final east = dx * math.cos(turn) - dy * math.sin(turn);
    final north = dx * math.sin(turn) + dy * math.cos(turn);
    return GeoPosition(
      centre.latitude + north / 111320,
      centre.longitude +
          east / (111320 * math.cos(centre.latitude * math.pi / 180)),
    );
  }

  return ImageGeoreference.fromControlPoints([
    (const ImagePosition(0, 0), at(0, 0)),
    (ImagePosition(planSize.width, 0), at(planSize.width, 0)),
    (ImagePosition(0, planSize.height), at(0, planSize.height)),
  ]);
}

/// The museum's floors, pinned to Strakonice by [demoMuseumGeoreference].
///
/// One reference for all three: they are one building, so a point on the
/// ground floor stands over the same point upstairs.
final List<MapLevel> georeferencedMuseumFloors = () {
  final reference = demoMuseumGeoreference(const Size(2664, 2048));
  return [
    for (final floor in rymarovMuseum.floors)
      MapLevel(
        id: floor.id,
        label: floor.label,
        image: floor.image,
        size: floor.size,
        focus: floor.focus,
        georeference: reference,
      ),
  ];
}();
