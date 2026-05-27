import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';
import '../screens/settings_screen.dart';
import '../screens/login_page.dart';
import '../models/dummy_data.dart';

class AuthDrawer extends StatefulWidget {
  const AuthDrawer({super.key});

  @override
  State<AuthDrawer> createState() => _AuthDrawerState();
}

class _AuthDrawerState extends State<AuthDrawer>
    with SingleTickerProviderStateMixin {
  // ── Auth UI state ──────────────────────────────────────
  bool _isLoggedIn = false;

  // ── User photo (loaded from Firestore) ─────────────────
  String? _userPhotoUrl;

  // ── Auth state stream ──────────────────────────────────
  StreamSubscription<fb_auth.User?>? _authSub;

  // ── Animation ──────────────────────────────────────────
  late AnimationController _animController;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = fb_auth.FirebaseAuth.instance.currentUser != null;
    if (_isLoggedIn) _loadUserPhoto();

    _authSub = fb_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      final loggedIn = user != null;
      if (loggedIn != _isLoggedIn) {
        setState(() => _isLoggedIn = loggedIn);
        if (loggedIn) {
          _animController.forward(from: 0);
          _loadUserPhoto();
        }
      }
    });

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════
  //  Auth logic
  // ══════════════════════════════════════════════════════

  Future<void> _doLogout() async {
    await fb_auth.FirebaseAuth.instance.signOut();
    if (mounted) {
      setState(() {
        _isLoggedIn   = false;
        _userPhotoUrl = null;
      });
      _animController.forward(from: 0);
    }
  }

  Future<void> _loadUserPhoto() async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      if (mounted && doc.exists) {
        setState(() =>
            _userPhotoUrl = doc.data()?['photoUrl'] as String?);
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: _isLoggedIn ? _buildProfile(context) : _buildGuestView(context),
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  GUEST VIEW (未登入 — 引導前往 LoginPage)
  // ══════════════════════════════════════════════════════
  Widget _buildGuestView(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final primary  = settings.currentTheme.primary;
    final primDark = settings.currentTheme.primaryDark;

    return SafeArea(
      child: Column(
        children: [
          // ── Gradient header ──────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primDark, primary],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🏯', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 14),
                const Text(
                  '探索諸羅',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '嘉義最完整的在地旅遊夥伴',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Login / Register prompt card ─────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceWarm,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Icon
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person_outline_rounded,
                        color: primary, size: 32),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '尚未登入',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '登入後可收藏景點、規劃行程、\n集章成就、與社群互動',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                        height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _openLoginPage(context),
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text('登入 / 註冊',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Feature highlights ────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('登入後解鎖功能',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primary)),
                const SizedBox(height: 12),
                _featureRow(Icons.favorite_outline_rounded, '收藏景點與美食'),
                _featureRow(Icons.calendar_today_outlined,  '個人化行程規劃'),
                _featureRow(Icons.military_tech_outlined,   '集章成就系統'),
                _featureRow(Icons.people_outline_rounded,   '與旅人社群互動'),
              ],
            ),
          ),

          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('探索諸羅 v1.0.0',
                style: TextStyle(color: AppColors.textHint, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textPrimary)),
    ]),
  );

  void _openLoginPage(BuildContext context) {
    // Capture root navigator BEFORE pop to avoid context invalidation
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop(); // close drawer
    rootNav.push(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  // ══════════════════════════════════════════════════════
  //  USER PROFILE
  // ══════════════════════════════════════════════════════
  Widget _buildProfile(BuildContext context) {
    final settings  = context.watch<AppSettingsProvider>();
    final primary   = settings.currentTheme.primary;
    final primDark  = settings.currentTheme.primaryDark;
    final fbUser    = fb_auth.FirebaseAuth.instance.currentUser;
    final userName  = fbUser?.displayName ?? '諸羅旅行者';
    final userEmail = fbUser?.email ?? '';

    return Column(
      children: [
        // Profile header
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
              24, MediaQuery.of(context).padding.top + 24, 24, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primDark, primary],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: ClipOval(
                      child: _userPhotoUrl != null
                          ? Image.network(
                              _userPhotoUrl!,
                              fit: BoxFit.cover,
                              width: 60, height: 60,
                              errorBuilder: (_, __, ___) =>
                                  const Center(child: Text('😊', style: TextStyle(fontSize: 28))),
                            )
                          : const Center(child: Text('😊', style: TextStyle(fontSize: 28))),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          userEmail,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white, size: 18),
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.push(MaterialPageRoute(
                        builder: (_) => const _EditProfilePage(),
                      )).then((_) {
                        if (mounted) _loadUserPhoto();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Stats — will be replaced with real Firestore data in future
              Row(
                children: [
                  _profileStat('—', '景點'),
                  _vDivider(),
                  _profileStat('—', '行程'),
                  _vDivider(),
                  _profileStat('—', '成就'),
                  _vDivider(),
                  _profileStat('—', '獲讚'),
                ],
              ),
            ],
          ),
        ),

        // Menu items
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _menuItem(Icons.person_outline_rounded, '我的資料', () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const _ProfileDetailPage()));
              }),
              _menuItem(Icons.favorite_outline_rounded, '收藏清單', () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const _FavoritesPage()));
              }),
              _menuItem(Icons.calendar_today_outlined, '我的行程', () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const _MyTripsPage()));
              }),
              _menuItem(Icons.military_tech_outlined, '成就徽章', () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const _BadgesPage()));
              }),
              _menuItem(Icons.camera_alt_outlined, '打卡照片', () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const _CheckinPhotosPage()));
              }),
              const Divider(height: 20, indent: 16, endIndent: 16),
              _menuItem(Icons.notifications_outlined, '通知設定',
                  () => _showNotifSettings(context)),
              _menuItem(Icons.palette_rounded, '外觀與語言', () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }),
              _menuItem(Icons.privacy_tip_outlined, '隱私政策', () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const _PrivacyPage()));
              }),
              _menuItem(Icons.help_outline_rounded, '常見問題',
                  () => _showFAQ(context)),
              const Divider(height: 20, indent: 16, endIndent: 16),
              ListTile(
                leading:
                    const Icon(Icons.logout_rounded, color: AppColors.error),
                title: const Text(
                  '登出',
                  style: TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w600),
                ),
                onTap: _doLogout,
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  '探索諸羅 v1.0.0',
                  style: TextStyle(color: AppColors.textHint, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 30, color: Colors.white24);

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textHint, size: 18),
      onTap: onTap,
    );
  }



  void _showNotifSettings(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('通知設定',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text('活動提醒'),
            activeThumbColor: Theme.of(ctx).colorScheme.primary,
          ),
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text('社群通知'),
            activeThumbColor: Theme.of(ctx).colorScheme.primary,
          ),
          SwitchListTile(
            value: false,
            onChanged: (_) {},
            title: const Text('行銷推播'),
            activeThumbColor: Theme.of(ctx).colorScheme.primary,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('儲存'),
          )
        ],
      ),
    );
  }

  void _showFAQ(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        builder: (c, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              const Text('常見問題',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              _faqItem('如何加入行程？',
                  '在景點詳情頁面點選「加入行程」即可，或在候選清單中拖移排序後轉為行程。'),
              _faqItem('分帳功能怎麼用？',
                  '點選底部導覽「分帳」，新增成員後即可記錄消費，系統自動計算最少轉帳方式。'),
              _faqItem('集章要怎麼集？',
                  '實際到訪景點後點選「打卡」，完成 GPS 驗證即可獲得印章。'),
              _faqItem('行程可以分享嗎？',
                  '在「我的行程」點選「分享」，可產生 QR Code 或直接分享到社群。'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _faqItem(String q, String a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMoss,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(q,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(a,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  Edit Profile Page
// ══════════════════════════════════════════════════════════
class _EditProfilePage extends StatefulWidget {
  const _EditProfilePage();
  @override
  State<_EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<_EditProfilePage> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  bool    _saving      = false;
  String  _avatar      = '😊';
  XFile?  _pickedImage;
  String? _photoUrl;   // currently saved URL from Firestore

  static const _avatars = ['😊','😎','🏔️','🌸','🎨','🚂','🦋','🍜','📷','🌲','⛰️','🎭'];

  @override
  void initState() {
    super.initState();
    final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
    _nameCtrl.text = fbUser?.displayName ?? '';
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _bioCtrl.text = doc.data()?['bio'] as String? ?? '';
          _avatar       = doc.data()?['avatar'] as String? ?? '😊';
          _photoUrl     = doc.data()?['photoUrl'] as String?;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512, maxHeight: 512,
        imageQuality: 85);
    if (picked != null && mounted) {
      setState(() {
        _pickedImage = picked;
        _avatar      = '😊'; // clear emoji selection when photo is chosen
      });
    }
  }

  Future<String?> _uploadPhoto(String uid) async {
    if (_pickedImage == null) return null;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('users/$uid/avatar.jpg');
      final task = await ref.putFile(
        File(_pickedImage!.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await task.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  Future<void> _save() async {
    final uid  = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    final name = _nameCtrl.text.trim();
    if (uid == null || name.isEmpty) return;
    setState(() => _saving = true);
    try {
      // Upload new photo if selected
      String? newPhotoUrl;
      if (_pickedImage != null) {
        newPhotoUrl = await _uploadPhoto(uid);
      }

      await fb_auth.FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'nickname': name,
        'bio':      _bioCtrl.text.trim(),
        'avatar':   _avatar,
        if (newPhotoUrl != null) 'photoUrl': newPhotoUrl,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('個人資料已更新 ✓'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('儲存失敗：$e'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    // Decide what to show in the big avatar circle
    Widget avatarContent;
    if (_pickedImage != null) {
      avatarContent = Image.file(File(_pickedImage!.path),
          fit: BoxFit.cover, width: 88, height: 88);
    } else if (_photoUrl != null) {
      avatarContent = Image.network(_photoUrl!, fit: BoxFit.cover,
          width: 88, height: 88,
          errorBuilder: (_, __, ___) =>
              Center(child: Text(_avatar, style: const TextStyle(fontSize: 44))));
    } else {
      avatarContent = Center(child: Text(_avatar, style: const TextStyle(fontSize: 44)));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('編輯個人資料',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: primary))
                : Text('儲存',
                    style: TextStyle(fontWeight: FontWeight.w700, color: primary, fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Avatar section ───────────────────────────────
          Center(
            child: Column(children: [
              GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.1),
                        border: Border.all(color: primary, width: 2),
                      ),
                      child: ClipOval(child: avatarContent),
                    ),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('點擊更換相片',
                  style: TextStyle(fontSize: 11, color: primary)),
              const SizedBox(height: 12),
              // Emoji picker (hidden when a real photo is chosen)
              if (_pickedImage == null && _photoUrl == null) ...[
                const Text('或選擇 Emoji 頭像',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10, runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: _avatars.map((a) {
                    final sel = a == _avatar && _pickedImage == null;
                    return GestureDetector(
                      onTap: () => setState(() => _avatar = a),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? primary.withValues(alpha: 0.15) : AppColors.surfaceMoss,
                          border: Border.all(
                              color: sel ? primary : AppColors.divider,
                              width: sel ? 2 : 1),
                        ),
                        child: Center(child: Text(a,
                            style: const TextStyle(fontSize: 24))),
                      ),
                    );
                  }).toList(),
                ),
              ] else
                // Show a "remove photo" option
                TextButton.icon(
                  onPressed: () => setState(() {
                    _pickedImage = null;
                    _photoUrl    = null;
                  }),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('移除照片，改用 Emoji'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Basic info ───────────────────────────────────
          const Text('基本資料',
              style: TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '暱稱',
              hintText: '輸入你的暱稱',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bioCtrl,
            maxLines: 3,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: '個人簡介',
              hintText: '介紹一下自己…（最多 100 字）',
              prefixIcon: Icon(Icons.edit_note_rounded, size: 18),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceMoss,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textHint),
              SizedBox(width: 8),
              Expanded(child: Text(
                '變更暱稱後需重新登入才會在所有裝置同步',
                style: TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.4),
              )),
            ]),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  Favorites Page (收藏清單)
// ══════════════════════════════════════════════════════════
class _FavoritesPage extends StatefulWidget {
  const _FavoritesPage();
  @override
  State<_FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<_FavoritesPage> {
  late List<Spot> _spots;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _spots = List.from(DummyData.spots);
  }

  void _remove(Spot s) {
    setState(() => _spots.removeWhere((x) => x.id == s.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已移除「${s.name}」'),
      action: SnackBarAction(
        label: '復原',
        onPressed: () => setState(() => _spots.insert(0, s)),
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final q = _search.toLowerCase();
    final filtered = q.isEmpty
        ? _spots
        : _spots.where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.address.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('收藏清單', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜尋收藏景點…',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: AppColors.surfaceMoss,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_spots.isEmpty ? '💔' : '🔍', style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(_spots.isEmpty ? '還沒有收藏的景點' : '找不到符合的景點',
                style: const TextStyle(color: AppColors.textHint, fontSize: 15)),
              if (_spots.isEmpty) ...[
                const SizedBox(height: 8),
                const Text('在地圖或景點詳情頁點愛心即可收藏',
                  style: TextStyle(color: AppColors.textHint, fontSize: 12)),
              ],
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final s = filtered[i];
                return Dismissible(
                  key: Key(s.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                      SizedBox(height: 2),
                      Text('移除', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  onDismissed: (_) => _remove(s),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWarm,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
                        child: Image.network(
                          s.imageUrl,
                          width: 90, height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 90, height: 90,
                            color: AppColors.surfaceMoss,
                            child: const Center(child: Text('🏔️', style: TextStyle(fontSize: 28))),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.location_on_outlined, size: 11, color: AppColors.textHint),
                              const SizedBox(width: 2),
                              Expanded(child: Text(s.address,
                                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(s.category, style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
                        onPressed: () {},
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  My Trips Page (我的行程)
// ══════════════════════════════════════════════════════════
class _MyTripsPage extends StatelessWidget {
  const _MyTripsPage();

  static const _mock = [
    _TripData('嘉義週末輕旅行', '2025-06-07 ～ 06-08', '2天1夜', false, ['阿里山國家風景區','北門車站','文化路夜市'], 'https://picsum.photos/seed/mytrip1/600/200'),
    _TripData('親子阿里山一日遊', '2025-05-18', '1天', true, ['阿里山國家風景區','嘉義公園','林聰明沙鍋魚頭'], 'https://picsum.photos/seed/mytrip2/600/200'),
    _TripData('故宮南院藝術之旅', '2025-04-12', '1天', true, ['故宮南院','嘉義市立美術館'], 'https://picsum.photos/seed/mytrip3/600/200'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('我的行程', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: primary),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('請至「行程管理」頁面建立新行程'),
              backgroundColor: primary, behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            )),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Summary chips
          Row(children: [
            _statChip('${_mock.length}', '總行程', primary),
            const SizedBox(width: 10),
            _statChip('${_mock.where((t) => t.done).length}', '已完成', AppColors.accentSky),
            const SizedBox(width: 10),
            _statChip('${_mock.where((t) => !t.done).length}', '計畫中', AppColors.warning),
          ]),
          const SizedBox(height: 16),
          ..._mock.map((t) => _TripCard(trip: t, primary: primary)),
        ],
      ),
    );
  }

  Widget _statChip(String val, String label, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Text(val, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: c)),
        Text(label, style: TextStyle(fontSize: 11, color: c)),
      ]),
    ),
  );
}

class _TripData {
  final String title, date, duration, cover;
  final bool done;
  final List<String> spots;
  const _TripData(this.title, this.date, this.duration, this.done, this.spots, this.cover);
}

class _TripCard extends StatelessWidget {
  final _TripData trip;
  final Color primary;
  const _TripCard({required this.trip, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
          child: Stack(children: [
            Image.network(trip.cover, height: 120, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(height: 120, color: AppColors.surfaceMoss,
                child: const Center(child: Text('🗾', style: TextStyle(fontSize: 40))))),
            Positioned(top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: trip.done ? AppColors.accentSky : primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(trip.done ? '✓ 已完成' : '計畫中',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trip.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(trip.date, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
              const SizedBox(width: 12),
              const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(trip.duration, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4,
              children: trip.spots.map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
                child: Text(s, style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600)),
              )).toList()),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  Badges Page (成就徽章)
// ══════════════════════════════════════════════════════════
class _BadgesPage extends StatelessWidget {
  const _BadgesPage();

  static const _badges = [
    _Badge('🏔️', '阿里山探索者', '完成阿里山景區所有必訪景點', true,  '2025-03-15'),
    _Badge('🍜', '雞肉飯達人',    '打卡 5 間以上雞肉飯名店',    true,  '2025-04-02'),
    _Badge('📸', '初心攝影師',    '上傳第一張打卡照片',         true,  '2025-02-10'),
    _Badge('🗺️', '地圖探索者',    '解鎖地圖上 20 個地點',       true,  '2025-01-28'),
    _Badge('🚂', '鐵道愛好者',    '搭乘阿里山小火車並打卡',      false, ''),
    _Badge('🌸', '四季旅人',      '在春夏秋冬各完成一次行程',    false, ''),
    _Badge('👥', '社群達人',      '獲得 50 個讚',               false, ''),
    _Badge('⭐', '諸羅傳說',      '完成所有成就',               false, ''),
  ];

  @override
  Widget build(BuildContext context) {
    final primary   = Theme.of(context).colorScheme.primary;
    final earned    = _badges.where((b) => b.earned).length;
    final total     = _badges.length;
    final progress  = earned / total;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('成就徽章', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Progress card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primary.withValues(alpha: 0.12), primary.withValues(alpha: 0.04)]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: primary.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('🏆', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('已解鎖 $earned / $total 個成就',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: primary)),
                  const SizedBox(height: 4),
                  Text('繼續探索嘉義，解鎖更多成就！',
                    style: TextStyle(fontSize: 12, color: primary.withValues(alpha: 0.7))),
                ])),
              ]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress, minHeight: 10,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
              ),
              const SizedBox(height: 6),
              Text('${(progress * 100).round()}% 完成', style: TextStyle(fontSize: 11, color: primary)),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('全部成就', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, childAspectRatio: 1.1, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: _badges.length,
            itemBuilder: (_, i) {
              final b = _badges[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: b.earned ? AppColors.surfaceWarm : AppColors.surfaceMoss,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: b.earned ? primary.withValues(alpha: 0.3) : AppColors.divider),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(b.emoji, style: TextStyle(fontSize: 36, color: b.earned ? null : const Color(0xFF999999))),
                  if (!b.earned) const SizedBox.shrink()
                  else Container(),
                  const SizedBox(height: 8),
                  Text(b.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12,
                      color: b.earned ? AppColors.textPrimary : AppColors.textHint),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(b.desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (b.earned && b.earnedDate.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                      child: Text(b.earnedDate, style: TextStyle(fontSize: 9, color: primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Badge {
  final String emoji, title, desc, earnedDate;
  final bool earned;
  const _Badge(this.emoji, this.title, this.desc, this.earned, this.earnedDate);
}

// ══════════════════════════════════════════════════════════
//  Checkin Photos Page (打卡照片)
// ══════════════════════════════════════════════════════════
class _CheckinPhotosPage extends StatefulWidget {
  const _CheckinPhotosPage();
  @override
  State<_CheckinPhotosPage> createState() => _CheckinPhotosPageState();
}

class _CheckinPhotosPageState extends State<_CheckinPhotosPage> {
  static final _photos = List.generate(12, (i) => _PhotoData(
    url:     'https://picsum.photos/seed/checkin${i + 1}/400/400',
    spot:    ['阿里山國家風景區','北門車站','文化路夜市','嘉義公園','故宮南院','嘉義市立美術館',
              '蘭潭水庫','奮起湖','阿里山鐵道','嘉義火車站','林聰明沙鍋魚頭','御品元冰品'][i % 12],
    date:    '2025-0${(i % 4) + 2}-${(i * 3 + 10).toString().padLeft(2, '0')}',
    emoji:   ['🌲','🚂','🌙','🌳','🏛️','🎨','🌊','☁️','🚃','🏯','🍜','🍧'][i % 12],
  ));

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('打卡照片', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${_photos.length} 張',
              style: TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 14))),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              _miniStat(Icons.camera_alt_outlined,    '${_photos.length} 張照片', primary),
              const SizedBox(width: 16),
              _miniStat(Icons.location_on_outlined,   '${_photos.length} 個地點', AppColors.accentSky),
              const SizedBox(width: 16),
              _miniStat(Icons.calendar_today_outlined, '近 4 個月',               AppColors.warning),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
              itemCount: _photos.length,
              itemBuilder: (_, i) {
                final p = _photos[i];
                return GestureDetector(
                  onTap: () => _showPhoto(context, i),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(p.url, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surfaceMoss,
                        child: Center(child: Text(p.emoji, style: const TextStyle(fontSize: 28))),
                      )),
                    Positioned(bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter, end: Alignment.topCenter,
                            colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent]),
                        ),
                        child: Text(p.spot,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, Color c) => Row(children: [
    Icon(icon, size: 14, color: c),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
  ]);

  void _showPhoto(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (_) {
        final p = _photos[index];
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(p.url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 200, color: AppColors.surfaceMoss,
                  child: Center(child: Text(p.emoji, style: const TextStyle(fontSize: 60))))),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Text(p.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.spot, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                  Text(p.date, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                ])),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _PhotoData {
  final String url, spot, date, emoji;
  const _PhotoData({required this.url, required this.spot, required this.date, required this.emoji});
}

// ══════════════════════════════════════════════════════════
//  Privacy Policy Page (隱私政策)
// ══════════════════════════════════════════════════════════
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('隱私政策', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.privacy_tip_outlined, color: primary, size: 20),
                const SizedBox(width: 8),
                Text('探索諸羅 隱私政策', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primary)),
              ]),
              const SizedBox(height: 6),
              const Text('最後更新：2025 年 6 月 1 日',
                style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            ]),
          ),
          const SizedBox(height: 20),
          _privSection('📋 一、資料收集範圍', '我們收集以下類型的個人資料：\n\n'
            '• 帳號資料：電子郵件、暱稱、頭像\n'
            '• 位置資料：您允許存取位置時，我們取得您的 GPS 座標以提供附近景點功能\n'
            '• 使用記錄：您的行程記錄、收藏清單、打卡地點、消費記錄\n'
            '• 社群內容：您發布的貼文、留言、照片\n'
            '• 裝置資訊：作業系統版本、App 版本，用於錯誤回報'),
          _privSection('🎯 二、資料使用目的', '我們使用您的資料以：\n\n'
            '• 提供核心功能：地圖探索、行程規劃、集章成就\n'
            '• 改善使用體驗：個人化推薦、使用習慣分析\n'
            '• 帳號管理：登入驗證、密碼重設\n'
            '• 社群功能：互動、追蹤、分享\n'
            '• 客服支援：問題回報與解決'),
          _privSection('🤝 三、資料共享', '我們不會將您的個人資料出售給第三方。我們僅在以下情況共享資料：\n\n'
            '• Firebase / Google Cloud：用於身份驗證、資料儲存\n'
            '• 交通資訊 API：匿名化請求，不傳送個人識別資料\n'
            '• 政府開放資料：景點、活動等資訊均來自公開來源\n'
            '• 法律要求：依法院命令或主管機關要求'),
          _privSection('🔒 四、資料安全', '我們採取以下措施保護您的資料：\n\n'
            '• 所有傳輸均使用 HTTPS 加密\n'
            '• Firebase Security Rules 限制資料存取\n'
            '• 密碼以雜湊方式儲存，我們無法得知您的密碼\n'
            '• 定期安全性審查'),
          _privSection('✅ 五、您的權利', '依據個人資料保護法，您擁有：\n\n'
            '• 查詢權：查閱我們持有的您的個人資料\n'
            '• 更正權：要求更正不正確的資料\n'
            '• 刪除權：要求刪除您的帳號及所有相關資料\n'
            '• 攜帶權：取得您的資料副本\n'
            '• 異議權：反對特定資料處理方式\n\n'
            '如需行使上述權利，請聯繫我們。'),
          _privSection('📧 六、聯絡我們', '如有隱私相關問題，請聯繫：\n\n'
            'Email：privacy@chiayicity-app.tw\n'
            '地址：嘉義市東區山子頂 1 號\n'
            '服務時間：週一至週五 09:00 - 17:00'),
          const SizedBox(height: 20),
          Center(
            child: Text('© 2025 探索諸羅 · All rights reserved',
              style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _privSection(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      Text(body, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.8)),
      const Divider(height: 24),
    ]),
  );
}

// ══════════════════════════════════════════════════════════
//  Profile Detail Page
// ══════════════════════════════════════════════════════════

class _ProfileUser {
  final String name, emoji, bio;
  final int trips;
  _ProfileUser(this.name, this.emoji, this.bio, this.trips);
}

class _ProfileDetailPage extends StatefulWidget {
  const _ProfileDetailPage();

  @override
  State<_ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<_ProfileDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  final List<_ProfileUser> _following = [
    _ProfileUser('阿里山達人', '🌲', '熱愛山林的嘉義人', 8),
    _ProfileUser('雞肉飯控', '🍜', '走遍嘉義大街小巷的美食家', 12),
    _ProfileUser('諸羅城市探索者', '🏛️', '古蹟文化深度旅遊', 5),
    _ProfileUser('嘉義單車客', '🚲', '用雙輪丈量嘉義每一條路', 7),
    _ProfileUser('北門攝影師', '📷', '記錄嘉義舊城角落的光影', 15),
  ];

  final List<_ProfileUser> _followers = [
    _ProfileUser('太平洋的風', '🌊', '喜歡到處旅行的背包客', 3),
    _ProfileUser('嘉義新移民', '🏡', '來自台北、愛上嘉義的人', 6),
    _ProfileUser('奮起湖鐵道迷', '🚂', '收集台灣所有支線鐵路記憶', 9),
    _ProfileUser('蘭潭釣魚人', '🎣', '週末就在蘭潭畔放空', 2),
    _ProfileUser('文化路夜市女王', '🌙', '嘉義小吃無所不知', 11),
    _ProfileUser('玉山登頂者', '⛰️', '百岳俱樂部成員，從嘉義出發', 4),
  ];

  final Set<String> _unfollowed = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '我的資料',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.textPrimary),
        ),
        bottom: TabBar(
          controller: _tab,
          unselectedLabelColor: AppColors.textHint,
          tabs: [
            Tab(text: '追蹤中 (${_following.length})'),
            Tab(text: '追蹤者 (${_followers.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildUserList(_following, isFollowing: true),
          _buildUserList(_followers, isFollowing: false),
        ],
      ),
    );
  }

  Widget _buildUserList(List<_ProfileUser> users,
      {required bool isFollowing}) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(isFollowing ? '👥' : '🔔',
                style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              isFollowing ? '還沒有追蹤任何人' : '還沒有人追蹤你',
              style: const TextStyle(
                  color: AppColors.textHint, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final u          = users[index];
        final unfollowed = _unfollowed.contains(u.name);
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceMoss,
              border: Border.all(color: AppColors.divider),
            ),
            child: Center(
                child: Text(u.emoji,
                    style: const TextStyle(fontSize: 22))),
          ),
          title: Text(
            u.name,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(u.bio,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textHint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${u.trips} 篇行程',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary)),
            ],
          ),
          trailing: isFollowing
              ? GestureDetector(
                  onTap: () => setState(() {
                    if (unfollowed) {
                      _unfollowed.remove(u.name);
                    } else {
                      _unfollowed.add(u.name);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: unfollowed
                          ? AppColors.surfaceMoss
                          : Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: unfollowed
                            ? AppColors.divider
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    child: Text(
                      unfollowed ? '已取消追蹤' : '追蹤中',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: unfollowed
                            ? AppColors.textSecondary
                            : Colors.white,
                      ),
                    ),
                  ),
                )
              : OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('追蹤',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
        );
      },
    );
  }
}
