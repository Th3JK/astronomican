import 'dart:io';

import '../config/cache_dir.dart';
import '../net/fetcher.dart';
import '../process/process_runner.dart';
import 'console.dart';

/// Everything a command reaches outside itself: the terminal, other
/// programs, the network, the cache and the platform. Tests hand in fakes.
class TilesContext {
  /// A context; unset parts are the real ones.
  TilesContext({
    Console? console,
    ProcessRunner? processes,
    Fetcher? fetcher,
    Directory? cache,
    Map<String, String>? environment,
    String? operatingSystem,
    this.docker = 'docker',
  }) : console = console ?? Console(),
       processes = processes ?? const IoProcessRunner(),
       fetcher = fetcher ?? IoFetcher(),
       environment = environment ?? Platform.environment,
       operatingSystem = operatingSystem ?? Platform.operatingSystem,
       cache =
           cache ??
           defaultCacheDirectory(
             environment: environment,
             operatingSystem: operatingSystem,
           );

  /// Where messages go.
  final Console console;

  /// How programs are run.
  final ProcessRunner processes;

  /// How things are fetched.
  final Fetcher fetcher;

  /// The shared cache.
  final Directory cache;

  /// The environment variables.
  final Map<String, String> environment;

  /// `windows`, `macos`, `linux`…
  final String operatingSystem;

  /// The docker executable.
  final String docker;

  /// Whether this is Windows.
  bool get isWindows => operatingSystem == 'windows';

  /// A copy with other [cache] or [docker].
  TilesContext copyWith({Directory? cache, String? docker, bool? verbose}) {
    if (verbose != null) console.verbose = verbose;
    return TilesContext(
      console: console,
      processes: processes,
      fetcher: fetcher,
      cache: cache ?? this.cache,
      environment: environment,
      operatingSystem: operatingSystem,
      docker: docker ?? this.docker,
    );
  }
}
