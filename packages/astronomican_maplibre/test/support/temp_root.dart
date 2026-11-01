import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A fresh temporary folder, removed after the test.
Future<Directory> tempRoot() async {
  final dir = await Directory.systemTemp.createTemp('astronomican_maplibre_');
  addTearDown(() async {
    // Windows can take a moment to release handles; try a few times.
    for (var i = 0; i < 5; i++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });
  return dir;
}
