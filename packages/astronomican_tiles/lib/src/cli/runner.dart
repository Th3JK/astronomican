import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'commands/build_command.dart';
import 'commands/clean_command.dart';
import 'commands/doctor_command.dart';
import 'commands/generate_command.dart';
import 'commands/init_command.dart';
import 'commands/manifest_command.dart';
import 'commands/pack_command.dart';
import 'commands/preview_command.dart';
import 'commands/style_command.dart';
import 'commands/validate_command.dart';
import 'console.dart';
import 'context.dart';
import 'tiles_exception.dart';

/// The `astronomican_tiles` command line.
class TilesRunner extends CommandRunner<int> {
  /// A runner working through [context].
  TilesRunner(TilesContext context)
    : _base = context,
      super(
        'astronomican_tiles',
        'Builds astronomican map packs from OpenStreetMap — OpenMapTiles '
            'vector tiles with Planetiler, any OpenMapTiles style made fully '
            'offline — and previews them, all through Docker Compose.',
      ) {
    argParser
      ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Say more.')
      ..addOption(
        'cache-dir',
        help:
            'The shared cache (fonts, styles, Planetiler sources). Also '
            'ASTRONOMICAN_TILES_CACHE.',
      )
      ..addOption(
        'docker',
        help: 'The docker executable.',
        defaultsTo: 'docker',
      );
    for (final command in <TilesCommand>[
      InitCommand(),
      DoctorCommand(),
      GenerateCommand(),
      StyleCommand(),
      PackCommand(),
      BuildCommand(),
      PreviewCommand(),
      ValidateCommand(),
      ManifestCommand(),
      CleanCommand(),
    ]) {
      addCommand(command);
    }
  }

  final TilesContext _base;

  /// The context commands run with, once the global flags are read.
  late TilesContext context;

  /// The console, before and after the global flags are read.
  Console get console => _base.console;

  @override
  void printUsage() => console.info(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    final cacheDir = topLevelResults['cache-dir'] as String?;
    context = _base.copyWith(
      cache: cacheDir == null ? null : Directory(cacheDir),
      docker: topLevelResults['docker'] as String,
      verbose: topLevelResults['verbose'] as bool,
    );
    return super.runCommand(topLevelResults);
  }

  /// Runs [args], turning failures into messages and exit codes.
  Future<int> execute(List<String> args) async {
    try {
      return await run(args) ?? ExitCodes.ok;
    } on UsageException catch (e) {
      _base.console.err
        ..writeln(e.message)
        ..writeln()
        ..writeln(e.usage);
      return ExitCodes.usage;
    } on TilesException catch (e) {
      _base.console.error(e.message);
      return e.exitCode;
    }
  }
}

/// A command with the runner's context at hand.
abstract class TilesCommand extends Command<int> {
  /// The context.
  TilesContext get context => (runner! as TilesRunner).context;

  @override
  void printUsage() => (runner! as TilesRunner).console.info(usage);

  /// The positional argument at [index], or [fallback].
  String positional(int index, {String? fallback, String? name}) {
    final rest = argResults!.rest;
    if (rest.length > index) return rest[index];
    if (fallback != null) return fallback;
    usageException('Missing ${name ?? 'argument'}.');
  }
}
