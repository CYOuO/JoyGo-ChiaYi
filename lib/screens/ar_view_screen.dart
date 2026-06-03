import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/spot.dart';
import '../services/spot_service.dart';

class ArViewScreen extends StatefulWidget {
  const ArViewScreen({super.key});
  @override State<ArViewScreen> createState() => _ArViewScreenState();
}

class _ArViewScreenState extends State<ArViewScreen> {
  CameraController? _camCtrl;
  bool _camReady = false;
  String? _error;
  Position? _pos;
  double _heading = 0;
  List<_ArSpot> _arSpots = [];
  StreamSubscription<MagnetometerEvent>? _magSub;

  static const _maxDistance = 2000.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initSensors();
    _initSpots();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { if (mounted) setState(() => _error = '找不到相機'); return; }
      _camCtrl = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await _camCtrl!.initialize();
      if (mounted) setState(() => _camReady = true);
    } catch (e) {
      debugPrint('AR camera error: $e');
      if (mounted) setState(() => _error = '相機啟動失敗');
    }
  }

  void _initSensors() {
    try {
      _magSub = magnetometerEventStream().listen((event) {
        final h = math.atan2(event.y, event.x) * (180 / math.pi);
        if (mounted) setState(() => _heading = h);
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _initSpots() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      _pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
    } catch (_) { return; }
    if (_pos == null) return;
    try {
      final spots = await SpotService.loadAllSpots();
      final lat = _pos!.latitude, lng = _pos!.longitude;
      final nearby = <_ArSpot>[];
      for (final s in spots) {
        final dist = Geolocator.distanceBetween(lat, lng, s.lat, s.lng);
        if (dist > _maxDistance) continue;
        nearby.add(_ArSpot(spot: s, distance: dist, bearing: Geolocator.bearingBetween(lat, lng, s.lat, s.lng)));
      }
      nearby.sort((a, b) => a.distance.compareTo(b.distance));
      if (mounted) setState(() => _arSpots = nearby.take(15).toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    _camCtrl?.dispose();
    _magSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, title: const Text('AR 探索')),
        body: Center(child: Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 16))),
      );
    }

    if (!_camReady) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, title: const Text('AR 探索')),
        body: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('啟動相機中…', style: TextStyle(color: Colors.white60, fontSize: 14)),
        ])),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black26, elevation: 0,
        title: const Text('AR 探索', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(children: [
        // Camera
        Positioned.fill(child: CameraPreview(_camCtrl!)),
        // Compass + count
        Positioned(
          top: top + 56, left: 0, right: 0,
          child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.explore_rounded, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text('${_heading.toStringAsFixed(0)}°', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${_arSpots.length} 個景點', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
          )),
        ),
        // AR scan frame overlay
        Positioned.fill(
          child: IgnorePointer(child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 1),
            ),
            margin: EdgeInsets.fromLTRB(24, top + 80, 24, 100),
            child: Stack(children: [
              Positioned(top: 0, left: 0, child: _corner(true, true)),
              Positioned(top: 0, right: 0, child: _corner(true, false)),
              Positioned(bottom: 0, left: 0, child: _corner(false, true)),
              Positioned(bottom: 0, right: 0, child: _corner(false, false)),
            ]),
          )),
        ),
        // Spots
        if (_arSpots.isEmpty && _pos != null)
          Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
            child: const Text('轉動手機尋找附近景點', style: TextStyle(color: Colors.white70, fontSize: 14)),
          )),
        ..._arSpots.map((ar) => _buildSpotLabel(ar)),
        // Bottom
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                _pos != null ? '附近 ${_maxDistance ~/ 1000}km 內有 ${_arSpots.length} 個景點' : '定位中…',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text('長按集章相機按鈕進入此頁', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _corner(bool top, bool left) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: Colors.white54, width: 2) : BorderSide.none,
          bottom: !top ? const BorderSide(color: Colors.white54, width: 2) : BorderSide.none,
          left: left ? const BorderSide(color: Colors.white54, width: 2) : BorderSide.none,
          right: !left ? const BorderSide(color: Colors.white54, width: 2) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSpotLabel(_ArSpot ar) {
    final relAngle = _normalizeAngle(ar.bearing - _heading);
    if (relAngle.abs() > 90) return const SizedBox.shrink();
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final x = screenW / 2 + (relAngle / 90) * (screenW / 2);
    final yFactor = (ar.distance / _maxDistance).clamp(0.15, 0.75);
    final y = screenH * 0.25 + (yFactor * screenH * 0.4);
    final opacity = (1 - ar.distance / _maxDistance).clamp(0.4, 1.0);
    final scale = (1 - ar.distance / _maxDistance * 0.5).clamp(0.6, 1.0);
    final isFood = ar.spot.category == 'restaurant';

    return Positioned(
      left: (x - 70).clamp(0, screenW - 140),
      top: y.clamp(100, screenH - 100),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isFood ? const Color(0xCC8B5E3C) : const Color(0xCC3D7A6A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white38, width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(isFood ? Icons.restaurant_rounded : Icons.place_rounded, color: Colors.white, size: 20),
              const SizedBox(height: 4),
              Text(ar.spot.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                child: Text(_formatDist(ar.distance), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  double _normalizeAngle(double a) {
    while (a > 180) a -= 360;
    while (a < -180) a += 360;
    return a;
  }

  String _formatDist(double m) => m < 1000 ? '${m.toStringAsFixed(0)}m' : '${(m / 1000).toStringAsFixed(1)}km';
}

class _ArSpot {
  final Spot spot;
  final double distance;
  final double bearing;
  const _ArSpot({required this.spot, required this.distance, required this.bearing});
}
