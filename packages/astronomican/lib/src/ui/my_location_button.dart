import 'package:flutter/material.dart';

import '../location/my_location_controller.dart';

/// The button that finds the visitor on the map and keeps them there.
///
/// Each tap is `MyLocationController.cycle`: it starts the feed and follows,
/// then turns the map to face the way the visitor does, then goes back to
/// following. The icon says which: hollow while the map is left alone,
/// filled while it follows, an arrow while it turns.
///
/// When the position cannot be had — access refused, location switched off —
/// a tap calls [onAccessProblem] with the reason, so the app can explain it
/// or open the settings, and tries again where trying again can help.
class MyLocationButton extends StatelessWidget {
  /// A button driving [controller].
  const MyLocationButton({
    super.key,
    required this.controller,
    this.onAccessProblem,
    this.backgroundColor,
    this.foregroundColor,
    this.activeColor,
  });

  /// The position it shows and follows.
  final MyLocationController controller;

  /// Called on a tap while the position cannot be had.
  final void Function(MyLocationStatus status)? onAccessProblem;

  /// The button's fill; the theme's surface by default.
  final Color? backgroundColor;

  /// The icon while the map is not following.
  final Color? foregroundColor;

  /// The icon while the map follows; the theme's primary by default.
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final status = controller.status;
        final mode = controller.mode;
        final following = mode != MyLocationMode.none;
        final (icon, label) = _look(status, mode);
        final colour = following && !status.isProblem
            ? activeColor ?? scheme.primary
            : foregroundColor ?? scheme.onSurfaceVariant;
        return FloatingActionButton.small(
          heroTag: null,
          tooltip: label,
          backgroundColor: backgroundColor ?? scheme.surface,
          foregroundColor: colour,
          onPressed: () => _pressed(status),
          child: status == MyLocationStatus.searching && following
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colour,
                  ),
                )
              : Icon(icon),
        );
      },
    );
  }

  void _pressed(MyLocationStatus status) {
    if (status.isProblem) {
      onAccessProblem?.call(status);
      // Only the settings can change these; asking again would do nothing.
      if (status == MyLocationStatus.deniedForever ||
          status == MyLocationStatus.unsupported) {
        return;
      }
    }
    controller.cycle();
  }

  static (IconData, String) _look(
    MyLocationStatus status,
    MyLocationMode mode,
  ) {
    if (status.isProblem) return (Icons.location_disabled, 'Location off');
    return switch (mode) {
      MyLocationMode.none => (Icons.location_searching, 'Show my location'),
      MyLocationMode.follow => (Icons.my_location, 'Face my direction'),
      MyLocationMode.heading => (Icons.navigation, 'Stop facing my direction'),
    };
  }
}
