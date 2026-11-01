import 'dart:convert';
import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Writes the `pack.json` for a folder of map data.
///
/// Every file under the folder is listed with its size and SHA-256. With a
/// split size, files larger than it are cut into numbered pieces for bundling
/// — Flutter reads an asset whole, so a large tileset is better shipped in
/// pieces — and the originals removed unless they are to be kept. Serve the
/// unsplit folder for downloads.
///
/// Running it again over a folder that was split already is safe: pieces
/// listed by the existing `pack.json` stand for their file, and are not listed
/// as files of their own.
final class ManifestWriter {
  /// A writer.
  const ManifestWriter();

  /// Lists [folder] and writes its `pack.json`, returning the manifest.
  ///
  /// Throws [PackManifestException] when the result is not a valid manifest.
  Future<MapPackManifest> write(
    Directory folder, {
    required String id,
    required int version,
    String? style,
    String? name,
    String? attribution,
    List<double>? bounds,
    num? minZoom,
    num? maxZoom,
    int? splitBytes,
    bool keepOriginals = false,
  }) async {
    final previous = await _previous(folder);
    final pieces = <String, List<String>>{
      for (final entry in previous?.files ?? const <PackFileEntry>[])
        if (entry.parts != null &&
            !File(_join(folder, entry.path)).existsSync() &&
            entry.parts!.every(
              (part) => File(_join(folder, part)).existsSync(),
            ))
          entry.path: entry.parts!,
    };
    final pieceNames = {for (final parts in pieces.values) ...parts};

    final paths = <String>{
      for (final entity in folder.listSync(recursive: true))
        if (entity is File) _relative(folder, entity),
    }..removeWhere((path) => !_included(path) || pieceNames.contains(path));
    paths.addAll(pieces.keys);

    final entries = <PackFileEntry>[];
    for (final path in paths.toList()..sort()) {
      final existingParts = pieces[path];
      final sources = [
        for (final piece in existingParts ?? [path]) File(_join(folder, piece)),
      ];
      final size = sources.fold<int>(0, (sum, f) => sum + f.lengthSync());
      final digest = await _sha256(sources);
      var parts = existingParts;
      if (parts == null && splitBytes != null && size > splitBytes) {
        parts = await _split(folder, path, splitBytes);
        if (!keepOriginals) File(_join(folder, path)).deleteSync();
      }
      entries.add(
        PackFileEntry(path: path, size: size, sha256: digest, parts: parts),
      );
    }

    final manifest = MapPackManifest(
      id: id,
      version: version,
      name: name,
      style: style,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      attribution: attribution,
      files: entries,
    )..validate();
    await File(
      p.join(folder.path, 'pack.json'),
    ).writeAsString('${manifest.encode()}\n');
    return manifest;
  }

  /// The pubspec asset lines [manifest] needs, under [prefix]: one per folder
  /// that holds files itself. Flutter's asset folders are not recursive, and
  /// a folder holding only folders adds nothing.
  static List<String> assetLines(MapPackManifest manifest, String prefix) {
    final folders = <String>{
      '',
      for (final entry in manifest.files)
        for (final path in entry.parts ?? [entry.path])
          path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '',
    };
    final base = prefix.endsWith('/')
        ? prefix.substring(0, prefix.length - 1)
        : prefix;
    return [
      for (final folder in folders.toList()..sort())
        '- ${folder.isEmpty ? base : '$base/$folder'}/',
    ];
  }

  static Future<MapPackManifest?> _previous(Directory folder) async {
    final file = File(p.join(folder.path, 'pack.json'));
    if (!await file.exists()) return null;
    try {
      return MapPackManifest.parse(await file.readAsString());
    } on PackManifestException {
      return null;
    }
  }

  static bool _included(String relative) {
    if (relative == 'pack.json') return false;
    // Hidden files and anything in a hidden folder: .DS_Store, .git.
    return !relative.split('/').any((segment) => segment.startsWith('.'));
  }

  static Future<String> _sha256(List<File> files) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    for (final file in files) {
      await for (final chunk in file.openRead()) {
        input.add(chunk);
      }
    }
    input.close();
    return output.value.toString();
  }

  static Future<List<String>> _split(
    Directory folder,
    String relative,
    int pieceSize,
  ) async {
    final parts = <String>[];
    final input = await File(_join(folder, relative)).open();
    try {
      var index = 0;
      while (true) {
        final chunk = await input.read(pieceSize);
        if (chunk.isEmpty) break;
        final name = '$relative.${index.toString().padLeft(3, '0')}';
        await File(_join(folder, name)).writeAsBytes(chunk);
        parts.add(name);
        index++;
      }
    } finally {
      await input.close();
    }
    return parts;
  }

  static String _relative(Directory folder, File file) =>
      p.relative(file.path, from: folder.path).split(p.separator).join('/');

  static String _join(Directory folder, String relative) =>
      p.joinAll([folder.path, ...relative.split('/')]);
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// The canonical JSON of [value]: keys sorted, no whitespace. For comparing
/// styles and manifests by content.
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  final Map<String, Object?> map => {
    for (final key in map.keys.toList()..sort()) key: _sorted(map[key]),
  },
  final List<Object?> list => [for (final item in list) _sorted(item)],
  _ => value,
};
