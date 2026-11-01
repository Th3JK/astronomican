import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'marker_icon.dart';

/// Turns a [MarkerIcon] into the PNG that MapLibre registers with its style.
///
/// Everything is drawn at the display's pixel ratio. Both platforms hand the
/// bitmap to the renderer as that many physical pixels per logical pixel, so an
/// icon rendered here comes out at [MarkerIcon.size] on screen, and stays sharp.
///
/// Results are kept by key and ratio. A map restyled on every selection change
/// asks for the same handful of icons over and over, and painting one is a
/// round trip through the GPU.
final class MarkerRasterizer {
  /// A rasterizer loading asset icons from [bundle], or the root bundle.
  MarkerRasterizer({AssetBundle? bundle}) : _bundle = bundle;

  final AssetBundle? _bundle;
  final Map<String, Future<Uint8List>> _cache = {};

  /// The PNG for [icon] at [pixelRatio].
  ///
  /// A failure is not kept, so a missing asset that has since been added is
  /// tried again rather than remembered as broken.
  Future<Uint8List> rasterize(
    MarkerIcon icon, {
    required double pixelRatio,
  }) async {
    final key = '${icon.key}@$pixelRatio';
    final pending = _cache.putIfAbsent(key, () => _render(icon, pixelRatio));
    try {
      return await pending;
    } catch (_) {
      // Its error is the one being rethrown; the entry only has to go.
      if (identical(_cache[key], pending)) _cache.remove(key)?.ignore();
      rethrow;
    }
  }

  /// Forgets every rendered icon.
  void clear() => _cache.clear();

  Future<Uint8List> _render(MarkerIcon icon, double pixelRatio) async {
    switch (icon) {
      case AssetMarkerIcon():
        final data = await (_bundle ?? rootBundle).load(icon.assetKey);
        final image = await _decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        return _drawn(icon.size, pixelRatio, image);
      case BytesMarkerIcon():
        return _drawn(icon.size, pixelRatio, await _decode(icon.bytes));
      case CanvasMarkerIcon():
        return _record(
          icon.size,
          pixelRatio,
          (canvas) => icon.paint(canvas, icon.size),
        );
    }
  }

  Future<Uint8List> _drawn(Size size, double pixelRatio, ui.Image image) async {
    try {
      return await _record(size, pixelRatio, (canvas) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Offset.zero & size,
          Paint()..filterQuality = FilterQuality.medium,
        );
      });
    } finally {
      image.dispose();
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<Uint8List> _record(
    Size size,
    double pixelRatio,
    void Function(Canvas canvas) paint,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
