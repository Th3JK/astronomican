import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs other programs — Docker, mostly. An interface so tests can record the
/// commands instead of running them.
abstract interface class ProcessRunner {
  /// Runs [executable] with [arguments] and collects its output.
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });

  /// Runs [executable] with its output going straight to the terminal, and
  /// returns its exit code. Ctrl+C is left to the child.
  Future<int> stream(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });

  /// Starts [executable] with its output going to the terminal, for a
  /// process the caller stops itself.
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

/// [ProcessRunner] on `dart:io`. Always an argument list, never a shell
/// string, so paths with spaces need no quoting on any platform.
class IoProcessRunner implements ProcessRunner {
  /// A runner.
  const IoProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  @override
  Future<int> stream(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final process = await start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    return process.exitCode;
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
}
