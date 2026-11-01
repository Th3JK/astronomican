import 'dart:io';
import 'dart:typed_data';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'pack_transport.dart';

/// A [PackTransport] over `dart:io`'s [HttpClient], with HTTP range requests
/// for resuming.
///
/// Any static file server works as a pack server: the pack's folder, served
/// as it is, with its `pack.json` at a known URL.
final class IoPackTransport implements PackTransport {
  /// A transport sending [headers] with every request.
  IoPackTransport({
    Map<String, String> headers = const {},
    Duration connectionTimeout = const Duration(seconds: 20),
    HttpClient? client,
  }) : _headers = headers,
       _client = (client ?? HttpClient())
         ..connectionTimeout = connectionTimeout;

  final Map<String, String> _headers;
  final HttpClient _client;

  @override
  Future<Uint8List> fetch(Uri uri) async {
    final response = await _get(uri);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw PackHttpException(uri, response.statusCode);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<PackResponse> open(Uri uri, {int offset = 0}) async {
    var response = await _get(uri, offset: offset);
    if (offset > 0 &&
        response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      // The part on disk is no prefix of what the server has now. Start over.
      await response.drain<void>();
      response = await _get(uri);
    }
    final int start;
    if (response.statusCode == HttpStatus.partialContent) {
      start = _rangeStart(response) ?? offset;
    } else if (response.statusCode == HttpStatus.ok) {
      start = 0;
    } else {
      await response.drain<void>();
      throw PackHttpException(uri, response.statusCode);
    }
    return PackResponse(
      body: response,
      start: start,
      length: response.contentLength >= 0 ? response.contentLength : null,
    );
  }

  /// Closes the client. In-flight downloads fail.
  void close({bool force = false}) => _client.close(force: force);

  Future<HttpClientResponse> _get(Uri uri, {int offset = 0}) async {
    final request = await _client.getUrl(uri);
    _headers.forEach(request.headers.set);
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    return request.close();
  }

  static int? _rangeStart(HttpClientResponse response) {
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = RegExp(r'bytes (\d+)-').firstMatch(range ?? '');
    return match == null ? null : int.parse(match.group(1)!);
  }
}
