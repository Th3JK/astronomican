import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astronomican_tiles/astronomican_tiles.dart';
import 'package:test/test.dart';

/// A fetcher serving from a map, counting requests.
class FakeFetcher implements Fetcher {
  FakeFetcher([Map<String, List<int>>? files]) : files = {...?files};

  final Map<String, List<int>> files;
  final List<String> requests = [];

  void putJson(String url, Object json) =>
      files[url] = utf8.encode(jsonEncode(json));

  @override
  Future<Uint8List?> get(Uri uri) async {
    requests.add('$uri');
    final bytes = files['$uri'];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> download(
    Uri uri,
    File target, {
    String? sha256,
    void Function(int received, int? total)? onProgress,
  }) async {
    final bytes = await get(uri);
    if (bytes == null) throw TilesException.unavailable('$uri answered 404');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
  }
}

/// A process runner answering from a script, recording every command.
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner(this.answer);

  /// Answers a command: its exit code, stdout and stderr. Throw a
  /// [ProcessException] to say the program is not there.
  final (int, String, String) Function(String exe, List<String> args) answer;
  final List<List<String>> commands = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    commands.add([executable, ...arguments]);
    final (code, out, err) = answer(executable, arguments);
    return ProcessResult(0, code, out, err);
  }

  @override
  Future<int> stream(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => (await run(executable, arguments)).exitCode;

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => throw UnimplementedError();
}

/// A context with buffers for output, fakes for the outside, and [cache].
({TilesContext context, StringBuffer out, StringBuffer err}) testContext({
  Fetcher? fetcher,
  ProcessRunner? processes,
  Directory? cache,
  String operatingSystem = 'linux',
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  return (
    context: TilesContext(
      console: Console(out: out, err: err),
      fetcher: fetcher ?? FakeFetcher(),
      processes: processes ?? FakeProcessRunner((_, _) => (0, '', '')),
      cache: cache ?? Directory.systemTemp,
      environment: const {},
      operatingSystem: operatingSystem,
    ),
    out: out,
    err: err,
  );
}

/// A fresh temporary folder, removed after the test.
Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('astronomican_tiles_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

/// A fixture file.
File fixture(String path) => File('test/fixtures/$path');

/// The example app's real Strakonice pack.
Directory get examplePack => Directory('../../example/assets/packs/strakonice');
