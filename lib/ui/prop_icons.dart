import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/prop.dart';

/// A small black-box glyph representing a prop's shape, echoing the icons used
/// by the original alexthepunk.com layout tool.
class PropShapeIcon extends StatelessWidget {
  const PropShapeIcon(this.shape, {super.key, this.size = 22});

  final PropShape shape;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
      ),
      child: CustomPaint(painter: _ShapePainter(shape)),
    );
  }
}

/// Paints [shape]'s icon glyph (the same look as [PropShapeIcon]'s black
/// box) directly onto [canvas] within [rect], for contexts that need a raw
/// canvas instead of a widget — e.g. the Layout Preview's PDF export, which
/// rasterizes the whole map in one [PictureRecorder] rather than mounting a
/// widget tree.
void paintPropShapeIcon(Canvas canvas, Rect rect, PropShape shape) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & rect.size, const Radius.circular(2)),
    Paint()..color = Colors.black,
  );
  _ShapePainter(shape).paint(canvas, rect.size);
  canvas.restore();
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.shape);

  final PropShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = Colors.white;
    final w = size.width;
    final h = size.height;
    final pad = w * 0.18;

    switch (shape) {
      case PropShape.arch:
        final rect = Rect.fromLTRB(pad, pad, w - pad, h + (h - pad));
        canvas.drawArc(rect, math.pi, math.pi, false, stroke);
        break;
      case PropShape.line:
      case PropShape.polyLine:
      case PropShape.other:
        canvas.drawLine(Offset(pad, h - pad), Offset(w - pad, pad), stroke);
        break;
      case PropShape.windowFrame:
        canvas.drawRect(Rect.fromLTRB(pad, pad, w - pad, h - pad), stroke);
        break;
      case PropShape.circle:
        canvas.drawCircle(Offset(w / 2, h / 2), (w - 2 * pad) / 2, stroke);
        canvas.drawCircle(Offset(w / 2, h / 2), (w - 2 * pad) / 4, stroke);
        break;
      case PropShape.tree:
        final path = Path()
          ..moveTo(w / 2, pad)
          ..lineTo(w - pad, h - pad)
          ..lineTo(pad, h - pad)
          ..close();
        canvas.drawPath(path, stroke);
        break;
      case PropShape.matrix:
        _drawGrid(canvas, size, fill, cols: 5, rows: 5);
        break;
      case PropShape.custom:
        _drawGrid(canvas, size, fill, cols: 4, rows: 4, dotted: true);
        break;
      case PropShape.star:
        _drawStar(canvas, size, stroke);
        break;
      case PropShape.movingHead:
        _drawMovingHead(canvas, size, stroke, fill);
        break;
      case PropShape.sphere:
        _drawSphere(canvas, size, stroke);
        break;
      case PropShape.cube:
        _drawCube(canvas, size, stroke);
        break;
    }
  }

  /// A wireframe cube: two offset squares (front/back faces) joined by
  /// diagonal edges, the standard isometric-box glyph.
  void _drawCube(Canvas canvas, Size size, Paint stroke) {
    final w = size.width;
    final h = size.height;
    final pad = w * 0.2;
    final depth = w * 0.22;

    final frontRect = Rect.fromLTRB(pad, pad + depth, w - pad - depth, h - pad);
    canvas.drawRect(frontRect, stroke);

    final backRect = Rect.fromLTRB(pad + depth, pad, w - pad, h - pad - depth);
    canvas.drawRect(backRect, stroke);

    canvas.drawLine(backRect.topLeft, frontRect.topLeft, stroke);
    canvas.drawLine(backRect.topRight, frontRect.topRight, stroke);
    canvas.drawLine(backRect.bottomLeft, frontRect.bottomLeft, stroke);
    canvas.drawLine(backRect.bottomRight, frontRect.bottomRight, stroke);
  }

  /// A globe: an outer circle with one meridian and one equator drawn as
  /// ellipses, reading as a 3D sphere rather than a flat disc.
  void _drawSphere(Canvas canvas, Size size, Paint stroke) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final r = (w - 2 * (w * 0.18)) / 2;

    canvas.drawCircle(center, r, stroke);
    // Meridian (vertical great circle, seen edge-on as a thin ellipse).
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 0.9, height: r * 2),
      stroke,
    );
    // Equator (horizontal great circle).
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 2, height: r * 0.9),
      stroke,
    );
  }

  /// A moving-head fixture: a base, a stem up to the lens, and a beam cone.
  void _drawMovingHead(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final w = size.width;
    final h = size.height;
    final pad = w * 0.18;
    final head = Offset(w / 2, h * 0.52);

    // Beam cone projecting up from the lens.
    final beam = Path()
      ..moveTo(head.dx, head.dy)
      ..lineTo(w * 0.27, pad)
      ..lineTo(w * 0.73, pad)
      ..close();
    canvas.drawPath(beam, stroke);

    // Base plate and the stem/yoke holding the head.
    canvas.drawLine(Offset(w * 0.3, h - pad), Offset(w * 0.7, h - pad), stroke);
    canvas.drawLine(Offset(w / 2, h - pad), head, stroke);

    // Lens, drawn last so it caps the beam apex.
    canvas.drawCircle(head, w * 0.13, fill);
  }

  void _drawGrid(Canvas canvas, Size size, Paint fill,
      {required int cols, required int rows, bool dotted = false}) {
    final pad = size.width * 0.16;
    final cw = (size.width - 2 * pad) / cols;
    final ch = (size.height - 2 * pad) / rows;
    final r = math.min(cw, ch) * 0.28;
    for (var c = 0; c < cols; c++) {
      for (var row = 0; row < rows; row++) {
        if (dotted && (c + row).isOdd) continue;
        final cx = pad + cw * (c + 0.5);
        final cy = pad + ch * (row + 0.5);
        canvas.drawCircle(Offset(cx, cy), r, fill);
      }
    }
  }

  void _drawStar(Canvas canvas, Size size, Paint stroke) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width * 0.36;
    final inner = outer * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) => oldDelegate.shape != shape;
}

/// Paints a small dark pill with white text showing a prop's port number
/// (e.g. "#7-12" or "#25A") just above [anchor] -- used by both the
/// interactive ControllerMapView and the rasterized PDF sectional drawings
/// so the printed and on-screen cross-sections match. [scale] is the
/// enclosing canvas's current transform factor; dividing [targetPixelSize]
/// by it keeps the label a constant size in the FINAL rendered output
/// (screen pixels for the interactive view, raster pixels for a print
/// export) regardless of what `scale` itself represents for that caller --
/// a viewport-fit factor on screen, or a fixed-print-resolution factor when
/// rasterizing, two very different magnitudes that both callers must pass
/// their own appropriate [targetPixelSize] for (the default suits the
/// on-screen view; the PDF rasterizer passes a larger one).
void paintPortLabel(
  Canvas canvas, {
  required String text,
  required Offset anchor,
  required double scale,
  double targetPixelSize = 9.0,
  bool dimmed = false,
}) {
  final fontSize = targetPixelSize / scale;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: dimmed ? 0.35 : 1.0),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final padH = 3.0 / scale;
  final padV = 1.5 / scale;
  final boxW = painter.width + padH * 2;
  final boxH = painter.height + padV * 2;
  final rect = Rect.fromLTWH(anchor.dx - boxW / 2, anchor.dy - boxH - 2 / scale, boxW, boxH);

  final bgPaint = Paint()..color = Colors.black.withValues(alpha: dimmed ? 0.18 : 0.72);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(2.5 / scale)),
    bgPaint,
  );
  painter.paint(canvas, Offset(rect.left + padH, rect.top + padV));
}
