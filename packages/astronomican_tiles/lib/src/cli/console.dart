import 'dart:io';

/// Where the tool talks to the user. Tests hand it buffers.
class Console {
  /// A console writing to [out] and [err].
  Console({StringSink? out, StringSink? err, this.verbose = false})
    : out = out ?? stdout,
      err = err ?? stderr;

  /// Normal output.
  final StringSink out;

  /// Warnings and errors.
  final StringSink err;

  /// Whether [detail] prints.
  bool verbose;

  /// Prints [message].
  void info(String message) => out.writeln(message);

  /// Prints [message] only with `--verbose`.
  void detail(String message) {
    if (verbose) out.writeln(message);
  }

  /// Prints a step header.
  void step(String message) => out.writeln('» $message');

  /// Prints [message] as a warning.
  void warn(String message) => err.writeln('warning: $message');

  /// Prints [message] as an error.
  void error(String message) => err.writeln('error: $message');
}
