import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../cli/tiles_exception.dart';
import '../docker/images.dart';
import '../net/fetcher.dart';

/// Builds the official OSM OpenMapTiles style from the openmaptiles
/// repository, as its `make build-style` does.
///
/// The repository keeps the style in pieces: a header, and each schema
/// layer's own `style.json`, whose layers carry an `order`. The merge — take
/// the header's first layer, then every layer of every tileset layer in
/// tileset order, sorted stably by `order`, and drop `order` — is small
/// enough to do here, rather than in the `openmaptiles-tools` image, which is
/// published for amd64 only. The sprite comes from spreet, run separately.
class OmtStyleBuilder {
  /// A builder keeping the repository under [cache], fetched with [fetcher].
  OmtStyleBuilder(this._fetcher, this._cache);

  final Fetcher _fetcher;
  final Directory _cache;

  /// The unpacked repository at the pinned tag, fetched once.
  Future<Directory> repository({void Function()? onDownload}) async {
    final root = Directory(
      p.join(_cache.path, 'openmaptiles', Upstream.openmaptilesTag),
    );
    final done = File(p.join(root.path, '.complete'));
    if (await done.exists()) return root;
    final zip = File(
      p.join(
        _cache.path,
        'downloads',
        'openmaptiles-${Upstream.openmaptilesTag}.zip',
      ),
    );
    if (!await zip.exists()) {
      onDownload?.call();
      await _fetcher.download(Upstream.openmaptilesZip, zip);
    }
    if (await root.exists()) await root.delete(recursive: true);
    final archive = ZipDecoder().decodeStream(InputFileStream(zip.path));
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      // Drop the archive's top folder ("openmaptiles-3.16/"), and keep only
      // what the style needs.
      final parts = entry.name.replaceAll(r'\', '/').split('/');
      if (parts.length < 2) continue;
      final relative = parts.sublist(1).join('/');
      if (!(relative == 'openmaptiles.yaml' ||
          relative.startsWith('style/') ||
          (relative.startsWith('layers/') &&
              (relative.endsWith('.yaml') ||
                  relative.endsWith('style.json'))))) {
        continue;
      }
      final out = File(p.joinAll([root.path, ...relative.split('/')]));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.readBytes() ?? const []);
    }
    await done.writeAsString(Upstream.openmaptilesTag);
    return root;
  }

  /// The merged style of the repository at [root].
  Future<Map<String, Object?>> merge(Directory root) async {
    final header = await _json(
      File(p.join(root.path, 'style', 'style-header.json')),
    );
    final tileset = loadYaml(
      await File(p.join(root.path, 'openmaptiles.yaml')).readAsString(),
    );
    final layerFiles =
        (tileset is YamlMap ? tileset['tileset'] : null) is YamlMap
        ? ((tileset as YamlMap)['tileset'] as YamlMap)['layers']
        : null;
    if (layerFiles is! YamlList) {
      throw const TilesException.config('openmaptiles.yaml lists no layers');
    }

    final layers = <Map<String, Object?>>[];
    for (final entry in layerFiles) {
      final path = entry is YamlMap ? '${entry['file']}' : '$entry';
      final styleFile = File(
        p.join(
          root.path,
          p.dirname(path.replaceAll('/', p.separator)),
          'style.json',
        ),
      );
      if (!await styleFile.exists()) continue;
      final json = await _json(styleFile);
      for (final layer in (json['layers'] as List<Object?>?) ?? const []) {
        if (layer is! Map<String, Object?>) continue;
        if (layer['order'] is! num) {
          throw TilesException.config(
            'Layer "${layer['id']}" in ${styleFile.path} has no order',
          );
        }
        layers.add(layer);
      }
    }
    // Stable: layers of equal order keep the tileset's order.
    final indexed = [for (var i = 0; i < layers.length; i++) (i, layers[i])];
    indexed.sort((a, b) {
      final byOrder = (a.$2['order']! as num).compareTo(b.$2['order']! as num);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    final headerLayers = (header['layers'] as List<Object?>?) ?? const [];
    return {
      ...header,
      'layers': [
        if (headerLayers.isNotEmpty) headerLayers.first,
        for (final (_, layer) in indexed) {...layer}..remove('order'),
      ],
    };
  }

  static Future<Map<String, Object?>> _json(File file) async {
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) {
      throw TilesException.config('${file.path} is not a JSON object');
    }
    return value;
  }
}
