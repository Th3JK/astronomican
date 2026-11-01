import 'dart:convert';
import 'dart:io';

import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/fakes.dart';

MapConfig _config(String yaml) {
  final dir = tempDir();
  File(p.join(dir.path, 'map.yaml')).writeAsStringSync(yaml);
  return MapConfig.load(dir.path);
}

const _strakonice = '''
id: strakonice
version: 1
area: jihocesky
bounds: [13.8748, 49.2435, 13.9309, 49.2749]
maxZoom: 14
planetiler:
  languages: [cs, en]
''';

void main() {
  group('compose file', () {
    YamlMap render(
      MapConfig config, {
      HostSettings host = const HostSettings(),
      Directory? icons,
      String? cache,
    }) =>
        loadYaml(
              ComposeFile.render(
                config: config,
                work: Directory(
                  cache == null
                      ? '/home/me/map/.work'
                      : r'C:\Users\me\map\.work',
                ),
                cache: Directory(cache ?? '/home/me/.cache/astronomican_tiles'),
                host: host,
                spreetIcons: icons,
              ),
            )
            as YamlMap;

    test('Linux: user, relabelling, pinned images, loopback ports', () {
      final compose = render(
        _config(_strakonice),
        host: const HostSettings(user: '1000:1000', selinux: true),
      );
      expect(compose['name'], 'astronomican-strakonice');
      final services = compose['services'] as YamlMap;
      expect(
        services.keys,
        containsAll(['planetiler', 'tileserver', 'maputnik']),
      );
      expect(services.keys, isNot(contains('spreet')));

      final planetiler = services['planetiler'] as YamlMap;
      expect(planetiler['image'], Images.defaultPlanetiler);
      expect(planetiler['user'], '1000:1000');
      expect(planetiler['profiles'], ['generate']);
      expect(
        planetiler['command'],
        containsAll([
          '--area=jihocesky',
          '--bounds=13.8748,49.2435,13.9309,49.2749',
          '--maxzoom=14',
          '--languages=cs,en',
          '--output=/output/strakonice.mbtiles',
        ]),
      );
      final volume = (planetiler['volumes'] as YamlList).first as YamlMap;
      expect(volume['target'], '/sources');
      expect((volume['bind'] as YamlMap)['selinux'], 'z');

      // Only Maputnik is amd64-only.
      for (final MapEntry(:key, :value) in services.entries) {
        expect(
          (value as YamlMap).containsKey('platform'),
          key == 'maputnik',
          reason: '$key',
        );
      }
      expect((services['tileserver'] as YamlMap)['ports'], [
        '127.0.0.1:8080:8080',
      ]);
      expect((services['maputnik'] as YamlMap)['ports'], [
        '127.0.0.1:8888:8000',
      ]);
    });

    test('Windows: forward-slash paths, no user', () {
      final compose = render(
        _config(_strakonice),
        cache: r'C:\Users\me\AppData\Local\astronomican_tiles\Cache',
      );
      final text = jsonEncode(compose);
      expect(text, isNot(contains(r'\\')));
      expect(text, contains('C:/Users/me/map/.work/tiles'));
      expect(
        (compose['services'] as YamlMap)['planetiler'] as YamlMap,
        isNot(contains('user')),
      );
    });

    test('existing tiles need no Planetiler; OSM OpenMapTiles adds spreet', () {
      final dir = tempDir();
      final config = _config(
        'id: t\nversion: 1\ntiles: ${p.join(dir.path, 'x.mbtiles').replaceAll(r'\', '/')}\n',
      );
      final services =
          render(config, icons: Directory('/icons'))['services'] as YamlMap;
      expect(services.keys, isNot(contains('planetiler')));
      expect(services.keys, contains('spreet'));
    });

    test('a local extract is mounted and read from /osm', () {
      final dir = tempDir();
      final args = Planetiler.arguments(
        _config(
          'id: t\nversion: 1\nosm: ${p.join(dir.path, 'region.osm.pbf').replaceAll(r'\', '/')}\nbounds: [1, 2, 3, 4]\n',
        ),
      );
      expect(args, contains('--osm_path=/osm/region.osm.pbf'));
      expect(args.any((a) => a.startsWith('--area')), isFalse);
    });
  });

  test('the TileServer GL config serves the pack as it is', () {
    final config =
        jsonDecode(TileserverConfig.render(id: 'town', bounds: [1, 2, 3, 4]))
            as Map;
    final paths = (config['options'] as Map)['paths'] as Map;
    expect(paths['mbtiles'], '/pack');
    expect(paths['sprites'], '/pack');
    expect(paths['fonts'], '/data/fonts');
    expect(((config['data'] as Map)['town'] as Map)['mbtiles'], 'town.mbtiles');
    expect(((config['styles'] as Map)['town'] as Map)['style'], 'town.json');
  });

  group('Docker checks say what to do', () {
    Future<Object?> check(
      (int, String, String) Function(String, List<String>) answer,
    ) async {
      final ctx = testContext(processes: FakeProcessRunner(answer));
      try {
        return await Docker(ctx.context).check();
      } on TilesException catch (e) {
        return e;
      }
    }

    test('not installed', () async {
      final e = await check(
        (_, _) => throw const ProcessException('docker', []),
      );
      expect((e! as TilesException).message, contains('not installed'));
      expect((e as TilesException).exitCode, ExitCodes.unavailable);
    });

    test('daemon down, and permission denied', () async {
      final down = await check(
        (_, args) =>
            args.first == 'info' ? (1, '', 'Cannot connect') : (0, '', ''),
      );
      expect((down! as TilesException).message, contains('not running'));
      final denied = await check(
        (_, args) => args.first == 'info'
            ? (1, '', 'permission denied while trying to connect')
            : (0, '', ''),
      );
      expect((denied! as TilesException).message, contains('docker group'));
    });

    test('Compose too old, or missing', () async {
      String info() =>
          jsonEncode({'Architecture': 'x86_64', 'MemTotal': 8 << 30});
      final old = await check(
        (_, args) => switch (args.first) {
          'info' => (0, info(), ''),
          'compose' => (0, 'v2.12.0', ''),
          _ => (0, '', ''),
        },
      );
      expect((old! as TilesException).message, contains('too old'));
      final ok = await check(
        (_, args) => switch (args.first) {
          'info' => (
            0,
            jsonEncode({
              'Architecture': 'aarch64',
              'MemTotal': 8 << 30,
              'SecurityOptions': ['name=seccomp', 'name=rootless'],
            }),
            '',
          ),
          'compose' => (0, '5.5.0\n', ''),
          _ => (0, '', ''),
        },
      );
      final info2 = ok! as DockerInfo;
      expect(info2.composeVersion, '5.5.0');
      expect(info2.rootless, isTrue);
      expect(info2.architecture, 'aarch64');
    });
  });

  test('compose is always called with the project and the file', () {
    expect(
      Docker.composeArgs('astronomican-t', File('/w/docker-compose.yml'), [
        'up',
        '-d',
      ]),
      [
        'compose',
        '-p',
        'astronomican-t',
        '-f',
        File('/w/docker-compose.yml').absolute.path,
        'up',
        '-d',
      ],
    );
  });
}
