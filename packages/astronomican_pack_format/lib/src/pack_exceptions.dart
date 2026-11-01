/// Something went wrong installing or downloading a map pack.
///
/// Sealed, so an app can tell the cases apart — a manifest from a newer app
/// version wants "please update", a dropped connection wants "try again".
sealed class PackException implements Exception {
  const PackException(this.message);

  /// What went wrong, for a log.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A `pack.json` that does not describe a valid pack.
final class PackManifestException extends PackException {
  /// A manifest problem described by [message].
  const PackManifestException(super.message);
}

/// A pack written in a newer manifest format than this app understands.
final class PackIncompatibleException extends PackException {
  /// A pack in [format], where this app reads up to [supported].
  PackIncompatibleException({required this.format, required this.supported})
    : super(
        'The pack is in format $format; this app reads up to $supported. '
        'Update the app to use it.',
      );

  /// The pack's format.
  final int format;

  /// The newest format this app reads.
  final int supported;
}

/// A file a bundled pack lists is not in the app's bundle.
///
/// Almost always the pubspec: Flutter's asset folders are not recursive, so
/// every subfolder of a pack — each glyph range's family, say — has to be
/// listed on its own line.
final class PackMissingAssetException extends PackException {
  /// The asset [key] could not be loaded.
  PackMissingAssetException(this.key)
    : super(
        'The asset "$key" is not in the bundle. Asset folders are not '
        'recursive: list its folder in the pubspec on its own line.',
      );

  /// The missing asset.
  final String key;
}

/// A file arrived at the wrong size, or with the wrong checksum.
final class PackIntegrityException extends PackException {
  /// [path] failed its check, as [message] says.
  const PackIntegrityException(this.path, String message) : super(message);

  /// The file inside the pack.
  final String path;
}

/// The pack server answered with an error.
final class PackHttpException extends PackException {
  /// [uri] answered with [statusCode].
  PackHttpException(this.uri, this.statusCode)
    : super('$uri answered $statusCode');

  /// What was asked for.
  final Uri uri;

  /// What the server said.
  final int statusCode;
}

/// A download was cancelled. What had arrived is kept for the next attempt.
final class PackCancelledException extends PackException {
  /// A cancelled download.
  const PackCancelledException() : super('The download was cancelled.');
}
