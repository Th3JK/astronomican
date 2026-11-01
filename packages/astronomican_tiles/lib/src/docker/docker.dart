import 'dart:convert';
import 'dart:io';

import '../cli/context.dart';
import '../cli/tiles_exception.dart';

/// What `docker info` says about the engine.
final class DockerInfo {
  /// The engine's facts.
  const DockerInfo({
    required this.architecture,
    required this.memoryBytes,
    required this.rootless,
    required this.selinux,
    required this.operatingSystem,
    required this.composeVersion,
  });

  /// `x86_64` or `aarch64`.
  final String architecture;

  /// Memory available to containers.
  final int memoryBytes;

  /// Rootless mode: files written in containers already belong to the user.
  final bool rootless;

  /// SELinux enforcing: bind mounts need relabelling.
  final bool selinux;

  /// The engine's OS, such as `Docker Desktop`.
  final String operatingSystem;

  /// `docker compose version --short`.
  final String composeVersion;
}

/// Docker, as the tool drives it: always `docker compose` with an explicit
/// project name and file, never a shell.
class Docker {
  /// Docker through [context].
  Docker(this.context);

  /// The context.
  final TilesContext context;

  /// Checks Docker is usable, and describes it.
  ///
  /// Throws [TilesException] with what to do about it: install Docker, start
  /// the daemon, join the docker group, or upgrade Compose.
  Future<DockerInfo> check() async {
    final docker = context.docker;
    ProcessResult version;
    try {
      version = await context.processes.run(docker, ['--version']);
    } on ProcessException {
      throw TilesException.unavailable(
        'Docker is not installed or not on PATH. Install Docker Desktop '
        '(https://docs.docker.com/desktop/) or Docker Engine with the Compose '
        'plugin (https://docs.docker.com/engine/install/).',
      );
    }
    if (version.exitCode != 0) {
      throw TilesException.unavailable(
        '`$docker --version` failed: ${version.stderr}',
      );
    }

    final info = await context.processes.run(docker, [
      'info',
      '--format',
      '{{json .}}',
    ]);
    if (info.exitCode != 0) {
      final err = '${info.stderr}';
      if (err.contains('permission denied')) {
        throw TilesException.unavailable(
          'Docker refused the connection (permission denied). Add yourself to '
          'the docker group — `sudo usermod -aG docker \$USER`, then log in '
          'again — or use rootless Docker.',
        );
      }
      throw TilesException.unavailable(
        'The Docker daemon is not running. Start Docker Desktop, or '
        '`sudo systemctl start docker`.\n$err',
      );
    }
    final Map<String, Object?> json;
    try {
      json = jsonDecode('${info.stdout}'.trim()) as Map<String, Object?>;
    } on FormatException {
      throw TilesException.unavailable(
        'Could not read `docker info`: ${info.stdout}',
      );
    }

    final compose = await context.processes.run(docker, [
      'compose',
      'version',
      '--short',
    ]);
    final composeVersion = '${compose.stdout}'.trim().replaceFirst(
      RegExp('^v'),
      '',
    );
    if (compose.exitCode != 0 || !_atLeast(composeVersion, 2, 17)) {
      throw TilesException.unavailable(
        compose.exitCode != 0
            ? 'Docker Compose v2 is not installed (`docker compose`). The old '
                  '`docker-compose` v1 is not supported.'
            : 'Docker Compose $composeVersion is too old; 2.17 or newer is needed.',
      );
    }

    final security = [
      for (final option
          in (json['SecurityOptions'] as List<Object?>?) ?? const [])
        '$option',
    ];
    return DockerInfo(
      architecture: '${json['Architecture'] ?? ''}',
      memoryBytes: (json['MemTotal'] as num?)?.toInt() ?? 0,
      rootless: security.any((o) => o.contains('rootless')),
      selinux: security.any((o) => o.contains('selinux')),
      operatingSystem: '${json['OperatingSystem'] ?? ''}',
      composeVersion: composeVersion,
    );
  }

  /// The arguments of `docker compose` for [project] from [file].
  static List<String> composeArgs(
    String project,
    File file,
    List<String> args,
  ) => ['compose', '-p', project, '-f', file.absolute.path, ...args];

  /// Runs `docker compose … args` with output to the terminal.
  Future<int> compose(String project, File file, List<String> args) => context
      .processes
      .stream(context.docker, composeArgs(project, file, args));

  /// Runs `docker compose … args` quietly and returns its result.
  Future<ProcessResult> composeQuiet(
    String project,
    File file,
    List<String> args,
  ) => context.processes.run(context.docker, composeArgs(project, file, args));

  /// The user containers run as on Linux and macOS, so what they write
  /// belongs to the user; null on Windows and with rootless Docker, where
  /// that is already so.
  Future<String?> containerUser(DockerInfo info) async {
    if (context.isWindows || info.rootless) return null;
    final uid = await context.processes.run('id', ['-u']);
    final gid = await context.processes.run('id', ['-g']);
    if (uid.exitCode != 0 || gid.exitCode != 0) return null;
    return '${'${uid.stdout}'.trim()}:${'${gid.stdout}'.trim()}';
  }

  static bool _atLeast(String version, int major, int minor) {
    final parts = version
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9].*'), '')) ?? 0)
        .toList();
    if (parts.isEmpty) return false;
    final ma = parts[0];
    final mi = parts.length > 1 ? parts[1] : 0;
    return ma > major || (ma == major && mi >= minor);
  }
}
