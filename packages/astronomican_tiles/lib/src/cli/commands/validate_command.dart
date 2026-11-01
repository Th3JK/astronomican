import 'dart:io';

import '../../pack/pack_validator.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Checks any pack folder — one this tool built, or one assembled by hand.
class ValidateCommand extends TilesCommand {
  /// The command.
  ValidateCommand() {
    argParser.addFlag(
      'strict',
      negatable: false,
      help: 'Treat warnings as errors.',
    );
  }

  @override
  String get name => 'validate';

  @override
  String get description =>
      'Checks a pack folder: manifest, files, sprites, glyphs, no keys left.';

  @override
  String get invocation => '${runner!.executableName} validate <pack-folder>';

  @override
  Future<int> run() async {
    final folder = Directory(positional(0, name: 'pack folder'));
    if (!await folder.exists()) {
      throw TilesException.missing('No folder at ${folder.path}');
    }
    final report = await const PackValidator().validate(folder);
    final console = context.console;
    for (final warning in report.warnings) {
      console.warn(warning);
    }
    for (final error in report.errors) {
      console.error(error);
    }
    final strict = argResults!['strict'] as bool;
    if (report.ok && (!strict || report.warnings.isEmpty)) {
      console.info('${folder.path}: the pack is valid.');
      return ExitCodes.ok;
    }
    return ExitCodes.config;
  }
}
