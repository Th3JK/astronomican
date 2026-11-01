@Tags(['isolation'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The reason this package exists apart from astronomican_maplibre: an app
/// that only draws pictures resolves without MapLibre's native SDK.
///
/// Resolves a scratch app against this package, as a consumer would, through
/// the repository's isolation script. Takes a while; skip it with
/// `flutter test --exclude-tags isolation`.
void main() {
  test('an app using only astronomican resolves without MapLibre', () async {
    final script = File('../../tool/check_dependency_isolation.dart');
    final result = await Process.run('dart', [
      'run',
      script.absolute.path,
      'core',
    ], runInShell: Platform.isWindows);
    expect(
      result.stdout,
      contains('PASS   core'),
      reason: '${result.stdout}\n${result.stderr}',
    );
  });
}
