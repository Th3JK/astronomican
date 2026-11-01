import 'dart:convert';
import 'dart:io';

import 'package:astronomican_pack_format/astronomican_pack_format.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../glyphs/glyph_pbf.dart';

/// What a pack check found.
final class ValidationReport {
  /// Problems that would break the map on a device.
  final List<String> errors = [];

  /// Things worth a look that do not break it.
  final List<String> warnings = [];

  /// Whether the pack is fit to ship.
  bool get ok => errors.isEmpty;
}

/// Checks a pack folder the way a device would use it — and more strictly,
/// because on a device every one of these failures shows only as a blank map,
/// missing icons, or labels that never appear.
///
/// * `pack.json` parses, and every file it lists is there, at its size and
///   checksum (a split file counts through its pieces).
/// * Every `pack://` in the style names a file of the pack.
/// * Each sprite has all four files: MapLibre asks for `@2x` on high-density
///   screens.
/// * Every font stack the style can ask for has a folder with the same set of
///   ranges, `0-255` among them, and every range file decodes. A missing
///   range makes MapLibre wait forever with the labels of the whole tile.
/// * Nothing carries a key or an unfilled `___PLACEHOLDER___`.
class PackValidator {
  /// A validator.
  const PackValidator();

  static final RegExp _secret = RegExp(
    r'[?&](key|access_token|api_key|apikey)=',
  );

  /// Checks the pack in [folder].
  Future<ValidationReport> validate(Directory folder) async {
    final report = ValidationReport();
    final manifestFile = File(p.join(folder.path, 'pack.json'));
    if (!await manifestFile.exists()) {
      report.errors.add('no pack.json in ${folder.path}');
      return report;
    }
    final MapPackManifest manifest;
    try {
      manifest = MapPackManifest.parse(await manifestFile.readAsString());
    } on PackManifestException catch (e) {
      report.errors.add('pack.json: ${e.message}');
      return report;
    }

    // Files.
    final listed = <String>{'pack.json'};
    for (final entry in manifest.files) {
      listed.add(entry.path);
      final parts = entry.parts;
      final whole = _file(folder, entry.path);
      final List<File> sources;
      if (await whole.exists()) {
        sources = [whole];
      } else if (parts != null) {
        listed.addAll(parts);
        sources = [for (final part in parts) _file(folder, part)];
        final missing = [
          for (final part in parts)
            if (!await _file(folder, part).exists()) part,
        ];
        if (missing.isNotEmpty) {
          report.errors.add(
            '${entry.path}: missing pieces ${missing.join(', ')}',
          );
          continue;
        }
      } else {
        report.errors.add('${entry.path}: listed in pack.json but not there');
        continue;
      }
      var size = 0;
      for (final source in sources) {
        size += await source.length();
      }
      if (size != entry.size) {
        report.errors.add(
          '${entry.path}: $size bytes, pack.json says ${entry.size}',
        );
        continue;
      }
      if (entry.sha256 != null && await _sha256(sources) != entry.sha256) {
        report.errors.add('${entry.path}: does not match its checksum');
      }
    }
    await for (final entity in folder.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = _relative(folder, entity);
      if (relative.split('/').any((s) => s.startsWith('.'))) continue;
      if (!listed.contains(relative)) {
        report.warnings.add('$relative is not listed in pack.json');
      }
    }

    // Style.
    final stylePath = manifest.stylePath;
    if (stylePath == null) {
      report.warnings.add('the pack has no style.json');
      return report;
    }
    final Map<String, Object?> style;
    try {
      final text = await _read(folder, stylePath, manifest);
      final json = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
      if (json is! Map<String, Object?>) {
        throw const FormatException('not an object');
      }
      style = json;
    } on FormatException catch (e) {
      report.errors.add('$stylePath: not a style (${e.message})');
      return report;
    }

    bool present(String relative) =>
        listed.contains(relative) || _file(folder, relative).existsSync();

    for (final s in PackStyle.strings(_withoutMetadata(style))) {
      if (_secret.hasMatch(s)) {
        report.errors.add('$stylePath carries a key: $s');
      }
      if (PackStyle.placeholderPattern.hasMatch(s)) {
        report.errors.add('$stylePath has an unfilled placeholder: $s');
      }
    }

    // Sources and other files named by pack://.
    for (final source
        in ((style['sources'] as Map<String, Object?>?) ?? {}).values) {
      if (source is! Map<String, Object?>) continue;
      for (final value in [
        source['url'],
        source['data'],
        ...?(source['tiles'] as List?),
      ]) {
        if (value is! String) continue;
        final relative = PackStyle.relativePath(value);
        if (relative != null && !present(relative)) {
          report.errors.add(
            '$stylePath names pack://$relative, which is not in the pack',
          );
        }
      }
    }

    // Sprites.
    final sprite = style['sprite'];
    final sprites = <String>[
      if (sprite is String) sprite,
      if (sprite is List)
        for (final e in sprite)
          if (e is Map && e['url'] is String) e['url'] as String,
    ];
    for (final url in sprites) {
      final relative = PackStyle.relativePath(url);
      if (relative == null) {
        report.warnings.add('the sprite is online: $url');
        continue;
      }
      for (final suffix in const ['.json', '.png', '@2x.json', '@2x.png']) {
        if (!present('$relative$suffix')) {
          report.errors.add('sprite: no $relative$suffix');
        }
      }
    }

    // Glyphs.
    final glyphs = style['glyphs'];
    final stacks = PackStyle.fontStacks(style, includeDefault: true);
    if (stacks.isNotEmpty && glyphs is! String) {
      report.errors.add('$stylePath has labels but no glyphs');
    } else if (glyphs is String && stacks.isNotEmpty) {
      final relative = PackStyle.relativePath(glyphs);
      if (relative == null) {
        report.warnings.add('the glyphs are online: $glyphs');
      } else if (!relative.endsWith('{fontstack}/{range}.pbf')) {
        report.errors.add(
          'glyphs must end in {fontstack}/{range}.pbf: $glyphs',
        );
      } else {
        final base = relative.substring(
          0,
          relative.length - '{fontstack}/{range}.pbf'.length,
        );
        await _checkGlyphs(folder, base, stacks, report);
      }
    }
    return report;
  }

  Future<void> _checkGlyphs(
    Directory folder,
    String base,
    Set<String> stacks,
    ValidationReport report,
  ) async {
    Set<String>? reference;
    String? referenceStack;
    for (final stack in stacks.toList()..sort()) {
      final dir = Directory(
        p.joinAll([folder.path, ...'$base$stack'.split('/')]),
      );
      if (!await dir.exists()) {
        report.errors.add('font stack "$stack": no folder $base$stack/');
        continue;
      }
      final ranges = <String>{};
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.pbf')) continue;
        final name = p.basenameWithoutExtension(entity.path);
        try {
          GlyphRange.parse(name);
          GlyphPbf.decode(await entity.readAsBytes());
          ranges.add(name);
        } on FormatException catch (e) {
          report.errors.add(
            'font stack "$stack": $name.pbf is broken (${e.message})',
          );
        }
      }
      if (!ranges.contains('0-255')) {
        report.errors.add('font stack "$stack": no 0-255.pbf');
      }
      if (reference == null) {
        reference = ranges;
        referenceStack = stack;
      } else if (reference.length != ranges.length ||
          !reference.containsAll(ranges)) {
        report.errors.add(
          'font stacks "$referenceStack" and "$stack" ship different ranges; '
          'a label in a range one of them lacks never draws',
        );
      }
    }
  }

  static File _file(Directory folder, String relative) =>
      File(p.joinAll([folder.path, ...relative.split('/')]));

  static String _relative(Directory folder, File file) =>
      p.relative(file.path, from: folder.path).split(p.separator).join('/');

  static Future<String> _read(
    Directory folder,
    String relative,
    MapPackManifest manifest,
  ) async {
    final whole = _file(folder, relative);
    if (await whole.exists()) return whole.readAsString();
    final parts = manifest.file(relative)?.parts ?? const [];
    final bytes = <int>[];
    for (final part in parts) {
      bytes.addAll(await _file(folder, part).readAsBytes());
    }
    return utf8.decode(bytes);
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

  static Object? _withoutMetadata(Object? node) => switch (node) {
    final Map<String, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key != 'metadata') key: _withoutMetadata(value),
    },
    final List<Object?> list => [
      for (final item in list) _withoutMetadata(item),
    ],
    _ => node,
  };
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
