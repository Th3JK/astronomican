import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../cli/tiles_exception.dart';

/// Fetches things over HTTP. An interface so tests serve from memory.
abstract interface class Fetcher {
  /// The body of [uri], or null for a 404.
  Future<Uint8List?> get(Uri uri);

  /// Streams [uri] into [target], through a `.part` file renamed into place,
  /// reporting progress to [onProgress]. Checks [sha256] when given.
  Future<void> download(
    Uri uri,
    File target, {
    String? sha256,
    void Function(int received, int? total)? onProgress,
  });
}

/// [Fetcher] on `dart:io`'s [HttpClient], which follows redirects and honours
/// the `HTTP(S)_PROXY` environment variables.
class IoFetcher implements Fetcher {
  /// A fetcher.
  IoFetcher() : _client = HttpClient() {
    _client
      ..userAgent = 'astronomican_tiles'
      ..findProxy = HttpClient.findProxyFromEnvironment
      ..connectionTimeout = const Duration(seconds: 30);
  }

  final HttpClient _client;

  @override
  Future<Uint8List?> get(Uri uri) async {
    final response = await _open(uri);
    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    _check(uri, response);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<void> download(
    Uri uri,
    File target, {
    String? sha256,
    void Function(int received, int? total)? onProgress,
  }) async {
    final response = await _open(uri);
    _check(uri, response);
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    final total = response.contentLength >= 0 ? response.contentLength : null;
    var received = 0;
    final digest = _DigestSink();
    final hash = sha256 == null ? null : _sha256.startChunkedConversion(digest);
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        hash?.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    if (hash != null) {
      hash.close();
      if (digest.value.toString() != sha256) {
        await part.delete();
        throw TilesException(
          '$uri did not match its checksum; the download is corrupt or the '
          'file has changed upstream.',
        );
      }
    }
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
  }

  static final _sha256 = sha256;

  Future<HttpClientResponse> _open(Uri uri) async {
    try {
      final request = await _client.getUrl(uri);
      return await request.close();
    } on SocketException catch (e) {
      throw TilesException.unavailable('Could not reach $uri: ${e.message}');
    } on HttpException catch (e) {
      throw TilesException.unavailable('Could not fetch $uri: ${e.message}');
    }
  }

  void _check(Uri uri, HttpClientResponse response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    unawaited(response.drain<void>());
    throw TilesException.unavailable('$uri answered ${response.statusCode}');
  }

  /// Closes the client.
  void close() => _client.close(force: true);
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
