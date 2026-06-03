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
  final Color marginColor;
  final double spacing;
  const _NotebookLinesPainter({
    required this.lineColor,
    required this.marginColor,
    this.spacing = 28,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(16, y), Offset(size.width - 16, y), paint);
    }
    // Margin line (left) — uses theme-aware color
    canvas.drawLine(
      const Offset(42, 0), Offset(42, size.height),
      Paint()..color = marginColor..strokeWidth = 0.7);
  }

  @override
  bool shouldRepaint(covariant _NotebookLinesPainter old) =>
      old.lineColor != lineColor || old.marginColor != marginColor;
}

class NotebookBackground extends StatelessWidget {
  final Widget child;
  final Color lineColor;
  final Color? marginColor; // null = auto from theme
  final double lineSpacing;
  const NotebookBackground({super.key, required this.child,
    this.lineColor = const Color(0x188FAABE),
    this.marginColor,
    this.lineSpacing = 28});

  @override
  Widget build(BuildContext context) {
    final mc = marginColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.18);
    return CustomPaint(
      painter: _NotebookLinesPainter(
          lineColor: lineColor, marginColor: mc, spacing: lineSpacing),
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

// ═══════════════════════════════════════════════════════════
//  DoodleHeart — 手繪愛心裝飾
// ═══════════════════════════════════════════════════════════

class _DoodleHeartPainter extends CustomPainter {
  final Color color;
  const _DoodleHeartPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final p = Paint()..color = color..style = PaintingStyle.fill;
    // More proportional heart — taller than wide
    final path = Path()
      ..moveTo(cx, h * 0.88)           // bottom tip
      ..cubicTo(w * -0.05, h * 0.60,   // left outer ctrl
                w * -0.05, h * 0.10,   // left inner ctrl
                cx,         h * 0.30)  // top centre dip
      ..cubicTo(w * 1.05,  h * 0.10,   // right inner ctrl
                w * 1.05,  h * 0.60,   // right outer ctrl
                cx,         h * 0.88)  // back to bottom tip
      ..close();
    canvas.drawPath(path, p);
  }
  @override
  bool shouldRepaint(covariant _DoodleHeartPainter old) => old.color != color;
}

class SlideUpFadeIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration staggerDelay;
  final Duration duration;
  const SlideUpFadeIn({super.key, required this.child, this.index = 0, this.staggerDelay = const Duration(milliseconds: 60), this.duration = const Duration(milliseconds: 400)});
  @override State<SlideUpFadeIn> createState() => _SlideUpFadeInState();
}
class _SlideUpFadeInState extends State<SlideUpFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(widget.staggerDelay * widget.index, () { if (mounted) _ctrl.forward(); });
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: SlideTransition(position: _slide, child: widget.child));
}

class DoodleHeart extends StatelessWidget {
  final Color? color;
  final double size;
  const DoodleHeart({super.key, this.color, this.size = 12});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.55);
    return SizedBox(width: size, height: size,
      child: CustomPaint(painter: _DoodleHeartPainter(color: c)));
  }
}

// ═══════════════════════════════════════════════════════════
//  DoodleLightning — 手繪閃電裝飾
// ═══════════════════════════════════════════════════════════

class _DoodleLightningPainter extends CustomPainter {
  final Color color;
  const _DoodleLightningPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(w * 0.63, 0)
      ..lineTo(w * 0.22, h * 0.50)
      ..lineTo(w * 0.52, h * 0.50)
      ..lineTo(w * 0.37, h)
      ..lineTo(w * 0.78, h * 0.50)
      ..lineTo(w * 0.48, h * 0.50)
      ..close();
    canvas.drawPath(path, p);
  }
  @override
  bool shouldRepaint(covariant _DoodleLightningPainter old) => old.color != color;
}

class DoodleLightning extends StatelessWidget {
  final Color? color;
  final double size;
  const DoodleLightning({super.key, this.color, this.size = 10});
  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFE8A020).withValues(alpha: 0.85);
    return SizedBox(width: size, height: size * 1.4,
      child: CustomPaint(painter: _DoodleLightningPainter(color: c)));
  }
}

// ═══════════════════════════════════════════════════════════
//  DoodleCloud — 手繪雲朵裝飾
// ═══════════════════════════════════════════════════════════

class _DoodleCloudPainter extends CustomPainter {
  final Color color;
  const _DoodleCloudPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.28, h * 0.60), w * 0.22, p);
    canvas.drawCircle(Offset(w * 0.50, h * 0.46), w * 0.27, p);
    canvas.drawCircle(Offset(w * 0.72, h * 0.58), w * 0.20, p);
    canvas.drawRect(Rect.fromLTWH(w * 0.08, h * 0.56, w * 0.84, h * 0.36), p);
  }
  @override
  bool shouldRepaint(covariant _DoodleCloudPainter old) => old.color != color;
}

class DoodleCloud extends StatelessWidget {
  final Color? color;
  final double width;
  const DoodleCloud({super.key, this.color, this.width = 28});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withValues(alpha: 0.65);
    return SizedBox(width: width, height: width * 0.6,
      child: CustomPaint(painter: _DoodleCloudPainter(color: c)));
  }
}

// ═══════════════════════════════════════════════════════════
//  DoodleButton — 手繪縫釦裝飾
// ═══════════════════════════════════════════════════════════

class _DoodleButtonPainter extends CustomPainter {
  final Color color;
  const _DoodleButtonPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r  = size.width / 2;
    canvas.drawCircle(Offset(cx, cy), r - 1,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.4);
    final hr = r * 0.14, off = r * 0.30;
    final fill = Paint()..color = color..style = PaintingStyle.fill;
    for (final dx in [-off, off])
      for (final dy in [-off, off])
        canvas.drawCircle(Offset(cx + dx, cy + dy), hr, fill);
    final thread = Paint()..color = color..strokeWidth = 0.7..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - off, cy - off), Offset(cx + off, cy + off), thread);
    canvas.drawLine(Offset(cx + off, cy - off), Offset(cx - off, cy + off), thread);
  }
  @override
  bool shouldRepaint(covariant _DoodleButtonPainter old) => old.color != color;
}

class DoodleButton extends StatelessWidget {
  final Color? color;
  final double size;
  const DoodleButton({super.key, this.color, this.size = 15});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.45);
    return SizedBox(width: size, height: size,
      child: CustomPaint(painter: _DoodleButtonPainter(color: c)));
  }
}

// ═══════════════════════════════════════════════════════════
//  JournalDivider — 帶裝飾的手帳分隔線
// ═══════════════════════════════════════════════════════════

class JournalDivider extends StatelessWidget {
  final Color? color;
  final String label;
  const JournalDivider({super.key, this.color, this.label = ''});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.28);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        DoodleHeart(color: c.withValues(alpha: 0.70), size: 9),
        const SizedBox(width: 6),
        Expanded(child: Container(height: 0.8, color: c)),
        if (label.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label,
              style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          ),
          Expanded(child: Container(height: 0.8, color: c)),
        ],
        const SizedBox(width: 6),
        DoodleLightning(color: c.withValues(alpha: 0.70), size: 7),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  JournalPageHeader — 手帳頁面裝飾標題列
// ═══════════════════════════════════════════════════════════

class JournalPageHeader extends StatelessWidget {
  final String title;
  final Color? color;
  final List<Widget>? trailing;
  const JournalPageHeader({super.key, required this.title, this.color, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(children: [
        DoodleButton(color: c.withValues(alpha: 0.35), size: 13),
        const SizedBox(width: 8),
        HandDrawnUnderline(
          color: c.withValues(alpha: 0.30),
          child: Text(title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        ),
        const SizedBox(width: 8),
        DoodleHeart(color: c.withValues(alpha: 0.40), size: 9),
        const Spacer(),
        ...?trailing,
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ScatteredDoodles — 隨機散布小裝飾（背景用）
// ═══════════════════════════════════════════════════════════

class ScatteredDoodles extends StatelessWidget {
  final Color? color;
  const ScatteredDoodles({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.11);
    // 只用右側定位，避免遮住左側時間軸（timeline 區域約佔左側 80px）
    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(children: [
          Positioned(top: 16,  right: 20, child: DoodleHeart(color: c, size: 10)),
          Positioned(top: 60,  right: 44, child: DoodleLightning(color: c, size: 8)),
          Positioned(top: 110, right: 18, child: DoodleCloud(color: c, width: 20)),
          Positioned(top: 175, right: 36, child: DoodleHeart(color: c, size: 8)),
          Positioned(top: 230, right: 22, child: DoodleLightning(color: c, size: 7)),
          Positioned(top: 290, right: 48, child: DoodleCloud(color: c, width: 16)),
          Positioned(top: 350, right: 14, child: DoodleHeart(color: c, size: 9)),
          Positioned(top: 410, right: 38, child: DoodleLightning(color: c, size: 6)),
        ]),
      ),
    );
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
