import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../ui/prop_icons.dart';
import 'layout_map.dart';

/// Longest side (in rasterized pixels) an exported map image is scaled to,
/// balancing print sharpness against a reasonable file size/render time even
/// for a very large layout.
const int kMapRasterTargetLongestSide = 2400;

/// Renders a [LayoutMap] to PNG bytes via a plain [ui.PictureRecorder] (there's
/// no vector "PDF canvas" equivalent to `dart:ui`'s `Canvas` readily available
/// in the `pdf` package), so this always captures the whole map at a fixed
/// target resolution regardless of what's currently on screen. Shared by
/// [PreviewPdf] (the whole-layout map) and [ReportPdf] (one rasterized map
/// per controller, for the printed Controller Wiring sectional drawings).
Future<Uint8List> rasterizeLayoutMap(
  LayoutMap map, {
  int targetLongestSide = kMapRasterTargetLongestSide,
  bool showPortLabels = false,
}) async {
  final scale = (targetLongestSide / math.max(map.canvasWidth, map.canvasHeight))
      .clamp(0.5, 4.0);
  final pixelW = (map.canvasWidth * scale).round();
  final pixelH = (map.canvasHeight * scale).round();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(scale);
  canvas.drawRect(
    ui.Offset.zero & ui.Size(map.canvasWidth, map.canvasHeight),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );

  for (final g in map.placed) {
    final paint = ui.Paint()
      ..color = ui.Color.fromRGBO(0, 0, 0, g.prop.isAssigned ? 0.9 : 0.35)
      ..strokeWidth = g.dotSize
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawPoints(ui.PointMode.points, g.canvasPoints, paint);

    // Only used for the per-controller sectional drawings (ReportPdf) --
    // the whole-layout Preview export leaves this off to avoid plastering a
    // single page with every prop's label.
    if (showPortLabels && g.prop.port > 0) {
      paintPortLabel(
        canvas,
        text: '#${g.prop.portRange}${g.prop.smartRemoteLetter}',
        anchor: ui.Offset((g.canvasLeft + g.canvasRight) / 2, g.canvasTop),
        scale: scale,
        // Larger than the on-screen default: `scale` here targets a fixed
        // print resolution (kMapRasterTargetLongestSide), not a viewport fit,
        // so this needs to land as a legible size on paper, not a screen.
        targetPixelSize: 26.0,
      );
    }
  }

  const iconSize = 28.0;
  for (final p in map.iconOnly) {
    final center = map.toCanvas(p.worldPosX, p.worldPosY);
    final rect = ui.Rect.fromCenter(center: center, width: iconSize, height: iconSize);
    if (p.isAssigned) {
      paintPropShapeIcon(canvas, rect, p.shape);
    } else {
      // Group-opacity trick: saveLayer's paint alpha scales everything
      // drawn before the matching restore(), same as the Opacity widget.
      canvas.saveLayer(rect.inflate(2), ui.Paint()..color = const ui.Color.fromARGB(115, 0, 0, 0));
      paintPropShapeIcon(canvas, rect, p.shape);
      canvas.restore();
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelW, pixelH);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
