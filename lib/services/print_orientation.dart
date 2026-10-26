import 'package:pdf/pdf.dart';

/// User-selectable page orientation for printed/exported PDFs (the Print
/// menu in the app bar). `auto` preserves each export's previous
/// content-shape-based default; portrait/landscape force that orientation
/// regardless of content shape.
enum PrintOrientation {
  auto,
  portrait,
  landscape;

  String get label => switch (this) {
        PrintOrientation.auto => 'Auto',
        PrintOrientation.portrait => 'Portrait',
        PrintOrientation.landscape => 'Landscape',
      };
}

extension PrintOrientationResolve on PrintOrientation {
  /// Resolves this choice to a concrete [PdfPageFormat]. [fallbackLandscape]
  /// is only consulted for `auto` (e.g. "is this content wider than tall?").
  PdfPageFormat resolve(PdfPageFormat format, {required bool fallbackLandscape}) {
    switch (this) {
      case PrintOrientation.portrait:
        return format.portrait;
      case PrintOrientation.landscape:
        return format.landscape;
      case PrintOrientation.auto:
        return fallbackLandscape ? format.landscape : format.portrait;
    }
  }
}
