import '../../build/map_build.dart';
import '../../config/map_config.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Generates the map's tiles with Planetiler.
class GenerateCommand extends TilesCommand {
  /// The command.
  GenerateCommand() {
    argParser
      ..addFlag('force', negatable: false, help: 'Generate even if up to date.')
      ..addFlag(
        'refresh-osm',
        negatable: false,
        help: 'Download the OpenStreetMap extract again.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the compose file and command instead of running them.',
      );
  }

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Generates OpenMapTiles-schema tiles from OpenStreetMap with Planetiler.';

  @override
  String get invocation => '${runner!.executableName} generate [<map>]';

  @override
  Future<int> run() async {
    final config = MapConfig.load(positional(0, fallback: '.'));
    final build = MapBuild(context, config);
    final ran = await build.generate(
      force: argResults!['force'] as bool,
      refreshOsm: argResults!['refresh-osm'] as bool,
      dryRun: argResults!['dry-run'] as bool,
    );
    if (ran) context.console.info('Tiles: ${build.tiles.path}');
    return ExitCodes.ok;
  }
}
