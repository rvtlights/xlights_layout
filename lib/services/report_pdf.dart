import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/prop.dart';
import 'layout_map.dart';
import 'layout_store.dart';
import 'map_rasterizer.dart';
import 'print_orientation.dart';

/// Builds a printable PDF of either report view. Used by `Printing.layoutPdf`,
/// which handles the native print dialog on desktop/mobile and the browser
/// print dialog on web from the same document.
class ReportPdf {
  static Future<Uint8List> build(
    PdfPageFormat format,
    LayoutStore store, {
    required bool detailed,
    PrintOrientation orientation = PrintOrientation.auto,
  }) async {
    final doc = pw.Document(title: 'xLights Layout');
    // Tables have no natural aspect ratio the way a map image does, so
    // `auto` keeps the previous default of landscape (more columns fit).
    final pageFormat = orientation
        .resolve(format, fallbackLandscape: true)
        .copyWith(marginTop: 24, marginBottom: 24, marginLeft: 24, marginRight: 24);

    final content = detailed ? _detailed(store) : await _condensed(store);

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        build: (context) => content,
      ),
    );
    return doc.save();
  }

  // ---- Detailed view -------------------------------------------------------

  static List<pw.Widget> _detailed(LayoutStore store) {
    return [
      if (store.controllers.isNotEmpty) ...[
        _heading('Controllers (${store.visibleControllers.length})'),
        _table(
          headers: const [
            'Name', 'Description', 'IP (protocol)', 'Vendor',
            'Model (Variant)', 'ID', 'Universes', 'Channels',
          ],
          rows: [
            for (final c in store.visibleControllers)
              [
                c.name,
                c.description,
                c.ipProtocol,
                c.vendor,
                c.modelVariant,
                c.id,
                c.universes > 0 ? '${c.universes}' : '',
                c.channels > 0 ? '${c.channels}' : '',
              ],
          ],
        ),
        pw.SizedBox(height: 18),
      ],
      _heading('Props (${store.props.length})'),
      _table(
        headers: const [
          'Prop Name', 'Node Count', 'Channel Count', 'Controller',
          'Universe', 'Start Channel', 'Controller Connection',
        ],
        rows: [
          for (final p in store.propsByName)
            [
              p.name,
              p.nodeCount > 0 ? '${p.nodeCount}' : '',
              p.channelCount > 0 ? '${p.channelCount}' : '',
              p.controllerName == 'No Controller' ? '' : p.controllerName,
              p.universe > 0 ? '${p.universe}' : '',
              p.startChannel > 0 ? '${p.startChannel}' : '',
              p.connectionLabel,
            ],
        ],
      ),
    ];
  }

  // ---- Condensed view (Controller Wiring) -----------------------------------

  /// One page per controller: a rasterized cross-section map of just that
  /// controller's props (same geometry/placement the on-screen
  /// ControllerMapView uses) above its full port table -- the "sectional
  /// drawing" an installer can carry on paper. Unassigned props get a
  /// table-only section first since there's no controller to map them onto.
  static Future<List<pw.Widget>> _condensed(LayoutStore store) async {
    final data = store.grouped;
    final widgets = <pw.Widget>[];
    var firstSection = true;

    if (!store.hideUnassigned && data.notAssigned.isNotEmpty) {
      widgets.add(_groupHeading('not assigned', italic: true));
      widgets.add(_groupBox([
        for (final p in data.notAssigned) _Row.prop('', p.name),
      ]));
      firstSection = false;
    }

    for (final group in data.groups) {
      if (!firstSection) widgets.add(pw.NewPage());
      firstSection = false;

      widgets.add(_groupHeading(group.name));

      final props = group.allProps;
      if (props.isNotEmpty) {
        final map = buildLayoutMap(props);
        final pngBytes = await rasterizeLayoutMap(map, showPortLabels: true);
        widgets.add(
          pw.ConstrainedBox(
            constraints: const pw.BoxConstraints(maxHeight: 260),
            child: pw.Center(
              child: pw.Image(pw.MemoryImage(pngBytes), fit: pw.BoxFit.contain),
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 10));
      }

      widgets.add(_groupBox(_rowsFor(group)));
    }

    return widgets;
  }

  static List<_Row> _rowsFor(ControllerGroup group) {
    final rows = <_Row>[];

    void addPortProps(List<XProp> props) {
      for (var i = 0; i < props.length; i++) {
        rows.add(_Row.prop(
          condensedPortLabel(props[i], firstOnPort: i == 0),
          props[i].name,
        ));
      }
    }

    void portSection(String title, Map<int, List<XProp>> ports) {
      if (ports.isEmpty) return;
      rows.add(_Row.header(title));
      for (final port in ControllerGroup.sortedKeys(ports)) {
        addPortProps(ports[port]!);
      }
    }

    portSection('String Ports', group.stringPorts);
    for (final receiver in group.sortedReceivers) {
      rows.add(_Row.header(group.smartReceiverLabel(receiver)));
      for (final port in receiver.sortedPorts) {
        addPortProps(receiver.ports[port]!);
      }
    }
    portSection('LED Panel Matrix', group.panelPorts);
    portSection('Serial Ports', group.serialPorts);
    for (final p in group.unported) {
      rows.add(_Row.prop(p.displayAs, p.name));
    }
    return rows;
  }

  // ---- Shared building blocks ----------------------------------------------

  static pw.Widget _heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _groupHeading(String text, {bool italic = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4, top: 2),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
          ),
        ),
      );

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellHeight: 14,
      cellAlignment: pw.Alignment.centerLeft,
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );
  }

  static pw.Widget _groupBox(List<_Row> rows) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Table(
        columnWidths: const {
          0: pw.FixedColumnWidth(130),
          1: pw.FlexColumnWidth(),
        },
        children: [
          for (var i = 0; i < rows.length; i++)
            if (rows[i].isHeader)
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
                    child: pw.Text(rows[i].col0,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(),
                ],
              )
            else
              pw.TableRow(
                decoration: i.isOdd
                    ? const pw.BoxDecoration(color: PdfColors.grey100)
                    : null,
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
                    child: pw.Text(rows[i].col0, style: const pw.TextStyle(fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
                    child: pw.Text(rows[i].col1, style: const pw.TextStyle(fontSize: 9)),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// A row in a condensed group box: a bold section header or a port/name pair.
class _Row {
  _Row.header(this.col0)
      : col1 = '',
        isHeader = true;
  _Row.prop(this.col0, this.col1) : isHeader = false;

  final String col0;
  final String col1;
  final bool isHeader;
}
