import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An [AssetBundle] served from a map of keys to bytes.
///
/// Counts every load by key, which is how a test proves that a relaunch reads
/// a pack's manifest and nothing else. Entries can be replaced between
/// "launches" to stand in for an app update.
class MemoryAssetBundle extends CachingAssetBundle {
  /// A bundle holding [assets].
  MemoryAssetBundle([Map<String, List<int>>? assets]) : _assets = {...?assets};

  final Map<String, List<int>> _assets;

  /// How many times each key has been loaded.
  final Map<String, int> loads = {};

  /// Adds or replaces the asset [key].
  void put(String key, List<int> bytes) => _assets[key] = bytes;

  /// Adds or replaces the asset [key] with [text] in UTF-8.
  void putString(String key, String text) => put(key, utf8.encode(text));

  /// Removes the asset [key].
  void remove(String key) => _assets.remove(key);

  /// How many loads have happened in total.
  int get totalLoads => loads.values.fold(0, (a, b) => a + b);

  @override
  Future<ByteData> load(String key) async {
    loads[key] = (loads[key] ?? 0) + 1;
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  // Never cached: a test that swaps an asset between launches must see the
  // new one.
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      super.loadString(key, cache: false);
}
