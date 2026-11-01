import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:path/path.dart' as p;

import '../../style/presets.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Writes a commented `map.yaml` to start a map from.
class InitCommand extends TilesCommand {
  /// The command.
  InitCommand() {
    argParser
      ..addOption('id', help: 'The pack\'s id. Defaults to the folder\'s name.')
      ..addOption('name', help: 'A human name.')
      ..addOption(
        'style',
        help:
            'A preset (${StylePreset.values.map((s) => s.id).join(', ')}), a '
            'path or a URL.',
        defaultsTo: 'osm-bright',
      )
      ..addOption('area', help: 'A Geofabrik id, such as jihocesky or monaco.')
      ..addOption('osm', help: 'A local .osm.pbf instead of an area.')
      ..addOption('tiles', help: 'An existing .mbtiles instead of generating.')
      ..addOption('bounds', help: 'west,south,east,north')
      ..addOption('min-zoom', defaultsTo: '0')
      ..addOption('max-zoom', defaultsTo: '14')
      ..addOption(
        'output',
        help: 'Where `pack` publishes, such as an app\'s assets/packs/<id>.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite an existing map.yaml.',
      );
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Writes a commented map.yaml to start a map from.';

  @override
  String get invocation => '${runner!.executableName} init <folder> [options]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final folder = Directory(positional(0, fallback: '.'));
    final file = File(p.join(folder.path, 'map.yaml'));
    if (await file.exists() && !(results['force'] as bool)) {
      throw TilesException.usage(
        '${file.path} exists. Pass --force to replace it.',
      );
    }
    final id =
        (results['id'] as String?) ??
        p
            .basename(folder.absolute.path)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_.-]+'), '-');
    if (!MapPackManifest.isValidId(id)) {
      throw TilesException.usage('"$id" is not a valid pack id; pass --id.');
    }
    final inputs = [
      'area',
      'osm',
      'tiles',
    ].where((k) => results[k] != null).toList();
    if (inputs.length > 1) {
      throw const TilesException.usage(
        'Give only one of --area, --osm and --tiles.',
      );
    }
    final bounds = results['bounds'] as String?;
    if (bounds != null &&
        bounds.split(',').map(double.tryParse).whereType<double>().length !=
            4) {
      throw const TilesException.usage('--bounds takes west,south,east,north.');
    }
    final input = inputs.isEmpty ? 'area' : inputs.single;
    final value = results[input] as String? ?? 'monaco';
    final output = results['output'] as String?;

    await folder.create(recursive: true);
    await file.writeAsString(
      template(
        id: id,
        name: results['name'] as String?,
        style: results['style'] as String,
        inputKey: input,
        inputValue: value,
        bounds: bounds,
        minZoom: results['min-zoom'] as String,
        maxZoom: results['max-zoom'] as String,
        output: output,
      ),
    );
    context.console
      ..info('Wrote ${file.path}.')
      ..info('')
      ..info('Next:')
      ..info(
        '  astronomican_tiles preview ${folder.path}   # build into .work and look',
      )
      ..info(
        '  astronomican_tiles build ${folder.path}     # ... and publish${output == null ? ' (set output: first)' : ''}',
      );
    return ExitCodes.ok;
  }

  /// The map.yaml text for these answers.
  static String template({
    required String id,
    required String style,
    required String inputKey,
    required String inputValue,
    required String minZoom,
    required String maxZoom,
    String? name,
    String? bounds,
    String? output,
  }) {
    String q(String s) => RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(s)
        ? s
        : '"${s.replaceAll('"', r'\"')}"';
    final b = bounds?.split(',').map((s) => s.trim()).join(', ');
    return '''
# An astronomican map pack, built by astronomican_tiles. Paths are relative to
# this file.
#   astronomican_tiles preview <this folder>   # build into .work and look; publishes nothing
#   astronomican_tiles build <this folder>     # build and publish to output
id: $id
${name == null ? '# name: My map' : 'name: ${q(name)}'}
# Installed apps recopy a bundled pack only when this goes up: bump it for
# every change you publish (`pack --bump` does it for you).
version: 1
# attribution: © OpenMapTiles © OpenStreetMap contributors

# Where the tiles come from — exactly one of:
#   area:  a Geofabrik id (https://download.geofabrik.de), such as jihocesky
#   osm:   a local .osm.pbf (then give bounds)
#   tiles: an existing .mbtiles, used as it is
$inputKey: ${q(inputValue)}
${b == null ? '# bounds: [west, south, east, north]   # clip to this area' : 'bounds: [$b]   # west, south, east, north'}
minZoom: $minZoom
maxZoom: $maxZoom   # at most 15; MapLibre overzooms past it

# A preset — osm-openmaptiles, maptiler-basic, osm-bright, positron,
# dark-matter, fiord-color — or a style.json path or URL. Any style for
# OpenMapTiles-schema tiles works; its sprite and fonts are packed offline.
style: ${q(style)}

glyphs:
  # Glyph ranges always shipped. The ranges the labels need are added.
  ranges: [0-255, 256-511]
  # detect: true
  # Extra font sources, tried before the OpenMapTiles fonts:
  # sources:
  #   - https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf

# planetiler:
#   memory: 2g          # Java heap; must fit in Docker's memory
#   languages: [cs, en] # keep only these name:xx tags

# Where `pack` publishes: an app's asset folder. Nothing is published without it.
${output == null ? '# output: ../../assets/packs/$id' : 'output: ${q(output)}'}
# split: 8              # ship files over 8 MB in pieces

# preview:
#   port: 8080
#   editorPort: 8888
''';
  }
}
