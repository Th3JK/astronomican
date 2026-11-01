/// A failure the command line reports as a message and an exit code, rather
/// than a stack trace.
class TilesException implements Exception {
  /// A failure described by [message], exiting with [exitCode].
  const TilesException(this.message, {this.exitCode = ExitCodes.failed});

  /// Something the user asked for that does not make sense.
  const TilesException.usage(this.message) : exitCode = ExitCodes.usage;

  /// A map.yaml, style or manifest that is not valid.
  const TilesException.config(this.message) : exitCode = ExitCodes.config;

  /// A file that should be there and is not.
  const TilesException.missing(this.message) : exitCode = ExitCodes.missing;

  /// Docker or the network is not available.
  const TilesException.unavailable(this.message)
    : exitCode = ExitCodes.unavailable;

  /// What went wrong, for the terminal.
  final String message;

  /// The process exit code.
  final int exitCode;

  @override
  String toString() => message;
}

/// Exit codes, after BSD's sysexits.
abstract final class ExitCodes {
  /// Done.
  static const int ok = 0;

  /// A step failed.
  static const int failed = 1;

  /// Bad command line.
  static const int usage = 64;

  /// Bad map.yaml, style or manifest.
  static const int config = 65;

  /// A file that should exist does not.
  static const int missing = 66;

  /// Docker or the network is unavailable.
  static const int unavailable = 69;

  /// Stopped with Ctrl+C.
  static const int interrupted = 130;
}
