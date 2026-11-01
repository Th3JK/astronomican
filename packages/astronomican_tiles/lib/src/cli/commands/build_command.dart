import '../../build/map_build.dart';
import '../../config/map_config.dart';
import '../runner.dart';
import '../tiles_exception.dart';
import 'pack_command.dart';

/// The whole thing: tiles, then the pack, then publishing.
class BuildCommand extends TilesCommand {
  /// The command.
  BuildCommand() {
    addPackFlags(this);
    argParser
      ..addFlag(
        'regenerate',
        negatable: false,
        help: 'Generate the tiles even if up to date.',
      )
      ..addFlag(
        'refresh-osm',
        negatable: false,
        help: 'Download the OpenStreetMap extract again.',
      );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Generates the tiles (if stale), assembles the pack and publishes it.';

  @override
  String get invocation => '${runner!.executableName} build [<map>]';

  @override
  Future<int> run() async {
    final config = MapConfig.load(positional(0, fallback: '.'));
    await MapBuild(context, config).generate(
      force: argResults!['regenerate'] as bool,
      refreshOsm: argResults!['refresh-osm'] as bool,
    );
    await packAndPublish(this, config);
    return ExitCodes.ok;
  }
}
