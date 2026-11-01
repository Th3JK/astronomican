import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// A picture a map draws: a floor plan, an illustrated map, an overlay.
///
/// Not an [ImageProvider], because the two engines need it in two shapes. The
/// image map decodes it through Flutter like any other picture; MapLibre's
/// image source wants the encoded bytes, and there is no getting those back out
/// of a provider. So the picture is described by where it comes from, and each
/// engine asks for the shape it needs.
@immutable
sealed class MapImage {
  const MapImage();

  /// A picture bundled with the app, like `Image.asset`.
  const factory MapImage.asset(String name, {String? package}) = AssetMapImage;

  /// A picture on disk — typically one that arrived inside a map pack.
  const factory MapImage.file(String path) = FileMapImage;

  /// A picture already in memory, encoded (PNG, JPEG, WebP).
  const factory MapImage.memory(Uint8List bytes) = MemoryMapImage;

  /// For drawing through Flutter.
  ImageProvider provider({AssetBundle? bundle});

  /// The encoded file, for MapLibre.
  Future<Uint8List> bytes({AssetBundle? bundle});
}

/// A picture bundled with the app.
final class AssetMapImage extends MapImage {
  /// The asset [name], from [package] when given.
  const AssetMapImage(this.name, {this.package});

  /// The asset key, as listed in the pubspec.
  final String name;

  /// The package the asset ships in, when it is not the app's own.
  final String? package;

  String get _key => package == null ? name : 'packages/$package/$name';

  @override
  ImageProvider provider({AssetBundle? bundle}) =>
      AssetImage(name, package: package, bundle: bundle);

  @override
  Future<Uint8List> bytes({AssetBundle? bundle}) async {
    final data = await (bundle ?? rootBundle).load(_key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  bool operator ==(Object other) =>
      other is AssetMapImage && other.name == name && other.package == package;

  @override
  int get hashCode => Object.hash(name, package);

  @override
  String toString() => 'MapImage.asset($_key)';
}

/// A picture on disk.
final class FileMapImage extends MapImage {
  /// The picture at [path].
  const FileMapImage(this.path);

  /// Absolute path to the file.
  final String path;

  @override
  ImageProvider provider({AssetBundle? bundle}) => FileImage(File(path));

  @override
  Future<Uint8List> bytes({AssetBundle? bundle}) => File(path).readAsBytes();

  @override
  bool operator ==(Object other) => other is FileMapImage && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'MapImage.file($path)';
}

/// A picture already in memory.
///
/// Compared by identity of the bytes, not their contents: hashing a
/// multi-megabyte plan on every rebuild to find out it has not changed would
/// cost more than redrawing it.
final class MemoryMapImage extends MapImage {
  /// The encoded picture in [data].
  const MemoryMapImage(this.data);

  /// The encoded picture.
  final Uint8List data;

  @override
  ImageProvider provider({AssetBundle? bundle}) => MemoryImage(data);

  @override
  Future<Uint8List> bytes({AssetBundle? bundle}) async => data;

  @override
  bool operator ==(Object other) =>
      other is MemoryMapImage && identical(other.data, data);

  @override
  int get hashCode => identityHashCode(data);

  @override
  String toString() => 'MapImage.memory(${data.length} bytes)';
}
