import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AuthDrawer extends StatefulWidget {
  const AuthDrawer({super.key});

  @override
  State<AuthDrawer> createState() => _AuthDrawerState();
}

class _AuthDrawerState extends State<AuthDrawer>
    with SingleTickerProviderStateMixin {
  bool _isLoggedIn = false;
  bool _showLogin = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: _isLoggedIn ? _buildProfile(context) : _buildAuth(context),
      ),
    );
  }

  // ===== AUTH (Login / Register) =====
  Widget _buildAuth(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏯', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  const Text(
                    '探索諸羅',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登入以解鎖完整功能',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Toggle tabs
            Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceMoss,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _authTab('登入', _showLogin),
                    _authTab('註冊', !_showLogin),
                  ],
                ),
              ),
            ),

            // Form
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _showLogin ? _buildLoginForm() : _buildRegisterForm(),
            ),

            // Divider
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('或',
                        style: TextStyle(
                            color: AppColors.textHint, fontSize: 12)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
            ),

            // Social login
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _socialButton(
                    'Google 帳號登入',
                    '🌐',
                    const Color(0xFFEA4335),
                  ),
                  const SizedBox(height: 10),
                  _socialButton(
                    'Facebook 帳號登入',
                    '📘',
                    const Color(0xFF1877F2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _authTab(String label, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _showLogin = label == '登入');
          _animController.forward(from: 0);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color:
                  isSelected ? AppColors.primary : AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '歡迎回來 👋',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '登入你的帳號繼續探索嘉義',
          style: TextStyle(color: AppColors.textHint, fontSize: 13),
        ),
        const SizedBox(height: 20),
        const TextField(
          decoration: InputDecoration(
            labelText: '電子郵件',
            prefixIcon: Icon(Icons.email_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(
            labelText: '密碼',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: Icon(Icons.visibility_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '忘記密碼？',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            setState(() => _isLoggedIn = true);
            _animController.forward(from: 0);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('登入'),
        ),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '建立帳號 🎉',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '加入探索諸羅，開始你的嘉義旅程',
          style: TextStyle(color: AppColors.textHint, fontSize: 13),
        ),
        const SizedBox(height: 20),
        const TextField(
          decoration: InputDecoration(
            labelText: '暱稱',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          decoration: InputDecoration(
            labelText: '電子郵件',
            prefixIcon: Icon(Icons.email_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(
            labelText: '密碼',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(
            labelText: '確認密碼',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            setState(() => _isLoggedIn = true);
            _animController.forward(from: 0);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('建立帳號'),
        ),
      ],
    );
  }

  Widget _socialButton(String label, String icon, Color color) {
    return OutlinedButton(
      onPressed: () {
        setState(() => _isLoggedIn = true);
        _animController.forward(from: 0);
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        side: BorderSide(color: color.withOpacity(0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ===== USER PROFILE =====
  Widget _buildProfile(BuildContext context) {
    return Column(
      children: [
        // Profile header
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
              24, MediaQuery.of(context).padding.top + 24, 24, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDark, AppColors.primary],
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
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Center(
                        child: Text('😊', style: TextStyle(fontSize: 28))),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '諸羅旅行者',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'traveler@chiayi.com',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white, size: 18),
                    onPressed: () => _showComingSoon(context, '編輯個人資料'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _profileStat('12', '景點'),
                  _vDivider(),
                  _profileStat('3', '行程'),
                  _vDivider(),
                  _profileStat('4', '成就'),
                  _vDivider(),
                  _profileStat('156', '獲讚'),
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
              _menuItem(Icons.person_outline_rounded, '我的資料', () => _showComingSoon(context, '個人資料編輯')),
              _menuItem(Icons.favorite_outline_rounded, '收藏清單', () => _showComingSoon(context, '收藏清單')),
              _menuItem(Icons.calendar_today_outlined, '我的行程', () { Navigator.pop(context); }),
              _menuItem(Icons.military_tech_outlined, '成就徽章', () { Navigator.pop(context); }),
              _menuItem(Icons.camera_alt_outlined, '打卡照片', () => _showComingSoon(context, '打卡照片相簿')),
              const Divider(height: 20, indent: 16, endIndent: 16),
              _menuItem(Icons.notifications_outlined, '通知設定', () => _showNotifSettings(context)),
              _menuItem(Icons.language_rounded, '語言設定', () => _showLangSettings(context)),
              _menuItem(Icons.privacy_tip_outlined, '隱私政策', () => _showComingSoon(context, '隱私政策')),
              _menuItem(Icons.help_outline_rounded, '常見問題', () => _showFAQ(context)),
              const Divider(height: 20, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.logout_rounded,
                    color: AppColors.error),
                title: const Text(
                  '登出',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  setState(() => _isLoggedIn = false);
                  _animController.forward(from: 0);
                },
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
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, height: 30, color: Colors.white24);
  }

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

  void _showComingSoon(BuildContext ctx, String name) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('$name — 連接 Firebase 後即可使用'),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showNotifSettings(BuildContext ctx) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('通知設定', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(value: true, onChanged: (_) {},
          title: const Text('活動提醒'), activeColor: AppColors.primary),
        SwitchListTile(value: true, onChanged: (_) {},
          title: const Text('社群通知'), activeColor: AppColors.primary),
        SwitchListTile(value: false, onChanged: (_) {},
          title: const Text('行銷推播'), activeColor: AppColors.primary),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('儲存'))],
    ));
  }

  void _showLangSettings(BuildContext ctx) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('語言設定', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('繁體中文'), trailing: const Icon(Icons.check_circle_rounded, color: AppColors.primary), onTap: () => Navigator.pop(ctx)),
        ListTile(title: const Text('English'), trailing: const Icon(Icons.radio_button_unchecked, color: AppColors.textHint), onTap: () => Navigator.pop(ctx)),
        ListTile(title: const Text('日本語'), trailing: const Icon(Icons.radio_button_unchecked, color: AppColors.textHint), onTap: () => Navigator.pop(ctx)),
      ]),
    ));
  }

  void _showFAQ(BuildContext ctx) {
    showModalBottomSheet(context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(initialChildSize: 0.6, builder: (c, scroll) =>
        Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [
            const Text('常見問題', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            _faqItem('如何加入行程？', '在景點詳情頁面點選「加入行程」即可，或在候選清單中拖移排序後轉為行程。'),
            _faqItem('分帳功能怎麼用？', '點選底部導覽「分帳」，新增成員後即可記錄消費，系統自動計算最少轉帳方式。'),
            _faqItem('集章要怎麼集？', '實際到訪景點後點選「打卡」，完成 GPS 驗證即可獲得印章。'),
            _faqItem('行程可以分享嗎？', '在「我的行程」點選「分享」，可產生 QR Code 或直接分享到社群。'),
          ]),
        )
      )
    );
  }

  Widget _faqItem(String q, String a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(a, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
      ]),
    );
  }

}