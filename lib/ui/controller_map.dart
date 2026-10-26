import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/prop.dart';
import '../services/layout_map.dart';
import 'prop_icons.dart';

/// An interactive, pan/zoomable cross-section map of one controller's props
/// -- scoped to just that controller (via [buildLayoutMap], same geometry/
/// placement code the full Preview tab uses, including its InteractiveViewer
/// pan/zoom pattern). Tapping a prop's dot cloud selects it; [selected]
/// drives both this map's highlight and the matching row in the port list
/// beside it (see CondensedTab), so the two stay in sync regardless of which
/// one the user clicks.
class ControllerMapView extends StatefulWidget {
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
  State<ControllerMapView> createState() => _ControllerMapViewState();
}

class _ControllerMapViewState extends State<ControllerMapView> {
  final _viewer = TransformationController();
  bool _fitted = false;

  @override
  void didUpdateWidget(covariant ControllerMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fit when this map starts showing a different controller's props
    // (list identity changes whenever CondensedTab rebuilds its groups);
    // keep the current pan/zoom if it's still the same controller re-rendering.
    if (!identical(oldWidget.props, widget.props)) {
      _fitted = false;
    }
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  void _fitToView(Size viewport, Size content) {
    final scaleX = viewport.width / content.width;
    final scaleY = viewport.height / content.height;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.02, 8.0);
    final dx = (viewport.width - content.width * scale) / 2;
    final dy = (viewport.height - content.height * scale) / 2;
    _viewer.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.props.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text('No positioned props', style: theme.textTheme.bodySmall),
        ),
      );
    }
    final map = buildLayoutMap(widget.props);
    final content = Size(map.canvasWidth, map.canvasHeight);

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);

          if (!_fitted) {
            _fitted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fitToView(viewport, content);
            });
          }

          void handleTapUp(TapUpDetails details) {
            // InteractiveViewer transforms its child, but a descendant
            // GestureDetector's localPosition is already reported in the
            // child's own untransformed coordinate space -- no manual
            // scale/offset math needed here regardless of current zoom/pan.
            final local = details.localPosition;
            XProp? hit;
            for (final g in map.placed) {
              if (local.dx >= g.canvasLeft &&
                  local.dx <= g.canvasRight &&
                  local.dy >= g.canvasTop &&
                  local.dy <= g.canvasBottom) {
                hit = g.prop; // last match wins -- same as the Preview tab's top-most-drawn convention
              }
            }
            widget.onSelect(identical(hit, widget.selected) ? null : hit);
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  InteractiveViewer(
                    transformationController: _viewer,
                    constrained: false,
                    minScale: 0.05,
                    maxScale: 8,
                    boundaryMargin: const EdgeInsets.all(200),
                    child: SizedBox(
                      width: content.width,
                      height: content.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: handleTapUp,
                        child: CustomPaint(
                          size: content,
                          painter: _ControllerMapPainter(
                            placed: map.placed,
                            normalColor: theme.colorScheme.primary,
                            highlightColor: theme.colorScheme.tertiary,
                            selected: widget.selected,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: FloatingActionButton.small(
                      heroTag: null, // many of these exist on one scrollable page at once
                      tooltip: 'Fit to view',
                      onPressed: () => _fitToView(viewport, content),
                      child: const Icon(Icons.fit_screen, size: 18),
                    ),
                  ),
                ],
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
    required this.normalColor,
    required this.highlightColor,
    required this.selected,
  });

  final List<PlacedGeometry> placed;
  final Color normalColor;
  final Color highlightColor;
  final XProp? selected;

  @override
  void paint(Canvas canvas, Size size) {
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
          ..strokeWidth = 1.5
          ..color = highlightColor.withValues(alpha: 0.9);
        canvas.drawRect(
          Rect.fromLTRB(g.canvasLeft, g.canvasTop, g.canvasRight, g.canvasBottom),
          boxPaint,
        );
      }

      if (g.prop.port > 0) {
        paintPortLabel(
          canvas,
          text: '#${g.prop.portRange}${g.prop.smartRemoteLetter}',
          anchor: Offset((g.canvasLeft + g.canvasRight) / 2, g.canvasTop),
          // Canvas-unit font size (not scale-compensated): InteractiveViewer
          // itself provides the zoom, so labels naturally get bigger/smaller
          // as the user zooms, same as the dots do -- the expected behavior
          // for a zoomable map, matching the Preview tab's own dots.
          fontSize: 13,
          dimmed: dimmed,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ControllerMapPainter old) =>
      old.placed != placed || old.selected != selected;
}
