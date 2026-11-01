import 'dart:typed_data';

import 'package:meta/meta.dart';

/// How pack files are fetched from a server.
///
/// An interface rather than a hard-wired HTTP client, so an app can route
/// downloads through its own client — with its auth headers, its certificate
/// pinning — and so tests can serve packs from memory. `IoPackTransport` is the
/// plain `dart:io` implementation.
abstract interface class PackTransport {
  /// The whole of [uri]. Used for manifests, which are small.
  Future<Uint8List> fetch(Uri uri);

  /// A stream of [uri]'s bytes from [offset] on, for resuming a download.
  ///
  /// A server that ignores the range sends the whole file; the response's
  /// [PackResponse.start] says which happened.
  Future<PackResponse> open(Uri uri, {int offset = 0});
}

/// A file being received.
@immutable
final class PackResponse {
  /// [body] holds the file from byte [start] on.
  const PackResponse({required this.body, required this.start, this.length});

  /// The bytes.
  final Stream<List<int>> body;

  /// Where in the file [body] begins: the offset asked for, or 0 when the
  /// server sent the whole file instead.
  final int start;

  /// How many bytes [body] holds, when the server said.
  final int? length;
}
