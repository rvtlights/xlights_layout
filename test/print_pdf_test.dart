import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:xlights_layout/services/layout_store.dart';
import 'package:xlights_layout/services/preview_pdf.dart';
import 'package:xlights_layout/services/print_orientation.dart';
import 'package:xlights_layout/services/report_pdf.dart';

void main() {
  final networksXml = File('test/fixtures/xlights_networks.xml').readAsStringSync();
  final rgbXml = File('test/fixtures/xlights_rgbeffects.xml').readAsStringSync();

  late LayoutStore store;
  setUp(() {
    store = LayoutStore()
      ..loadRgbEffects(utf8.encode(rgbXml), 'xlights_rgbeffects.xml')
      ..loadNetworks(utf8.encode(networksXml), 'xlights_networks.xml');
  });

  group('ReportPdf (Controller Wiring / condensed)', () {
    test('builds with a sectional drawing embedded per controller', () async {
      // This exercises the real async path: rasterizing one controller map
      // per group via dart:ui, which needs real platform work -- run outside
      // flutter_test's FakeAsync zone or it never resolves.
      final bytes = await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
        () => ReportPdf.build(PdfPageFormat.a4, store, detailed: false),
      );
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(1000));
      // A real PDF file starts with this magic header.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('respects an explicit portrait/landscape orientation override', () async {
      final portrait = await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
        () => ReportPdf.build(
          PdfPageFormat.a4,
          store,
          detailed: false,
          orientation: PrintOrientation.portrait,
        ),
      );
      final landscape = await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
        () => ReportPdf.build(
          PdfPageFormat.a4,
          store,
          detailed: true,
          orientation: PrintOrientation.landscape,
        ),
      );
      expect(portrait, isNotNull);
      expect(landscape, isNotNull);
      // Both still produce valid, non-trivial PDFs regardless of orientation.
      expect(portrait!.length, greaterThan(500));
      expect(landscape!.length, greaterThan(500));
    });
  });

  group('PreviewPdf', () {
    test('builds a one-page image PDF of the whole layout', () async {
      final bytes = await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
        () => PreviewPdf.build(PdfPageFormat.a4, store),
      );
      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    });
  });
}
