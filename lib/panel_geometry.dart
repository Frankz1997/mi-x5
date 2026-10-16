import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum TrayEdge { top, bottom, left, right }

class TrayPlacement {
  final Offset position;
  final TrayEdge edge;
  final double anchor;
  const TrayPlacement(this.position, this.edge, this.anchor);
}

TrayPlacement trayPanelPlacement(Rect icon, Rect workArea, Size panel) {
  final center = icon.center;
  final TrayEdge edge;
  if (center.dy <= workArea.top) {
    edge = TrayEdge.top;
  } else if (center.dy >= workArea.bottom) {
    edge = TrayEdge.bottom;
  } else if (center.dx <= workArea.left) {
    edge = TrayEdge.left;
  } else if (center.dx >= workArea.right) {
    edge = TrayEdge.right;
  } else {
    final distances = {
      TrayEdge.top: (center.dy - workArea.top).abs(),
      TrayEdge.bottom: (center.dy - workArea.bottom).abs(),
      TrayEdge.left: (center.dx - workArea.left).abs(),
      TrayEdge.right: (center.dx - workArea.right).abs(),
    };
    edge = distances.entries.reduce((a, b) => a.value < b.value ? a : b).key;
  }
  final horizontal = edge == TrayEdge.top || edge == TrayEdge.bottom;
  final x = switch (edge) {
    TrayEdge.left => icon.right + 8,
    TrayEdge.right => icon.left - panel.width - 8,
    _ => center.dx - panel.width + 52,
  };
  final y = switch (edge) {
    TrayEdge.top => icon.bottom + 8,
    TrayEdge.bottom => icon.top - panel.height - 8,
    _ => center.dy - panel.height + 52,
  };
  final position = Offset(
    x.clamp(
      workArea.left,
      math.max(workArea.left, workArea.right - panel.width),
    ),
    y.clamp(
      workArea.top,
      math.max(workArea.top, workArea.bottom - panel.height),
    ),
  );
  final anchor =
      horizontal
          ? (center.dx - position.dx - 8) / (panel.width - 16)
          : (center.dy - position.dy - 8) / (panel.height - 16);
  return TrayPlacement(position, edge, anchor);
}

EdgeInsets pointerInsets(TrayEdge edge) => switch (edge) {
  TrayEdge.top => const EdgeInsets.only(top: 16),
  TrayEdge.bottom => const EdgeInsets.only(bottom: 16),
  TrayEdge.left => const EdgeInsets.only(left: 16),
  TrayEdge.right => const EdgeInsets.only(right: 16),
};

Path panelOutline(Size size, TrayEdge edge, double fraction) {
  final horizontal = edge == TrayEdge.top || edge == TrayEdge.bottom;
  final span = horizontal ? size.width : size.height;
  final depth = horizontal ? size.height : size.width;
  final anchor =
      (span * fraction).clamp(44.0, math.max(44.0, span - 44)).toDouble();
  final path =
      Path()
        ..moveTo(27, 17)
        ..lineTo(anchor - 16, 17)
        ..cubicTo(anchor - 10, 17, anchor - 7, 1, anchor, 1)
        ..cubicTo(anchor + 7, 1, anchor + 10, 17, anchor + 16, 17)
        ..lineTo(span - 27, 17)
        ..quadraticBezierTo(span - 1, 17, span - 1, 43)
        ..lineTo(span - 1, depth - 27)
        ..quadraticBezierTo(span - 1, depth - 1, span - 27, depth - 1)
        ..lineTo(27, depth - 1)
        ..quadraticBezierTo(1, depth - 1, 1, depth - 27)
        ..lineTo(1, 43)
        ..quadraticBezierTo(1, 17, 27, 17)
        ..close();
  final matrix = switch (edge) {
    TrayEdge.top => [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    TrayEdge.bottom => [1.0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, depth, 0, 1],
    TrayEdge.left => [0.0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    TrayEdge.right => [0.0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, depth, 0, 0, 1],
  };
  return path.transform(
    Float64List.fromList(matrix.map((n) => n.toDouble()).toList()),
  );
}

List<double> backdropOutline(Size window, TrayEdge edge, double anchor) {
  final shape = panelOutline(
    Size(window.width - 16, window.height - 16),
    edge,
    anchor,
  ).shift(const Offset(8, 8));
  final points = <double>[];
  for (final contour in shape.computeMetrics()) {
    for (var distance = 0.0; distance < contour.length; distance += 2) {
      final point = contour.getTangentForOffset(distance)!.position;
      points.addAll([point.dx, point.dy]);
    }
  }
  return points;
}
