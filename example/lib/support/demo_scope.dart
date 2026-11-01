import 'package:astronomican/astronomican.dart';
import 'package:flutter/widgets.dart';

/// Hands the app's pack manager, and where the visitor's position comes
/// from, to every demo.
class DemoScope extends InheritedWidget {
  /// Provides [packs] and [location] to [child].
  const DemoScope({
    super.key,
    required this.packs,
    this.location,
    required super.child,
  });

  /// The app's one pack manager.
  final MapPackManager packs;

  /// The street maps' position: a simulated walk or the device's GPS. Null
  /// hides the location button.
  final LocationFeed? location;

  /// The pack manager above [context].
  static MapPackManager packsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoScope>()!.packs;

  /// The position feed above [context].
  static LocationFeed? locationOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoScope>()!.location;

  @override
  bool updateShouldNotify(DemoScope oldWidget) =>
      oldWidget.packs != packs || oldWidget.location != location;
}
