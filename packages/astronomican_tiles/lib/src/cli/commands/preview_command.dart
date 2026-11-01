import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../build/map_build.dart';
import '../../config/map_config.dart';
import '../../docker/docker.dart';
import '../../style/presets.dart';
import '../../style/style_forms.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Serves the pack in TileServer GL — exactly the files that ship — and,
/// with `--edit`, Maputnik on the same tiles.
class PreviewCommand extends TilesCommand {
  /// The command.
  PreviewCommand() {
    argParser
      ..addFlag(
        'build',
        defaultsTo: true,
        help:
            'Build the tiles and pack first. --no-build serves .work/pack as it is.',
      )
      ..addFlag(
        'edit',
        negatable: false,
        help:
            'Also start Maputnik; edits come back to the map\'s style file '
            'when the preview stops.',
      )
      ..addFlag('open', negatable: false, help: 'Open the viewer in a browser.')
      ..addFlag(
        'detach',
        negatable: false,
        help: 'Leave the preview running and return.',
      )
      ..addFlag('stop', negatable: false, help: 'Stop a detached preview.');
  }

  @override
  String get name => 'preview';

  @override
  String get description =>
      'Serves the pack in TileServer GL at http://localhost:8080 (and '
      'Maputnik with --edit) until Ctrl+C. Publishes nothing.';

  @override
  String get invocation =>
      '${runner!.executableName} preview [<map>] [--edit] [--open]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final config = MapConfig.load(positional(0, fallback: '.'));
    final build = MapBuild(context, config);
    final docker = Docker(context);
    final console = context.console;
    final edit = results['edit'] as bool;

    final editFile = File(p.join(build.editDirectory.path, 'style.json'));
    final seedFile = File(p.join(build.editDirectory.path, '.seed'));

    if (results['stop'] as bool) {
      if (!await build.composeFile.exists()) {
        console.info('No preview to stop.');
        return ExitCodes.ok;
      }
      await _down(docker, build);
      await _syncBack(config, editFile, seedFile);
      return ExitCodes.ok;
    }

    final ownStyle =
        StylePreset.find(config.style) == null &&
        !config.style.startsWith('http://') &&
        !config.style.startsWith('https://');
    if (edit && !ownStyle) {
      throw const TilesException.usage(
        'Editing needs the map\'s own style file. Run `style --eject` first to '
        'copy the preset beside map.yaml.',
      );
    }

    if (results['build'] as bool) {
      await build.generate();
      await build.assemble();
    } else if (!await File(p.join(build.pack.path, 'pack.json')).exists()) {
      throw const TilesException.missing(
        'No pack in .work yet; drop --no-build.',
      );
    }
    await build.writePreview();

    if (edit) {
      final style =
          jsonDecode(
                await File(
                  p.join(build.pack.path, 'style.json'),
                ).readAsString(),
              )
              as Map<String, Object?>;
      final browser = StyleForms.packToBrowser(
        style,
        config.id,
        Uri.parse('http://localhost:${config.previewPort}'),
      );
      await build.editDirectory.create(recursive: true);
      final seeded = const JsonEncoder.withIndent('  ').convert(browser);
      await editFile.writeAsString(seeded);
      // What Maputnik was given: a stop, now or from `--stop` after
      // `--detach`, saves the style back only if it changed.
      await seedFile.writeAsString(_hash(seeded));
    } else if (await seedFile.exists()) {
      await seedFile.delete();
    }

    await build.prepareDocker();
    await _down(docker, build, quiet: true);
    await _checkPort(config.previewPort, 'preview.port');
    if (edit) await _checkPort(config.editorPort, 'preview.editorPort');

    console.step('Starting TileServer GL${edit ? ' and Maputnik' : ''}');
    final up = await docker.compose(build.project, build.composeFile, [
      '--profile',
      'preview',
      if (edit) ...['--profile', 'edit'],
      'up',
      '-d',
      '--wait',
    ]);
    if (up != 0) throw TilesException('The preview did not start (exit $up).');

    final viewer = build.viewerUrl();
    console
      ..info('')
      ..info('  Map:        $viewer')
      ..info(
        '  Tiles:      http://localhost:${config.previewPort}/data/${config.id}/',
      )
      ..info('  All:        http://localhost:${config.previewPort}/');
    if (edit) {
      console.info('  Editor:     http://localhost:${config.editorPort}/');
    }
    console.info('');
    if (results['open'] as bool) await _open(viewer);

    if (results['detach'] as bool) {
      console.info(
        'Running. Stop it with: astronomican_tiles preview --stop ${config.directory.path}',
      );
      return ExitCodes.ok;
    }

    console.info('Ctrl+C stops the preview.');
    final logs = await context.processes.start(
      context.docker,
      Docker.composeArgs(build.project, build.composeFile, [
        '--profile',
        'preview',
        if (edit) ...['--profile', 'edit'],
        'logs',
        '-f',
      ]),
    );
    final stopped = Completer<bool>();
    final signals = ProcessSignal.sigint.watch().listen((_) {
      if (!stopped.isCompleted) stopped.complete(true);
    });
    unawaited(
      logs.exitCode.then((_) {
        if (!stopped.isCompleted) stopped.complete(false);
      }),
    );
    final interrupted = await stopped.future;
    await signals.cancel();
    logs.kill();
    await _down(docker, build);
    await _syncBack(config, editFile, seedFile);
    return interrupted ? ExitCodes.interrupted : ExitCodes.ok;
  }

  Future<void> _down(
    Docker docker,
    MapBuild build, {
    bool quiet = false,
  }) async {
    final args = [
      '--profile',
      'preview',
      '--profile',
      'edit',
      'down',
      '--remove-orphans',
    ];
    if (quiet) {
      await docker.composeQuiet(build.project, build.composeFile, args);
    } else {
      await docker.compose(build.project, build.composeFile, args);
    }
  }

  /// Writes the style Maputnik edited back to the map's style file, if it
  /// was edited.
  Future<void> _syncBack(MapConfig config, File edited, File seed) async {
    if (!await seed.exists() || !await edited.exists()) return;
    final now = await edited.readAsString();
    final unchanged = _hash(now) == await seed.readAsString();
    await seed.delete();
    if (unchanged) return;
    final json = jsonDecode(now) as Map<String, Object?>;
    final pack = StyleForms.browserToPack(
      json,
      config.id,
      Uri.parse('http://localhost:${config.previewPort}'),
    );
    final target = File(p.join(config.directory.path, config.style));
    await target.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(pack)}\n',
    );
    context.console.info(
      'Saved the edited style to ${target.path}. `pack --bump` publishes it.',
    );
  }

  static String _hash(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static Future<void> _checkPort(int port, String key) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
    } on SocketException {
      throw TilesException.unavailable(
        'Port $port is in use. Stop what uses it, or set $key in map.yaml.',
      );
    }
  }

  Future<void> _open(String url) async {
    final (exe, args) = switch (context.operatingSystem) {
      'windows' => ('cmd', ['/c', 'start', '', url]),
      'macos' => ('open', [url]),
      _ => ('xdg-open', [url]),
    };
    try {
      await context.processes.run(exe, args);
    } on ProcessException {
      // No browser to open; the address is printed anyway.
    }
  }
}
