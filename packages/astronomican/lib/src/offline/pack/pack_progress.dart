import 'package:meta/meta.dart';

/// Where an install or a download has got to.
enum PackPhase {
  /// Reading the manifest and what is installed.
  checking,

  /// Copying files out of the app's bundle.
  copying,

  /// Fetching files from the server.
  downloading,

  /// Finished, and the new version is installed.
  done,

  /// Finished without doing anything: the installed version is as new.
  upToDate,
}

/// A report on an install or a download, for a progress bar.
@immutable
final class PackProgress {
  /// [bytesDone] of [bytesTotal] through the [phase] of installing [packId].
  const PackProgress({
    required this.packId,
    required this.version,
    required this.phase,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.file,
  });

  /// The pack.
  final String packId;

  /// The version being installed, or the one found up to date.
  final int version;

  /// What is happening.
  final PackPhase phase;

  /// How many bytes are in place.
  final int bytesDone;

  /// How many bytes the pack holds.
  final int bytesTotal;

  /// The file being worked on, if any.
  final String? file;

  /// From 0 to 1, or null when there is nothing to measure yet.
  double? get fraction {
    if (phase == PackPhase.done || phase == PackPhase.upToDate) return 1;
    if (bytesTotal <= 0) return null;
    return (bytesDone / bytesTotal).clamp(0, 1).toDouble();
  }

  /// Whether this is the last report.
  bool get isFinished => phase == PackPhase.done || phase == PackPhase.upToDate;

  @override
  String toString() =>
      'PackProgress($packId v$version ${phase.name} $bytesDone/$bytesTotal'
      '${file == null ? '' : ' $file'})';
}
