import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const SplashScreen({super.key, required this.onFinish});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _screenFade;

  @override
  void initState() {
    super.initState();
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _screenFade = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut));

    _runSequence();
  }

  void _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    await _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    await _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 900));
    await _fadeCtrl.forward();
    widget.onFinish();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _screenFade,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6EA870), Color(0xFF4A7A50), Color(0xFF3A6140)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Logo ──
              ScaleTransition(
                scale: _logoScale,
                child: FadeTransition(
                  opacity: _logoOpacity,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, spreadRadius: 2)],
                    ),
                    child: const Center(child: Text('🏯', style: TextStyle(fontSize: 52))),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Text ──
              SlideTransition(
                position: _textSlide,
                child: FadeTransition(
                  opacity: _textOpacity,
                  child: Column(children: [
                    const Text(
                      '探索諸羅',
                      style: TextStyle(
                        fontSize: 36, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: 4,
                        shadows: [Shadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Explore Chiayi',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.80), letterSpacing: 3)),
                    const SizedBox(height: 10),
                    Text('嘉義 · 在地旅遊全攻略',
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.70), letterSpacing: 1.5)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}