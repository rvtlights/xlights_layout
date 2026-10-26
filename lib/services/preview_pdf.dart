import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'layout_map.dart';
import 'layout_store.dart';
import 'map_rasterizer.dart';
import 'print_orientation.dart';

/// Builds a one-page, image-based PDF of the Layout Preview tab's site map --
/// unlike [ReportPdf]'s tables, this is a raster export (see
/// [rasterizeLayoutMap]) rendered at a fixed target resolution rather than
/// mounting the on-screen widget tree, so it always captures the whole map
/// regardless of the current pan/zoom.
class PreviewPdf {
  static Future<Uint8List> build(
    PdfPageFormat format,
    LayoutStore store, {
    String? group,
    PrintOrientation orientation = PrintOrientation.auto,
  }) async {
    final props = group == null
        ? store.props
        : store.props.where((p) => p.layoutGroup == group).toList();
    final map = buildLayoutMap(props);
    final pngBytes = await rasterizeLayoutMap(map);

    final doc = pw.Document(title: 'xLights Layout Preview');
    final image = pw.MemoryImage(pngBytes);
    final pageFormat = orientation
        .resolve(format, fallbackLandscape: map.canvasWidth >= map.canvasHeight)
        .copyWith(marginTop: 24, marginBottom: 24, marginLeft: 24, marginRight: 24);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    return doc.save();
  }
}
