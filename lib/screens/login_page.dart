import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../providers/app_settings_provider.dart';

// ══════════════════════════════════════════════════════════
//  LoginPage — 手帳日記風 + 嘉義插畫橫幅
// ══════════════════════════════════════════════════════════
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  bool _showLogin = true;
  bool _isLoading = false;

  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  bool _loginPwVisible    = false;
  bool _registerPwVisible = false;
  bool _confirmPwVisible  = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nicknameCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Auth helpers ─────────────────────────────────────────
  String _authErrorMsg(String code) {
    switch (code) {
      case 'email-already-in-use':   return '此電子郵件已被註冊，請直接登入';
      case 'invalid-email':          return '電子郵件格式不正確';
      case 'weak-password':          return '密碼強度不足，至少需要 6 個字元';
      case 'user-not-found':         return '找不到此帳號，請先註冊';
      case 'wrong-password':         return '密碼錯誤，請重新輸入';
      case 'invalid-credential':     return '帳號或密碼不正確，請重新確認';
      case 'too-many-requests':      return '嘗試次數過多，請稍後再試';
      case 'network-request-failed': return '網路連線異常，請稍後再試';
      case 'user-disabled':          return '此帳號已被停用，請聯繫客服';
      default:                       return '操作失敗（$code），請稍後再試';
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _doLogin() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passwordCtrl.text;
    if (email.isEmpty || pass.isEmpty) { _showError('請填寫電子郵件和密碼'); return; }
    setState(() => _isLoading = true);
    try {
      await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on fb_auth.FirebaseAuthException catch (e) {
      _showError(_authErrorMsg(e.code));
    } catch (_) {
      _showError('登入失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _doGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) { setState(() => _isLoading = false); return; }

      final googleAuth = await googleUser.authentication;
      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);

      final uid  = userCred.user!.uid;
      final user = userCred.user!;
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc    = await docRef.get();

      if (!doc.exists) {
        // 第一次登入：建立完整文件
        await docRef.set({
          'email':                user.email ?? '',
          'nickname':             user.displayName ?? '使用者',
          'photoURL':             user.photoURL ?? '',
          'bio':                  '',
          'createdAt':            FieldValue.serverTimestamp(),
          'following':            [],
          'followers':            [],
          'savedSpots':           [],
          'savedRestaurants':     [],
          'savedTrips':           [],
          'checkedInSpots':       [],
          'checkedInRestaurants': [],
          'themeIndex':           7,
          'language':             'zh',
          'postCount':            0,
          'likeCount':            0,
          'followersCount':       0,
          'followingCount':       0,
        });
      } else {
        // 舊帳號：補寫 email / photoURL / nickname（確保搜尋得到）
        await docRef.set({
          'email':    user.email ?? '',
          'photoURL': user.photoURL ?? '',
          'nickname': doc.data()?['nickname'] ?? user.displayName ?? '使用者',
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on fb_auth.FirebaseAuthException catch (e) {
      _showError(_authErrorMsg(e.code));
    } catch (_) {
      _showError('Google 登入失敗，請確認網路並重試');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _doRegister() async {
    final nickname = _nicknameCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final pass     = _passwordCtrl.text;
    final confirm  = _confirmCtrl.text;

    if (nickname.isEmpty || email.isEmpty || pass.isEmpty || confirm.isEmpty) {
      _showError('請填寫所有欄位'); return;
    }
    if (pass.length < 6) { _showError('密碼至少需要 6 個字元'); return; }
    if (pass != confirm)  { _showError('兩次輸入的密碼不一致'); return; }

    setState(() => _isLoading = true);
    try {
      final cred = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      await cred.user?.updateDisplayName(nickname);
      await FirebaseFirestore.instance
          .collection('users').doc(cred.user!.uid).set({
        'email':                email,
        'nickname':             nickname,
        'photoURL':             '',
        'bio':                  '',
        'createdAt':            FieldValue.serverTimestamp(),
        'following':            [],
        'followers':            [],
        'savedSpots':           [],
        'savedRestaurants':     [],
        'savedTrips':           [],
        'checkedInSpots':       [],
        'checkedInRestaurants': [],
        'themeIndex':           2,
        'language':             'zh',
        'postCount':            0,
        'likeCount':            0,
        'followersCount':       0,
        'followingCount':       0,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('歡迎加入探索諸羅，$nickname！'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      });
    } on fb_auth.FirebaseAuthException catch (e) {
      _showError(_authErrorMsg(e.code));
    } catch (_) {
      _showError('註冊失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPassword() {
    showDialog(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('重設密碼', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('請輸入你的電子郵件，\n我們將寄送密碼重設連結。',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '電子郵件',
                prefixIcon: Icon(Icons.email_outlined, size: 18),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final email = ctrl.text.trim();
                if (email.isEmpty) return;
                try {
                  await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('密碼重設郵件已寄出，請檢查收件匣'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
                } on fb_auth.FirebaseAuthException catch (e) {
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _showError(_authErrorMsg(e.code));
                }
              },
              child: const Text('發送'),
            ),
          ],
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final primary  = settings.currentTheme.primary;
    final mist     = Color.lerp(primary, Colors.white, 0.88)!;
    final screenH  = MediaQuery.of(context).size.height;

    final accentPurple = primary;
    final softPurple   = Color.lerp(primary, Colors.white, 0.42)!;
    final titleDark    = Color.lerp(primary, Colors.black, 0.55)!;

    // 插畫區高度：縮小讓表單盡量靠上
    final illustrationH = (screenH * 0.20).clamp(100.0, 160.0);
    // 插畫頂部偏移：往下移讓標題文字有乾淨背景
    final illustrationTop = screenH * 0.09;
    // 佔位 spacer 縮小 → 表單卡更靠上，不用滑動就能看到登入按鈕
    final headerTextH = 100.0;
    final spacerH = (illustrationTop + illustrationH - headerTextH - MediaQuery.of(context).padding.top).clamp(4.0, 60.0);

    return Scaffold(
      backgroundColor: Color.lerp(primary, Colors.white, 0.96)!,
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [

          // ── 1. 頂部插畫區背景漸層 ─────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: illustrationTop + illustrationH + 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(primary, Colors.white, 0.85)!, Color.lerp(primary, Colors.white, 0.96)!],
                ),
              ),
            ),
          ),

          // ── 2. 嘉義景觀插畫 ───────────────────────────
          Positioned(
            top: illustrationTop,
            left: 0, right: 0,
            child: SizedBox(
              height: illustrationH,
              child: CustomPaint(
                painter: _ChiayiIllustrationPainter(
                  primaryColor: accentPurple,
                  softColor: softPurple,
                ),
              ),
            ),
          ),

          // ── 3. 星光裝飾 ───────────────────────────────
          Positioned(top: 42, right: 55, child: IgnorePointer(child: CustomPaint(painter: _StarPaint(accentPurple.withValues(alpha: 0.55)), size: const Size(7, 7)))),
          Positioned(top: 72, right: 28, child: IgnorePointer(child: CustomPaint(painter: _StarPaint(softPurple.withValues(alpha: 0.45)), size: const Size(5, 5)))),
          Positioned(top: 55, left: 50,  child: IgnorePointer(child: CustomPaint(painter: _StarPaint(accentPurple.withValues(alpha: 0.40)), size: const Size(6, 6)))),
          Positioned(top: 90, left: 80,  child: IgnorePointer(child: CustomPaint(painter: _StarPaint(softPurple.withValues(alpha: 0.35)), size: const Size(4, 4)))),

          // ── 4. 主體內容 ───────────────────────────────
          SafeArea(
            child: Column(children: [

              // 返回按鈕
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.80),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: accentPurple.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded, color: primary, size: 17)),
                  ),
                ]),
              ),

              // 品牌標題
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    HandDrawnUnderline(
                      color: accentPurple.withValues(alpha: 0.35),
                      child: Text('探索諸羅',
                        style: TextStyle(color: titleDark, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.5, height: 1.1)),
                    ),
                    const SizedBox(width: 8),
                    Text(' JoyGo',
                      style: TextStyle(color: primary, fontSize: 20, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    DoodleHeart(color: accentPurple.withValues(alpha: 0.60), size: 9),
                    const SizedBox(width: 5),
                    Text('嘉義旅遊夥伴，陪你玩遍嘉義！',
                      style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 5),
                    DoodleHeart(color: accentPurple.withValues(alpha: 0.60), size: 9),
                  ]),
                ]),
              ),

              // 插畫佔位（動態高度）
              SizedBox(height: spacerH),

              // ── 5. 白色表單卡 ──────────────────────────
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.13), blurRadius: 24, offset: const Offset(0, -6))],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    child: Stack(children: [
                      // 筆記本橫線底紋
                      Positioned.fill(
                        child: NotebookBackground(
                          lineColor: accentPurple.withValues(alpha: 0.06),
                          marginColor: accentPurple.withValues(alpha: 0.08),
                          lineSpacing: 32,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      // 表單內容
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                        child: Column(children: [
                          const SizedBox(height: 16),
                          _WashiTapeRow(primaryColor: accentPurple),
                          const SizedBox(height: 20),
                          _JournalTabBar(
                            showLogin: _showLogin,
                            primary: accentPurple,
                            mist: mist,
                            onTabChange: (isLogin) {
                              setState(() => _showLogin = isLogin);
                              _animCtrl.forward(from: 0);
                            },
                          ),
                          const SizedBox(height: 24),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
                                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                                child: child,
                              )),
                            child: _showLogin
                                ? _loginForm(accentPurple, key: const ValueKey('login'))
                                : _registerForm(accentPurple, key: const ValueKey('reg')),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: JournalDivider(color: accentPurple.withValues(alpha: 0.30), label: '或'),
                          ),
                          _socialBtn('Google',   accentPurple, Icons.g_mobiledata_rounded, accentPurple, onTap: _doGoogleSignIn),
                          const SizedBox(height: 10),
                          _socialBtn('Facebook', const Color(0xFF1877F2), Icons.facebook_rounded,     accentPurple),
                          const SizedBox(height: 20),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.shield_outlined, size: 12, color: accentPurple.withValues(alpha: 0.55)),
                            const SizedBox(width: 5),
                            RichText(text: TextSpan(
                              style: TextStyle(fontSize: 11, color: accentPurple.withValues(alpha: 0.55)),
                              children: [
                                const TextSpan(text: '登入即代表同意 JoyGo '),
                                TextSpan(text: '服務條款與隱私政策',
                                  style: TextStyle(color: accentPurple, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: accentPurple)),
                              ],
                            )),
                          ]),
                          const SizedBox(height: 12),
                          _BottomWaveDecoration(color: accentPurple),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── 登入表單 ──────────────────────────────────────────────
  Widget _loginForm(Color primary, {Key? key}) {
    return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FormTitle(title: '歡迎回來！', subtitle: '登入帳號繼續探索嘉義', primary: primary),
      const SizedBox(height: 20),
      _field(_emailCtrl, '電子郵件', Icons.mail_outline_rounded, primary, type: TextInputType.emailAddress, action: TextInputAction.next),
      const SizedBox(height: 12),
      _pwField(_passwordCtrl, '密碼', _loginPwVisible, () => setState(() => _loginPwVisible = !_loginPwVisible), primary, onSubmit: _doLogin),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: _showForgotPassword,
          child: Text('忘記密碼？', style: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 22),
      _submitBtn('登入 ✦', _isLoading, primary, _doLogin),
    ]);
  }

  // ── 註冊表單 ──────────────────────────────────────────────
  Widget _registerForm(Color primary, {Key? key}) {
    return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FormTitle(title: '建立帳號', subtitle: '加入探索諸羅，嘉義等你', primary: primary),
      const SizedBox(height: 20),
      _field(_nicknameCtrl, '暱稱', Icons.person_outline_rounded, primary, action: TextInputAction.next),
      const SizedBox(height: 12),
      _field(_emailCtrl, '電子郵件', Icons.mail_outline_rounded, primary, type: TextInputType.emailAddress, action: TextInputAction.next),
      const SizedBox(height: 12),
      _pwField(_passwordCtrl, '密碼（至少 6 位）', _registerPwVisible, () => setState(() => _registerPwVisible = !_registerPwVisible), primary, action: TextInputAction.next),
      const SizedBox(height: 12),
      _pwField(_confirmCtrl, '確認密碼', _confirmPwVisible, () => setState(() => _confirmPwVisible = !_confirmPwVisible), primary, onSubmit: _doRegister),
      const SizedBox(height: 22),
      _submitBtn('建立帳號 ✦', _isLoading, primary, _doRegister),
    ]);
  }

  // ── 欄位 ──────────────────────────────────────────────────
  Widget _field(TextEditingController ctrl, String label, IconData icon, Color primary, {TextInputType? type, TextInputAction? action}) =>
      TextField(
        controller: ctrl, keyboardType: type, textInputAction: action,
        style: const TextStyle(fontSize: 14, color: Color(0xFF3D2A5A)),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelStyle: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 13),
          prefixIcon: Icon(icon, size: 18, color: primary.withValues(alpha: 0.60)),
          filled: true, fillColor: Color.lerp(primary, Colors.white, 0.94)!,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary.withValues(alpha: 0.15), width: 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  Widget _pwField(TextEditingController ctrl, String label, bool visible, VoidCallback toggle, Color primary, {TextInputAction? action, VoidCallback? onSubmit}) =>
      TextField(
        controller: ctrl, obscureText: !visible,
        textInputAction: action ?? TextInputAction.done,
        onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
        style: const TextStyle(fontSize: 14, color: Color(0xFF3D2A5A)),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelStyle: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 13),
          prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: primary.withValues(alpha: 0.60)),
          suffixIcon: IconButton(
            icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: primary.withValues(alpha: 0.55)),
            onPressed: toggle,
          ),
          filled: true, fillColor: Color.lerp(primary, Colors.white, 0.94)!,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary.withValues(alpha: 0.15), width: 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  Widget _submitBtn(String label, bool loading, Color primary, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: loading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary, foregroundColor: Colors.white,
            disabledBackgroundColor: primary.withValues(alpha: 0.55),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      );

  // ── Social button ─────────────────────────────────────────
  Widget _socialBtn(String platform, Color accent, IconData icon, Color primary, {VoidCallback? onTap}) {
    final isReal = onTap != null;
    return OutlinedButton(
      onPressed: _isLoading ? null : (isReal ? onTap : () {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$platform 登入 — 即將推出'),
          backgroundColor: primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        // 統一用淺紫灰邊框，不用品牌色做背景
        side: BorderSide(color: Color.lerp(primary, Colors.white, 0.60)!, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: Colors.white,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: accent, size: 20),  // icon 才帶品牌色
        const SizedBox(width: 10),
        Text('使用 $platform 帳號登入',
          style: TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 14)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  _JournalTabBar — 手帳風標籤列
// ══════════════════════════════════════════════════════════
class _JournalTabBar extends StatelessWidget {
  final bool showLogin;
  final Color primary, mist;
  final void Function(bool) onTabChange;
  const _JournalTabBar({required this.showLogin, required this.primary, required this.mist, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return StitchedBox(
      color: Color.lerp(primary, Colors.white, 0.94)!,
      stitchColor: primary.withValues(alpha: 0.22),
      radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
      padding: const EdgeInsets.all(4),
      child: Row(children: [_tab('登入', showLogin), _tab('註冊', !showLogin)]),
    );
  }

  Widget _tab(String label, bool selected) => Expanded(
    child: GestureDetector(
      onTap: () => onTabChange(label == '登入'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? [BoxShadow(color: primary.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: selected ? primary : Color.lerp(primary, Colors.white, 0.55)!)),
          if (selected) ...[
            const SizedBox(height: 3),
            Container(width: 20, height: 2, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(1))),
          ],
        ]),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════
//  _FormTitle — 表單標題
// ══════════════════════════════════════════════════════════
class _FormTitle extends StatelessWidget {
  final String title, subtitle;
  final Color primary;
  const _FormTitle({required this.title, required this.subtitle, required this.primary});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: primary, letterSpacing: 0.5)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: Color(0xFFAA99BB), fontSize: 13)),
      ])),
      Column(children: [
        CustomPaint(painter: _StarPaint(primary.withValues(alpha: 0.60)), size: const Size(10, 10)),
        const SizedBox(height: 4),
        CustomPaint(painter: _StarPaint(primary.withValues(alpha: 0.35)), size: const Size(6, 6)),
      ]),
    ],
  );
}

// ══════════════════════════════════════════════════════════
//  _WashiTapeRow — 和紙膠帶裝飾條
// ══════════════════════════════════════════════════════════
class _WashiTapeRow extends StatelessWidget {
  final Color primaryColor;
  const _WashiTapeRow({required this.primaryColor});

  @override
  Widget build(BuildContext context) => Row(children: [
    _tape(primaryColor.withValues(alpha: 0.40)),
    Container(width: 2, height: 6, color: Colors.white.withValues(alpha: 0.7)),
    _tape(const Color(0xFFCB9E5A).withValues(alpha: 0.45)),
    Container(width: 2, height: 6, color: Colors.white.withValues(alpha: 0.7)),
    _tape(const Color(0xFF8AAEC4).withValues(alpha: 0.45)),
    Container(width: 2, height: 6, color: Colors.white.withValues(alpha: 0.7)),
    _tape(const Color(0xFFD08878).withValues(alpha: 0.40)),
  ]);

  Widget _tape(Color c) => Expanded(child: Container(height: 6, color: c));
}


// ══════════════════════════════════════════════════════════
//  _BottomWaveDecoration
// ══════════════════════════════════════════════════════════
class _BottomWaveDecoration extends StatelessWidget {
  final Color color;
  const _BottomWaveDecoration({required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36, width: double.infinity,
    child: CustomPaint(painter: _WaveRowPainter(color: color)),
  );
}

class _WaveRowPainter extends CustomPainter {
  final Color color;
  const _WaveRowPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    _wave(canvas, size, amplitude: 6, phase: 0,            yBase: size.height * 0.50, alpha: 0.22, width: 2.0);
    _wave(canvas, size, amplitude: 5, phase: math.pi * 0.6, yBase: size.height * 0.70, alpha: 0.15, width: 1.5);
    _wave(canvas, size, amplitude: 4, phase: math.pi * 1.2, yBase: size.height * 0.85, alpha: 0.10, width: 1.2);
  }
  void _wave(Canvas c, Size s, {required double amplitude, required double phase, required double yBase, required double alpha, required double width}) {
    final p = Paint()..color = color.withValues(alpha: alpha)..strokeWidth = width..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i <= 60; i++) {
      final x = s.width * i / 60;
      final y = yBase + amplitude * math.sin(phase + i * math.pi * 2 / 12);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    c.drawPath(path, p);
  }
  @override bool shouldRepaint(_WaveRowPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════
//  _ChiayiIllustrationPainter — 嘉義景觀插畫
// ══════════════════════════════════════════════════════════
class _ChiayiIllustrationPainter extends CustomPainter {
  final Color primaryColor, softColor;
  const _ChiayiIllustrationPainter({required this.primaryColor, required this.softColor});

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;

    // 地面線 (ground line) — 所有建築從這裡往上長
    final gnd = h * 0.73;

    // 雲：靠右側且更高，讓左側標題保持淨空
    _cloud(canvas, Offset(w * 0.86, h * 0.07), w * 0.042, softColor.withValues(alpha: 0.40));
    _cloud(canvas, Offset(w * 0.67, h * 0.12), w * 0.045, softColor.withValues(alpha: 0.44));
    _cloud(canvas, Offset(w * 0.57, h * 0.21), w * 0.035, softColor.withValues(alpha: 0.30));

    // 草地
    final g1 = Paint()..color = const Color(0xFFD5EAD0).withValues(alpha: 0.72);
    final gp1 = Path()
      ..moveTo(0, gnd)
      ..cubicTo(w * .25, gnd - h * .04, w * .55, gnd + h * .03, w * .80, gnd - h * .02)
      ..cubicTo(w * .90, gnd - h * .04, w * .96, gnd + h * .01, w, gnd)
      ..lineTo(w, h)..lineTo(0, h)..close();
    canvas.drawPath(gp1, g1);
    final g2 = Paint()..color = const Color(0xFFC2DEB8).withValues(alpha: 0.52);
    final gp2 = Path()
      ..moveTo(0, gnd + h * .06)
      ..cubicTo(w * .20, gnd + h * .02, w * .60, gnd + h * .08, w * .80, gnd + h * .04)
      ..lineTo(w, gnd + h * .04)..lineTo(w, h)..lineTo(0, h)..close();
    canvas.drawPath(gp2, g2);

    // ── 元素：小火車靠左、日式建築＋樹靠右 ──
    // 小火車（稍離左緣，尺寸小不擋字）
    final tW = w * 0.13;
    _train(canvas, w * 0.15, gnd - tW * 0.52, tW, primaryColor, softColor);

    // 日式建築 (x: 61-83%)
    final bW = w * 0.22;
    final bH = h * 0.72;
    _japaneseBuilding(canvas, w * 0.61, gnd - bH * 0.49, bW, bH, primaryColor, softColor);

    // 小樹 (x center: 89%)
    final treeH = h * 0.26;
    _tree(canvas, w * 0.89, gnd - treeH, treeH, primaryColor, softColor);
  }

  void _cloud(Canvas c, Offset center, double r, Color color) {
    final p = Paint()..color = color..style = PaintingStyle.fill;
    c.drawCircle(center, r * 0.6, p);
    c.drawCircle(center + Offset(-r*.55, r*.15), r*.45, p);
    c.drawCircle(center + Offset( r*.55, r*.15), r*.40, p);
    c.drawRect(Rect.fromCenter(center: center + Offset(0, r*.35), width: r*1.5, height: r*.5), p);
  }

  void _castle(Canvas c, double x, double y, double w, double h, Color primary, Color soft) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = const Color(0xFFC8A8D8).withValues(alpha: 0.85);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+w*.10,y+h*.02,w*.80,h*.48), const Radius.circular(4)), p);
    p.color = const Color(0xFF9478B8).withValues(alpha: 0.88);
    c.drawPath(Path()..moveTo(x+w*.50,y)..lineTo(x+w*.05,y+h*.13)..lineTo(x+w*.95,y+h*.13)..close(), p);
    p.color = const Color(0xFFC8A8D8).withValues(alpha: 0.70);
    c.drawRect(Rect.fromLTWH(x,y+h*.40,w,h*.12), p);
    p.color = Colors.white.withValues(alpha: 0.60);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+w*.30,y+h*.12,w*.40,h*.14), const Radius.circular(3)), p);
    p.color = const Color(0xFF9478B8).withValues(alpha: 0.65);
    c.drawPath(Path()..addArc(Rect.fromCenter(center: Offset(x+w*.50,y+h*.42), width: w*.30, height: w*.30), math.pi, math.pi)..lineTo(x+w*.65,y+h*.52)..lineTo(x+w*.35,y+h*.52)..close(), p);
  }

  void _train(Canvas c, double x, double y, double w, Color primary, Color soft) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = const Color(0xFFB87040).withValues(alpha: 0.88);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,y,w,w*.42), const Radius.circular(5)), p);
    p.color = const Color(0xFF8A5028).withValues(alpha: 0.90);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+w*.05,y-w*.10,w*.90,w*.14), const Radius.circular(3)), p);
    p.color = const Color(0xFFD0EAFA).withValues(alpha: 0.85);
    final winW = w * 0.18;
    for (int i = 0; i < 3; i++) c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+w*.10+i*(winW+w*.07),y+w*.07,winW,w*.22), const Radius.circular(2)), p);
    p.color = const Color(0xFF555555).withValues(alpha: 0.75);
    c.drawCircle(Offset(x+w*.22,y+w*.42), w*.10, p);
    c.drawCircle(Offset(x+w*.75,y+w*.42), w*.10, p);
    final tp = Paint()..color=const Color(0xFF888880).withValues(alpha:0.55)..strokeWidth=2..style=PaintingStyle.stroke;
    c.drawLine(Offset(x-w*.15,y+w*.52),Offset(x+w*1.15,y+w*.52),tp);
    c.drawLine(Offset(x-w*.15,y+w*.56),Offset(x+w*1.15,y+w*.56),tp);
  }

  void _japaneseBuilding(Canvas c, double x, double y, double w, double h, Color primary, Color soft) {
    final p = Paint()..style = PaintingStyle.fill;
    final roofC = const Color(0xFF6A7890).withValues(alpha: 0.88);
    final bodyC = const Color(0xFFEDE4D8).withValues(alpha: 0.90);
    p.color = roofC; _curvedRoof(c, x-w*.05, y, w*1.10, h*.12, p);
    p.color = bodyC; c.drawRect(Rect.fromLTWH(x+w*.05,y+h*.11,w*.90,h*.14), p);
    p.color = roofC; _curvedRoof(c, x-w*.12, y+h*.20, w*1.24, h*.13, p);
    p.color = bodyC; c.drawRect(Rect.fromLTWH(x,y+h*.31,w,h*.18), p);
    p.color = const Color(0xFF5A6880).withValues(alpha: 0.75);
    final colW = w * 0.07;
    for (int i = 0; i < 4; i++) c.drawRect(Rect.fromLTWH(x+w*.06+i*(w*.27),y+h*.31,colW,h*.18), p);
    p.color = const Color(0xFF3A3228).withValues(alpha: 0.70);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+w*.35,y+h*.39,w*.30,h*.10), const Radius.circular(3)), p);
  }

  void _curvedRoof(Canvas c, double x, double y, double w, double h, Paint p) {
    c.drawPath(Path()..moveTo(x+w*.50,y)..cubicTo(x+w*.30,y+h*.30,x+w*.05,y+h*.70,x,y+h)..lineTo(x+w,y+h)..cubicTo(x+w*.95,y+h*.70,x+w*.70,y+h*.30,x+w*.50,y)..close(), p);
  }

  void _tree(Canvas c, double x, double y, double h, Color primary, Color soft) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = const Color(0xFF8B6040).withValues(alpha: 0.75);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x-5,y+h*.55,10,h*.45), const Radius.circular(3)), p);
    p.color = const Color(0xFF7EB870).withValues(alpha: 0.75); c.drawCircle(Offset(x,y+h*.40),h*.32,p);
    p.color = const Color(0xFF5FA060).withValues(alpha: 0.80); c.drawCircle(Offset(x-h*.10,y+h*.52),h*.24,p); c.drawCircle(Offset(x+h*.08,y+h*.50),h*.22,p);
    p.color = const Color(0xFF4A8A50).withValues(alpha: 0.70); c.drawCircle(Offset(x,y+h*.60),h*.18,p);
  }

  void _foodBowl(Canvas c, double x, double y, double r, Color primary, Color soft) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = const Color(0xFFEEDDCC).withValues(alpha: 0.90);
    c.drawPath(Path()..moveTo(x-r,y)..cubicTo(x-r*1.1,y+r*.5,x-r*.8,y+r,x,y+r)..cubicTo(x+r*.8,y+r,x+r*1.1,y+r*.5,x+r,y)..close(), p);
    p.color = const Color(0xFFCCBBA8).withValues(alpha: 0.80);
    c.drawOval(Rect.fromCenter(center: Offset(x,y), width: r*2, height: r*.5), p);
    p.color = const Color(0xFFF5F0E8).withValues(alpha: 0.90);
    c.drawOval(Rect.fromCenter(center: Offset(x,y-r*.05), width: r*1.7, height: r*.38), p);
    p.color = const Color(0xFFB8845A).withValues(alpha: 0.78);
    c.drawOval(Rect.fromCenter(center: Offset(x-r*.18,y-r*.14), width: r*.6, height: r*.20), p);
    p.color = const Color(0xFFA06840).withValues(alpha: 0.70);
    c.drawOval(Rect.fromCenter(center: Offset(x+r*.12,y-r*.18), width: r*.50, height: r*.16), p);
  }

  void _tower(Canvas c, double x, double y, double w, double h, Color primary, Color soft) {
    final p = Paint()..style = PaintingStyle.fill;
    final colBg = const Color(0xFF9A88B8).withValues(alpha: 0.78);
    final roofC = const Color(0xFF6A5890).withValues(alpha: 0.85);
    p.color = colBg;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+w*.25,y+h*.56,w*.50,h*.06), const Radius.circular(2)), p);
    c.drawRect(Rect.fromLTWH(x+w*.44,y+h*.22,w*.12,h*.35), p);
    for (int i = 0; i < 3; i++) {
      final tw = w * (0.90 - i * 0.20);
      p.color = roofC.withValues(alpha: 0.78 - i * 0.08);
      _curvedRoof(c, x+(w-tw)/2, y+h*(0.22+i*0.12), tw, h*.08, p);
    }
    p.color = roofC;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+w*.44,y+h*.15,w*.12,h*.08), const Radius.circular(2)), p);
    c.drawCircle(Offset(x+w*.50,y+h*.13), w*.07, p);
  }

  @override
  bool shouldRepaint(covariant _ChiayiIllustrationPainter old) => old.primaryColor != primaryColor;
}

// ══════════════════════════════════════════════════════════
//  _StarPaint — 十字星光
// ══════════════════════════════════════════════════════════
class _StarPaint extends CustomPainter {
  final Color color;
  const _StarPaint(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color..strokeWidth = 1.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final cx = s.width / 2, cy = s.height / 2;
    canvas.drawLine(Offset(cx - s.width, cy), Offset(cx + s.width, cy), p);
    canvas.drawLine(Offset(cx, cy - s.height), Offset(cx, cy + s.height), p);
    canvas.drawLine(Offset(cx - s.width*.65, cy - s.height*.65), Offset(cx + s.width*.65, cy + s.height*.65), p);
    canvas.drawLine(Offset(cx + s.width*.65, cy - s.height*.65), Offset(cx - s.width*.65, cy + s.height*.65), p);
  }
  @override bool shouldRepaint(_StarPaint o) => o.color != color;
}
