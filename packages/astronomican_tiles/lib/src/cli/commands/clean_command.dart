import 'dart:io';

import '../../build/map_build.dart';
import '../../config/map_config.dart';
import '../../docker/docker.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Stops the map's containers and removes its work folder.
class CleanCommand extends TilesCommand {
  /// The command.
  CleanCommand() {
    argParser
      ..addFlag(
        'cache',
        negatable: false,
        help:
            'Also empty the shared cache (fonts, styles, Planetiler sources).',
      )
      ..addFlag('dry-run', negatable: false, help: 'Say what would go.');
  }

  @override
  String get name => 'clean';

  @override
  String get description =>
      'Stops the map\'s containers and removes .work; --cache empties the shared cache.';

  @override
  String get invocation => '${runner!.executableName} clean [<map>] [--cache]';

  @override
  Future<int> run() async {
    final config = MapConfig.load(positional(0, fallback: '.'));
    final build = MapBuild(context, config);
    final dryRun = argResults!['dry-run'] as bool;
    final console = context.console;

    final targets = [
      build.work,
      if (argResults!['cache'] as bool) context.cache,
    ];
    for (final target in targets) {
      if (!await target.exists()) continue;
      console.info(
        '${dryRun ? 'Would remove' : 'Removing'} ${target.path} '
        '(${_megabytes(target)} MB)',
      );
    }
    if (dryRun) return ExitCodes.ok;

    if (await build.composeFile.exists()) {
      try {
        await Docker(context).composeQuiet(build.project, build.composeFile, [
          '--profile',
          'preview',
          '--profile',
          'edit',
          'down',
          '--remove-orphans',
        ]);
      } on ProcessException {
        // No Docker: nothing can be running.
      }
    }
    for (final target in targets) {
      if (await target.exists()) await target.delete(recursive: true);
    }
    return ExitCodes.ok;
  }

  static String _megabytes(Directory dir) {
    var bytes = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) bytes += entity.lengthSync();
    }
    return (bytes / 1048576).toStringAsFixed(1);
  }
}
