import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import '../../build/map_build.dart';
import '../../config/map_config.dart';
import '../../style/presets.dart';
import '../../style/style_converter.dart';
import '../../style/style_forms.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Resolves and checks the map's style, lists the presets, copies a preset
/// out for editing, or brings back a style edited in Maputnik.
class StyleCommand extends TilesCommand {
  /// The command.
  StyleCommand() {
    argParser
      ..addFlag('list', negatable: false, help: 'List the preset styles.')
      ..addFlag(
        'refresh',
        negatable: false,
        help: 'Fetch a preset or URL style again rather than from the cache.',
      )
      ..addFlag(
        'eject',
        negatable: false,
        help:
            'Copy the style and its sprite beside map.yaml to edit, and '
            'point map.yaml at the copy.',
      )
      ..addOption(
        'import',
        help:
            'A style exported from Maputnik, to bring back as the map\'s style.',
      );
  }

  @override
  String get name => 'style';

  @override
  String get description =>
      'Checks the map\'s style; --list, --eject a preset to edit, --import one edited in Maputnik.';

  @override
  String get invocation =>
      '${runner!.executableName} style [<map>] [--list | --eject | --import <file>]';

  @override
  Future<int> run() async {
    final console = context.console;
    final results = argResults!;
    if (results['list'] as bool) {
      for (final preset in StylePreset.values) {
        console.info(
          '${preset.id.padRight(18)} ${preset.url ?? 'built from openmaptiles'}\n'
          '${''.padRight(18)} ${preset.license}',
        );
      }
      return ExitCodes.ok;
    }

    final config = MapConfig.load(positional(0, fallback: '.'));
    final build = MapBuild(context, config);

    final import = results['import'] as String?;
    if (import != null) {
      await importStyle(config, File(import));
      return ExitCodes.ok;
    }

    final loaded = await build.loadStyle(refresh: results['refresh'] as bool);
    final conversion = const StyleConverter().convert(
      loaded,
      id: config.id,
      attribution: config.attribution,
      tilesSource: config.tilesSource,
      otherSources: config.otherSources,
    );

    if (results['eject'] as bool) {
      final target = File(p.join(config.directory.path, 'style.json'));
      if (await target.exists() && StylePreset.find(config.style) == null) {
        throw TilesException.usage(
          'The map already uses its own style (${config.style}).',
        );
      }
      for (final sprite in conversion.sprites) {
        for (final suffix in SpriteRef.suffixes) {
          final bytes = await _read(Uri.parse('${sprite.source}$suffix'));
          if (bytes == null) {
            throw TilesException.missing('No ${sprite.source}$suffix');
          }
          await File(
            p.join(config.directory.path, '${sprite.name}$suffix'),
          ).writeAsBytes(bytes);
        }
      }
      await target.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(conversion.style)}\n',
      );
      await _setStyle(config, 'style.json');
      console.info(
        'Wrote ${target.path} and its sprite, and set style: style.json in '
        'map.yaml. Edit it by hand or with `preview --edit`.',
      );
      return ExitCodes.ok;
    }

    console
      ..info('Style: ${loaded.label}')
      ..info('Font stacks (${conversion.fontStacks.length}):');
    for (final stack in conversion.fontStacks.toList()..sort()) {
      console.info('  $stack');
    }
    for (final sprite in conversion.sprites) {
      console.info('Sprite ${sprite.id}: ${sprite.source}');
    }
    for (final warning in conversion.warnings) {
      console.warn(warning);
    }
    return ExitCodes.ok;
  }

  /// Brings [edited] — a style in browser form, as Maputnik exports it —
  /// back as [config]'s own style file.
  Future<void> importStyle(MapConfig config, File edited) async {
    if (!await edited.exists()) {
      throw TilesException.missing('No file at ${edited.path}');
    }
    final json = jsonDecode(await edited.readAsString());
    if (json is! Map<String, Object?>) {
      throw TilesException.config('${edited.path} is not a style');
    }
    final pack = StyleForms.browserToPack(
      json,
      config.id,
      Uri.parse('http://localhost:${config.previewPort}'),
    );
    final isFile =
        StylePreset.find(config.style) == null &&
        !config.style.startsWith('http');
    final target = File(
      p.join(config.directory.path, isFile ? config.style : 'style.json'),
    );
    await target.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(pack)}\n',
    );
    if (!isFile) await _setStyle(config, 'style.json');
    context.console.info('Wrote ${target.path}.');
  }

  Future<void> _setStyle(MapConfig config, String value) async {
    final editor = YamlEditor(await config.file.readAsString())
      ..update(['style'], value);
    await config.file.writeAsString(editor.toString());
  }

  Future<Uint8List?> _read(Uri uri) async {
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      return await file.exists() ? file.readAsBytes() : null;
    }
    return context.fetcher.get(uri);
  }
}
