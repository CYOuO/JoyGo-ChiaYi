import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════
//  縫線布塊 — 給「快速導覽」圖標加上內縮虛線縫邊。
// ═══════════════════════════════════════════════════════════

/// 共用虛線繪製。
void drawDashedPath(
    Canvas canvas, Path source, Paint paint, double dash, double gap) {
  for (final metric in source.computeMetrics()) {
    double dist = 0;
    while (dist < metric.length) {
      final next = dist + dash;
      canvas.drawPath(
        metric.extractPath(dist, next.clamp(0, metric.length).toDouble()),
        paint,
      );
      dist = next + gap;
    }
  }
}

class _StitchRectPainter extends CustomPainter {
  final Color stitchColor;
  final double radius, inset, dash, gap, strokeWidth;
  const _StitchRectPainter({
    required this.stitchColor,
    required this.radius,
    required this.inset,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
        inset, inset, size.width - inset * 2, size.height - inset * 2);
    if (r.width <= 0 || r.height <= 0) return;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          r, Radius.circular((radius - inset).clamp(0, radius))));
    drawDashedPath(
      canvas,
      path,
      Paint()
        ..color = stitchColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
      dash,
      gap,
    );
  }

  @override
  bool shouldRepaint(covariant _StitchRectPainter old) =>
      old.stitchColor != stitchColor ||
      old.radius != radius ||
      old.inset != inset;
}

// ═══════════════════════════════════════════════════════════
//  SketchyBorderBox — 手繪風不規則邊框（微微晃動的線條）
// ═══════════════════════════════════════════════════════════

class _SketchyBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double wobble;
  final int seed;
  const _SketchyBorderPainter({
    required this.color, this.strokeWidth = 1.5, this.wobble = 2.5, this.seed = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final r = 12.0;
    final w = size.width, h = size.height;
    // Draw 2 slightly offset passes for a sketchy double-line effect
    for (int pass = 0; pass < 2; pass++) {
      final ox = (pass == 0 ? 0.0 : 0.8);
      final oy = (pass == 0 ? 0.0 : -0.6);
      final path = Path();
      // Top edge (left to right with wobble)
      path.moveTo(r + ox, 0 + oy);
      for (double x = r; x < w - r; x += 14) {
        final wobY = ((x * 7 + seed).hashCode % 100) / 100 * wobble - wobble / 2;
        path.lineTo(x + ox, wobY + oy);
      }
      // Top-right corner
      path.quadraticBezierTo(w + ox, 0 + oy, w + ox, r + oy);
      // Right edge
      for (double y = r; y < h - r; y += 14) {
        final wobX = ((y * 11 + seed).hashCode % 100) / 100 * wobble - wobble / 2;
        path.lineTo(w + wobX + ox, y + oy);
      }
      // Bottom-right corner
      path.quadraticBezierTo(w + ox, h + oy, w - r + ox, h + oy);
      // Bottom edge
      for (double x = w - r; x > r; x -= 14) {
        final wobY = ((x * 13 + seed).hashCode % 100) / 100 * wobble - wobble / 2;
        path.lineTo(x + ox, h + wobY + oy);
      }
      // Bottom-left corner
      path.quadraticBezierTo(0 + ox, h + oy, 0 + ox, h - r + oy);
      // Left edge
      for (double y = h - r; y > r; y -= 14) {
        final wobX = ((y * 17 + seed).hashCode % 100) / 100 * wobble - wobble / 2;
        path.lineTo(wobX + ox, y + oy);
      }
      // Top-left corner
      path.quadraticBezierTo(0 + ox, 0 + oy, r + ox, 0 + oy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchyBorderPainter old) =>
      old.color != color || old.seed != seed;
}

class SketchyBorderBox extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final Color? fillColor;
  final double strokeWidth;
  final EdgeInsetsGeometry padding;
  final int seed;

  const SketchyBorderBox({
    super.key, required this.child, required this.borderColor,
    this.fillColor, this.strokeWidth = 1.5,
    this.padding = const EdgeInsets.all(12), this.seed = 0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: fillColor != null ? null : null,
      foregroundPainter: _SketchyBorderPainter(
        color: borderColor, strokeWidth: strokeWidth, seed: seed),
      child: Container(
        decoration: fillColor != null ? BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(12)) : null,
        padding: padding, child: child),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  NotebookLines — 橫線筆記本底紋
// ═══════════════════════════════════════════════════════════

class _NotebookLinesPainter extends CustomPainter {
  final Color lineColor;
  final double spacing;
  const _NotebookLinesPainter({required this.lineColor, this.spacing = 28});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(16, y), Offset(size.width - 16, y), paint);
    }
    // Red margin line (left)
    canvas.drawLine(
      Offset(42, 0), Offset(42, size.height),
      Paint()..color = const Color(0x30E57373)..strokeWidth = 0.7);
  }

  @override
  bool shouldRepaint(covariant _NotebookLinesPainter old) => false;
}

class NotebookBackground extends StatelessWidget {
  final Widget child;
  final Color lineColor;
  final double lineSpacing;
  const NotebookBackground({super.key, required this.child,
    this.lineColor = const Color(0x188FAABE), this.lineSpacing = 28});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NotebookLinesPainter(lineColor: lineColor, spacing: lineSpacing),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  HandDrawnUnderline — 手繪底線（不完美的波浪線）
// ═══════════════════════════════════════════════════════════

class _HandUnderlinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _HandUnderlinePainter({required this.color, this.strokeWidth = 2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    final y = size.height - 2;
    path.moveTo(0, y);
    for (double x = 0; x < size.width; x += 8) {
      final wobble = ((x * 7).hashCode % 50) / 50 * 3 - 1.5;
      path.lineTo(x, y + wobble);
    }
    path.lineTo(size.width, y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HandUnderlinePainter old) => old.color != color;
}

class HandDrawnUnderline extends StatelessWidget {
  final Widget child;
  final Color? color;
  const HandDrawnUnderline({super.key, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);
    return CustomPaint(
      foregroundPainter: _HandUnderlinePainter(color: c),
      child: Padding(padding: const EdgeInsets.only(bottom: 4), child: child),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  DoodleCircle — 手繪不規則圓圈裝飾
// ═══════════════════════════════════════════════════════════

class _DoodleCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _DoodleCirclePainter({required this.color, this.strokeWidth = 1.5});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = (size.width < size.height ? size.width : size.height) / 2 - 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (int i = 0; i <= 36; i++) {
      final angle = i * 3.14159 * 2 / 36;
      final wobble = 1.0 + ((i * 7).hashCode % 30) / 100 * 0.12;
      final x = cx + r * wobble * math.cos(angle);
      final y = cy + r * wobble * math.sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DoodleCirclePainter old) => old.color != color;
}

class DoodleCircle extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double size;
  const DoodleCircle({super.key, required this.child, this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5);
    return SizedBox(width: size, height: size,
      child: CustomPaint(
        painter: _DoodleCirclePainter(color: c),
        child: Center(child: child)));
  }
}

/// 任意內容外加填色 + 內縮虛線縫邊。
class StitchedBox extends StatelessWidget {
  final Widget child;
  final Color color;
  final Color stitchColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? boxShadow;
  final double inset;
  final double dashWidth;
  final double dashGap;
  final double stitchStrokeWidth;

  const StitchedBox({
    super.key,
    required this.child,
    required this.color,
    required this.stitchColor,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
    this.boxShadow,
    this.inset = 4.5,
    this.dashWidth = 5,
    this.dashGap = 4,
    this.stitchStrokeWidth = 1.3,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: boxShadow,
      ),
      child: CustomPaint(
        foregroundPainter: _StitchRectPainter(
          stitchColor: stitchColor,
          radius: radius,
          inset: inset,
          dash: dashWidth,
          gap: dashGap,
          strokeWidth: stitchStrokeWidth,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
