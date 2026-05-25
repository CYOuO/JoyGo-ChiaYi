import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/static_data_cache.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // 0 = midnight  0.25 = dawn  0.5 = noon  0.75 = dusk  1 = midnight
  late AnimationController _skyCtrl;
  // 0→1: train travels across screen, loops
  late AnimationController _trainCtrl;
  // clouds drift
  late AnimationController _cloudCtrl;
  // initial fade-in
  late AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();

    _skyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5500))
      ..repeat();

    _trainCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat();

    _cloudCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 9))
      ..repeat();

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();

    _startupSequence();
  }

  /// 動畫至少跑 6.2s；同時背景預載 Firestore 靜態資料。
  /// - 一般情況：快取已存在 → prewarm 幾乎瞬間完成 → 動畫秒數決定何時進首頁
  /// - 第一次安裝：prewarm 需要時間 → 最多等到 9s 強制進入首頁（避免無網卡死）
  Future<void> _startupSequence() async {
    final animation = Future.delayed(const Duration(milliseconds: 6200));
    final prewarm = StaticDataCache.prewarm().timeout(
      const Duration(seconds: 9),
      onTimeout: () {
        debugPrint('[Splash] prewarm timeout — proceeding anyway');
      },
    );
    // 等動畫 + 預載都完成（取 max）；prewarm 自帶 9s 上限
    await Future.wait([animation, prewarm]);
    if (mounted) widget.onFinish();
  }

  @override
  void dispose() {
    _skyCtrl.dispose();
    _trainCtrl.dispose();
    _cloudCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleR = math.min(size.width, size.height) * 0.385;
    final cx = size.width / 2;
    final cy = size.height * 0.43;

    return Scaffold(
      body: FadeTransition(
        opacity: _entryCtrl,
        child: AnimatedBuilder(
          animation:
              Listenable.merge([_skyCtrl, _trainCtrl, _cloudCtrl]),
          builder: (ctx, _) {
            final t = _skyCtrl.value;
            final trainT = _trainCtrl.value;
            final cloudT = _cloudCtrl.value;

            // train screen-space position (inside circle)
            final trainX =
                cx - circleR * 0.55 + trainT * (circleR * 2.2) - 18;
            final trackY = cy + circleR * 0.46;
            final bounce = math.sin(trainT * math.pi * 10) * 1.8;

            final isDark = t < 0.21 || t > 0.82;

            return Stack(
              children: [
                // All environment painting
                CustomPaint(
                  size: size,
                  painter: _ScenePainter(
                    skyT: t,
                    cloudT: cloudT,
                    circleCenter: Offset(cx, cy),
                    circleRadius: circleR,
                  ),
                ),

                // Train (outside CustomPaint for easier emoji rendering)
                // trackY is the top rail line; shift widget up so the 🚞 body
                // sits ON the rail rather than below it.
                Positioned(
                  left: trainX,
                  top: trackY - 16 + bounce,
                  child: _TrainWidget(
                      isDark: isDark, trainT: trainT),
                ),

                // App title
                Positioned(
                  bottom: size.height * 0.09,
                  left: 0,
                  right: 0,
                  child: Column(children: [
                    const Text(
                      '探索諸羅',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5,
                        shadows: [
                          Shadow(color: Colors.black45, blurRadius: 12)
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '阿里山 · 諸羅城 · 嘉義探索',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                        letterSpacing: 2,
                        shadows: const [
                          Shadow(color: Colors.black38, blurRadius: 6)
                        ],
                      ),
                    ),
                  ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Train widget ────────────────────────────────────────────
class _TrainWidget extends StatelessWidget {
  final bool isDark;
  final double trainT;
  const _TrainWidget({required this.isDark, required this.trainT});

  @override
  Widget build(BuildContext context) {
    final steamDx = math.sin(trainT * math.pi * 3) * 4;
    final steamDy = -8 - math.cos(trainT * math.pi * 5).abs() * 7;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Steam puff
        Transform.translate(
          offset: Offset(steamDx + 4, steamDy),
          child: Opacity(
            opacity: isDark ? 0.2 : 0.6,
            child: Text('☁',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Colors.grey.shade300
                      : Colors.white,
                )),
          ),
        ),
        // Train body
        const Text('🚞', style: TextStyle(fontSize: 36)),
      ],
    );
  }
}

// ── Main scene painter ──────────────────────────────────────
class _ScenePainter extends CustomPainter {
  final double skyT;
  final double cloudT;
  final Offset circleCenter;
  final double circleRadius;

  // Pre-baked star positions (fixed seed = same every frame)
  static final _rand = math.Random(42);
  static final _stars = List.generate(
    80,
    (_) => Offset(
      _rand.nextDouble(),
      _rand.nextDouble() * 0.85,
    ),
  );

  const _ScenePainter({
    required this.skyT,
    required this.cloudT,
    required this.circleCenter,
    required this.circleRadius,
  });

  // ── Color helpers ──────────────────────────────────────────
  static Color _lerp(List<(double, Color)> stops, double t) {
    t = t.clamp(0.0, 1.0);
    for (int i = 0; i < stops.length - 1; i++) {
      final (t0, c0) = stops[i];
      final (t1, c1) = stops[i + 1];
      if (t >= t0 && t <= t1) {
        return Color.lerp(c0, c1, (t - t0) / (t1 - t0))!;
      }
    }
    return stops.last.$2;
  }

  // ── Muted / ink-wash palette ──────────────────────────────
  // All colours desaturated ~40 % for a misty-mountain feel.

  static Color _outerBg(double t) => _lerp([
        (0.00, const Color(0xFF08101E)),   // deep navy
        (0.22, const Color(0xFF0C1428)),
        (0.28, const Color(0xFF181428)),   // muted purple-night
        (0.36, const Color(0xFF101828)),
        (0.55, const Color(0xFF101828)),
        (0.72, const Color(0xFF181424)),
        (0.82, const Color(0xFF0C1020)),
        (1.00, const Color(0xFF08101E)),
      ], t);

  static Color _innerSkyTop(double t) => _lerp([
        (0.00, const Color(0xFF101828)),   // midnight navy
        (0.22, const Color(0xFF141C30)),
        (0.27, const Color(0xFF6B3A38)),   // dusty rose-red (was vivid #9C2818)
        (0.33, const Color(0xFF8A5A44)),   // muted terra-cotta (was #D05020)
        (0.42, const Color(0xFF6080A0)),   // steel blue (was vivid #5AAAD4)
        (0.55, const Color(0xFF4E6E8C)),   // slate blue (was vivid #3490C0)
        (0.68, const Color(0xFF50708A)),   // muted blue
        (0.74, const Color(0xFF7A5040)),   // muted amber-sienna (was vivid #B84018)
        (0.82, const Color(0xFF1C1428)),
        (1.00, const Color(0xFF101828)),
      ], t);

  static Color _innerSkyBottom(double t) => _lerp([
        (0.00, const Color(0xFF141E2C)),
        (0.22, const Color(0xFF161E30)),
        (0.27, const Color(0xFF8A5050)),   // dusty rose (was vivid #D04830)
        (0.33, const Color(0xFFAA7860)),   // muted warm (was vivid #E87040)
        (0.42, const Color(0xFF7898B0)),   // muted sky (was vivid #78C8E8)
        (0.55, const Color(0xFF6888A8)),   // slate sky (was vivid #60C0E8)
        (0.68, const Color(0xFF6888A8)),
        (0.74, const Color(0xFF8A6450)),   // muted amber (was vivid #D06030)
        (0.82, const Color(0xFF201820)),
        (1.00, const Color(0xFF141E2C)),
      ], t);

  double get _starsAlpha {
    if (skyT < 0.21) return 1.0;
    if (skyT < 0.32) return 1.0 - (skyT - 0.21) / 0.11;
    if (skyT > 0.80) return (skyT - 0.80) / 0.12;
    if (skyT > 0.74) return 0.0;
    return 0.0;
  }

  double get _cloudsAlpha {
    if (skyT < 0.36 || skyT > 0.73) return 0.0;
    if (skyT < 0.44) return (skyT - 0.36) / 0.08;
    if (skyT > 0.65) return 1.0 - (skyT - 0.65) / 0.08;
    return 1.0;
  }

  // ── Main paint ─────────────────────────────────────────────
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Outer background (fills screen behind circle)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _outerBg(skyT),
    );

    // 2. Stars (full-screen, above outer bg)
    if (_starsAlpha > 0.01) _drawStars(canvas, size);

    // 3. Inner circle — clip and draw landscape
    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(Rect.fromCircle(
            center: circleCenter, radius: circleRadius)),
    );
    _drawInnerSky(canvas, size);
    if (_cloudsAlpha > 0.01) _drawClouds(canvas, size);
    _drawMountains(canvas, size);
    _drawGround(canvas, size);
    _drawTrack(canvas, size);
    canvas.restore();

    // 4. Ring border
    _drawRing(canvas, size);

    // 5. Sun + Moon on ring
    _drawSunMoon(canvas, size);
  }

  // ── Stars ──────────────────────────────────────────────────
  void _drawStars(Canvas canvas, Size size) {
    final alpha = (_starsAlpha * 255).round().clamp(0, 255);
    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 240);
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      // small stars pulse
      final r =
          (i % 3 == 0 ? 1.8 : i % 3 == 1 ? 1.2 : 0.8) +
              math.sin(skyT * math.pi * 6 + i) * 0.3;
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        r,
        paint,
      );
    }
  }

  // ── Inner sky gradient ──────────────────────────────────────
  void _drawInnerSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_innerSkyTop(skyT), _innerSkyBottom(skyT)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  // ── Clouds ─────────────────────────────────────────────────
  void _drawClouds(Canvas canvas, Size size) {
    final alpha = (_cloudsAlpha * 200).round().clamp(0, 255);
    final paint = Paint()..color = Color.fromARGB(alpha, 255, 255, 255);
    // Two clouds drifting at different speeds
    for (int ci = 0; ci < 3; ci++) {
      final speed = 0.2 + ci * 0.15;
      final phase = ci * 0.33;
      final dx = ((cloudT * speed + phase) % 1.2 - 0.1) * size.width;
      final dy = circleCenter.dy - circleRadius * (0.55 + ci * 0.12);
      _drawPuffCloud(canvas, Offset(dx, dy), 22.0 + ci * 6, paint);
    }
  }

  void _drawPuffCloud(Canvas canvas, Offset center, double r, Paint paint) {
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center + Offset(r * 0.9, r * 0.1), r * 0.75, paint);
    canvas.drawCircle(center + Offset(-r * 0.8, r * 0.1), r * 0.7, paint);
    canvas.drawCircle(center + Offset(r * 0.4, -r * 0.35), r * 0.6, paint);
  }

  // ── Mountains ─────────────────────────────────────────────
  void _drawMountains(Canvas canvas, Size size) {
    final cy = circleCenter.dy;
    final cr = circleRadius;
    final groundTop = cy + cr * 0.30;

    // --- Far range (5 cute rounded peaks) ---
    // Muted sage green (day) / dark ink (night)
    final farColor = skyT > 0.28 && skyT < 0.78
        ? const Color(0xFF4A6854)   // muted sage (was vivid #3A6644)
        : const Color(0xFF182418);
    _drawMountainRow(
      canvas,
      size,
      peakFraction: 0.48,
      baseY: groundTop + cr * 0.10,
      count: 5,
      color: farColor,
      circleCenter: circleCenter,
      circleRadius: cr,
      addSnowOnIndex: 2,
    );

    // --- Near range (3 taller peaks) ---
    // Deeper muted green (day) / near-black ink (night)
    final nearColor = skyT > 0.28 && skyT < 0.78
        ? const Color(0xFF354A3A)   // deep muted forest (was vivid #2A4E34)
        : const Color(0xFF101810);
    _drawMountainRow(
      canvas,
      size,
      peakFraction: 0.28,
      baseY: groundTop + cr * 0.15,
      count: 3,
      color: nearColor,
      circleCenter: circleCenter,
      circleRadius: cr,
      addSnowOnIndex: 1,
      wide: 1.3,
    );
  }

  void _drawMountainRow(
    Canvas canvas,
    Size size, {
    required double peakFraction,
    required double baseY,
    required int count,
    required Color color,
    required Offset circleCenter,
    required double circleRadius,
    int? addSnowOnIndex,
    double wide = 1.0,
  }) {
    final segW = size.width / count;
    final peakY = circleCenter.dy - circleRadius * peakFraction;
    final paint = Paint()..color = color;

    for (int i = 0; i < count; i++) {
      final cx = (i + 0.5) * segW;
      final halfW = segW * 0.55 * wide;

      // Cute rounded peak via quadratic bezier
      final path = Path()
        ..moveTo(cx - halfW, baseY)
        ..quadraticBezierTo(cx - halfW * 0.3, peakY + (baseY - peakY) * 0.35, cx, peakY)
        ..quadraticBezierTo(cx + halfW * 0.3, peakY + (baseY - peakY) * 0.35, cx + halfW, baseY)
        ..close();
      canvas.drawPath(path, paint);

      // Snow cap (optional)
      if (i == addSnowOnIndex) {
        final snowH = (baseY - peakY) * 0.22;
        final snowPaint = Paint()
          ..color = Colors.white.withValues(
              alpha: skyT > 0.28 && skyT < 0.78 ? 0.85 : 0.50);
        final snowPath = Path()
          ..moveTo(cx - halfW * 0.22, peakY + snowH)
          ..quadraticBezierTo(cx - halfW * 0.05, peakY + snowH * 0.3,
              cx, peakY)
          ..quadraticBezierTo(cx + halfW * 0.05, peakY + snowH * 0.3,
              cx + halfW * 0.22, peakY + snowH)
          ..close();
        canvas.drawPath(snowPath, snowPaint);
      }
    }
  }

  // ── Ground strip ──────────────────────────────────────────
  void _drawGround(Canvas canvas, Size size) {
    final cy = circleCenter.dy;
    final cr = circleRadius;
    final top = cy + cr * 0.38;

    // Muted earthy ground
    final grassColor = skyT > 0.28 && skyT < 0.78
        ? const Color(0xFF3C5C40)   // muted olive-green (was vivid #3E7040)
        : const Color(0xFF141E16);

    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, size.height),
      Paint()..color = grassColor,
    );

    // Subtle highlight line
    canvas.drawLine(
      Offset(0, top),
      Offset(size.width, top),
      Paint()
        ..color = (skyT > 0.28 && skyT < 0.78
                ? const Color(0xFF506850)
                : const Color(0xFF243024))
            .withValues(alpha: 0.5)
        ..strokeWidth = 2.5,
    );
  }

  // ── Railway track ─────────────────────────────────────────
  void _drawTrack(Canvas canvas, Size size) {
    final cy = circleCenter.dy;
    final cr = circleRadius;
    final trackY = cy + cr * 0.46;

    // Rails
    final railPaint = Paint()
      ..color = const Color(0xFF8B7355).withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, trackY), Offset(size.width, trackY), railPaint);
    canvas.drawLine(
        Offset(0, trackY + 6), Offset(size.width, trackY + 6), railPaint);

    // Sleepers (ties)
    final tiePaint = Paint()
      ..color = const Color(0xFF5C3D1E).withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    const tieSpacing = 20.0;
    for (double x = 0; x < size.width; x += tieSpacing) {
      canvas.drawLine(
          Offset(x, trackY - 2), Offset(x, trackY + 8), tiePaint);
    }
  }

  // ── Ring ──────────────────────────────────────────────────
  void _drawRing(Canvas canvas, Size size) {
    final isDay = skyT > 0.30 && skyT < 0.75;
    // Muted: antique gold during day, slate at night
    final ringColor = isDay
        ? const Color(0xFFB09060)   // antique gold (was vivid #D4A84C)
        : const Color(0xFF606880);  // muted slate (was vivid #7080B8)

    final glow = Paint()
      ..color = ringColor.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    canvas.drawCircle(circleCenter, circleRadius, glow);

    canvas.drawCircle(
      circleCenter,
      circleRadius,
      Paint()
        ..color = ringColor.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  // ── Sun + Moon ────────────────────────────────────────────
  void _drawSunMoon(Canvas canvas, Size size) {
    // sunAngle: 0 (midnight bottom) → pi/2 at t=0.25 (right/dawn)
    //   → pi at t=0.5 (top/noon) → 3pi/2 at t=0.75 (left/dusk)
    // In screen coords (y down): right=0, bottom=pi/2, left=pi, top=3pi/2
    // We want sun at right(east) at dawn(0.25), top(noon) at 0.5, left(west) at 0.75
    // angle(t) = (t - 0.25) * 2pi — offset so right=0 at dawn
    // right = Offset(cx+r*cos, cy+r*sin), cos(0)=1,sin(0)=0 → right ✓
    // top   = cos(-pi/2)=0, sin(-pi/2)=-1 → (cx, cy-r) ✓ at t=0.5: (0.25)*2pi=pi/2,subtract pi/2 from angle
    // Let's define: angle = -(skyT - 0.25) * 2 * pi  (goes counterclockwise)
    // t=0.25: angle=0          → (cx+r, cy) = east  ✓
    // t=0.5:  angle=-pi/2      → (cx, cy-r) = top/noon ✓
    // t=0.75: angle=-pi        → (cx-r, cy) = west/dusk ✓
    // t=0:    angle=pi/2       → (cx, cy+r) = bottom/midnight ✓
    final sunAngle = -(skyT - 0.25) * 2 * math.pi;
    final moonAngle = sunAngle + math.pi;

    final sunX = circleCenter.dx + circleRadius * math.cos(sunAngle);
    final sunY = circleCenter.dy + circleRadius * math.sin(sunAngle);
    final moonX = circleCenter.dx + circleRadius * math.cos(moonAngle);
    final moonY = circleCenter.dy + circleRadius * math.sin(moonAngle);

    // Sun visibility: visible roughly when above horizon (top half of ring)
    // sun is above horizon when sunY < circleCenter.dy → sinAngle < 0
    final sunAbove = math.sin(sunAngle) < 0.15; // plus a little past horizon
    final moonAbove = math.sin(moonAngle) < 0.15;

    // Draw Moon first (behind sun if both visible)
    if (moonAbove || _starsAlpha > 0.1) {
      _drawMoon(canvas, Offset(moonX, moonY));
    }

    // Draw Sun
    if (sunAbove || (skyT > 0.22 && skyT < 0.78)) {
      _drawSun(canvas, Offset(sunX, sunY));
    }
  }

  void _drawSun(Canvas canvas, Offset pos) {
    // Soft glow (muted warm white)
    canvas.drawCircle(
      pos,
      20,
      Paint()
        ..color = const Color(0xFFE8D8A0).withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Body — warm ivory instead of vivid yellow
    canvas.drawCircle(
      pos,
      13,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFEEDFA0), Color(0xFFCCAA58)],
        ).createShader(Rect.fromCircle(center: pos, radius: 13)),
    );
    // Border — muted gold
    canvas.drawCircle(
      pos,
      13,
      Paint()
        ..color = const Color(0xFFBB9858).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Rays — subtle, low opacity
    final rayPaint = Paint()
      ..color = const Color(0xFFCCAA58).withValues(alpha: 0.38)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + skyT * math.pi * 2;
      canvas.drawLine(
        pos + Offset(math.cos(a) * 16, math.sin(a) * 16),
        pos + Offset(math.cos(a) * 21, math.sin(a) * 21),
        rayPaint,
      );
    }
  }

  void _drawMoon(Canvas canvas, Offset pos) {
    // Soft glow
    canvas.drawCircle(
      pos,
      18,
      Paint()
        ..color = const Color(0xFFCCD8E8).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Body — cool grey-white instead of bright white
    canvas.drawCircle(pos, 12,
        Paint()..color = const Color(0xFFCED8E4));
    // Crescent cut
    canvas.drawCircle(
      pos + const Offset(5, -3),
      10,
      Paint()..color = _outerBg(skyT),
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.skyT != skyT ||
      old.cloudT != cloudT;
}
