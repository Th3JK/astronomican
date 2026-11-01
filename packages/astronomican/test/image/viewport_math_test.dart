import 'package:astronomican/astronomican.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewport = Size(400, 800);
  const content = Size(2000, 1000);

  test('fitScale fits the tighter axis', () {
    expect(ViewportMath.fitScale(viewport, content), 0.2);
    expect(
      ViewportMath.fitScale(viewport, content, const EdgeInsets.all(100)),
      closeTo(0.1, 1e-12),
    );
    expect(ViewportMath.fitScale(Size.zero, content), 0);
  });

  test('fitRect centres the rect and respects the scale limits', () {
    const rect = Rect.fromLTWH(500, 250, 400, 200);
    final m = ViewportMath.fitRect(
      rect,
      viewport: viewport,
      minScale: 0.2,
      maxScale: 0.8,
    );
    expect(ViewportMath.scaleOf(m), closeTo(0.8, 1e-12)); // wanted 1.0
    final centre = ViewportMath.toScreen(m, rect.center);
    expect(centre.dx, closeTo(200, 1e-9));
    expect(centre.dy, closeTo(400, 1e-9));
  });

  test('toContent inverts toScreen', () {
    final m = ViewportMath.centreOn(
      const Offset(700, 300),
      0.35,
      const Offset(120, 90),
    );
    const p = Offset(1234, 567);
    final back = ViewportMath.toContent(m, ViewportMath.toScreen(m, p));
    expect(back.dx, closeTo(p.dx, 1e-9));
    expect(back.dy, closeTo(p.dy, 1e-9));
  });

  test('zoomAbout keeps the focal point still', () {
    final m = ViewportMath.centreOn(
      const Offset(1000, 500),
      0.2,
      const Offset(200, 400),
    );
    const focal = Offset(50, 600);
    final before = ViewportMath.toContent(m, focal);
    final zoomed = ViewportMath.zoomAbout(m, focal, 0.6);
    expect(ViewportMath.scaleOf(zoomed), closeTo(0.6, 1e-12));
    final after = ViewportMath.toContent(zoomed, focal);
    expect(after.dx, closeTo(before.dx, 1e-9));
    expect(after.dy, closeTo(before.dy, 1e-9));
  });

  test('resize keeps the middle and the relative zoom', () {
    final m = ViewportMath.centreOn(
      const Offset(800, 400),
      0.4,
      const Offset(200, 400),
    );
    const to = Size(800, 400);
    final fromFit = ViewportMath.fitScale(viewport, content);
    final toFit = ViewportMath.fitScale(to, content);
    final r = ViewportMath.resize(
      m,
      from: viewport,
      to: to,
      fromFit: fromFit,
      toFit: toFit,
    );
    expect(ViewportMath.scaleOf(r) / toFit, closeTo(0.4 / fromFit, 1e-12));
    final middle = ViewportMath.toContent(r, const Offset(400, 200));
    expect(middle.dx, closeTo(800, 1e-9));
    expect(middle.dy, closeTo(400, 1e-9));
  });

  group('clamp', () {
    Matrix4 clamp(Matrix4 m) => ViewportMath.clamp(
      m,
      viewport: viewport,
      content: content,
      overscroll: 0.04,
      rest: const Offset(1000, 500),
    );

    test('returns the same instance when nothing is out of bounds', () {
      final m = ViewportMath.centreOn(
        const Offset(1000, 500),
        1,
        const Offset(200, 400),
      );
      expect(identical(clamp(m), m), isTrue);
    });

    test('pulls a picture dragged too far back to its edge plus slack', () {
      // Scale 1: the picture is 2000 wide on a 400 screen. Dragged so its left
      // edge sits 300 in from the screen's.
      final m = Matrix4.identity()
        ..translateByDouble(300, -100, 0, 1)
        ..scaleByDouble(1, 1, 1, 1);
      final c = clamp(m);
      expect(c.getTranslation().x, closeTo(2000 * 0.04, 1e-9));
      expect(c.getTranslation().y, closeTo(-100, 1e-9));
    });

    test('centres an axis with nothing to scroll through', () {
      // Scale 0.2: 400 × 200 on a 400 × 800 screen — vertically there is room.
      final m = Matrix4.identity()
        ..translateByDouble(0, 5, 0, 1)
        ..scaleByDouble(0.2, 0.2, 0.2, 1);
      final c = clamp(m);
      expect(c.getTranslation().y, closeTo(300, 1e-9));
    });

    test('clampAxis keeps the rest point inside the screen', () {
      // A drawing 100 long on a 300 screen whose focus would put it at -50.
      expect(ViewportMath.clampAxis(0, 100, 300, 10, -50), 0);
      expect(ViewportMath.clampAxis(0, 100, 300, 10, 400), 200);
      expect(ViewportMath.clampAxis(-900, 1000, 300, 10, 0), -710);
    });
  });

  group('turned', () {
    const quarter = 1.5707963267948966;

    test('centreOn puts the point where asked, turned', () {
      final m = ViewportMath.centreOn(
        const Offset(300, 200),
        0.5,
        const Offset(200, 400),
        rotation: quarter,
      );
      expect(ViewportMath.rotationOf(m), closeTo(quarter, 1e-9));
      expect(ViewportMath.scaleOf(m), closeTo(0.5, 1e-9));
      final at = ViewportMath.toScreen(m, const Offset(300, 200));
      expect(at.dx, closeTo(200, 1e-9));
      expect(at.dy, closeTo(400, 1e-9));
      // A quarter turn clockwise: a step east on the picture goes down.
      final east = ViewportMath.toScreen(m, const Offset(400, 200));
      expect(east.dx, closeTo(200, 1e-9));
      expect(east.dy, closeTo(450, 1e-9));
      final back = ViewportMath.toContent(m, const Offset(200, 450));
      expect(back.dx, closeTo(400, 1e-9));
    });

    test('zoom, resize and fit keep the turn', () {
      final m = ViewportMath.centreOn(
        const Offset(1000, 500),
        0.3,
        const Offset(200, 400),
        rotation: 0.4,
      );
      final zoomed = ViewportMath.zoomAbout(m, const Offset(100, 100), 0.6);
      expect(ViewportMath.rotationOf(zoomed), closeTo(0.4, 1e-9));
      final under = ViewportMath.toContent(m, const Offset(100, 100));
      final still = ViewportMath.toScreen(zoomed, under);
      expect(still.dx, closeTo(100, 1e-9));
      expect(still.dy, closeTo(100, 1e-9));

      final resized = ViewportMath.resize(
        m,
        from: viewport,
        to: const Size(800, 400),
        fromFit: 0.2,
        toFit: 0.4,
      );
      expect(ViewportMath.rotationOf(resized), closeTo(0.4, 1e-9));

      final fitted = ViewportMath.fitRect(
        const Rect.fromLTWH(0, 0, 2000, 1000),
        viewport: viewport,
        minScale: 0,
        maxScale: 10,
        rotation: quarter,
      );
      // Turned a quarter, the wide plan stands up: 1000 across, 2000 tall.
      expect(ViewportMath.scaleOf(fitted), closeTo(0.4, 1e-9));
    });

    test('rotateAbout keeps the focal point and the scale', () {
      final m = ViewportMath.centreOn(
        const Offset(1000, 500),
        0.3,
        const Offset(200, 400),
      );
      final turned = ViewportMath.rotateAbout(m, const Offset(200, 400), 1);
      expect(ViewportMath.rotationOf(turned), closeTo(1, 1e-9));
      expect(ViewportMath.scaleOf(turned), closeTo(0.3, 1e-9));
      final centre = ViewportMath.toContent(turned, const Offset(200, 400));
      expect(centre.dx, closeTo(1000, 1e-9));
      expect(centre.dy, closeTo(500, 1e-9));
    });

    test('visibleRect covers the turned screen', () {
      final m = ViewportMath.centreOn(
        const Offset(1000, 500),
        1,
        const Offset(200, 400),
        rotation: quarter,
      );
      final visible = ViewportMath.visibleRect(m, viewport);
      // A 400 by 800 screen turned a quarter sees 800 by 400 of the plan.
      expect(visible.width, closeTo(800, 1e-6));
      expect(visible.height, closeTo(400, 1e-6));
      expect(visible.center.dx, closeTo(1000, 1e-6));
    });

    test('a turned map keeps the middle of the screen on the picture', () {
      final off = ViewportMath.centreOn(
        const Offset(2600, -300),
        0.5,
        const Offset(200, 400),
        rotation: 0.3,
      );
      final held = ViewportMath.clamp(
        off,
        viewport: viewport,
        content: content,
        overscroll: 0,
        rest: const Offset(1000, 500),
      );
      final centre = ViewportMath.toContent(held, const Offset(200, 400));
      expect(centre.dx, closeTo(2000, 1e-6));
      expect(centre.dy, closeTo(0, 1e-6));
      expect(ViewportMath.rotationOf(held), closeTo(0.3, 1e-9));

      final inside = ViewportMath.centreOn(
        const Offset(1500, 900),
        0.5,
        const Offset(200, 400),
        rotation: 0.3,
      );
      final kept = ViewportMath.clampCentre(
        inside,
        viewport: viewport,
        content: content,
      );
      expect(identical(kept, inside), isTrue);
    });

    test('clampCentre lets a point by the edge come to the middle', () {
      // Unturned, the edge-to-edge clamp would pull this back; following the
      // visitor needs the point by the edge in the middle all the same.
      final byEdge = ViewportMath.centreOn(
        const Offset(20, 20),
        0.4,
        const Offset(200, 400),
      );
      final held = ViewportMath.clampCentre(
        byEdge,
        viewport: viewport,
        content: content,
      );
      expect(identical(held, byEdge), isTrue);
    });
  });
}
