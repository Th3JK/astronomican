import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpException;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import '../offline/pack/pack_transport.dart';

/// A pack server in memory.
///
/// Serves whatever has been [put], honours ranges unless told not to, and can
/// drop or stall a transfer partway — everything a resumable download has to
/// survive, without a socket.
class FakePackTransport implements PackTransport {
  /// A server holding [files].
  FakePackTransport([Map<Uri, List<int>>? files]) : _files = {...?files};

  final Map<Uri, List<int>> _files;
  final Map<Uri, int> _dropAfter = {};
  final Map<Uri, (int, Completer<void>)> _stalls = {};

  /// Every request, as the URI and the offset asked for.
  final List<(Uri, int)> requests = [];

  /// Whether ranged requests get just the range. Off, every file is sent
  /// whole, as by a server that does not support ranges.
  bool honourRanges = true;

  /// How many bytes each chunk of a body holds.
  int chunkSize = 1024;

  /// Serves [bytes] at [uri].
  void put(Uri uri, List<int> bytes) => _files[uri] = bytes;

  /// Serves [text] in UTF-8 at [uri].
  void putString(Uri uri, String text) => put(uri, utf8.encode(text));

  /// Removes [uri]; requests for it answer 404.
  void remove(Uri uri) => _files.remove(uri);

  /// Makes the next transfer of [uri] fail after [bytes] bytes of the file,
  /// like a dropped connection.
  void dropAfter(Uri uri, int bytes) => _dropAfter[uri] = bytes;

  /// Makes the next transfer of [uri] pause once [bytes] bytes of the file
  /// have been sent, until the returned completer is completed.
  Completer<void> stallAfter(Uri uri, int bytes) {
    final gate = Completer<void>();
    _stalls[uri] = (bytes, gate);
    return gate;
  }

  /// How many requests were made for [uri].
  int requestsFor(Uri uri) => requests.where((r) => r.$1 == uri).length;

  @override
  Future<Uint8List> fetch(Uri uri) async {
    requests.add((uri, 0));
    final bytes = _files[uri];
    if (bytes == null) throw PackHttpException(uri, 404);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<PackResponse> open(Uri uri, {int offset = 0}) async {
    requests.add((uri, offset));
    final bytes = _files[uri];
    if (bytes == null) throw PackHttpException(uri, 404);
    final start = honourRanges ? math.min(offset, bytes.length) : 0;
    final drop = _dropAfter.remove(uri);
    final stall = _stalls.remove(uri);
    return PackResponse(
      body: _body(bytes, start, drop, stall),
      start: start,
      length: bytes.length - start,
    );
  }

  Stream<List<int>> _body(
    List<int> bytes,
    int start,
    int? drop,
    (int, Completer<void>)? stall,
  ) async* {
    final end = drop == null ? bytes.length : math.min(drop, bytes.length);
    var at = start;
    while (at < end) {
      if (stall != null && at >= stall.$1 && !stall.$2.isCompleted) {
        await stall.$2.future;
      }
      var next = math.min(at + chunkSize, end);
      if (stall != null && at < stall.$1 && next > stall.$1) next = stall.$1;
      yield bytes.sublist(at, next);
      at = next;
      // One chunk per turn of the event loop, like a real socket.
      await Future<void>.delayed(Duration.zero);
    }
    if (drop != null) {
      throw const HttpException('Connection closed while receiving data');
    }
  }
}
