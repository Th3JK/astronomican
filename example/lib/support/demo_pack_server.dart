import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// A pack server on the phone itself, so the download demo needs no real one.
///
/// Serves `/strakonice/pack.json` and `/strakonice/style.json` from
/// `assets/remote/strakonice/` — version 2 of the pack — and every other file
/// from the bundled version 1, which is what an unchanged file on a real
/// server would be. Honours HTTP ranges, and is deliberately slow, so progress,
/// cancelling and resuming can be watched.
class DemoPackServer {
  DemoPackServer._(this._server, this._bundle);

  /// Starts a server on a free loopback port.
  static Future<DemoPackServer> start({AssetBundle? bundle}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final demo = DemoPackServer._(server, bundle ?? rootBundle);
    server.listen(demo._handle);
    return demo;
  }

  final HttpServer _server;
  final AssetBundle _bundle;

  /// Bytes per second sent.
  int bytesPerSecond = 256 * 1024;

  /// The manifest of the pack on offer.
  Uri get strakoniceManifest =>
      Uri.parse('http://127.0.0.1:${_server.port}/strakonice/pack.json');

  /// Stops the server.
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final path = Uri.decodeComponent(request.uri.path);
      const prefix = '/strakonice/';
      if (!path.startsWith(prefix) || path.contains('..')) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final name = path.substring(prefix.length);
      final ByteData data;
      try {
        data = await _bundle.load(
          name == 'pack.json' || name == 'style.json'
              ? 'assets/remote/strakonice/$name'
              : 'assets/packs/strakonice/$name',
        );
      } catch (_) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      var start = 0;
      final range = RegExp(
        r'bytes=(\d+)-',
      ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range != null) {
        start = int.parse(range.group(1)!);
        if (start >= bytes.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          return;
        }
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${bytes.length - 1}/${bytes.length}',
          );
      }
      response.contentLength = bytes.length - start;

      const chunk = 16 * 1024;
      final pause = Duration(
        microseconds: (chunk / bytesPerSecond * 1e6).round(),
      );
      for (var at = start; at < bytes.length; at += chunk) {
        response.add(bytes.sublist(at, math.min(at + chunk, bytes.length)));
        await response.flush();
        await Future<void>.delayed(pause);
      }
    } catch (_) {
      // The client went away mid-transfer: exactly what cancel does.
    } finally {
      unawaited(response.close().catchError((_) {}));
    }
  }
}
