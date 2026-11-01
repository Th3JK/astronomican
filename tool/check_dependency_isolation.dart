// Proves the point of splitting astronomican into packages: what an app pulls
// in matches what it asked for. Above all, an app that only draws pictures
// must not carry MapLibre's native SDK.
//
// `pub deps` inside a package reports that package's own graph, dev
// dependencies included, so the check is made from outside: a scratch app is
// resolved against the packages exactly as a consumer would, by path.
//
// Only dart: imports, so it runs anywhere Dart does, Windows included:
//   dart run tool/check_dependency_isolation.dart          # every scenario
//   dart run tool/check_dependency_isolation.dart core     # one by name

import 'dart:convert';
import 'dart:io';

class _Scenario {
  const _Scenario(
    this.name,
    this.packages, {
    required this.flutter,
    this.forbidden = const {},
    this.required = const {},
  });

  final String name;
  final List<String> packages;

  /// Whether the probe is a Flutter app. The pure-Dart packages claim to need
  /// no Flutter, and the only way to test that is a probe with no Flutter SDK
  /// dependency to hide behind.
  final bool flutter;
  final Set<String> forbidden;
  final Set<String> required;
}

const _maplibre = {
  'maplibre_gl',
  'maplibre_gl_platform_interface',
  'maplibre_gl_web',
};
// What only the command-line tools bring. Not `args`, `yaml` or `archive`:
// apps get those anyway, through path_provider (jni, hooks) and maplibre_gl
// (image), so they could not tell a leak from the platform.
const _toolsOnly = {'astronomican_tiles', 'yaml_edit'};
// What only the location package brings: the GPS and compass plugins, which
// an app that never shows the visitor must not carry, nor explain a location
// permission for.
const _sensors = {'astronomican_location', 'geolocator', 'compassx'};

const _scenarios = [
  _Scenario(
    'core',
    ['astronomican'],
    flutter: true,
    forbidden: {
      ..._maplibre,
      ..._toolsOnly,
      ..._sensors,
      'astronomican_maplibre',
    },
  ),
  _Scenario(
    'pack_format',
    ['astronomican_pack_format'],
    flutter: false,
    forbidden: {'flutter', 'sky_engine', 'path_provider', 'crypto'},
  ),
  _Scenario(
    'maplibre',
    ['astronomican_maplibre'],
    flutter: true,
    forbidden: {..._toolsOnly, ..._sensors},
    required: {'maplibre_gl', 'astronomican'},
  ),
  _Scenario(
    'location',
    ['astronomican_location'],
    flutter: true,
    forbidden: {..._maplibre, ..._toolsOnly, 'astronomican_maplibre'},
    required: {'geolocator', 'compassx', 'astronomican'},
  ),
  _Scenario(
    'tiles',
    ['astronomican_tiles'],
    flutter: false,
    forbidden: {'flutter', 'sky_engine', 'path_provider', ..._maplibre},
  ),
];

Future<void> main(List<String> args) async {
  final repo = Directory.fromUri(Platform.script.resolve('..'));
  final chosen = args.isEmpty
      ? _scenarios
      : [
          for (final s in _scenarios)
            if (args.contains(s.name)) s,
        ];
  if (chosen.isEmpty) {
    stderr.writeln(
      'Unknown scenario. Choose from: ${_scenarios.map((s) => s.name).join(', ')}',
    );
    exitCode = 64;
    return;
  }

  var failed = false;
  for (final scenario in chosen) {
    final missing = [
      for (final package in scenario.packages)
        if (!File('${repo.path}/packages/$package/pubspec.yaml').existsSync())
          package,
    ];
    if (missing.isNotEmpty) {
      stdout.writeln('SKIP   ${scenario.name}: no ${missing.join(', ')} yet');
      continue;
    }
    final result = await _run(scenario, repo);
    if (result == null) {
      stdout.writeln('PASS   ${scenario.name}');
    } else {
      failed = true;
      stdout.writeln('FAIL   ${scenario.name}: $result');
    }
  }
  exitCode = failed ? 1 : 0;
}

/// Null when the scenario holds, otherwise what went wrong.
Future<String?> _run(_Scenario scenario, Directory repo) async {
  final work = await Directory.systemTemp.createTemp('astronomican_isolation_');
  try {
    // Absolute, with forward slashes: `D:/projects/...` resolves on Windows
    // and needs no escaping in YAML.
    String path(String package) =>
        Directory('${repo.path}/packages/$package').absolute.path
            .replaceAll(r'\', '/')
            .replaceAll(RegExp('/+'), '/');

    final pubspec = StringBuffer()
      ..writeln('name: isolation_probe')
      ..writeln('publish_to: none')
      ..writeln('environment:')
      ..writeln('  sdk: ^3.9.0')
      ..writeln('dependencies:');
    if (scenario.flutter) {
      pubspec
        ..writeln('  flutter:')
        ..writeln('    sdk: flutter');
    }
    for (final package in scenario.packages) {
      pubspec
        ..writeln('  $package:')
        ..writeln('    path: "${path(package)}"');
    }
    await File('${work.path}/pubspec.yaml').writeAsString(pubspec.toString());

    final tool = scenario.flutter ? 'flutter' : 'dart';
    final get = await Process.run(
      tool,
      ['pub', 'get'],
      workingDirectory: work.path,
      runInShell: Platform.isWindows,
    );
    if (get.exitCode != 0) return 'pub get failed:\n${get.stderr}${get.stdout}';

    final deps = await Process.run(
      tool,
      // No --no-dev: pub refuses it with --json, and the probe has no dev
      // dependencies of its own (a dependency's dev dependencies are never
      // resolved).
      ['pub', 'deps', '--json'],
      workingDirectory: work.path,
      runInShell: Platform.isWindows,
    );
    if (deps.exitCode != 0) return 'pub deps failed:\n${deps.stderr}';
    final json =
        jsonDecode(_jsonPart(deps.stdout as String)) as Map<String, Object?>;
    final names = {
      for (final package in json['packages']! as List<Object?>)
        (package! as Map<String, Object?>)['name']! as String,
    };

    final leaked = scenario.forbidden.intersection(names);
    final absent = scenario.required.difference(names);
    if (leaked.isEmpty && absent.isEmpty) return null;
    return [
      if (leaked.isNotEmpty) 'leaked ${leaked.join(', ')}',
      if (absent.isNotEmpty) 'missing ${absent.join(', ')}',
    ].join('; ');
  } finally {
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  }
}

/// The JSON object in [output], past anything the tool printed before it.
String _jsonPart(String output) => output.substring(output.indexOf('{'));
