import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'viewport_math.dart';

/// Paints an image map's markers at a constant size on screen.
///
/// The markers live inside the scaled picture, so the viewer's pinch and pan
/// reach them as they reach the picture — a pinch that starts on a marker still
/// zooms. Each one is painted at its position and then scaled back down by the
/// camera's own scale, which cancels out: a marker is always its own size on
/// the glass, drawn at full resolution.
///
/// Because this is a paint transform, a pinch costs a repaint and nothing more.
/// Resizing the markers through layout instead would rebuild every one of them
/// on every frame of the gesture. And a `Flow` hit-tests its children through
/// the same transforms it painted them with, so taps land where the markers
/// are seen.
@internal
class MarkerFlowDelegate extends FlowDelegate {
  /// Markers at [positions] in the picture's frame, each standing on the point
  /// [anchors] names within it, under the camera [transform].
  MarkerFlowDelegate({
    required this.transform,
    required this.positions,
    required this.anchors,
  }) : super(repaint: transform);

  /// The camera; repainted whenever it moves.
  final TransformationController transform;

  /// Where each marker stands, in the picture's logical frame.
  final List<Offset> positions;

  /// Which point of each marker stands there.
  final List<Alignment> anchors;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      const BoxConstraints();

  /// On a map turned to face the visitor's heading, each marker is also
  /// turned back, so pins still stand upright and their labels read.
  @override
  void paintChildren(FlowPaintingContext context) {
    final matrix = transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final inverse = scale > 0 ? 1 / scale : 1.0;
    final turn = ViewportMath.rotationOf(matrix);
    for (var i = 0; i < context.childCount; i++) {
      final size = context.getChildSize(i) ?? Size.zero;
      final anchor = anchors[i].alongSize(size);
      final position = positions[i];
      final child = Matrix4.translationValues(position.dx, position.dy, 0);
      if (turn != 0) child.rotateZ(-turn);
      context.paintChild(
        i,
        transform: child
          ..scaleByDouble(inverse, inverse, 1, 1)
          ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1),
      );
    }
  }

  @override
  bool shouldRepaint(MarkerFlowDelegate oldDelegate) =>
      oldDelegate.transform != transform ||
      !listEquals(oldDelegate.positions, positions) ||
      !listEquals(oldDelegate.anchors, anchors);
}
