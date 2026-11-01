import 'dart:ui' show Color;

import 'package:meta/meta.dart';

import 'package:astronomican/astronomican.dart';
import 'style/blank_style.dart';
import 'style/pack_style_resolver.dart';
import 'style/raster_style.dart';

/// What a `GeoMap` draws underneath its markers.
///
/// ```dart
/// // Online: a provider's style.
/// GeoMapSource.styleUrl('https://tiles.openfreemap.org/styles/liberty')
///
/// // Online: plain raster tiles.
/// GeoMapSource.rasterTiles(
///   urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
///   attribution: '© OpenStreetMap contributors',
/// )
///
/// // Offline: a pack bundled with the app, installed on first use.
/// GeoMapSource.bundledPack(packs, 'assets/packs/town/pack.json')
///
/// // Nothing: a background for a map that is all overlay.
/// GeoMapSource.blank()
/// ```
@immutable
sealed class GeoMapSource {
  const GeoMapSource();

  /// A style document served at [url] — the usual way to use an online
  /// provider such as OpenFreeMap or MapTiler.
  const factory GeoMapSource.styleUrl(String url, {String? attribution}) =
      StyleUrlSource;

  /// A style document given as JSON text.
  const factory GeoMapSource.styleJson(String json, {String? attribution}) =
      StyleJsonSource;

  /// Raster tiles from [urlTemplate], wrapped in a generated style.
  const factory GeoMapSource.rasterTiles({
    required String urlTemplate,
    int tileSize,
    int minZoom,
    int maxZoom,
    String? attribution,
    List<String> subdomains,
    Color background,
  }) = RasterTileSource;

  /// An installed map pack, drawn with its own style — or [styleFile] from
  /// inside it.
  const factory GeoMapSource.pack(
    InstalledPack pack, {
    String? styleFile,
    Map<String, String> tokens,
  }) = PackSource;

  /// A pack bundled with the app, installed through [manager] the first time
  /// it is needed (and on later launches only if the bundle is newer).
  const factory GeoMapSource.bundledPack(
    MapPackManager manager,
    String manifestAsset, {
    String? styleFile,
    Map<String, String> tokens,
  }) = BundledPackSource;

  /// Just a background colour.
  const factory GeoMapSource.blank({Color background}) = BlankSource;

  /// Turns the source into what MapLibre takes: a style URL or document.
  Future<ResolvedStyle> resolve();
}

/// A source resolved: the style MapLibre is handed, and what is known about
/// its data.
@immutable
final class ResolvedStyle {
  /// [style] is a URL, a file path or a JSON document.
  const ResolvedStyle(
    this.style, {
    this.bounds,
    this.minZoom,
    this.maxZoom,
    this.attribution,
    this.pack,
  });

  /// What MapLibre is handed as its style string.
  final String style;

  /// Where the data is, when known — a camera with nowhere else to go opens
  /// on it.
  final GeoBounds? bounds;

  /// The lowest zoom the data is cut for.
  final double? minZoom;

  /// The highest zoom the data is cut for.
  final double? maxZoom;

  /// The credit the data asks for.
  final String? attribution;

  /// The pack drawn, for a pack source.
  final InstalledPack? pack;
}

/// A style served at a URL.
final class StyleUrlSource extends GeoMapSource {
  /// The style at [url].
  const StyleUrlSource(this.url, {this.attribution});

  /// Where the style document is.
  final String url;

  /// The credit, if the app wants to show it itself.
  final String? attribution;

  @override
  Future<ResolvedStyle> resolve() async =>
      ResolvedStyle(url, attribution: attribution);

  @override
  bool operator ==(Object other) =>
      other is StyleUrlSource &&
      other.url == url &&
      other.attribution == attribution;

  @override
  int get hashCode => Object.hash(url, attribution);
}

/// A style given as JSON.
final class StyleJsonSource extends GeoMapSource {
  /// The style [json].
  const StyleJsonSource(this.json, {this.attribution});

  /// The style document.
  final String json;

  /// The credit, if the app wants to show it itself.
  final String? attribution;

  @override
  Future<ResolvedStyle> resolve() async =>
      ResolvedStyle(json.trimLeft(), attribution: attribution);

  @override
  bool operator ==(Object other) =>
      other is StyleJsonSource &&
      other.json == json &&
      other.attribution == attribution;

  @override
  int get hashCode => Object.hash(json, attribution);
}

/// Raster tiles, wrapped in a generated style.
final class RasterTileSource extends GeoMapSource {
  /// Tiles at [urlTemplate]; see `RasterStyle.build`.
  const RasterTileSource({
    required this.urlTemplate,
    this.tileSize = 256,
    this.minZoom = 0,
    this.maxZoom = 19,
    this.attribution,
    this.subdomains = const ['a', 'b', 'c'],
    this.background = const Color(0xFFF2EFE9),
  });

  /// The tile URL, with `{z}`, `{x}`, `{y}` and optionally `{s}`.
  final String urlTemplate;

  /// The tiles' size in pixels.
  final int tileSize;

  /// The lowest zoom the provider serves.
  final int minZoom;

  /// The highest zoom the provider serves; the map overzooms past it.
  final int maxZoom;

  /// The provider's credit.
  final String? attribution;

  /// What `{s}` is expanded over.
  final List<String> subdomains;

  /// Shown where no tile has loaded.
  final Color background;

  @override
  Future<ResolvedStyle> resolve() async => ResolvedStyle(
    RasterStyle.build(
      urlTemplate: urlTemplate,
      tileSize: tileSize,
      minZoom: minZoom,
      maxZoom: maxZoom,
      attribution: attribution,
      subdomains: subdomains,
      background: background,
    ),
    attribution: attribution,
  );

  @override
  bool operator ==(Object other) =>
      other is RasterTileSource &&
      other.urlTemplate == urlTemplate &&
      other.tileSize == tileSize &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.attribution == attribution &&
      other.background == background;

  @override
  int get hashCode => Object.hash(
    urlTemplate,
    tileSize,
    minZoom,
    maxZoom,
    attribution,
    background,
  );
}

/// An installed pack.
final class PackSource extends GeoMapSource {
  /// [pack], drawn with its style or [styleFile].
  const PackSource(this.pack, {this.styleFile, this.tokens = const {}});

  /// The pack.
  final InstalledPack pack;

  /// A style inside the pack other than its default.
  final String? styleFile;

  /// Extra substitutions; see `PackStyleResolver.tokens`.
  final Map<String, String> tokens;

  @override
  Future<ResolvedStyle> resolve() async =>
      _resolvePack(pack, styleFile, tokens);

  @override
  bool operator ==(Object other) =>
      other is PackSource &&
      other.pack == pack &&
      other.styleFile == styleFile &&
      _mapEquals(other.tokens, tokens);

  @override
  int get hashCode => Object.hash(pack, styleFile, tokens.length);
}

/// A bundled pack, installed on first use.
final class BundledPackSource extends GeoMapSource {
  /// The pack whose manifest is [manifestAsset], installed by [manager].
  const BundledPackSource(
    this.manager,
    this.manifestAsset, {
    this.styleFile,
    this.tokens = const {},
  });

  /// The manager that installs it.
  final MapPackManager manager;

  /// The bundled `pack.json`.
  final String manifestAsset;

  /// A style inside the pack other than its default.
  final String? styleFile;

  /// Extra substitutions; see `PackStyleResolver.tokens`.
  final Map<String, String> tokens;

  @override
  Future<ResolvedStyle> resolve() async {
    final pack = await manager.ensureBundled(manifestAsset);
    return _resolvePack(pack, styleFile, tokens);
  }

  @override
  bool operator ==(Object other) =>
      other is BundledPackSource &&
      identical(other.manager, manager) &&
      other.manifestAsset == manifestAsset &&
      other.styleFile == styleFile &&
      _mapEquals(other.tokens, tokens);

  @override
  int get hashCode => Object.hash(manager, manifestAsset, styleFile);
}

/// A background colour and nothing else.
final class BlankSource extends GeoMapSource {
  /// A plain [background].
  const BlankSource({this.background = const Color(0xFFF0E0C6)});

  /// The colour.
  final Color background;

  @override
  Future<ResolvedStyle> resolve() async =>
      ResolvedStyle(BlankStyle.build(background: background));

  @override
  bool operator ==(Object other) =>
      other is BlankSource && other.background == background;

  @override
  int get hashCode => background.hashCode;
}

Future<ResolvedStyle> _resolvePack(
  InstalledPack pack,
  String? styleFile,
  Map<String, String> tokens,
) async {
  final style = await PackStyleResolver(
    pack,
    tokens: tokens,
  ).resolve(styleFile);
  final manifest = pack.manifest;
  return ResolvedStyle(
    style,
    bounds: pack.bounds,
    minZoom: manifest.minZoom?.toDouble(),
    maxZoom: manifest.maxZoom?.toDouble(),
    attribution: manifest.attribution,
    pack: pack,
  );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    if (b[key] != value) return false;
  }
  return true;
}
