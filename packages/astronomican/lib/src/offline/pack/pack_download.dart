import 'dart:async';

import 'package:meta/meta.dart';

import 'installed_pack.dart';
import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'pack_progress.dart';

/// A pack download under way, from `MapPackManager.download`.
///
/// Cancelling keeps what has arrived: calling `download` again for the same
/// version picks up where this one stopped, file by file and within a file.
final class PackDownload {
  /// A download of the manifest at [url].
  @internal
  PackDownload(this.url) {
    // The result is there for whoever wants it; nobody asking for it must not
    // turn a failed download into an uncaught error.
    _result.future.ignore();
  }

  /// The manifest being downloaded.
  final Uri url;

  final StreamController<PackProgress> _progress =
      StreamController<PackProgress>.broadcast();
  final Completer<InstalledPack> _result = Completer<InstalledPack>();
  PackProgress? _latest;
  bool _cancelled = false;
  void Function()? _abort;

  /// Reports as the download goes. Closes when it ends, however it ends.
  Stream<PackProgress> get progress => _progress.stream;

  /// The most recent report, for a screen that starts listening late.
  PackProgress? get latest => _latest;

  /// The installed pack: the new version, or the one already installed when
  /// it was as new. Fails with a [PackException] — [PackCancelledException]
  /// after [cancel].
  Future<InstalledPack> get result => _result.future;

  /// Whether the download has finished, one way or another.
  bool get isFinished => _result.isCompleted;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Stops the download. What has arrived is kept for the next attempt.
  void cancel() {
    if (_cancelled || isFinished) return;
    _cancelled = true;
    _abort?.call();
  }

  /// Registers how to stop the transfer in flight, or clears it.
  @internal
  set abort(void Function()? abort) => _abort = abort;

  /// Throws [PackCancelledException] once [cancel] has been called.
  @internal
  void checkCancelled() {
    if (_cancelled) throw const PackCancelledException();
  }

  /// Publishes [progress].
  @internal
  void report(PackProgress progress) {
    _latest = progress;
    if (!_progress.isClosed) _progress.add(progress);
  }

  /// Ends the download with [pack].
  @internal
  void complete(InstalledPack pack) {
    if (_result.isCompleted) return;
    _result.complete(pack);
    unawaited(_progress.close());
  }

  /// Ends the download with [error].
  @internal
  void fail(Object error, StackTrace stackTrace) {
    if (_result.isCompleted) return;
    _result.completeError(
      _cancelled ? const PackCancelledException() : error,
      _cancelled ? StackTrace.current : stackTrace,
    );
    unawaited(_progress.close());
  }
}
