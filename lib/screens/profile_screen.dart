import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../widgets/common_widgets.dart' show TapFeedback, SectionHeader;
import '../services/community_service.dart';
import 'stamp_screen.dart';
import 'login_page.dart';
import 'settings_screen.dart';
import 'community_screen.dart' show FirebasePostDetailPage;

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        return user == null
            ? _GuestProfileView()
            : _LoggedInProfileView(user: user);
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
//  共用 UI helpers
// ════════════════════════════════════════════════════════════

// ── 造型頭像框：雙環 + 虛線裝飾圓 ─────────────────────────────
class _StyledAvatar extends StatelessWidget {
  final double size;
  final Color primary;
  final Widget child;
  const _StyledAvatar({required this.size, required this.primary, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _AvatarFramePainter(color: primary),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [primary, Color.lerp(primary, Colors.white, 0.5)!, primary],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        padding: const EdgeInsets.all(3.5),
        child: ClipOval(
          child: Container(
            color: primary.withValues(alpha: 0.06),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AvatarFramePainter extends CustomPainter {
  final Color color;
  const _AvatarFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 + 5;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // 外圈虛線裝飾
    const dashCount = 20;
    const dashLen = 0.18; // radians
    final gap = (2 * 3.14159 - dashCount * dashLen) / dashCount;
    double angle = 0;
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle, dashLen, false, paint);
      angle += dashLen + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarFramePainter old) => old.color != color;
}

Widget _statBox(String value, String label) {
  return Expanded(child: Column(children: [
    Text(value,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
          color: AppColors.textPrimary)),
    const SizedBox(height: 2),
    Text(label,
      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
  ]));
}

Widget _statDivider() => Container(
  width: 1, height: 28, color: AppColors.divider);

Widget _menuItem(BuildContext context, {
  required IconData icon,
  required Color iconColor,
  required String title,
  String? badge,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Icon(icon, size: 18, color: iconColor)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary))),
        if (badge != null)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(badge,
              style: const TextStyle(fontSize: 10, color: AppColors.error,
                  fontWeight: FontWeight.w700)),
          ),
        const Icon(Icons.chevron_right_rounded,
            size: 18, color: AppColors.textHint),
      ]),
    ),
  );
}

Widget _menuDivider() => const Divider(
    height: 1, indent: 66, endIndent: 0, color: AppColors.divider);

// ── 旅人會員卡 ──────────────────────────────────────────────
Widget _memberCard(BuildContext context, Color primary, {bool isGuest = false}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color.lerp(primary, const Color(0xFFFFE0B2), 0.55)!,
          Color.lerp(primary, const Color(0xFFFFF3E0), 0.72)!,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isGuest ? '登入享探索旅人特權' : '旅人會員',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
          const SizedBox(height: 3),
          Text(isGuest ? '行程管理 · 集章成就 · 旅行分享' : '效期至 2025/12/31',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      )),
      const SizedBox(width: 12),
      ElevatedButton(
        onPressed: isGuest
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LoginPage()))
            : () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: Text(isGuest ? '立即登入' : '查看權益'),
      ),
    ]),
  );
}

// ── 我的資料快捷區塊（一行 4 格，各色縫線邊框）──────────────────
Widget _myDataSection(BuildContext context, Color primary, {bool dimmed = false}) {
  // 四種顏色各異：綠、暖橘、藍、粉紅
  final tiles = [
    (Icons.photo_camera_outlined,  '打卡照片', const Color(0xFFE6F0E6), () {}),
    (Icons.emoji_events_outlined,  '成就徽章', const Color(0xFFF5EFE6),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StampScreen()))),
    (Icons.map_outlined,           '我的足跡', const Color(0xFFE8EFF8), () {}),
    (Icons.bookmark_border_rounded,'收藏景點', const Color(0xFFF8EAF0), () {}),
  ];

  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHeader(title: '我的資料'),
    const SizedBox(height: 12),
    Row(
      children: tiles.asMap().entries.map((e) {
        final isLast = e.key == tiles.length - 1;
        final t = e.value;
        return Expanded(
          child: Container(
            margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(right: 8),
            child: Opacity(
              opacity: dimmed ? 0.35 : 1.0,
              child: TapFeedback(
                onTap: t.$4,
                child: StitchedBox(
                  color: t.$3,
                  stitchColor: AppColors.textHint.withValues(alpha: 0.55),
                  radius: 14, inset: 4, dashWidth: 4, dashGap: 3.5, stitchStrokeWidth: 1.0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.$1, color: AppColors.textPrimary, size: 22),
                    const SizedBox(height: 4),
                    Text(t.$2, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  ]),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ),
  ]);
}

// ── 分享橫幅 ─────────────────────────────────────────────────
Widget _referralBanner(Color primary) {
  return Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color.lerp(primary, Colors.white, 0.55)!,
          Color.lerp(primary, const Color(0xFF80DEEA), 0.50)!,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('分享旅行，賺取回饋！',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('邀請好友註冊，雙方都能獲得優惠獎勵！',
            style: TextStyle(fontSize: 11,
                color: AppColors.textPrimary.withValues(alpha: 0.65))),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: const Text('立即邀請'),
          ),
        ],
      )),
      const SizedBox(width: 8),
      const Text('🤝', style: TextStyle(fontSize: 52)),
    ]),
  );
}

// ── 隱私政策 / 常見問題連結 ──────────────────────────────────
Widget _faqLinks(BuildContext context) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _textLink(context, '隱私政策'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Text('·', style: TextStyle(color: AppColors.textHint)),
      ),
      _textLink(context, '常見問題'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Text('·', style: TextStyle(color: AppColors.textHint)),
      ),
      _textLink(context, '關於我們'),
    ],
  );
}

Widget _textLink(BuildContext context, String label) => GestureDetector(
  onTap: () => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text('$label 頁面即將推出，敬請期待。',
          style: const TextStyle(color: AppColors.textSecondary)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('確定'))],
    ),
  ),
  child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
);

// ════════════════════════════════════════════════════════════
//  未登入 — 訪客視圖
// ════════════════════════════════════════════════════════════
class _GuestProfileView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── 頂部頭像區 ──────────────────────────────────────
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(children: [
                  Row(children: [
                    const Text('我的',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary)),
                  ]),
                  const SizedBox(height: 20),
                  // Avatar（訪客）— 造型框
                  _StyledAvatar(
                    size: 94, primary: primary,
                    child: Center(child: Icon(Icons.person_rounded,
                        size: 46, color: primary.withValues(alpha: 0.35))),
                  ),
                  const SizedBox(height: 10),
                  const Text('訪客',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('登入以儲存你的旅行足跡',
                    style: TextStyle(fontSize: 12,
                        color: AppColors.textHint)),
                  const SizedBox(height: 20),
                  // Stats
                  Row(children: [
                    _statBox('--', '旅行次數'),
                    _statDivider(),
                    _statBox('--', '收藏景點'),
                    _statDivider(),
                    _statBox('--', '集章數'),
                  ]),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),

          // ── 卡片區塊 ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(children: [
                _memberCard(context, primary, isGuest: true),
                const SizedBox(height: 14),
                // 我的資料（縫線快捷，dim）
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: _myDataSection(context, primary, dimmed: true),
                ),
                const SizedBox(height: 14),
                // Menu
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Column(children: [
                    _menuItem(context, icon: Icons.favorite_border_rounded,
                      iconColor: const Color(0xFFE91E63), title: '我的收藏',
                      onTap: () => _requireLogin(context)),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.history_rounded,
                      iconColor: const Color(0xFF9C27B0), title: '瀏覽紀錄',
                      onTap: () => _requireLogin(context)),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.local_offer_outlined,
                      iconColor: const Color(0xFFFF9800), title: '優惠券',
                      onTap: () => _requireLogin(context)),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.settings_outlined,
                      iconColor: AppColors.textSecondary, title: '設定',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                  ]),
                ),
                const SizedBox(height: 14),
                _referralBanner(primary),
                const SizedBox(height: 14),
                _faqLinks(context),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _requireLogin(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LoginPage()));
  }
}

// ════════════════════════════════════════════════════════════
//  已登入 — 完整個人頁面
// ════════════════════════════════════════════════════════════
class _LoggedInProfileView extends StatefulWidget {
  final User user;
  const _LoggedInProfileView({required this.user});

  @override
  State<_LoggedInProfileView> createState() => _LoggedInProfileViewState();
}

class _LoggedInProfileViewState extends State<_LoggedInProfileView> {
  int _tripCount  = 0;
  int _savedCount = 0;
  int _stampCount = 0;
  // 頭貼上傳狀態
  File? _localPhoto;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _pickAndUploadPhoto(BuildContext context) async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('從相簿選取'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    final picked = await picker.pickImage(source: choice, imageQuality: 80, maxWidth: 600);
    if (picked == null || !mounted) return;

    setState(() { _localPhoto = File(picked.path); _uploading = true; });
    try {
      final ref = FirebaseStorage.instance.ref('avatars/${widget.user.uid}.jpg');
      await ref.putFile(_localPhoto!);
      final url = await ref.getDownloadURL();
      await widget.user.updatePhotoURL(url);
      await FirebaseFirestore.instance
          .collection('users').doc(widget.user.uid)
          .set({'photoURL': url}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上傳失敗：$e'), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _loadCounts() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(widget.user.uid).get();
      final d = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _tripCount  = (d['tripCount']  as num?)?.toInt() ?? 0;
        _savedCount = (d['savedCount'] as num?)?.toInt() ?? 0;
        _stampCount = (d['stampCount'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }


  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final user    = widget.user;
    final name    = user.displayName ?? '旅行家';
    final photo   = user.photoURL;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── 頂部頭像區 ──────────────────────────────────────
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(children: [
                  const Row(children: [
                    Text('我的',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary)),
                  ]),
                  const SizedBox(height: 20),
                  // Avatar — 造型框 + 相機按鈕
                  GestureDetector(
                    onTap: () => _pickAndUploadPhoto(context),
                    child: Stack(children: [
                      _StyledAvatar(
                        size: 94, primary: primary,
                        child: _uploading
                          ? CircularProgressIndicator(strokeWidth: 2.5, color: primary)
                          : (_localPhoto != null
                            ? Image.file(_localPhoto!, fit: BoxFit.cover, width: 94, height: 94)
                            : (photo != null
                              ? Image.network(photo, fit: BoxFit.cover, width: 94, height: 94,
                                  errorBuilder: (_, __, ___) => Icon(Icons.person_rounded,
                                      size: 46, color: primary.withValues(alpha: 0.5)))
                              : Icon(Icons.person_rounded, size: 46,
                                  color: primary.withValues(alpha: 0.5)))),
                      ),
                      Positioned(
                        bottom: 2, right: 2,
                        child: Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color: primary, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 4)],
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Text(name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                  const SizedBox(height: 20),
                  // Stats row
                  Row(children: [
                    _statBox('$_tripCount', '旅行次數'),
                    _statDivider(),
                    _statBox('$_savedCount', '收藏景點'),
                    _statDivider(),
                    _statBox('$_stampCount', '集章數'),
                  ]),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),

          // ── 卡片區塊 ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(children: [
                // 旅人會員卡
                _memberCard(context, primary),
                const SizedBox(height: 14),
                // 我的資料（縫線快捷區塊）
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: _myDataSection(context, primary),
                ),
                const SizedBox(height: 14),
                // Menu list
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Column(children: [
                    _menuItem(context, icon: Icons.favorite_border_rounded,
                      iconColor: const Color(0xFFE91E63), title: '我的收藏',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SavedPostsPage()))),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.history_rounded,
                      iconColor: const Color(0xFF9C27B0), title: '瀏覽紀錄', onTap: () {}),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.local_offer_outlined,
                      iconColor: const Color(0xFFFF9800), title: '優惠券', onTap: () {}),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.people_outline_rounded,
                      iconColor: const Color(0xFF2196F3), title: '旅伴管理', onTap: () {}),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.emoji_events_outlined,
                      iconColor: const Color(0xFFF57F17), title: '集章成就',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const StampScreen()))),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.settings_outlined,
                      iconColor: AppColors.textSecondary, title: '設定',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                  ]),
                ),
                const SizedBox(height: 14),
                _referralBanner(primary),
                const SizedBox(height: 14),
                _faqLinks(context),
                const SizedBox(height: 14),
                // 登出
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _logout(context),
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('登出'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('確認登出', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('確定要登出帳號嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('登出',
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) await FirebaseAuth.instance.signOut();
  }
}

// ════════════════════════════════════════════════════════════
// 收藏的貼文頁面 — 從 Firestore users/{uid}/saved_posts 讀取
// ════════════════════════════════════════════════════════════
class SavedPostsPage extends StatelessWidget {
  const SavedPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏的貼文', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
            onPressed: () => Navigator.pop(context)),
      ),
      body: uid == null
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🔒', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('請先登入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]))
        : StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users').doc(uid).collection('saved_posts')
                .orderBy('savedAt', descending: true)
                .snapshots(),
            builder: (ctx, userSnap) {
              if (!userSnap.hasData) {
                return Center(child: CircularProgressIndicator(color: primary));
              }
              final savedIds = userSnap.data!.docs.map((d) => d.id).toList();
              if (savedIds.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('🔖', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  const Text('還沒有收藏的貼文', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  const Text('去社群探索喜歡的貼文並收藏吧！', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                ]));
              }
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('community_posts')
                    .where(FieldPath.documentId, whereIn: savedIds.take(10).toList())
                    .snapshots(),
                builder: (_, postSnap) {
                  if (!postSnap.hasData) {
                    return Center(child: CircularProgressIndicator(color: primary));
                  }
                  final posts = postSnap.data!.docs.map(CommunityPost.fromDoc).toList();
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: posts.length,
                    itemBuilder: (_, i) {
                      final p = posts[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => FirebasePostDetailPage(post: p))),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10, offset: const Offset(0, 3))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              CircleAvatar(radius: 14,
                                backgroundImage: p.authorPhoto.isNotEmpty
                                    ? NetworkImage(p.authorPhoto) : null,
                                backgroundColor: primary.withValues(alpha: 0.1)),
                              const SizedBox(width: 8),
                              Text(p.authorName,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              Text(p.type == 'trip' ? '🧳 行程' : '💬 討論',
                                style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600)),
                            ]),
                            const SizedBox(height: 8),
                            Text(p.title,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            if (p.content.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(p.content,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 8),
                            Row(children: [
                              const Icon(Icons.favorite_rounded, size: 14, color: AppColors.error),
                              const SizedBox(width: 3),
                              Text('${p.likeCount}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                              const SizedBox(width: 10),
                              const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppColors.textHint),
                              const SizedBox(width: 3),
                              Text('${p.commentCount}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                            ]),
                          ]),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
    );
  }
}
