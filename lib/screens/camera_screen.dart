import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  int _selectedFrame = 0;
  bool _showGallery = false;

  final List<_Frame> _frames = [
    _Frame('諸羅風華', '🏯', AppColors.primary, AppColors.accentStraw),
    _Frame('阿里山晨霧', '🌲', const Color(0xFF2D6A4F), const Color(0xFF95D5B2)),
    _Frame('火雞肉飯', '🍜', const Color(0xFFE76F51), const Color(0xFFE9C46A)),
    _Frame('嘉義夜市', '🌙', const Color(0xFF1A1A2E), const Color(0xFFE9C46A)),
    _Frame('極簡白', '⬜', Colors.white, const Color(0xFFDDDDDD)),
    _Frame('復古底片', '📷', const Color(0xFF5C3D2E), const Color(0xFFE8C99A)),
  ];

  final List<Map<String, String>> _gallery = [
    {'emoji': '🌲', 'name': '阿里山神木', 'date': '05/12'},
    {'emoji': '🍜', 'name': '文化路夜市', 'date': '05/10'},
    {'emoji': '🏛️', 'name': '嘉義美術館', 'date': '05/08'},
    {'emoji': '🚂', 'name': '北門車站', 'date': '05/05'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _showGallery ? _buildGallery(context) : _buildCamera(context),
    );
  }

  Widget _buildCamera(BuildContext context) {
    return Stack(
      children: [
        // Simulated camera viewfinder
        Container(
          color: const Color(0xFF1A1A1A),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_rounded,
                    color: Colors.white.withOpacity(0.2), size: 80),
                const SizedBox(height: 12),
                Text(
                  '相機預覽',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Selected frame overlay
        Positioned.fill(
          child: _buildFrameOverlay(_frames[_selectedFrame]),
        ),

        // Top controls
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _cameraButton(Icons.close_rounded, () => Navigator.pop(context)),
                const Spacer(),
                _cameraButton(Icons.flash_off_rounded, () {}),
                const SizedBox(width: 8),
                _cameraButton(Icons.flip_camera_ios_rounded, () {}),
                const SizedBox(width: 8),
                _cameraButton(Icons.photo_library_outlined, () {
                  setState(() => _showGallery = true);
                }),
              ],
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              children: [
                // Frame selector
                _buildFrameSelector(),
                const SizedBox(height: 20),

                // Shutter row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Last photo thumbnail
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: const Center(
                        child: Text('🏛️', style: TextStyle(fontSize: 24)),
                      ),
                    ),

                    // Shutter button
                    GestureDetector(
                      onTap: () => _showPhotoResult(context),
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.circle,
                            size: 64, color: Colors.white),
                      ),
                    ),

                    // Location badge toggle
                    GestureDetector(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primaryLight),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('📍', style: TextStyle(fontSize: 18)),
                            Text(
                              '位置',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
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

  Widget _buildFrameOverlay(_Frame frame) {
    return CustomPaint(
      painter: _FramePainter(
        primaryColor: frame.primaryColor,
        accentColor: frame.accentColor,
        name: frame.name,
        emoji: frame.emoji,
      ),
    );
  }

  Widget _buildFrameSelector() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _frames.length,
        itemBuilder: (context, index) {
          final frame = _frames[index];
          final isSelected = _selectedFrame == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedFrame = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 70,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white30,
                  width: isSelected ? 2.5 : 1,
                ),
                color: frame.primaryColor.withOpacity(isSelected ? 0.6 : 0.3),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(frame.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    frame.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
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

  Widget _buildGallery(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          '打卡相簿',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => setState(() => _showGallery = false),
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('選取'),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: _gallery.length + 2,
        itemBuilder: (context, index) {
          if (index >= _gallery.length) {
            return Container(
              color: AppColors.surfaceMoss,
              child: const Center(
                child: Icon(Icons.add_photo_alternate_outlined,
                    color: AppColors.textHint, size: 36),
              ),
            );
          }
          final photo = _gallery[index];
          return GestureDetector(
            child: Container(
              color: const Color(0xFF2A2A2A),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Text(
                      photo['emoji']!,
                      style: const TextStyle(fontSize: 48),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      color: Colors.black54,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              photo['name']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            photo['date']!,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 9),
                          ),
                        ],
                      ),
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

  Widget _cameraButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  void _showPhotoResult(BuildContext context) {
    final frame = _frames[_selectedFrame];
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Simulated photo with frame
            Container(
              width: 300,
              height: 360,
              decoration: BoxDecoration(
                color: frame.primaryColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: frame.accentColor, width: 4),
              ),
              child: Stack(
                children: [
                  // Photo area
                  Positioned.fill(
                    bottom: 60,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(frame.emoji,
                                style: const TextStyle(fontSize: 60)),
                            const SizedBox(height: 8),
                            const Text('📸 拍照預覽',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Frame footer
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Text('🏯',
                              style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '探索諸羅',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '阿里山景區 · 05/14',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: const Text('儲存'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Frame {
  final String name, emoji;
  final Color primaryColor, accentColor;

  _Frame(this.name, this.emoji, this.primaryColor, this.accentColor);
}

class _FramePainter extends CustomPainter {
  final Color primaryColor, accentColor;
  final String name, emoji;

  _FramePainter({
    required this.primaryColor,
    required this.accentColor,
    required this.name,
    required this.emoji,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = primaryColor.withOpacity(0.7)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final cornerPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 30.0;
    const padding = 16.0;

    // Border
    canvas.drawRect(
      Rect.fromLTWH(padding, padding, size.width - padding * 2,
          size.height - padding * 2),
      borderPaint,
    );

    // Corner accents
    final corners = [
      [Offset(padding, padding + cornerLen), Offset(padding, padding),
        Offset(padding + cornerLen, padding)],
      [Offset(size.width - padding - cornerLen, padding),
        Offset(size.width - padding, padding),
        Offset(size.width - padding, padding + cornerLen)],
      [Offset(padding, size.height - padding - cornerLen),
        Offset(padding, size.height - padding),
        Offset(padding + cornerLen, size.height - padding)],
      [Offset(size.width - padding - cornerLen, size.height - padding),
        Offset(size.width - padding, size.height - padding),
        Offset(size.width - padding, size.height - padding - cornerLen)],
    ];

    for (final corner in corners) {
      final path = Path()
        ..moveTo(corner[0].dx, corner[0].dy)
        ..lineTo(corner[1].dx, corner[1].dy)
        ..lineTo(corner[2].dx, corner[2].dy);
      canvas.drawPath(path, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
