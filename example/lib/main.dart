import 'dart:async';

import 'package:astronomican_location/astronomican_location.dart';
import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_data.dart';
import 'demo_markers.dart';
import 'demos/downloads_page.dart';
import 'demos/uc1_online_page.dart';
import 'demos/uc2_offline_pack_page.dart';
import 'demos/uc3_overlay_page.dart';
import 'demos/uc4_image_map_page.dart';
import 'demos/uc5_floor_plans_page.dart';
import 'demos/uc6_indoor_page.dart';
import 'support/demo_scope.dart';
import 'support/simulated_walk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The compass reads where the top of the phone points; turned sideways the
  // maps would face a quarter turn off.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final packs = await MapPackManager.open(transport: IoPackTransport());
  // Copy the bundled pack out while the first screen is up, so the first map
  // opens straight away. On every launch after the first this only reads
  // pack.json: the copy happens again only when its version goes up.
  unawaited(
    packs
        .ensureBundled(strakonicePack)
        .then<void>(
          (_) {},
          onError: (Object e) => debugPrint('Could not install the pack: $e'),
        ),
  );
  runApp(AstronomicanDemo(packs: packs));
}

/// The demo app.
class AstronomicanDemo extends StatefulWidget {
  /// The app, installing packs through [packs].
  const AstronomicanDemo({super.key, required this.packs});

  /// The app's pack manager.
  final MapPackManager packs;

  @override
  State<AstronomicanDemo> createState() => _AstronomicanDemoState();
}

class _AstronomicanDemoState extends State<AstronomicanDemo> {
  // Nothing runs until a location button is tapped: a feed starts with the
  // first controller that asks.
  final SimulatedWalk _walk = SimulatedWalk.strakonice();
  final DeviceLocationFeed _device = DeviceLocationFeed();
  bool _simulated = true;

  @override
  void dispose() {
    _walk.dispose();
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DemoScope(
      packs: widget.packs,
      location: _simulated ? _walk : _device,
      child: MaterialApp(
        title: 'Astronomican',
        theme: ThemeData(colorSchemeSeed: DemoColors.navy),
        home: DemoList(
          simulated: _simulated,
          onSimulatedChanged: (value) => setState(() => _simulated = value),
        ),
      ),
    );
  }
}

/// One demo on the list.
class Demo {
  /// A demo called [title], opening [page].
  const Demo(
    this.title,
    this.subtitle,
    this.icon,
    this.page, {
    this.geo = false,
  });

  /// Its name.
  final String title;

  /// What it shows.
  final String subtitle;

  /// Its icon.
  final IconData icon;

  /// Builds its page.
  final WidgetBuilder page;

  /// Whether it needs MapLibre.
  final bool geo;
}

/// Every demo.
final List<Demo> demos = [
  Demo(
    '1 · Online map',
    'An online style or raster tiles, with the walk\'s stops.',
    Icons.public,
    (_) => const OnlineMapPage(),
    geo: true,
  ),
  Demo(
    '2 · Offline pack',
    'A bundled .mbtiles with its own style, copied out once.',
    Icons.offline_pin_outlined,
    (_) => const OfflinePackPage(),
    geo: true,
  ),
  Demo(
    '3 · Image overlay',
    'A picture pinned to the town, over streets or parchment.',
    Icons.layers_outlined,
    (_) => const OverlayPage(),
    geo: true,
  ),
  Demo(
    '4 · Image as the map',
    'A floor plan as the whole map, stops placed by x, y.',
    Icons.image_outlined,
    (_) => const ImageMapPage(),
  ),
  Demo(
    '5 · Floor plans',
    'Several floors and two buildings, with a level selector.',
    Icons.stairs_outlined,
    (_) => const FloorPlansPage(),
  ),
  Demo(
    '6 · Indoor on the map',
    'A building on the offline map: its floors over the streets, or as plans.',
    Icons.meeting_room_outlined,
    (_) => const IndoorPage(),
    geo: true,
  ),
  Demo(
    'Downloads',
    'A newer pack from a server, and offline areas of an online style.',
    Icons.download_outlined,
    (_) => const DownloadsPage(),
  ),
];

/// The list of demos.
class DemoList extends StatelessWidget {
  /// The list, with the choice of a [simulated] walk or the device's GPS.
  const DemoList({super.key, this.simulated = true, this.onSimulatedChanged});

  /// Whether the maps show a simulated walk rather than the device's GPS.
  final bool simulated;

  /// Called when the choice changes.
  final ValueChanged<bool>? onSimulatedChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Astronomican')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (onSimulatedChanged != null)
            SwitchListTile(
              secondary: const Icon(Icons.directions_walk),
              title: const Text('Simulated walk'),
              subtitle: Text(
                simulated
                    ? 'The location button walks the Strakonice stops.'
                    : 'The location button uses this device\'s GPS.',
              ),
              value: simulated,
              onChanged: onSimulatedChanged,
            ),
          for (final demo in demos)
            ListTile(
              leading: Icon(demo.icon),
              title: Text(demo.title),
              subtitle: Text(
                demo.geo && !GeoMap.isSupported
                    ? '${demo.subtitle}\nMapLibre runs on Android and iOS.'
                    : demo.subtitle,
              ),
              isThreeLine: demo.geo && !GeoMap.isSupported,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: demo.page)),
            ),
        ],
      ),
    );
  }
}
