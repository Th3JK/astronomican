import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import '../../build/map_build.dart';
import '../../config/map_config.dart';
import '../../pack/manifest_writer.dart';
import '../../pack/publisher.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Flags shared by `pack` and `build`.
void addPackFlags(TilesCommand command) {
  command.argParser
    ..addFlag(
      'refresh',
      negatable: false,
      help: 'Fetch a preset or URL style again rather than from the cache.',
    )
    ..addFlag(
      'publish',
      defaultsTo: true,
      help: 'Publish to the output. --no-publish builds .work/pack only.',
    )
    ..addOption('out', help: 'Publish here instead of map.yaml\'s output.')
    ..addOption('split', help: 'Ship files larger than this many MB in pieces.')
    ..addFlag(
      'bump',
      negatable: false,
      help:
          'When the output has this version with other content, raise the '
          'version in map.yaml and publish.',
    )
    ..addFlag(
      'force',
      negatable: false,
      help: 'Replace an output that is not a pack of this id.',
    );
}

/// Assembles the pack and publishes it — the part of `build` after the tiles.
Future<void> packAndPublish(TilesCommand command, MapConfig config) async {
  final results = command.argResults!;
  final context = command.context;
  final build = MapBuild(context, config);
  var manifest = await build.assemble(refresh: results['refresh'] as bool);
  context.console.info(
    'Built ${build.pack.path}: ${manifest.id} v${manifest.version}, '
    '${manifest.files.length} files, '
    '${(manifest.totalBytes / 1048576).toStringAsFixed(1)} MB.',
  );

  final out = results['out'] as String?;
  final output = out == null ? config.output : Directory(out);
  if (!(results['publish'] as bool) || output == null) {
    if (output == null) {
      context.console.info(
        'No output set in map.yaml, so nothing was published. The pack in '
        '${build.pack.path} is also the folder to serve for downloads.',
      );
    }
    return;
  }

  final splitMb =
      int.tryParse(results['split'] as String? ?? '') ?? config.splitMegabytes;
  final splitBytes = splitMb == null ? null : splitMb * 1048576;
  final publisher = const Publisher();
  PublishOutcome outcome;
  try {
    (outcome, manifest) = await publisher.publish(
      pack: build.pack,
      output: output,
      splitBytes: splitBytes,
      force: results['force'] as bool,
    );
  } on VersionConflict catch (conflict) {
    if (!(results['bump'] as bool)) rethrow;
    final version = conflict.published + 1;
    final editor = YamlEditor(await config.file.readAsString())
      ..update(['version'], version);
    await config.file.writeAsString(editor.toString());
    context.console.info('Raised version to $version in ${config.file.path}.');
    final current = MapPackManifest.parse(
      await File(p.join(build.pack.path, 'pack.json')).readAsString(),
    );
    await const ManifestWriter().write(
      build.pack,
      id: current.id,
      version: version,
      style: current.style,
      name: current.name,
      attribution: current.attribution,
      bounds: current.bounds,
      minZoom: current.minZoom,
      maxZoom: current.maxZoom,
    );
    (outcome, manifest) = await publisher.publish(
      pack: build.pack,
      output: output,
      splitBytes: splitBytes,
      force: results['force'] as bool,
    );
  }

  final console = context.console;
  if (outcome == PublishOutcome.upToDate) {
    console.info('${output.path} already has this pack; nothing to publish.');
    return;
  }
  console
    ..info('Published ${manifest.id} v${manifest.version} to ${output.path}.')
    ..info('')
    ..info('pubspec.yaml assets:');
  final prefix = config.assetPrefix ?? _assetPrefix(output);
  for (final line in ManifestWriter.assetLines(manifest, prefix)) {
    console.info('    $line');
  }
}

/// The output's path relative to the app it is in, as the pubspec lists
/// assets: from the nearest folder above holding a pubspec.yaml.
String _assetPrefix(Directory output) {
  var dir = output.absolute;
  while (true) {
    final parent = dir.parent;
    if (File(p.join(parent.path, 'pubspec.yaml')).existsSync()) {
      return p
          .relative(output.absolute.path, from: parent.path)
          .replaceAll(r'\', '/');
    }
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return output.path.replaceAll(r'\', '/');
}

/// Assembles the pack from the tiles and publishes it.
class PackCommand extends TilesCommand {
  /// The command.
  PackCommand() {
    addPackFlags(this);
  }

  @override
  String get name => 'pack';

  @override
  String get description =>
      'Assembles the pack (tiles, style, sprite, glyphs, pack.json) and '
      'publishes it to the output.';

  @override
  String get invocation => '${runner!.executableName} pack [<map>]';

  @override
  Future<int> run() async {
    await packAndPublish(this, MapConfig.load(positional(0, fallback: '.')));
    return ExitCodes.ok;
  }
}
