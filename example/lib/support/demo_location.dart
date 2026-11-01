import 'package:astronomican/astronomican.dart';
import 'package:flutter/material.dart';

import 'demo_scope.dart';

/// Gives a street-map page its own position controller over the app's feed.
///
/// Each page follows on its own, but the GPS — or the simulated walk — runs
/// once for all of them.
mixin DemoLocation<W extends StatefulWidget> on State<W> {
  MyLocationController? _myLocation;

  /// The page's position controller, once the scope has a feed.
  MyLocationController? get myLocation => _myLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_myLocation != null) return;
    final feed = DemoScope.locationOf(context);
    if (feed != null) _myLocation = MyLocationController(feed: feed);
  }

  @override
  void dispose() {
    _myLocation?.dispose();
    super.dispose();
  }

  /// The location button, explaining when the position cannot be had.
  Widget locationButton() {
    final controller = _myLocation;
    if (controller == null) return const SizedBox.shrink();
    return MyLocationButton(
      controller: controller,
      onAccessProblem: (status) => explainLocation(context, status),
    );
  }
}

/// Tells the visitor why their position cannot be shown.
void explainLocation(BuildContext context, MyLocationStatus status) {
  final text = switch (status) {
    MyLocationStatus.denied => 'Allow location to see where you are.',
    MyLocationStatus.deniedForever =>
      'Location is refused for this app; allow it in the system settings.',
    MyLocationStatus.serviceDisabled => 'Location is off. Switch it on.',
    MyLocationStatus.unsupported => 'This device cannot be located.',
    _ => null,
  };
  if (text == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
