import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../widgets/common_widgets.dart' show TapFeedback, SectionHeader;
import '../services/community_service.dart';
import 'saved_posts_page.dart';
import 'travel_companions_page.dart';
import 'package:share_plus/share_plus.dart';
import 'stamp_screen.dart';
import 'login_page.dart';
import 'settings_screen.dart';
import 'community_screen.dart' show FirebasePostDetailPage;
import 'trip_screen.dart' show TripScreen;
import 'info_pages.dart';
import '../services/local_fav_service.dart';

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

// ── 加入時間轉換為會員稱號 ─────────────────────────────────
String _memberTitle(DateTime? createdAt) {
  if (createdAt == null) return '旅途探索者';
  final days = DateTime.now().difference(createdAt).inDays;
  if (days < 30)  return '探索新手 🌱';
  if (days < 90)  return '旅途探索者 🗺️';
  if (days < 365) return '資深旅人 ✈️';
  return '★ 小火雞';
}

String _formatJoinDate(DateTime? createdAt) {
  if (createdAt == null) return '加入中…';
  return '加入：${createdAt.year} 年 ${createdAt.month} 月 ${createdAt.day} 日';
}

// ── 旅人會員卡 ──────────────────────────────────────────────
Widget _memberCard(BuildContext context, Color primary, {bool isGuest = false, DateTime? joinedAt}) {
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
          Text(
            isGuest ? '登入享探索旅人特權' : _memberTitle(joinedAt),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 3),
          Text(
            isGuest ? '行程管理 · 集章成就 · 旅行分享' : _formatJoinDate(joinedAt),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      )),
      const SizedBox(width: 12),
      ElevatedButton(
        onPressed: isGuest
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LoginPage()))
            : () => _showBenefitsDialog(context, primary),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: Text(isGuest ? '立即登入' : '旅行統計'),
      ),
    ]),
  );
}

void _showBenefitsDialog(BuildContext context, Color primary) {
  // 旅行統計：從 SharedPreferences + Firestore 取資料
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _TravelStatsSheet(primary: primary),
  );
}

class _TravelStatsSheet extends StatefulWidget {
  final Color primary;
  const _TravelStatsSheet({required this.primary});
  @override State<_TravelStatsSheet> createState() => _TravelStatsSheetState();
}

class _TravelStatsSheetState extends State<_TravelStatsSheet> {
  int _stamps = 0, _trips = 0, _streak = 0, _saved = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 打卡數 + 連續打卡：從 SharedPreferences
      final raw = prefs.getString('stamp_visited_v1');
      int stamps = 0;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        stamps = decoded.values.where((v) => (v as int) > 0).length;
      }
      final streak = prefs.getInt('stamp_streak_v1') ?? 0;

      // 行程數：從 Firestore trips 集合直接計算（準確）
      int trips = 0, saved = 0;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final tripsSnap = await FirebaseFirestore.instance
            .collection('trips')
            .where('uid', isEqualTo: uid)
            .get();
        trips = tripsSnap.docs.length;
      }
      // 收藏景點數：從 LocalFavService（本地 SharedPreferences）
      final savedSpots = await LocalFavService.getSavedSpotsData();
      saved = savedSpots.length;

      if (mounted) setState(() {
        _stamps = stamps; _trips = trips; _streak = streak; _saved = saved; _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
        Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: p.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.bar_chart_rounded, color: p, size: 22)),
          const SizedBox(width: 12),
          const Text('旅行統計', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 20),
        if (!_loaded)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: CircularProgressIndicator(color: p, strokeWidth: 2))
        else
          Row(children: [
            _statTile(p, Icons.approval_rounded, '$_stamps', '打卡景點'),
            const SizedBox(width: 8),
            _statTile(p, Icons.local_fire_department_rounded, '$_streak', '連續打卡'),
            const SizedBox(width: 8),
            _statTile(p, Icons.map_rounded, '$_trips', '行程數'),
            const SizedBox(width: 8),
            _statTile(p, Icons.bookmark_rounded, '$_saved', '收藏數'),
          ]),
        const SizedBox(height: 16),
        // 激勵文字
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: p.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Text(
            _stamps >= 10 ? '你已打卡 $_stamps 個景點，是資深探索者！🌟'
              : _stamps >= 5 ? '繼續探索，還有 ${10 - _stamps} 個景點等你！✨'
              : '開始你的第一次打卡，探索嘉義的美！🗺️',
            style: TextStyle(fontSize: 12, color: p, fontWeight: FontWeight.w600, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }

  Widget _statTile(Color p, IconData icon, String val, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: p.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: p, size: 20),
        const SizedBox(height: 6),
        Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: p)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
      ]),
    ),
  );
}

// ── 我的資料快捷區塊（一行 4 格，各色縫線邊框）──────────────────
Widget _myDataSection(BuildContext context, Color primary, {bool dimmed = false}) {
  // 四種顏色各異：綠、暖橘、藍、粉紅
  final tiles = [
    // tab 1 = 打卡照片
    (Icons.photo_camera_outlined, '打卡照片', const Color(0xFFE6F0E6),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StampScreen(initialTab: 1)))),
    // tab 2 = 成就徽章
    (Icons.emoji_events_outlined, '成就徽章', const Color(0xFFF5EFE6),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StampScreen(initialTab: 2)))),
    // tab 4 = 小地圖（我的足跡）
    (Icons.map_outlined, '我的足跡', const Color(0xFFE8EFF8),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StampScreen(initialTab: 4)))),
    // 收藏景點 → 本地收藏頁
    (Icons.bookmark_border_rounded, '收藏景點', const Color(0xFFF8EAF0),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _GuestSavedSpotsPage()))),
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
            onPressed: () => Share.share(
              '我正在使用「探索諸羅」探索嘉義！\n一起來玩嘉義吧！\n\n下載 App：探索諸羅',
              subject: '探索諸羅 App 邀請',
            ),
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
      const Text('🤝', style: TextStyle(fontSize: 46)),
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
  onTap: () {
    Widget page;
    if (label == '隱私政策') page = const PrivacyPolicyPage();
    else if (label == '常見問題') page = const FAQPage();
    else page = const AboutPage();
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  },
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
                    const Text('關於我',
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
                    _menuItem(context, icon: Icons.bookmark_outline_rounded,
                      iconColor: const Color(0xFFE91E63), title: '我的收藏',
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

  Future<void> _showEditNameDialog(BuildContext context, Color primary, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('修改名稱', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '輸入新的暱稱'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({'nickname': newName});
        }
        if (mounted) setState(() {});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名稱已更新'), behavior: SnackBarBehavior.floating));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失敗：$e'), behavior: SnackBarBehavior.floating));
      }
    }
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
      // Firestore：行程數 + 收藏數
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(widget.user.uid).get();
      final d = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _tripCount  = (d['tripCount']  as num?)?.toInt() ?? 0;
        _savedCount = (d['savedCount'] as num?)?.toInt() ?? 0;
      });
      // SharedPreferences：打卡數（stamp data 存在本地）
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('stamp_visited_v1');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final count = decoded.values.where((v) => (v as int) > 0).length;
        if (mounted) setState(() => _stampCount = count);
      }
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
                  GestureDetector(
                    onTap: () => _showEditNameDialog(context, primary, name),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_rounded, size: 15, color: primary.withValues(alpha: 0.6)),
                    ]),
                  ),
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
                _memberCard(context, primary, joinedAt: user.metadata.creationTime),
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
                    _menuItem(context, icon: Icons.local_offer_outlined,
                      iconColor: const Color(0xFFFF9800), title: '優惠券',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const CouponsScreen()))),
                    _menuDivider(),
                    _menuItem(context, icon: Icons.people_outline_rounded,
                      iconColor: const Color(0xFF2196F3), title: '旅伴管理',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const TravelCompanionsPage()))),
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
            const Icon(Icons.lock_rounded, size: 48, color: AppColors.textHint),
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
                  const Icon(Icons.bookmark_border_rounded, size: 48, color: AppColors.textHint),
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
                  // Sort to match saved order
                  posts.sort((a, b) {
                    final ia = savedIds.indexOf(a.id);
                    final ib = savedIds.indexOf(b.id);
                    return ia.compareTo(ib);
                  });
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: posts.length,
                    itemBuilder: (_, i) {
                      final p = posts[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => FirebasePostDetailPage(post: p))),
                          child: StitchedBox(
                            color: Colors.white,
                            stitchColor: primary.withValues(alpha: 0.20),
                            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
                            padding: EdgeInsets.zero,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              // Cover image
                              if (p.imageURLs.isNotEmpty)
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                  child: Image.network(p.imageURLs.first,
                                    height: 130, width: double.infinity, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    CircleAvatar(radius: 14,
                                      backgroundImage: p.authorPhoto.isNotEmpty
                                          ? NetworkImage(p.authorPhoto) : null,
                                      backgroundColor: primary.withValues(alpha: 0.1),
                                      child: p.authorPhoto.isEmpty
                                          ? Icon(Icons.person_rounded, size: 14, color: primary) : null),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(p.authorName,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: primary.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8)),
                                      child: Text(p.type == 'trip' ? '🧳 行程' : '💬 討論',
                                        style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600))),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(p.title,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                                  if (p.content.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(p.content,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    const Icon(Icons.favorite_rounded, size: 13, color: AppColors.error),
                                    const SizedBox(width: 3),
                                    Text('${p.likeCount}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.chat_bubble_outline_rounded, size: 13, color: AppColors.textHint),
                                    const SizedBox(width: 3),
                                    Text('${p.commentCount}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                                    const Spacer(),
                                    // 取消收藏
                                    GestureDetector(
                                      onTap: () async {
                                        await CommunityService.toggleSave(p.id);
                                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                          content: Text('已取消收藏「${p.title}」'),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ));
                                      },
                                      child: Icon(Icons.bookmark_remove_outlined,
                                          size: 18, color: primary.withValues(alpha: 0.7)),
                                    ),
                                  ]),
                                ]),
                              ),
                            ]),
                          ),
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

// ── Helper: "即將推出" SnackBar ──────────────────────────────
void _showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.rocket_launch_rounded, size: 16),
      const SizedBox(width: 10),
      Text('$feature 功能即將推出，敬請期待！'),
    ]),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

// ── 收藏景點捷徑：登入用戶→TripScreen，訪客→本地收藏頁 ─────────
class _SavedSpotsShortcut extends StatelessWidget {
  const _SavedSpotsShortcut();
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null ? const TripScreen() : const _GuestSavedSpotsPage();
  }
}

// ── 訪客收藏景點頁面 ────────────────────────────────────────────
class _GuestSavedSpotsPage extends StatefulWidget {
  const _GuestSavedSpotsPage();
  @override State<_GuestSavedSpotsPage> createState() => _GuestSavedSpotsPageState();
}

class _GuestSavedSpotsPageState extends State<_GuestSavedSpotsPage> {
  List<Map<String, dynamic>> _spots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    LocalFavService.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    LocalFavService.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load();

  Future<void> _load() async {
    final data = await LocalFavService.getSavedSpotsData();
    if (mounted) setState(() { _spots = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏景點', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _spots.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.favorite_border_rounded, size: 52, color: AppColors.textHint.withValues(alpha: 0.4)),
                  const SizedBox(height: 14),
                  const Text('還沒有收藏景點', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  const Text('點擊景點上的愛心即可收藏', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                  const SizedBox(height: 20),
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('去探索景點')),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _spots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = _spots[i];
                    final name     = s['spotName'] as String? ?? '';
                    final imageUrl = s['imageUrl'] as String? ?? '';
                    final rating   = (s['rating'] as num?)?.toDouble() ?? 0.0;
                    final category = s['category'] as String? ?? '';
                    final spotId   = s['spotId'] as String? ?? '';
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Row(children: [
                        // 封面圖
                        ClipRRect(
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                          child: imageUrl.isNotEmpty
                              ? Image.network(imageUrl, width: 80, height: 90, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(primary))
                              : _placeholder(primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (category.isNotEmpty) Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                              child: Text(category, style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 5),
                            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (rating > 0) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(Icons.star_rounded, size: 13, color: AppColors.accentStraw),
                                const SizedBox(width: 3),
                                Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w600)),
                              ]),
                            ],
                          ]),
                        )),
                        // 取消收藏
                        IconButton(
                          icon: const Icon(Icons.favorite_rounded, color: AppColors.error, size: 20),
                          onPressed: () async {
                            await LocalFavService.toggleWithMeta(spotId, spotName: name);
                          },
                        ),
                      ]),
                    );
                  },
                ),
    );
  }

  Widget _placeholder(Color primary) => Container(
    width: 80, height: 90,
    color: primary.withValues(alpha: 0.08),
    child: Icon(Icons.place_rounded, size: 30, color: primary.withValues(alpha: 0.4)),
  );
}

// ════════════════════════════════════════════════════════════
//  優惠券頁面（Firestore 驅動）
//  Firestore 結構：
//    coupons/{couponId}
//      title, desc, expiryDate (Timestamp), couponCode (String),
//      maxUses (int), usedCount (int), isActive (bool),
//      iconName (String), colorHex (String), createdBy (String)
//    users/{uid}/claimed_coupons/{couponId}
//      claimedAt (Timestamp), isUsed (bool), usedAt (Timestamp?)
// ════════════════════════════════════════════════════════════
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});
  @override State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  /// 領取優惠券
  Future<void> _claimCoupon(String couponId, Map<String, dynamic> coupon) async {
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('請先登入才能領取優惠券'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    // 檢查是否已領取
    final alreadyClaimed = await _db
        .collection('users').doc(uid)
        .collection('claimed_coupons').doc(couponId).get();
    if (alreadyClaimed.exists) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('你已經領取過這張優惠券了'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    // 檢查是否超過使用上限
    final maxUses = (coupon['maxUses'] as num?)?.toInt() ?? 9999;
    final usedCount = (coupon['usedCount'] as num?)?.toInt() ?? 0;
    if (usedCount >= maxUses) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('此優惠券已發放完畢'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    // 寫入 claimed_coupons + 更新 usedCount
    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(uid).collection('claimed_coupons').doc(couponId),
      {'claimedAt': FieldValue.serverTimestamp(), 'isUsed': false},
    );
    batch.update(_db.collection('coupons').doc(couponId), {
      'usedCount': FieldValue.increment(1),
    });
    await batch.commit();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('優惠券已成功領取！'),
      backgroundColor: Theme.of(context).colorScheme.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// 使用優惠券（出示優惠碼）
  Future<void> _useCoupon(BuildContext ctx, String couponId, String couponCode, Color color) async {
    final uid = _uid;
    if (uid == null) return;
    // 顯示優惠碼 dialog
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('出示優惠碼', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('請向店家出示以下優惠碼：', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.local_offer_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Text(couponCode.isNotEmpty ? couponCode : 'CHIAYI2026',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                    color: color, letterSpacing: 2)),
            ]),
          ),
          const SizedBox(height: 12),
          const Text('確認使用後此優惠券將標記為已使用',
            style: TextStyle(fontSize: 12, color: AppColors.textHint), textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0),
            child: const Text('確認使用'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 標記為已使用
    await _db.collection('users').doc(uid)
        .collection('claimed_coupons').doc(couponId)
        .update({'isUsed': true, 'usedAt': FieldValue.serverTimestamp()});
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: const Text('優惠券使用成功！'),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Color _parseColor(String hex) {
    try { return Color(int.parse(hex.replaceFirst('#', '0xFF'))); } catch (_) { return AppColors.accentSky; }
  }

  IconData _parseIcon(String name) {
    const map = {
      'account_balance': Icons.account_balance_rounded,
      'landscape':       Icons.landscape_rounded,
      'restaurant':      Icons.restaurant_rounded,
      'local_offer':     Icons.local_offer_rounded,
      'hotel':           Icons.hotel_rounded,
      'directions_bus':  Icons.directions_bus_rounded,
    };
    return map[name] ?? Icons.local_offer_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final uid = _uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('優惠券', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 不加 orderBy 避免 Firestore composite index 需求，client 端排序
        stream: _db.collection('coupons')
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (ctx, couponSnap) {
          // 只在第一次等待時顯示 loading，避免一直轉圈
          if (couponSnap.connectionState == ConnectionState.waiting &&
              !couponSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // 有錯誤（如 Firestore 權限/index）或無資料 → 直接顯示空狀態
          if (couponSnap.hasError || !couponSnap.hasData) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.local_offer_outlined, size: 52, color: AppColors.textHint.withValues(alpha: 0.5)),
              const SizedBox(height: 14),
              const Text('目前沒有優惠券', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('敬請期待管理員上架更多優惠！', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
            ]));
          }
          // 按 createdAt 降序排序（client 端）
          final coupons = couponSnap.data!.docs.toList()
            ..sort((a, b) {
              final ta = (a.data() as Map)['createdAt'];
              final tb = (b.data() as Map)['createdAt'];
              if (ta == null || tb == null) return 0;
              return (tb as Timestamp).compareTo(ta as Timestamp);
            });

          if (coupons.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.local_offer_outlined, size: 52, color: AppColors.textHint.withValues(alpha: 0.5)),
              const SizedBox(height: 14),
              const Text('目前沒有優惠券', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('敬請期待管理員上架更多優惠！', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
            ]));
          }

          return uid == null
              ? _buildGuestView(coupons, primary)
              : StreamBuilder<QuerySnapshot>(
                  stream: _db.collection('users').doc(uid)
                      .collection('claimed_coupons').snapshots(),
                  builder: (ctx, claimSnap) {
                    final claimed = <String, Map<String, dynamic>>{};
                    for (final d in claimSnap.data?.docs ?? []) {
                      claimed[d.id] = d.data() as Map<String, dynamic>;
                    }
                    return _buildCouponList(coupons, claimed, primary);
                  },
                );
        },
      ),
    );
  }

  Widget _buildGuestView(List<QueryDocumentSnapshot> coupons, Color primary) {
    return Column(children: [
      Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, color: primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('登入後即可領取優惠券！',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
        ]),
      ),
      Expanded(child: _buildCouponList(coupons, {}, primary)),
    ]);
  }

  Widget _buildCouponList(
      List<QueryDocumentSnapshot> coupons,
      Map<String, Map<String, dynamic>> claimed,
      Color primary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 提示橫幅
        Container(
          padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primary.withValues(alpha: 0.12), primary.withValues(alpha: 0.05)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(Icons.local_fire_department_rounded, color: primary, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('集章打卡，解鎖更多優惠！',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primary)),
              const Text('探索嘉義各景點即可獲得景點周邊折扣',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ])),
          ]),
        ),
        ...coupons.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final claimInfo = claimed[doc.id];
          final isClaimed = claimInfo != null;
          final isUsed    = claimInfo?['isUsed'] as bool? ?? false;
          final maxUses   = (d['maxUses']   as num?)?.toInt() ?? 9999;
          final usedCount = (d['usedCount'] as num?)?.toInt() ?? 0;
          final isFull    = usedCount >= maxUses;
          final color     = _parseColor(d['colorHex'] as String? ?? '#88B8C8');
          final icon      = _parseIcon(d['iconName']  as String? ?? 'local_offer');
          final code      = d['couponCode'] as String? ?? '';
          final expiry    = d['expiryDate'] as Timestamp?;
          final expiryStr = expiry != null
              ? '${expiry.toDate().year}/${expiry.toDate().month}/${expiry.toDate().day}'
              : '--';

          return _CouponCard(
            couponId:   doc.id,
            title:      d['title']   as String? ?? '',
            desc:       d['desc']    as String? ?? '',
            expiryStr:  expiryStr,
            couponCode: code,
            icon:       icon,
            color:      color,
            isClaimed:  isClaimed,
            isUsed:     isUsed,
            isFull:     isFull,
            usedCount:  usedCount,
            maxUses:    maxUses,
            onClaim:  () => _claimCoupon(doc.id, d),
            onUse:    () => _useCoupon(context, doc.id, code, color),
          );
        }),
      ],
    );
  }
}

class _CouponCard extends StatefulWidget {
  final String couponId, title, desc, expiryStr, couponCode;
  final IconData icon;
  final Color color;
  final bool isClaimed, isUsed, isFull;
  final int usedCount, maxUses;
  final VoidCallback onClaim, onUse;
  const _CouponCard({
    required this.couponId, required this.title, required this.desc,
    required this.expiryStr, required this.couponCode,
    required this.icon, required this.color,
    required this.isClaimed, required this.isUsed, required this.isFull,
    required this.usedCount, required this.maxUses,
    required this.onClaim, required this.onUse,
  });
  @override State<_CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends State<_CouponCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final dimmed = widget.isUsed || widget.isFull;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dimmed ? AppColors.background : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dimmed ? AppColors.divider : c.withValues(alpha: 0.35), width: 1.5),
        boxShadow: dimmed ? [] : [
          BoxShadow(color: c.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: (dimmed ? AppColors.textHint : c).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: dimmed ? AppColors.textHint : c, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: dimmed ? AppColors.textHint : AppColors.textPrimary,
                  decoration: widget.isUsed ? TextDecoration.lineThrough : null,
                )),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.access_time_rounded, size: 11, color: AppColors.textHint),
                  const SizedBox(width: 3),
                  Text('效期至 ${widget.expiryStr}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                  const SizedBox(width: 8),
                  Text('${widget.usedCount}/${widget.maxUses == 9999 ? "∞" : widget.maxUses}',
                    style: TextStyle(fontSize: 10, color: AppColors.textHint.withValues(alpha: 0.7))),
                ]),
              ])),
              // 狀態 chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.isUsed ? AppColors.divider
                      : widget.isFull ? AppColors.divider
                      : widget.isClaimed ? c.withValues(alpha: 0.12)
                      : c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.isUsed ? '已使用'
                      : widget.isFull ? '已發完'
                      : widget.isClaimed ? '已領取'
                      : '未領取',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: widget.isUsed || widget.isFull ? AppColors.textHint : c,
                  ),
                ),
              ),
            ]),
          ),
        ),
        if (_expanded && !widget.isUsed && !widget.isFull) ...[
          Divider(height: 1, color: c.withValues(alpha: 0.15)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.desc,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.isClaimed ? widget.onUse : widget.onClaim,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c, foregroundColor: Colors.white,
                    elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(widget.isClaimed ? '立即使用' : '領取優惠券',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

