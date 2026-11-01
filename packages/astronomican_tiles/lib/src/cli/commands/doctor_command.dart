import '../../docker/docker.dart';
import '../../style/presets.dart';
import '../runner.dart';
import '../tiles_exception.dart';

/// Checks everything a build needs, and says what to fix.
class DoctorCommand extends TilesCommand {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Checks Docker, Compose, the cache and the network, and says what to fix.';

  @override
  Future<int> run() async {
    final console = context.console;
    var ok = true;

    try {
      final info = await Docker(context).check();
      console
        ..info(
          '✓ Docker ${info.operatingSystem}, ${info.architecture}, '
          '${(info.memoryBytes / (1 << 30)).toStringAsFixed(1)} GB for containers',
        )
        ..info('✓ Docker Compose ${info.composeVersion}');
      if (info.rootless) console.info('  rootless: files are written as you');
      if (info.selinux) {
        console.info('  SELinux: bind mounts are relabelled (:z)');
      }
      if (info.architecture != 'x86_64' && info.architecture != 'amd64') {
        console.info(
          '  Maputnik (preview --edit) is published for amd64 only and runs '
          'emulated here.',
        );
      }
      if (info.memoryBytes > 0 && info.memoryBytes < 3 * (1 << 30)) {
        console.warn(
          'Docker has less than 3 GB of memory; Planetiler may need more for '
          'a large area (Docker Desktop → Settings → Resources).',
        );
      }
    } on TilesException catch (e) {
      ok = false;
      console.error(e.message);
    }

    console.info('✓ Cache: ${context.cache.path}');

    try {
      final url = StylePreset.osmBright.url!;
      final body = await context.fetcher.get(url);
      if (body == null) throw TilesException.unavailable('$url answered 404');
      console.info('✓ Network: GitHub Pages reachable');
    } on TilesException catch (e) {
      ok = false;
      console.error('Network: ${e.message}');
    }
    return ok ? ExitCodes.ok : ExitCodes.unavailable;
  }
}
