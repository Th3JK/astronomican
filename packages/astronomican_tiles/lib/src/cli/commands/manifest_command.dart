import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:path/path.dart' as p;

import '../../pack/manifest_writer.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Writes the `pack.json` for a folder assembled by hand — what
/// `astronomican:pack_manifest` did.
class ManifestCommand extends TilesCommand {
  /// The command.
  ManifestCommand() {
    argParser
      ..addOption(
        'id',
        help: 'The pack\'s id (lowercase letters, digits, _ . -).',
      )
      ..addOption(
        'version',
        help: 'Its version; bump it whenever anything changes.',
      )
      ..addOption('style', help: 'The style document inside the folder.')
      ..addOption('name', help: 'A human name.')
      ..addOption('attribution', help: 'The credit the data asks for.')
      ..addOption('bounds', help: 'The area covered: west,south,east,north.')
      ..addOption('min-zoom', help: 'The lowest zoom the tiles are cut for.')
      ..addOption('max-zoom', help: 'The highest zoom the tiles are cut for.')
      ..addOption(
        'split',
        help: 'Cut files larger than this many MB into pieces.',
      )
      ..addFlag(
        'keep-originals',
        negatable: false,
        help: 'Keep the files that were split.',
      )
      ..addOption(
        'asset-prefix',
        help: 'The folder\'s asset path, for the pubspec lines.',
      );
  }

  @override
  String get name => 'manifest';

  @override
  String get description =>
      'Writes pack.json for a folder of map data: every file with its size '
      'and SHA-256.';

  @override
  String get invocation =>
      '${runner!.executableName} manifest <folder> --id <id> --version <n>';

  @override
  Future<int> run() async {
    final folder = Directory(positional(0, name: 'folder'));
    if (!await folder.exists()) {
      throw TilesException.missing('No folder at ${folder.path}');
    }
    final results = argResults!;
    final id = results['id'] as String? ?? usageException('--id is required.');
    final version =
        int.tryParse(results['version'] as String? ?? '') ??
        usageException('--version must be a whole number.');
    num? number(String key) {
      final value = results[key] as String?;
      if (value == null) return null;
      return num.tryParse(value) ?? usageException('--$key must be a number.');
    }

    final boundsText = results['bounds'] as String?;
    final bounds = boundsText?.split(',').map(double.tryParse).toList();
    if (bounds != null && (bounds.length != 4 || bounds.contains(null))) {
      usageException('--bounds takes west,south,east,north.');
    }
    final split = number('split');

    final MapPackManifest manifest;
    try {
      manifest = await const ManifestWriter().write(
        folder,
        id: id,
        version: version,
        style: results['style'] as String?,
        name: results['name'] as String?,
        attribution: results['attribution'] as String?,
        bounds: bounds?.cast<double>(),
        minZoom: number('min-zoom'),
        maxZoom: number('max-zoom'),
        splitBytes: split == null ? null : (split * 1048576).round(),
        keepOriginals: results['keep-originals'] as bool,
      );
    } on PackManifestException catch (e) {
      throw TilesException.config(e.message);
    }

    final console = context.console;
    final total = manifest.totalBytes;
    console
      ..info(
        'Wrote pack.json: $id v$version, ${manifest.files.length} files, '
        '${(total / 1048576).toStringAsFixed(1)} MB.',
      )
      ..info('')
      ..info('pubspec.yaml assets:');
    final prefix =
        results['asset-prefix'] as String? ??
        p.posix.normalize(folder.path.replaceAll(r'\', '/'));
    for (final line in ManifestWriter.assetLines(manifest, prefix)) {
      console.info('    $line');
    }
    console
      ..info('')
      ..info(
        'Bump --version whenever anything in the pack changes: installed apps '
        'recopy the pack only when the version goes up.',
      );
    return ExitCodes.ok;
  }
}
