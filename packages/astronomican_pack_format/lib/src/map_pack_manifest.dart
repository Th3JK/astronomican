import 'dart:convert';

import 'package:meta/meta.dart';

import 'pack_exceptions.dart';

/// The `pack.json` that describes a map pack: which files it holds and which
/// version it is.
///
/// A pack is a folder — an `.mbtiles` tileset, the style that draws it, the
/// sprite and glyphs that style needs, any overlay pictures — plus this
/// manifest. The same manifest format describes a pack bundled in the app's
/// assets and one served for download, so both go through one install path
/// and one version sequence.
///
/// **[version] is the "this is new" flag.** A pack is copied out of the bundle
/// on first launch and then left alone; it is copied again only when an app
/// update ships a manifest with a higher version. Bump it whenever any file in
/// the pack changes, and use the same sequence on the server: a downloaded v5
/// is never replaced by a bundled v4.
///
/// Pure Dart — no Flutter — so the `pack_manifest` command-line tool can
/// write it.
///
/// ```json
/// {
///   "format": 1,
///   "id": "strakonice",
///   "version": 3,
///   "style": "style.json",
///   "bounds": [13.8748, 49.2435, 13.9309, 49.2749],
///   "maxZoom": 14,
///   "files": [
///     {"path": "strakonice.mbtiles", "size": 1564672, "sha256": "…"},
///     {"path": "style.json", "size": 114688}
///   ]
/// }
/// ```
@immutable
final class MapPackManifest {
  /// A manifest; see [validate] for what makes one valid.
  const MapPackManifest({
    required this.id,
    required this.version,
    required this.files,
    this.format = currentFormat,
    this.name,
    this.style,
    this.bounds,
    this.minZoom,
    this.maxZoom,
    this.attribution,
  });

  /// Parses and validates the text of a `pack.json`.
  ///
  /// Throws [PackManifestException] when it is not a valid manifest.
  factory MapPackManifest.parse(String source) {
    final Object? json;
    try {
      // A byte-order mark is legal at the start of a UTF-8 file and fatal to
      // jsonDecode.
      json = jsonDecode(source.startsWith('﻿') ? source.substring(1) : source);
    } on FormatException catch (e) {
      throw PackManifestException('not JSON: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw const PackManifestException('the manifest must be a JSON object');
    }
    return MapPackManifest.fromJson(json);
  }

  /// Reads and validates a decoded manifest.
  factory MapPackManifest.fromJson(Map<String, Object?> json) {
    final files = json['files'];
    if (files is! List<Object?>) {
      throw const PackManifestException('"files" must be a list');
    }
    final bounds = json['bounds'];
    final manifest = MapPackManifest(
      format: _int(json, 'format') ?? 1,
      id: _string(json, 'id') ?? '',
      version: _int(json, 'version') ?? -1,
      name: _string(json, 'name'),
      style: _string(json, 'style'),
      bounds: bounds == null
          ? null
          : bounds is List<Object?> && bounds.every((v) => v is num)
          ? [for (final v in bounds) (v! as num).toDouble()]
          : throw const PackManifestException(
              '"bounds" must be [west, south, east, north]',
            ),
      minZoom: _num(json, 'minZoom'),
      maxZoom: _num(json, 'maxZoom'),
      attribution: _string(json, 'attribution'),
      files: [
        for (final entry in files)
          if (entry is Map<String, Object?>)
            PackFileEntry.fromJson(entry)
          else
            throw const PackManifestException('every file must be an object'),
      ],
    );
    manifest.validate();
    return manifest;
  }

  /// The manifest format this code writes and reads.
  static const int currentFormat = 1;

  /// Names inside a pack's folder that belong to the installer.
  static const Set<String> reservedNames = {'.pack.json', '.remote.json'};

  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9_.-]{0,63}$');

  /// Whether [id] may name a pack: lowercase letters, digits, `_`, `.` and
  /// `-`, starting with a letter or digit, at most 64 characters.
  static bool isValidId(String id) => _idPattern.hasMatch(id);
  static final RegExp _shaPattern = RegExp(r'^[0-9a-f]{64}$');

  /// The manifest format. An app refuses packs in a format newer than it
  /// knows.
  final int format;

  /// Names the pack. Lowercase letters, digits, `_`, `.` and `-`; it is also
  /// a folder name on the device.
  final String id;

  /// Which version of the pack this is. Higher is newer; see the class notes.
  final int version;

  /// Every file in the pack.
  final List<PackFileEntry> files;

  /// A human name, for a download screen.
  final String? name;

  /// The style document inside the pack, when it has one. Defaults to
  /// `style.json` when that file is listed.
  final String? style;

  /// The area the pack covers, as `[west, south, east, north]` — the same
  /// order as an mbtiles metadata table.
  final List<double>? bounds;

  /// The lowest zoom the tiles are cut for.
  final num? minZoom;

  /// The highest zoom the tiles are cut for; the map overzooms past it.
  final num? maxZoom;

  /// The credit the data asks for, such as `© OpenStreetMap contributors`.
  final String? attribution;

  /// The style document to draw with: [style], or `style.json` if listed.
  String? get stylePath {
    if (style != null) return style;
    return files.any((f) => f.path == 'style.json') ? 'style.json' : null;
  }

  /// The first `.mbtiles` file, which the legacy style placeholders point at.
  String? get mbtilesPath {
    for (final file in files) {
      if (file.path.endsWith('.mbtiles')) return file.path;
    }
    return null;
  }

  /// Sum of every file's size.
  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  /// The entry for [path], if the pack has it.
  PackFileEntry? file(String path) {
    for (final entry in files) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  /// Throws [PackManifestException] unless this is a usable manifest.
  ///
  /// Paths are checked with care because they become paths on the device: a
  /// `..` or an absolute path in a downloaded manifest must not be able to
  /// write outside the pack's folder.
  void validate() {
    if (format < 1) throw const PackManifestException('"format" must be ≥ 1');
    if (!_idPattern.hasMatch(id)) {
      throw PackManifestException(
        '"$id" is not a valid id: use lowercase letters, digits, _ . and -',
      );
    }
    if (version < 1) throw const PackManifestException('"version" must be ≥ 1');
    if (files.isEmpty) throw const PackManifestException('"files" is empty');
    final seen = <String>{};
    for (final file in files) {
      checkPath(file.path);
      if (file.path.endsWith('.part')) {
        throw PackManifestException(
          '"${file.path}": the .part suffix is reserved for downloads',
        );
      }
      // Case-insensitively: iOS file systems usually are.
      if (!seen.add(file.path.toLowerCase())) {
        throw PackManifestException('"${file.path}" is listed twice');
      }
      if (file.size < 0) {
        throw PackManifestException('"${file.path}" has a negative size');
      }
      final sha = file.sha256;
      if (sha != null && !_shaPattern.hasMatch(sha)) {
        throw PackManifestException(
          '"${file.path}": sha256 must be 64 lowercase hex digits',
        );
      }
      for (final part in file.parts ?? const <String>[]) {
        checkPath(part);
      }
    }
    final style = this.style;
    if (style != null && file(style) == null) {
      throw PackManifestException('the style "$style" is not among the files');
    }
    final bounds = this.bounds;
    if (bounds != null &&
        (bounds.length != 4 ||
            bounds[0] > bounds[2] ||
            bounds[1] > bounds[3] ||
            bounds[1] < -90 ||
            bounds[3] > 90)) {
      throw const PackManifestException(
        '"bounds" must be [west, south, east, north]',
      );
    }
  }

  /// Throws [PackManifestException] unless [path] is a safe relative path.
  static void checkPath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains(r'\') ||
        path.contains(':') ||
        path.contains('\u0000')) {
      throw PackManifestException('"$path" is not a relative path');
    }
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw PackManifestException('"$path" is not a plain relative path');
      }
    }
    if (reservedNames.contains(path)) {
      throw PackManifestException('"$path" is a reserved name');
    }
  }

  /// The manifest as JSON.
  Map<String, Object?> toJson() => {
    'format': format,
    'id': id,
    'version': version,
    if (name != null) 'name': name,
    if (style != null) 'style': style,
    if (bounds != null) 'bounds': bounds,
    if (minZoom != null) 'minZoom': minZoom,
    if (maxZoom != null) 'maxZoom': maxZoom,
    if (attribution != null) 'attribution': attribution,
    'files': [for (final file in files) file.toJson()],
  };

  /// The manifest as the text of a `pack.json`.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static String? _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null || value is String) return value as String?;
    throw PackManifestException('"$key" must be a string');
  }

  static int? _int(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null || value is int) return value as int?;
    throw PackManifestException('"$key" must be a whole number');
  }

  static num? _num(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null || value is num) return value as num?;
    throw PackManifestException('"$key" must be a number');
  }

  @override
  bool operator ==(Object other) =>
      other is MapPackManifest && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// One file in a map pack.
@immutable
final class PackFileEntry {
  /// A file at [path], [size] bytes long.
  const PackFileEntry({
    required this.path,
    required this.size,
    this.sha256,
    this.parts,
  });

  /// Reads an entry from its JSON.
  factory PackFileEntry.fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final size = json['size'];
    final sha = json['sha256'];
    final parts = json['parts'];
    if (path is! String) {
      throw const PackManifestException('every file needs a "path"');
    }
    if (size is! int) {
      throw PackManifestException('"$path" needs a whole-number "size"');
    }
    if (sha != null && sha is! String) {
      throw PackManifestException('"$path": sha256 must be a string');
    }
    if (parts != null &&
        (parts is! List<Object?> || parts.any((p) => p is! String))) {
      throw PackManifestException('"$path": parts must be a list of paths');
    }
    return PackFileEntry(
      path: path,
      size: size,
      sha256: sha as String?,
      parts: parts == null ? null : List<String>.from(parts as List<Object?>),
    );
  }

  /// Where the file goes, relative to the pack's folder, with `/` between
  /// folders.
  final String path;

  /// Its length in bytes. Every install checks it.
  final int size;

  /// Its SHA-256, in lowercase hex. Downloads verify it, and an update reuses
  /// the installed copy of a file whose checksum has not changed.
  final String? sha256;

  /// For a bundled pack: the pieces the file is shipped in, in order,
  /// relative to the manifest.
  ///
  /// Flutter can only read an asset whole, so a 200 MB tileset read in one go
  /// is 200 MB of memory. Split into pieces, the installer only ever holds one
  /// piece. Downloads always fetch [path] itself.
  final List<String>? parts;

  /// The entry as JSON.
  Map<String, Object?> toJson() => {
    'path': path,
    'size': size,
    if (sha256 != null) 'sha256': sha256,
    if (parts != null) 'parts': parts,
  };

  @override
  bool operator ==(Object other) =>
      other is PackFileEntry &&
      other.path == path &&
      other.size == size &&
      other.sha256 == sha256 &&
      _listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hash(
    path,
    size,
    sha256,
    parts == null ? null : Object.hashAll(parts!),
  );

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
