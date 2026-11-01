import 'dart:io';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:astronomican_example/demo_data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real Strakonice pack, as the app bundles it — the port of strakonice's
/// map_style_service_test.
///
/// Everything checked here shows up on a device only as a blank map or labels
/// that never appear: a file the pubspec forgot, a placeholder left in the
/// style, a font with no glyphs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('astronomican_example_');
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('installs, and its style resolves to files that exist', () async {
    final packs = MapPackManager(root: root, bundle: rootBundle);
    final pack = await packs.ensureBundled(strakonicePack);

    expect(pack.id, 'strakonice');
    expect(
      await pack.file('strakonice.mbtiles').length(),
      greaterThan(1000000),
    );
    expect(pack.bounds, strakoniceBounds);

    final resolver = PackStyleResolver(pack);
    final style = await resolver.resolve();
    expect(style.startsWith('{'), isTrue);
    expect(await resolver.validate(style), isEmpty);
  });

  test('a second launch copies nothing', () async {
    await MapPackManager(
      root: root,
      bundle: rootBundle,
    ).ensureBundled(strakonicePack);
    final tiles = File('${root.path}/strakonice/v000001/strakonice.mbtiles');
    final stamp = await tiles.lastModified();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await MapPackManager(
      root: root,
      bundle: rootBundle,
    ).ensureBundled(strakonicePack);
    expect(await tiles.lastModified(), stamp);
  });

  test('the server\'s version 2 differs only in its style', () async {
    final v1 = MapPackManifest.parse(
      await rootBundle.loadString(strakonicePack),
    );
    final v2 = MapPackManifest.parse(
      await rootBundle.loadString('assets/remote/strakonice/pack.json'),
    );
    expect(v2.version, greaterThan(v1.version));
    final changed = [
      for (final file in v2.files)
        if (v1.file(file.path)?.sha256 != file.sha256) file.path,
    ];
    expect(changed, ['style.json']);
  });
}
