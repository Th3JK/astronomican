import 'dart:io';

import 'package:astronomican/astronomican.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late IoPackTransport transport;
  final body = List<int>.generate(10000, (i) => i & 0xFF);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/missing') {
        response.statusCode = HttpStatus.notFound;
      } else {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final match = RegExp(r'bytes=(\d+)-').firstMatch(range ?? '');
        if (match != null && request.uri.path != '/norange') {
          final start = int.parse(match.group(1)!);
          response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-${body.length - 1}/${body.length}',
            )
            ..contentLength = body.length - start
            ..add(body.sublist(start));
        } else {
          response
            ..contentLength = body.length
            ..add(body);
        }
      }
      await response.close();
    });
    transport = IoPackTransport();
  });

  tearDown(() async {
    transport.close(force: true);
    await server.close(force: true);
  });

  Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<List<int>> read(PackResponse response) async => [
    await for (final chunk in response.body) ...chunk,
  ];

  test('fetches a whole file', () async {
    expect(await transport.fetch(at('/pack.json')), body);
  });

  test('resumes with a range', () async {
    final response = await transport.open(at('/tiles'), offset: 6000);
    expect(response.start, 6000);
    expect(response.length, 4000);
    expect(await read(response), body.sublist(6000));
  });

  test('reports a server that sends the whole file instead', () async {
    final response = await transport.open(at('/norange'), offset: 6000);
    expect(response.start, 0);
    expect(await read(response), body);
  });

  test('turns an error status into a PackHttpException', () async {
    await expectLater(
      transport.fetch(at('/missing')),
      throwsA(
        isA<PackHttpException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
  });
}
