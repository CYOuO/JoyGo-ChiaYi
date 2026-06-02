import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/static_data_cache.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _skyCtrl;
  late AnimationController _trainCtrl;
  late AnimationController _cloudCtrl;
  late AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();

    _skyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 6200))
      ..forward();

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

  Future<void> _startupSequence() async {
    final animation = Future.delayed(const Duration(milliseconds: 6200));
    final prewarm = StaticDataCache.prewarm().timeout(
      const Duration(seconds: 9),
      onTimeout: () {
        debugPrint('[Splash] prewarm timeout — proceeding anyway');
      },
    );
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
          animation: Listenable.merge([_skyCtrl, _trainCtrl, _cloudCtrl]),
          builder: (ctx, _) {
            final t = _skyCtrl.value;
            final trainT = _trainCtrl.value;
            final cloudT = _cloudCtrl.value;

            final trackY = cy + circleR * 0.46;
            final bounce = math.sin(trainT * math.pi * 10) * 1.5;
            final sceneOpacity = t > 0.9 ? (1.0 - (t - 0.9) * 10).clamp(0.0, 1.0) : 1.0;

            final localTrainX = trainT * (circleR * 2 + 80) - 60;
            final localTrackY = trackY - (cy - circleR);

            final isDayBg = t < 0.25 || t > 0.75;
            final titleColor = isDayBg ? AppColors.primaryDark : Colors.white;
            final subtitleColor = isDayBg ? AppColors.primary : Colors.white70;

            return Stack(
              children: [
                Container(color: _InnerScenePainter._outerBg(t)),

                Opacity(
                  opacity: sceneOpacity,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: size,
                        painter: _InnerScenePainter(
                          skyT: t,
                          cloudT: cloudT,
                          circleCenter: Offset(cx, cy),
                          circleRadius: circleR,
                        ),
                      ),

                      Positioned(
                        left: cx - circleR,
                        top: cy - circleR,
                        width: circleR * 2,
                        height: circleR * 2,
                        child: ClipOval(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: localTrainX,
                                top: localTrackY - 24 + bounce,
                                child: _TrainWidget(trainT: trainT, skyT: t),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: size.height * 0.09,
                        left: 0,
                        right: 0,
                        child: Column(children: [
                          Text(
                            '探索諸羅',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 6,
                              shadows: [
                                // 🌟 拿掉白天時的白色陰影，改為透明 (Colors.transparent)
                                isDayBg
                                    ? const Shadow(color: Colors.transparent)
                                    : const Shadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 4))
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '阿里山 · 諸羅城 · 嘉義探索',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                isDayBg
                                    ? const Shadow(color: Colors.transparent)
                                    : const Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2))
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── 火車 Widget ────────────────────────────────────────────
class _TrainWidget extends StatelessWidget {
  final double trainT;
  final double skyT;
  const _TrainWidget({required this.trainT, required this.skyT});

  @override
  Widget build(BuildContext context) {
    final steamDx = math.sin(trainT * math.pi * 3) * 4;
    final steamDy = -6 - math.cos(trainT * math.pi * 5).abs() * 7;
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 46 + steamDx,
          top: steamDy,
          child: const Opacity(
            opacity: 0.5,
            child: Icon(Icons.cloud_rounded, size: 14, color: Colors.white70),
          ),
        ),
        CustomPaint(
          size: const Size(60, 24),
          painter: _AlishanTrainPainter(skyT: skyT),
        ),
      ],
    );
  }
}

class _AlishanTrainPainter extends CustomPainter {
  final double skyT;
  _AlishanTrainPainter({required this.skyT});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final isNight = skyT >= 0.25 && skyT <= 0.75;

    if (isNight) {
      final lightPath = Path()
        ..moveTo(57, 14)
        ..lineTo(140, 2)
        ..lineTo(140, 35)
        ..close();
      paint.shader = LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [Colors.yellowAccent.withOpacity(0.5), Colors.yellowAccent.withOpacity(0.0)],
      ).createShader(lightPath.getBounds());
      canvas.drawPath(lightPath, paint);
      paint.shader = null;
    }

    paint.color = const Color(0xFF8B7355); 
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 4, 30, 16), const Radius.circular(2)), paint);
    
    paint.color = isNight ? const Color(0xFFFFD54F).withOpacity(0.9) : const Color(0xFFE8D8A0).withOpacity(0.6); 
    canvas.drawRect(const Rect.fromLTWH(4, 8, 5, 5), paint);
    canvas.drawRect(const Rect.fromLTWH(12, 8, 5, 5), paint);
    canvas.drawRect(const Rect.fromLTWH(20, 8, 5, 5), paint);

    paint.color = const Color(0xFF1A1A1A);
    canvas.drawLine(const Offset(30, 16), const Offset(32, 16), paint..strokeWidth = 2);

    paint.color = const Color(0xFFA64232);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(32, 8, 25, 12), const Radius.circular(2)), paint);
    
    paint.color = const Color(0xFF1A1A1A); 
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(32, 0, 10, 20), const Radius.circular(2)), paint);
    paint.color = const Color(0xFFA64232); 
    canvas.drawRect(const Rect.fromLTWH(48, 2, 4, 6), paint);

    paint.color = isNight ? Colors.yellowAccent : Colors.white70;
    canvas.drawCircle(const Offset(57, 14), 2.5, paint);

    paint.color = const Color(0xFF111111);
    const wheelY = 20.5; 
    final wheelXs = [6.0, 15.0, 24.0, 37.0, 46.0, 53.0];
    for (final x in wheelXs) {
      canvas.drawCircle(Offset(x, wheelY), 3.5, paint);
      canvas.drawCircle(Offset(x, wheelY), 1.0, Paint()..color = Colors.grey.shade400); 
    }
  }

  @override
  bool shouldRepaint(covariant _AlishanTrainPainter old) => old.skyT != skyT;
}

// ── 風景畫 ──────────────────────────
class _InnerScenePainter extends CustomPainter {
  final double skyT;
  final double cloudT;
  final Offset circleCenter;
  final double circleRadius;

  static final _rand = math.Random(42);
  static final _stars = List.generate(
    80,
    (_) => Offset(_rand.nextDouble(), _rand.nextDouble() * 0.85),
  );

  const _InnerScenePainter({
    required this.skyT,
    required this.cloudT,
    required this.circleCenter,
    required this.circleRadius,
  });

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

  static Color _outerBg(double t) => _lerp([
        (0.00, const Color(0xFFE2E8F0)),   
        (0.30, const Color(0xFF0F172A)),   
        (0.70, const Color(0xFF0F172A)),   
        (0.90, const Color(0xFFE2E8F0)),   
        (1.00, AppColors.background),      
      ], t);

  static Color _innerSkyTop(double t) => _lerp([
        (0.00, const Color(0xFF4DA8DA)),   
        (0.30, const Color(0xFF020617)),   
        (0.70, const Color(0xFF020617)),
        (0.90, const Color(0xFF4DA8DA)),
        (1.00, AppColors.background),
      ], t);

  static Color _innerSkyBottom(double t) => _lerp([
        (0.00, const Color(0xFF9CE5F4)),   
        (0.30, const Color(0xFF1E293B)),   
        (0.70, const Color(0xFF1E293B)),
        (0.90, const Color(0xFF9CE5F4)),
        (1.00, AppColors.background),
      ], t);

  static Color _farMountain(double t) => _lerp([
        (0.00, const Color(0xFF7E9FB9)),
        (0.30, const Color(0xFF1E293B)),
        (0.70, const Color(0xFF1E293B)),
        (0.90, const Color(0xFF7E9FB9)),
        (1.00, const Color(0xFF7E9FB9)),
      ], t);

  static Color _nearMountain(double t) => _lerp([
        (0.00, const Color(0xFF486A7A)),
        (0.30, const Color(0xFF0F172A)),
        (0.70, const Color(0xFF0F172A)),
        (0.90, const Color(0xFF486A7A)),
        (1.00, const Color(0xFF486A7A)),
      ], t);

  static Color _ground(double t) => _lerp([
        (0.00, const Color(0xFF5A8F7B)),
        (0.30, const Color(0xFF0B211E)),
        (0.70, const Color(0xFF0B211E)),
        (0.90, const Color(0xFF5A8F7B)),
        (1.00, const Color(0xFF5A8F7B)),
      ], t);

  double get _starsAlpha {
    if (skyT < 0.20 || skyT > 0.80) return 0.0;
    if (skyT < 0.35) return (skyT - 0.20) / 0.15; 
    if (skyT > 0.65) return 1.0 - (skyT - 0.65) / 0.15; 
    return 1.0;
  }

  double get _cloudsAlpha {
    if (skyT < 0.2) return 1.0;
    if (skyT < 0.35) return 1.0 - ((skyT - 0.2) / 0.15); 
    if (skyT > 0.8) return 1.0;
    if (skyT > 0.65) return (skyT - 0.65) / 0.15; 
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_starsAlpha > 0.01) _drawStars(canvas, size);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: circleCenter, radius: circleRadius)));
    
    _drawInnerSky(canvas, size);
    if (_cloudsAlpha > 0.01) _drawClouds(canvas, size);
    _drawMountains(canvas, size);
    _drawGround(canvas, size);
    _drawTrack(canvas, size);
    
    canvas.restore();

    _drawRing(canvas, size);
    _drawSunMoon(canvas, size);
  }

  void _drawStars(Canvas canvas, Size size) {
    final alpha = (_starsAlpha * 255).round().clamp(0, 255);
    final paint = Paint()..color = Color.fromARGB(alpha, 255, 255, 240);
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final r = (i % 3 == 0 ? 1.8 : i % 3 == 1 ? 1.2 : 0.8) + math.sin(skyT * math.pi * 10 + i) * 0.4;
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), r.clamp(0.0, 2.5), paint);
    }
  }

  void _drawInnerSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [_innerSkyTop(skyT), _innerSkyBottom(skyT)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  void _drawClouds(Canvas canvas, Size size) {
    final alpha = (_cloudsAlpha * 220).round().clamp(0, 255);
    final paint = Paint()..color = Color.fromARGB(alpha, 255, 255, 255);
    for (int ci = 0; ci < 3; ci++) {
      final speed = 0.2 + ci * 0.15;
      final phase = ci * 0.33;
      final dx = ((cloudT * speed + phase) % 1.2 - 0.1) * size.width;
      final dy = circleCenter.dy - circleRadius * (0.55 + ci * 0.12);
      canvas.drawCircle(Offset(dx, dy), 24.0 + ci * 6, paint);
      canvas.drawCircle(Offset(dx, dy) + Offset(21, 2), 18, paint);
      canvas.drawCircle(Offset(dx, dy) + Offset(-19, 2), 16, paint);
      canvas.drawCircle(Offset(dx, dy) + Offset(9, -8), 14, paint);
    }
  }

  void _drawMountains(Canvas canvas, Size size) {
    final cy = circleCenter.dy;
    final cr = circleRadius;
    final groundTop = cy + cr * 0.30;

    _drawMountainRow(canvas, size, peakFraction: 0.48, baseY: groundTop + cr * 0.10, count: 5, color: _farMountain(skyT), circleCenter: circleCenter, circleRadius: cr, addSnowOnIndex: 2);
    _drawMountainRow(canvas, size, peakFraction: 0.28, baseY: groundTop + cr * 0.15, count: 3, color: _nearMountain(skyT), circleCenter: circleCenter, circleRadius: cr, addSnowOnIndex: 1, wide: 1.3);
  }

  void _drawMountainRow(Canvas canvas, Size size, {required double peakFraction, required double baseY, required int count, required Color color, required Offset circleCenter, required double circleRadius, int? addSnowOnIndex, double wide = 1.0}) {
    final segW = size.width / count;
    final peakY = circleCenter.dy - circleRadius * peakFraction;
    
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color, color.withOpacity(0.5)],
      ).createShader(Rect.fromLTWH(0, peakY, size.width, baseY - peakY));

    for (int i = 0; i < count; i++) {
      final cx = (i + 0.5) * segW;
      final halfW = segW * 0.55 * wide;

      final path = Path()
        ..moveTo(cx - halfW, baseY)
        ..quadraticBezierTo(cx - halfW * 0.3, peakY + (baseY - peakY) * 0.35, cx, peakY)
        ..quadraticBezierTo(cx + halfW * 0.3, peakY + (baseY - peakY) * 0.35, cx + halfW, baseY)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawGround(Canvas canvas, Size size) {
    final top = circleCenter.dy + circleRadius * 0.38;
    final grassColor = _ground(skyT);

    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, size.height), 
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [grassColor.withOpacity(0.8), grassColor.withOpacity(0.3)]
      ).createShader(Rect.fromLTRB(0, top, size.width, size.height))
    );
    canvas.drawLine(Offset(0, top), Offset(size.width, top), Paint()..color = const Color(0xFF022C22).withValues(alpha: 0.4)..strokeWidth = 2.0);
  }

  void _drawTrack(Canvas canvas, Size size) {
    final trackY = circleCenter.dy + circleRadius * 0.46;
    final railPaint = Paint()..color = const Color(0xFF78716C).withValues(alpha: 0.9)..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    
    canvas.drawLine(Offset(0, trackY), Offset(size.width, trackY), railPaint);
    canvas.drawLine(Offset(0, trackY + 7), Offset(size.width, trackY + 7), railPaint);

    final tiePaint = Paint()..color = const Color(0xFF451A03).withValues(alpha: 0.8)..strokeWidth = 3..strokeCap = StrokeCap.square;
    for (double x = 0; x < size.width; x += 20.0) {
      canvas.drawLine(Offset(x, trackY - 2), Offset(x, trackY + 9), tiePaint);
    }
  }

  void _drawRing(Canvas canvas, Size size) {
    final ringColor = skyT < 0.25 || skyT > 0.75 ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final glow = Paint()..color = ringColor.withValues(alpha: 0.15)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)..style = PaintingStyle.stroke..strokeWidth = 14;
    
    canvas.drawCircle(circleCenter, circleRadius, glow);
    canvas.drawCircle(circleCenter, circleRadius, Paint()..color = ringColor.withValues(alpha: 0.7)..style = PaintingStyle.stroke..strokeWidth = 3.5);
  }

  void _drawSunMoon(Canvas canvas, Size size) {
    final sunAngle = -math.pi / 2 - (skyT * math.pi * 2);
    final moonAngle = sunAngle + math.pi;

    final sunX = circleCenter.dx + circleRadius * math.cos(sunAngle);
    final sunY = circleCenter.dy + circleRadius * math.sin(sunAngle);
    final moonX = circleCenter.dx + circleRadius * math.cos(moonAngle);
    final moonY = circleCenter.dy + circleRadius * math.sin(moonAngle);

    final sunAbove = math.sin(sunAngle) < 0.15;
    final moonAbove = math.sin(moonAngle) < 0.15;

    if (moonAbove || _starsAlpha > 0.1) _drawMoon(canvas, Offset(moonX, moonY));
    if (sunAbove || (skyT < 0.35 || skyT > 0.65)) _drawSun(canvas, Offset(sunX, sunY));
  }

  void _drawSun(Canvas canvas, Offset pos) {
    canvas.drawCircle(pos, 22, Paint()..color = const Color(0xFFFFFBEB).withValues(alpha: 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(pos, 12, Paint()..color = const Color(0xFFFEF3C7));
  }

  void _drawMoon(Canvas canvas, Offset pos) {
    canvas.drawCircle(pos, 20, Paint()..color = const Color(0xFFF1F5F9).withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawCircle(pos, 11, Paint()..color = const Color(0xFFF8FAFC));
    canvas.drawCircle(pos + const Offset(4, -3), 9, Paint()..color = _outerBg(skyT)); 
  }

  @override
  bool shouldRepaint(covariant _InnerScenePainter old) => old.skyT != skyT || old.cloudT != cloudT;
}