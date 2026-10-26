import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/prop.dart';
import '../services/layout_map.dart';
import 'prop_icons.dart';

/// A static, fit-to-box cross-section map of one controller's props --
/// scoped to just that controller (via [buildLayoutMap], same geometry/
/// placement code the full Preview tab uses). Tapping a prop's dot cloud
/// selects it; [selected] drives both this map's highlight and the matching
/// row in the port list beside it (see CondensedTab), so the two stay in
/// sync regardless of which one the user clicks.
///
/// Deliberately not pan/zoomable: an InteractiveViewer here (tried briefly)
/// intercepts scroll/drag gestures meant for the surrounding page, which
/// felt "touchy" since this widget sits inside CondensedTab's scrollable
/// list, not in its own dedicated viewport the way the full-layout Preview
/// tab is.
class ControllerMapView extends StatelessWidget {
  const ControllerMapView({
    super.key,
    required this.props,
    required this.selected,
    required this.onSelect,
    this.height = 420,
  });

  final List<XProp> props;
  final XProp? selected;
  final ValueChanged<XProp?> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (props.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No positioned props', style: theme.textTheme.bodySmall),
        ),
      );
    }
    final map = buildLayoutMap(props);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaleX = constraints.maxWidth / map.canvasWidth;
          final scaleY = constraints.maxHeight / map.canvasHeight;
          final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.02, 8.0);
          final drawnW = map.canvasWidth * scale;
          final drawnH = map.canvasHeight * scale;
          final offset = Offset(
            (constraints.maxWidth - drawnW) / 2,
            (constraints.maxHeight - drawnH) / 2,
          );

          void handleTapUp(TapUpDetails details) {
            final local = (details.localPosition - offset) / scale;
            XProp? hit;
            for (final g in map.placed) {
              if (local.dx >= g.canvasLeft &&
                  local.dx <= g.canvasRight &&
                  local.dy >= g.canvasTop &&
                  local.dy <= g.canvasBottom) {
                hit = g.prop; // last match wins -- same as the Preview tab's top-most-drawn convention
              }
            }
            onSelect(identical(hit, selected) ? null : hit);
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: handleTapUp,
                child: CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _ControllerMapPainter(
                    placed: map.placed,
                    scale: scale,
                    offset: offset,
                    normalColor: theme.colorScheme.primary,
                    highlightColor: theme.colorScheme.tertiary,
                    selected: selected,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ControllerMapPainter extends CustomPainter {
  _ControllerMapPainter({
    required this.placed,
    required this.scale,
    required this.offset,
    required this.normalColor,
    required this.highlightColor,
    required this.selected,
  });

  final List<PlacedGeometry> placed;
  final double scale;
  final Offset offset;
  final Color normalColor;
  final Color highlightColor;
  final XProp? selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale, scale);

    for (final g in placed) {
      final isSelected = identical(g.prop, selected);
      final dimmed = selected != null && !isSelected;
      final paint = Paint()
        ..color = (isSelected ? highlightColor : normalColor).withValues(
          alpha: dimmed ? 0.22 : (g.prop.isAssigned ? 0.95 : 0.4),
        )
        ..strokeWidth = isSelected ? g.dotSize * 1.8 : g.dotSize
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, g.canvasPoints, paint);

      if (isSelected) {
        final boxPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..color = highlightColor.withValues(alpha: 0.9);
        canvas.drawRect(
          Rect.fromLTRB(g.canvasLeft, g.canvasTop, g.canvasRight, g.canvasBottom),
          boxPaint,
        );
      }

      if (g.prop.port > 0) {
        // Divide a target on-screen pixel size by `scale` so the label
        // stays a roughly constant, legible size across controllers
        // regardless of how zoomed-in/out this particular fit ended up.
        paintPortLabel(
          canvas,
          text: '#${g.prop.portRange}${g.prop.smartRemoteLetter}',
          anchor: Offset((g.canvasLeft + g.canvasRight) / 2, g.canvasTop),
          fontSize: 9.0 / scale,
          dimmed: dimmed,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ControllerMapPainter old) =>
      old.placed != placed || old.scale != scale || old.offset != offset || old.selected != selected;
}
