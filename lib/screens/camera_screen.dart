import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  static const kPhotoPathsKey = 'stamp_photo_paths_v1';

  static Future<List<String>> getSavedPhotoPaths() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(kPhotoPathsKey) ?? [];
  }

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ── Camera ─────────────────────────────────────────────────
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;
  String? _initError;
  int _cameraIdx = 0;
  bool _flashOn = false;
  bool _takingPicture = false;

  // ── Zoom ───────────────────────────────────────────────────
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  double _baseZoom = 1.0;

  // ── Exposure ───────────────────────────────────────────────
  double _exposureOffset = 0.0;
  bool _showExposureSlider = false;

  // ── Frame & Gallery ────────────────────────────────────────
  int _selectedFrame = 0;
  bool _showGallery = false;
  final List<String> _capturedPhotos = []; // real photo paths
  final GlobalKey _repaintKey = GlobalKey();

  // ── ⑩ AR 掃描感 ─────────────────────────────────────────────
  bool _showScanOverlay = false;
  bool _showDetected    = false;
  String _detectedLocation = '嘉義景點';

  static const _kLocations = ['阿里山國家風景區','北門車站','嘉義市立美術館','文化路夜市','故宮南院','檜意森活村','嘉義公園','蘭潭水庫'];

  Future<void> _runScanEffect() async {
    final rng = DateTime.now().millisecond % _kLocations.length;
    setState(() { _showScanOverlay = true; _showDetected = false; _detectedLocation = _kLocations[rng]; });
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _showDetected = true);
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) setState(() { _showScanOverlay = false; _showDetected = false; });
  }

  // ── Frames ─────────────────────────────────────────────────
  final List<_Frame> _frames = [
    _Frame('諸羅風華',  '🏯', const Color(0xFF5B8A5F), AppColors.accentStraw),
    _Frame('阿里山晨霧','🌲', const Color(0xFF2D6A4F), const Color(0xFF95D5B2)),
    _Frame('火雞肉飯',  '🍜', const Color(0xFFE76F51), const Color(0xFFE9C46A)),
    _Frame('嘉義夜市',  '🌙', const Color(0xFF1A1A2E), const Color(0xFFE9C46A)),
    _Frame('極簡白',    '⬜', Colors.white,             const Color(0xFFDDDDDD)),
    _Frame('復古底片',  '📷', const Color(0xFF5C3D2E), const Color(0xFFE8C99A)),
  ];

  // ── Lifecycle ──────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _controller!.dispose();
      if (mounted) setState(() => _initialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // ── Camera init ────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (mounted) setState(() { _initialized = false; _initError = null; });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _initError = '找不到相機裝置');
        return;
      }
      final idx = _cameraIdx.clamp(0, _cameras.length - 1);
      await _setupController(_cameras[idx]);
    } on CameraException catch (e) {
      if (mounted) setState(() => _initError = _errMsg(e.code));
    }
  }

  Future<void> _setupController(CameraDescription cam) async {
    final old = _controller;
    _controller = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await old?.dispose();
    try {
      await _controller!.initialize();
      // Fetch zoom limits after init
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _zoomLevel = _minZoom;
      if (mounted) setState(() { _initialized = true; _initError = null; });
    } on CameraException catch (e) {
      if (mounted) setState(() => _initError = _errMsg(e.code));
    }
  }

  String _errMsg(String code) {
    if (code == 'CameraAccessDenied') return '相機存取被拒絕\n請至設定開啟相機權限';
    return '相機初始化失敗\n請重新開啟相機';
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _cameraIdx = 1 - _cameraIdx;
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    if (!_initialized || _controller == null) return;
    _flashOn = !_flashOn;
    await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() {});
  }

  Future<void> _takePhoto() async {
    if (!_initialized || _controller == null || _takingPicture) return;
    if (mounted) setState(() => _takingPicture = true);
    try {
      final xfile = await _controller!.takePicture();
      setState(() => _capturedPhotos.insert(0, xfile.path));
      HapticFeedback.mediumImpact(); // ⑤ 拍照觸覺
      _runScanEffect(); // ⑩ AR 掃描感
      if (mounted) _showPhotoResult(context, xfile.path);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  // ── Pick from device gallery ───────────────────────────────
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    setState(() {
      _capturedPhotos.insert(0, xfile.path);
      _showGallery = false;
    });
    if (mounted) _showPhotoResult(context, xfile.path);
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _showGallery ? _buildGallery(context) : _buildCamera(context),
    );
  }

  // ── Camera view ────────────────────────────────────────────
  Widget _buildCamera(BuildContext context) {
    final frame = _frames[_selectedFrame];
    return Stack(
      fit: StackFit.expand,
      children: [
        // Live preview with pinch-to-zoom
        if (_initialized && _controller != null)
          GestureDetector(
            onScaleStart: (_) => _baseZoom = _zoomLevel,
            onScaleUpdate: (details) async {
              if (!_initialized || _controller == null) return;
              final newZoom = (_baseZoom * details.scale)
                  .clamp(_minZoom, _maxZoom);
              if ((newZoom - _zoomLevel).abs() > 0.05) {
                setState(() => _zoomLevel = newZoom);
                try { await _controller!.setZoomLevel(newZoom); } catch (_) {}
              }
            },
            child: CameraPreview(_controller!),
          )
        else
          _buildPlaceholder(),

        // Frame overlay
        Positioned.fill(
          child: CustomPaint(
            painter: _FramePainter(
              primaryColor: frame.primaryColor,
              accentColor: frame.accentColor,
              name: frame.name,
              frameIndex: _selectedFrame,
            ),
          ),
        ),

        // Error overlay
        if (_initError != null) Positioned.fill(child: _buildErrorOverlay()),

        // ⑩ AR 掃描感 overlay
        if (_showScanOverlay) _buildScanOverlay(),

        // ── Top controls ──────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _camBtn(Icons.close_rounded, () => Navigator.pop(context)),
                  const Spacer(),
                  if (_zoomLevel > _minZoom + 0.05)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_zoomLevel.toStringAsFixed(1)}×',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(width: 8),
                  _camBtn(
                    _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    _toggleFlash,
                    highlight: _flashOn,
                  ),
                  const SizedBox(width: 8),
                  _camBtn(Icons.flip_camera_ios_rounded, _flipCamera),
                ],
              ),
            ),
          ),
        ),

        // ── Exposure slider (vertical, right side) ────────────
        if (_showExposureSlider)
          Positioned(
            right: 14,
            bottom: 200,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.brightness_high_rounded,
                      color: Colors.white70, size: 14),
                  SizedBox(
                    width: 28,
                    height: 130,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: _exposureOffset,
                        min: -2.0,
                        max: 2.0,
                        divisions: 16,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: (v) async {
                          setState(() => _exposureOffset = v);
                          if (_initialized && _controller != null) {
                            try { await _controller!.setExposureOffset(v); }
                            catch (_) {}
                          }
                        },
                      ),
                    ),
                  ),
                  const Icon(Icons.brightness_low_rounded,
                      color: Colors.white70, size: 14),
                ],
              ),
            ),
          ),

        // ── Frame name badge (well above controls) ────────────
        Positioned(
          bottom: 275,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(frame.emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 5),
              Text(frame.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),

        // ── Bottom controls ───────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFrameSelector(),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildGalleryBtn(),    // LEFT  — opens real gallery
                    _buildShutterBtn(frame), // CENTER — shutter
                    _buildExposureBtn(),   // RIGHT  — exposure slider
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Left button: gallery ───────────────────────────────────
  Widget _buildGalleryBtn() {
    return GestureDetector(
      onTap: () => setState(() => _showGallery = true),
      child: Container(
        width: 54, height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white54, width: 2),
          color: Colors.black45,
        ),
        child: _capturedPhotos.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_capturedPhotos.first),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 28),
                ),
              )
            : const Icon(Icons.photo_library_outlined,
                color: Colors.white, size: 28),
      ),
    );
  }

  // ── Right button: exposure ─────────────────────────────────
  Widget _buildExposureBtn() {
    return GestureDetector(
      onTap: () => setState(() => _showExposureSlider = !_showExposureSlider),
      child: Container(
        width: 54, height: 54,
        decoration: BoxDecoration(
          color: _showExposureSlider ? Colors.white24 : Colors.black45,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white30),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wb_sunny_rounded,
                color: _showExposureSlider ? Colors.yellow : Colors.white,
                size: 22),
            const SizedBox(height: 2),
            const Text('曝光',
                style: TextStyle(color: Colors.white70, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildShutterBtn(_Frame frame) {
    return GestureDetector(
      onTap: _takePhoto,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: _takingPicture ? 68 : 78,
        height: _takingPicture ? 68 : 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: frame.accentColor, width: 4),
          boxShadow: [
            BoxShadow(
              color: frame.primaryColor.withOpacity(0.45),
              blurRadius: 20, spreadRadius: 3,
            ),
          ],
        ),
        child: _takingPicture
            ? Center(
                child: SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(
                      color: frame.primaryColor, strokeWidth: 2.5),
                ))
            : Icon(Icons.circle,
                size: 62,
                color: frame.primaryColor.withOpacity(0.85)),
      ),
    );
  }

  Widget _buildFrameSelector() {
    return SizedBox(
      height: 86,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _frames.length,
        itemBuilder: (_, i) {
          final f = _frames[i];
          final isSelected = _selectedFrame == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedFrame = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 68,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white30,
                  width: isSelected ? 2.5 : 1,
                ),
                color: f.primaryColor.withOpacity(isSelected ? 0.55 : 0.25),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(f.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    f.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ⑩ AR 掃描感 overlay
  Widget _buildScanOverlay() {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _showScanOverlay ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Stack(children: [
          // Scan line animation
          if (!_showDetected)
            _ScanLineAnimation(color: const Color(0xFF00E5A0)),
          // Corner brackets
          Positioned.fill(child: CustomPaint(painter: _ScanBracketPainter(color: const Color(0xFF00E5A0)))),
          // Detected badge
          if (_showDetected)
            Positioned(
              bottom: 120, left: 0, right: 0,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  builder: (_, t, child) => Transform.scale(scale: t, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF00E5A0), width: 1.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF00E5A0)),
                      const SizedBox(width: 8),
                      Text(_detectedLocation, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF00E5A0).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                        child: const Text('已識別', style: TextStyle(fontSize: 9, color: Color(0xFF00E5A0), fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF111111),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(
                color: Colors.white38, strokeWidth: 2),
          ),
          const SizedBox(height: 16),
          Text('相機載入中…',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.35), fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_rounded,
              color: Colors.white38, size: 56),
          const SizedBox(height: 16),
          Text(
            _initError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white60, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _initCamera,
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54)),
            child: const Text('重試',
                style: TextStyle(color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget _camBtn(IconData icon, VoidCallback onTap,
      {bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: highlight ? Colors.white24 : Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  // ── Real Gallery ───────────────────────────────────────────
  Widget _buildGallery(BuildContext context) {
    final frame = _frames[_selectedFrame];
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white),
                  onPressed: () => setState(() => _showGallery = false),
                ),
                const Expanded(
                  child: Text('打卡相簿',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: Colors.white)),
                ),
                // Pick from device gallery
                TextButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.add_photo_alternate_outlined,
                      color: Colors.white70, size: 18),
                  label: const Text('從相簿匯入',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ]),
            ),
            // Current frame badge
            Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(children: [
                Text(frame.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text('套用框：${frame.name}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
                const Spacer(),
                const Text('點圖預覽',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
            const Divider(height: 1, color: Colors.white12),
            // Grid
            if (_capturedPhotos.isEmpty)
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.camera_alt_outlined,
                        color: Colors.white24, size: 60),
                    const SizedBox(height: 14),
                    const Text('還沒有照片',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Text('拍照後會自動出現在這裡',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 12)),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white54, size: 18),
                      label: const Text('從相簿匯入',
                          style: TextStyle(color: Colors.white54)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                  ]),
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(2),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2),
                  itemCount: _capturedPhotos.length,
                  itemBuilder: (_, index) {
                    final path = _capturedPhotos[index];
                    return GestureDetector(
                      onTap: () => _showPhotoResult(context, path),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.white38)),
                          ),
                          // Frame overlay preview
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _FramePainter(
                                primaryColor: frame.primaryColor,
                                accentColor: frame.accentColor,
                                name: frame.name,
                                                  frameIndex: _selectedFrame,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Photo result dialog (with real save/share) ─────────────
  void _showPhotoResult(BuildContext context, String imagePath) {
    final frame = _frames[_selectedFrame];
    final now = DateTime.now();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                // Photo + frame composite — captured by RepaintBoundary
                RepaintBoundary(
                  key: _repaintKey,
                  child: SizedBox(
                    width: 300,
                    height: 380,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Photo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(imagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                color: frame.primaryColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(frame.emoji, style: const TextStyle(fontSize: 60)),
                              ),
                            ),
                          ),
                        ),
                        // Frame overlay
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CustomPaint(
                              painter: _FramePainter(
                                primaryColor: frame.primaryColor,
                                accentColor: frame.accentColor,
                                name: frame.name,
                                                  frameIndex: _selectedFrame,
                              ),
                            ),
                          ),
                        ),
                        // Bottom info gradient strip
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(
                                14, 24, 14, 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withOpacity(0.72),
                                  Colors.transparent,
                                ],
                              ),
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(16)),
                            ),
                            child: Row(children: [
                              Text(frame.emoji, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('探索諸羅',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13)),
                                  Text(
                                    '${now.month}/${now.day} · 打卡留念',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _saveWithFrame(ctx),
                      icon: const Icon(Icons.save_alt_rounded, size: 16),
                      label: const Text('儲存'),
                      style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _shareWithFrame(ctx),
                      icon: const Icon(Icons.share_rounded,
                          size: 16, color: Colors.white),
                      label: const Text('分享',
                          style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Colors.white38),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('關閉',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  // ── Capture RepaintBoundary → PNG bytes ────────────────────
  Future<Uint8List?> _captureFramedImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 80));
      final boundary = _repaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ── Save to gallery + record path for photo wall ───────────
  static Future<void> recordPhotoPath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(CameraScreen.kPhotoPathsKey) ?? [];
      paths.insert(0, path);
      if (paths.length > 100) paths.removeLast();
      await prefs.setStringList(CameraScreen.kPhotoPathsKey, paths);
    } catch (_) {}
  }

  Future<void> _saveWithFrame(BuildContext ctx) async {
    final bytes = await _captureFramedImage();
    if (bytes == null) {
      _showSnack('截圖失敗，請重試');
      return;
    }
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) await Gal.requestAccess();
      final ts = DateTime.now().millisecondsSinceEpoch;
      await Gal.putImageBytes(bytes, name: '探索諸羅_$ts');
      // 同時儲存到 app 文件目錄供照片牆使用
      try {
        final dir = await getApplicationDocumentsDirectory();
        final stampsDir = Directory('${dir.path}/stamp_photos');
        if (!stampsDir.existsSync()) stampsDir.createSync(recursive: true);
        final file = File('${stampsDir.path}/$ts.jpg');
        await file.writeAsBytes(bytes);
        await recordPhotoPath(file.path);
      } catch (_) {}
      if (mounted) {
        Navigator.pop(ctx);
        _showSnack('已儲存到相簿！');
      }
    } catch (e) {
      _showSnack('儲存失敗，請確認相簿權限');
    }
  }

  // ── Share with frame ───────────────────────────────────────
  Future<void> _shareWithFrame(BuildContext ctx) async {
    final bytes = await _captureFramedImage();
    if (bytes == null) {
      _showSnack('截圖失敗，請重試');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '在嘉義探索諸羅打卡！#探索諸羅 #嘉義旅遊',
      );
    } catch (e) {
      _showSnack('分享失敗，請重試');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }
}

// ── ⑩ AR 掃描感 Helpers ──────────────────────────────────────
class _ScanLineAnimation extends StatefulWidget {
  final Color color;
  const _ScanLineAnimation({required this.color});
  @override State<_ScanLineAnimation> createState() => _ScanLineAnimationState();
}

class _ScanLineAnimationState extends State<_ScanLineAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.05, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, box) => AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Stack(children: [
        Positioned(
          top: box.maxHeight * _anim.value - 1,
          left: 0, right: 0,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.transparent, widget.color.withValues(alpha: 0.8), Colors.transparent]),
            ),
          ),
        ),
      ]),
    ));
  }
}

class _ScanBracketPainter extends CustomPainter {
  final Color color;
  const _ScanBracketPainter({required this.color});
  @override void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const len = 24.0, inset = 40.0;
    // Corners
    for (final pts in [
      // TL
      [Offset(inset, inset + len), Offset(inset, inset), Offset(inset + len, inset)],
      // TR
      [Offset(s.width - inset - len, inset), Offset(s.width - inset, inset), Offset(s.width - inset, inset + len)],
      // BL
      [Offset(inset, s.height - inset - len), Offset(inset, s.height - inset), Offset(inset + len, s.height - inset)],
      // BR
      [Offset(s.width - inset - len, s.height - inset), Offset(s.width - inset, s.height - inset), Offset(s.width - inset, s.height - inset - len)],
    ]) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy)..lineTo(pts[1].dx, pts[1].dy)..lineTo(pts[2].dx, pts[2].dy);
      canvas.drawPath(path, p);
    }
  }
  @override bool shouldRepaint(_ScanBracketPainter old) => old.color != color;
}

// ── Models ─────────────────────────────────────────────────
class _Frame {
  final String name, emoji;
  final Color primaryColor, accentColor;
  _Frame(this.name, this.emoji, this.primaryColor, this.accentColor);
}

// ── Frame overlay painter (full-screen) ────────────────────
class _FramePainter extends CustomPainter {
  final Color primaryColor, accentColor;
  final String name;
  final int frameIndex;

  const _FramePainter({
    required this.primaryColor,
    required this.accentColor,
    required this.name,
    required this.frameIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (frameIndex) {
      case 0: _paintTraditional(canvas, size); break;
      case 1: _paintForest(canvas, size); break;
      case 2: _paintFood(canvas, size); break;
      case 3: _paintNight(canvas, size); break;
      case 4: _paintMinimal(canvas, size); break;
      case 5: _paintVintage(canvas, size); break;
      default: _paintTraditional(canvas, size);
    }
  }

  // ── Frame 0: 諸羅風華 — Traditional / cultural ─────────────
  void _paintTraditional(Canvas canvas, Size size) {
    const pad = 20.0;
    const cornerLen = 44.0;

    canvas.drawRect(
      Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2),
      Paint()
        ..color = primaryColor.withOpacity(0.35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    const innerPad = 30.0;
    canvas.drawRect(
      Rect.fromLTWH(innerPad, innerPad,
          size.width - innerPad * 2, size.height - innerPad * 2),
      Paint()
        ..color = accentColor.withOpacity(0.28)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    final cp = Paint()
      ..color = accentColor
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawCornerL(canvas, Offset(pad, pad), cornerLen, 1, 1, cp);
    _drawCornerL(canvas, Offset(size.width - pad, pad), cornerLen, -1, 1, cp);
    _drawCornerL(canvas, Offset(pad, size.height - pad), cornerLen, 1, -1, cp);
    _drawCornerL(canvas, Offset(size.width - pad, size.height - pad),
        cornerLen, -1, -1, cp);

    final diamondPaint = Paint()
      ..color = accentColor.withOpacity(0.75)
      ..style = PaintingStyle.fill;
    final midX = size.width / 2;
    final midY = size.height / 2;
    for (final pos in [
      Offset(midX, pad),
      Offset(midX, size.height - pad),
      Offset(pad, midY),
      Offset(size.width - pad, midY),
    ]) {
      _drawDiamond(canvas, pos, 6, diamondPaint);
    }

    final dotPaint = Paint()
      ..color = primaryColor.withOpacity(0.45)
      ..style = PaintingStyle.fill;
    for (final pos in [
      Offset(pad + cornerLen + 10, pad),
      Offset(size.width - pad - cornerLen - 10, pad),
      Offset(pad + cornerLen + 10, size.height - pad),
      Offset(size.width - pad - cornerLen - 10, size.height - pad),
      Offset(pad, pad + cornerLen + 10),
      Offset(pad, size.height - pad - cornerLen - 10),
      Offset(size.width - pad, pad + cornerLen + 10),
      Offset(size.width - pad, size.height - pad - cornerLen - 10),
    ]) {
      canvas.drawCircle(pos, 3, dotPaint);
    }
  }

  // ── Frame 1: 阿里山晨霧 — Forest / nature ──────────────────
  void _paintForest(Canvas canvas, Size size) {
    const pad = 18.0;

    final topRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.28);
    canvas.drawRect(topRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryColor.withOpacity(0.42), Colors.transparent],
          ).createShader(topRect));

    final botRect = Rect.fromLTWH(
        0, size.height * 0.78, size.width, size.height * 0.22);
    canvas.drawRect(botRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [primaryColor.withOpacity(0.28), Colors.transparent],
          ).createShader(botRect));

    final wavePaint = Paint()
      ..color = accentColor.withOpacity(0.55)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    _drawWavyLine(canvas, Offset(pad, pad),
        Offset(size.width - pad, pad), true, wavePaint);
    _drawWavyLine(canvas, Offset(pad, size.height - pad),
        Offset(size.width - pad, size.height - pad), true, wavePaint);
    _drawWavyLine(canvas, Offset(pad, pad),
        Offset(pad, size.height - pad), false, wavePaint);
    _drawWavyLine(canvas, Offset(size.width - pad, pad),
        Offset(size.width - pad, size.height - pad), false, wavePaint);

    final leafPaint = Paint()
      ..color = accentColor.withOpacity(0.65)
      ..style = PaintingStyle.fill;
    _drawLeaf(canvas, Offset(pad + 4, pad + 4), 22, math.pi * 0.25, leafPaint);
    _drawLeaf(canvas, Offset(size.width - pad - 4, pad + 4), 22,
        math.pi * 0.75, leafPaint);
    _drawLeaf(canvas, Offset(pad + 4, size.height - pad - 4), 22,
        -math.pi * 0.25, leafPaint);
    _drawLeaf(canvas, Offset(size.width - pad - 4, size.height - pad - 4),
        22, -math.pi * 0.75, leafPaint);

    final dewPaint = Paint()
      ..color = accentColor.withOpacity(0.45)
      ..style = PaintingStyle.fill;
    for (final t in [0.15, 0.35, 0.50, 0.65, 0.85]) {
      canvas.drawCircle(Offset(size.width * t, pad - 1), 2.5, dewPaint);
      canvas.drawCircle(
          Offset(size.width * t, size.height - pad + 1), 2.5, dewPaint);
    }
  }

  // ── Frame 2: 火雞肉飯 — Warm / food ────────────────────────
  void _paintFood(Canvas canvas, Size size) {
    const pad = 18.0;

    final leftRect = Rect.fromLTWH(0, 0, size.width * 0.10, size.height);
    canvas.drawRect(leftRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [primaryColor.withOpacity(0.38), Colors.transparent],
          ).createShader(leftRect));

    final rightRect =
        Rect.fromLTWH(size.width * 0.90, 0, size.width * 0.10, size.height);
    canvas.drawRect(rightRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [primaryColor.withOpacity(0.38), Colors.transparent],
          ).createShader(rightRect));

    const scallops = 11;
    final stepH = (size.width - pad * 2) / scallops;
    final stepV = (size.height - pad * 2) / (scallops + 4);
    final r = stepH * 0.38;

    final scallop = Paint()
      ..color = accentColor.withOpacity(0.50)
      ..style = PaintingStyle.fill;
    for (var i = 0; i <= scallops; i++) {
      final x = pad + i * stepH;
      canvas.drawCircle(Offset(x, pad), r, scallop);
      canvas.drawCircle(Offset(x, size.height - pad), r, scallop);
    }
    for (var i = 1; i < scallops + 4; i++) {
      final y = pad + i * stepV;
      canvas.drawCircle(Offset(pad, y), r * 0.65, scallop);
      canvas.drawCircle(Offset(size.width - pad, y), r * 0.65, scallop);
    }

    canvas.drawRect(
      Rect.fromLTWH(pad + r * 1.3, pad + r * 1.3,
          size.width - (pad + r * 1.3) * 2, size.height - (pad + r * 1.3) * 2),
      Paint()
        ..color = primaryColor.withOpacity(0.30)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    final sparkPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final pos in [
      Offset(pad + r * 1.3 + 14, pad + r * 1.3 + 14),
      Offset(size.width - pad - r * 1.3 - 14, pad + r * 1.3 + 14),
      Offset(pad + r * 1.3 + 14, size.height - pad - r * 1.3 - 14),
      Offset(size.width - pad - r * 1.3 - 14,
          size.height - pad - r * 1.3 - 14),
    ]) {
      _drawSparkle(canvas, pos, 10, sparkPaint);
    }
  }

  // ── Frame 3: 嘉義夜市 — Night market ───────────────────────
  void _paintNight(Canvas canvas, Size size) {
    final vigPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [Colors.transparent, primaryColor.withOpacity(0.65)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vigPaint);

    const pad = 20.0;
    final dashPaint = Paint()
      ..color = accentColor.withOpacity(0.75)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    _drawDashedRect(canvas,
        Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2),
        dashPaint);

    final starFill = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    final starDim = Paint()
      ..color = accentColor.withOpacity(0.50)
      ..style = PaintingStyle.fill;
    final stars = [
      (Offset(pad + 14, pad + 14), 6.0, starFill),
      (Offset(size.width / 2, pad + 8), 4.0, starDim),
      (Offset(size.width - pad - 14, pad + 14), 6.0, starFill),
      (Offset(pad + 8, size.height / 2), 3.0, starDim),
      (Offset(size.width - pad - 8, size.height / 2), 3.0, starDim),
      (Offset(pad + 14, size.height - pad - 14), 6.0, starFill),
      (Offset(size.width / 2, size.height - pad - 8), 4.0, starDim),
      (Offset(size.width - pad - 14, size.height - pad - 14), 6.0, starFill),
    ];
    for (final s in stars) {
      _drawStar(canvas, s.$1, s.$2, s.$3);
    }

    final dotPaint = Paint()
      ..color = accentColor.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    for (final pos in [
      Offset(pad + 34, pad + 10),
      Offset(size.width - pad - 34, pad + 10),
      Offset(pad + 10, pad + 34),
      Offset(size.width - pad - 10, pad + 34),
      Offset(pad + 10, size.height - pad - 34),
      Offset(size.width - pad - 10, size.height - pad - 34),
      Offset(pad + 34, size.height - pad - 10),
      Offset(size.width - pad - 34, size.height - pad - 10),
    ]) {
      canvas.drawCircle(pos, 2.5, dotPaint);
    }
  }

  // ── Frame 4: 極簡白 — Minimal ──────────────────────────────
  void _paintMinimal(Canvas canvas, Size size) {
    const pad = 26.0;
    const cornerLen = 22.0;

    canvas.drawRect(
      Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2),
      Paint()
        ..color = primaryColor.withOpacity(0.45)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    final dotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    for (final pos in [
      Offset(pad, pad),
      Offset(size.width - pad, pad),
      Offset(pad, size.height - pad),
      Offset(size.width - pad, size.height - pad),
    ]) {
      canvas.drawCircle(pos, 4.5, dotPaint);
    }

    final tickPaint = Paint()
      ..color = accentColor.withOpacity(0.85)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    _drawCornerL(canvas, Offset(pad, pad), cornerLen, 1, 1, tickPaint);
    _drawCornerL(
        canvas, Offset(size.width - pad, pad), cornerLen, -1, 1, tickPaint);
    _drawCornerL(
        canvas, Offset(pad, size.height - pad), cornerLen, 1, -1, tickPaint);
    _drawCornerL(canvas, Offset(size.width - pad, size.height - pad),
        cornerLen, -1, -1, tickPaint);
  }

  // ── Frame 5: 復古底片 — Vintage film ───────────────────────
  void _paintVintage(Canvas canvas, Size size) {
    const stripH = 30.0;
    const holeSpacing = 26.0;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, stripH),
        Paint()..color = primaryColor.withOpacity(0.88));
    canvas.drawRect(
        Rect.fromLTWH(0, size.height - stripH, size.width, stripH),
        Paint()..color = primaryColor.withOpacity(0.88));

    final holePaint = Paint()
      ..color = accentColor.withOpacity(0.72)
      ..style = PaintingStyle.fill;
    var x = holeSpacing * 0.5;
    while (x < size.width) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, stripH / 2), width: 12, height: 8),
            const Radius.circular(3)),
        holePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, size.height - stripH / 2),
                width: 12,
                height: 8),
            const Radius.circular(3)),
        holePaint,
      );
      x += holeSpacing;
    }

    const innerPad = stripH + 8.0;
    canvas.drawRect(
      Rect.fromLTWH(innerPad * 0.5, innerPad,
          size.width - innerPad, size.height - innerPad * 2),
      Paint()
        ..color = accentColor.withOpacity(0.38)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    final cornerDot = Paint()
      ..color = accentColor.withOpacity(0.80)
      ..style = PaintingStyle.fill;
    for (final pos in [
      Offset(innerPad * 0.5, innerPad),
      Offset(size.width - innerPad * 0.5, innerPad),
      Offset(innerPad * 0.5, size.height - innerPad),
      Offset(size.width - innerPad * 0.5, size.height - innerPad),
    ]) {
      canvas.drawCircle(pos, 4, cornerDot);
    }

    final vigPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.72,
        colors: [Colors.transparent, primaryColor.withOpacity(0.32)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vigPaint);
  }

  // ── Shared drawing helpers ──────────────────────────────────

  void _drawCornerL(Canvas canvas, Offset corner, double len,
      double dx, double dy, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(corner.dx, corner.dy + dy * len)
        ..lineTo(corner.dx, corner.dy)
        ..lineTo(corner.dx + dx * len, corner.dy),
      paint,
    );
  }

  void _drawDiamond(Canvas canvas, Offset center, double r, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r, center.dy)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r, center.dy)
        ..close(),
      paint,
    );
  }

  void _drawLeaf(Canvas canvas, Offset tip, double sz, double angle,
      Paint paint) {
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(sz * 0.35, -sz * 0.35, sz * 0.75, -sz * 0.08)
        ..quadraticBezierTo(sz * 0.35, sz * 0.12, 0, 0),
      paint,
    );
    canvas.restore();
  }

  void _drawWavyLine(Canvas canvas, Offset start, Offset end,
      bool horizontal, Paint paint) {
    const waveAmp = 3.5;
    const waveLen = 18.0;
    final path = Path()..moveTo(start.dx, start.dy);
    if (horizontal) {
      var x = start.dx;
      var up = true;
      while (x < end.dx - 0.5) {
        final nextX = (x + waveLen / 2).clamp(start.dx, end.dx);
        path.quadraticBezierTo(
            (x + nextX) / 2, start.dy + (up ? -waveAmp : waveAmp),
            nextX, start.dy);
        x = nextX;
        up = !up;
      }
    } else {
      var y = start.dy;
      var left = true;
      while (y < end.dy - 0.5) {
        final nextY = (y + waveLen / 2).clamp(start.dy, end.dy);
        path.quadraticBezierTo(
            start.dx + (left ? -waveAmp : waveAmp), (y + nextY) / 2,
            start.dx, nextY);
        y = nextY;
        left = !left;
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLen = 11.0;
    const gapLen = 6.0;
    void drawDash(Offset s, Offset e) {
      final dist = (e - s).distance;
      final dir = (e - s) / dist;
      var t = 0.0;
      var drawing = true;
      while (t < dist) {
        final seg = drawing ? dashLen : gapLen;
        final next = (t + seg).clamp(0.0, dist);
        if (drawing) canvas.drawLine(s + dir * t, s + dir * next, paint);
        t = next;
        drawing = !drawing;
      }
    }

    drawDash(rect.topLeft, rect.topRight);
    drawDash(rect.topRight, rect.bottomRight);
    drawDash(rect.bottomRight, rect.bottomLeft);
    drawDash(rect.bottomLeft, rect.topLeft);
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outerA = i * 2 * math.pi / 5 - math.pi / 2;
      final innerA = outerA + math.pi / 5;
      final outer =
          center + Offset(r * math.cos(outerA), r * math.sin(outerA));
      final inner = center +
          Offset(r * 0.38 * math.cos(innerA), r * 0.38 * math.sin(innerA));
      if (i == 0) path.moveTo(outer.dx, outer.dy);
      else path.lineTo(outer.dx, outer.dy);
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSparkle(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final len = i.isEven ? r : r * 0.55;
      path
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + len * math.cos(angle),
          center.dy + len * math.sin(angle),
        );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.primaryColor != primaryColor ||
      old.accentColor != accentColor ||
      old.frameIndex != frameIndex;
}
