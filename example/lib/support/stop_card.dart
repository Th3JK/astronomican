import 'package:flutter/material.dart';

/// A card along the bottom naming the stop that was tapped.
class StopCard extends StatelessWidget {
  /// A card for [title], with [subtitle], closed by [onClose].
  const StopCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.onClose,
  });

  /// The stop's name.
  final String title;

  /// A second line.
  final String? subtitle;

  /// Called to close it.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: ListTile(
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle!),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
        ),
      ),
    );
  }
}

/// What a geo demo shows where MapLibre does not run.
Widget unsupportedMap(BuildContext context) => const Center(
  child: Padding(
    padding: EdgeInsets.all(32),
    child: Text(
      'MapLibre draws on Android and iOS.\n\n'
      'The image-map demos (4 and 5) and pack downloads run here too.',
      textAlign: TextAlign.center,
    ),
  ),
);
