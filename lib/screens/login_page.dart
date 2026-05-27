import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';

// ══════════════════════════════════════════════════════════
//  LoginPage — 獨立的登入 / 註冊頁面
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
      vsync: this, duration: const Duration(milliseconds: 280));
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
      case 'email-already-in-use':  return '此電子郵件已被註冊，請直接登入';
      case 'invalid-email':         return '電子郵件格式不正確';
      case 'weak-password':         return '密碼強度不足，至少需要 6 個字元';
      case 'user-not-found':        return '找不到此帳號，請先註冊';
      case 'wrong-password':        return '密碼錯誤，請重新輸入';
      case 'invalid-credential':    return '帳號或密碼不正確，請重新確認';
      case 'too-many-requests':     return '嘗試次數過多，請稍後再試';
      case 'network-request-failed':return '網路連線異常，請稍後再試';
      case 'user-disabled':         return '此帳號已被停用，請聯繫客服';
      default:                      return '操作失敗（$code），請稍後再試';
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
      // Pop back to drawer — drawer's auth listener will show profile
      Navigator.of(context).pop(true); // true = logged in
    } on fb_auth.FirebaseAuthException catch (e) {
      _showError(_authErrorMsg(e.code));
    } catch (_) {
      _showError('登入失敗，請稍後再試');
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
    if (pass != confirm) { _showError('兩次輸入的密碼不一致'); return; }

    setState(() => _isLoading = true);
    try {
      final cred = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      await cred.user?.updateDisplayName(nickname);
      await FirebaseFirestore.instance
          .collection('users').doc(cred.user!.uid).set({
        'email':                email,
        'nickname':             nickname,
        'photoUrl':             null,
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
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      // Show welcome snackbar on the screen below
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('歡迎加入探索諸羅，$nickname！🎉'),
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
          title: const Text('重設密碼',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('請輸入你的電子郵件，\n我們將寄送密碼重設連結。',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final email = ctrl.text.trim();
                if (email.isEmpty) return;
                try {
                  await fb_auth.FirebaseAuth.instance
                      .sendPasswordResetEmail(email: email);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('密碼重設郵件已寄出，請檢查收件匣'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
    final settings  = context.watch<AppSettingsProvider>();
    final primary   = settings.currentTheme.primary;
    final primDark  = settings.currentTheme.primaryDark;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Hero header ────────────────────────────────
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                    24, MediaQuery.of(context).padding.top + 20, 24, 36),
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
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('🏯', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text(
                      '探索諸羅',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '登入以解鎖完整功能，開始你的嘉義旅程',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tab selector ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMoss,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _tab('登入',  _showLogin),
                      _tab('註冊', !_showLogin),
                    ],
                  ),
                ),
              ),

              // ── Form ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _showLogin ? _loginForm() : _registerForm(),
              ),

              // ── Divider ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('或',
                        style: TextStyle(
                            color: AppColors.textHint, fontSize: 12)),
                  ),
                  const Expanded(child: Divider()),
                ]),
              ),

              // ── Social buttons ──────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  _socialBtn('Google 帳號登入',   '🌐', const Color(0xFFEA4335)),
                  const SizedBox(height: 10),
                  _socialBtn('Facebook 帳號登入', '📘', const Color(0xFF1877F2)),
                ]),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab chip ──────────────────────────────────────────────
  Widget _tab(String label, bool selected) => Expanded(
    child: GestureDetector(
      onTap: () {
        setState(() => _showLogin = label == '登入');
        _animCtrl.forward(from: 0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 4)]
              : [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : AppColors.textHint,
          ),
        ),
      ),
    ),
  );

  // ── Login form ────────────────────────────────────────────
  Widget _loginForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('歡迎回來 👋',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
              color: AppColors.textPrimary)),
      const SizedBox(height: 4),
      const Text('登入你的帳號繼續探索嘉義',
          style: TextStyle(color: AppColors.textHint, fontSize: 13)),
      const SizedBox(height: 22),
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '電子郵件',
          prefixIcon: Icon(Icons.email_outlined, size: 18),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _passwordCtrl,
        obscureText: !_loginPwVisible,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _doLogin(),
        decoration: InputDecoration(
          labelText: '密碼',
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
          suffixIcon: IconButton(
            icon: Icon(
              _loginPwVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18),
            onPressed: () => setState(() => _loginPwVisible = !_loginPwVisible),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: _showForgotPassword,
          child: Text('忘記密碼？',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity, height: 50,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _doLogin,
          child: _isLoading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('登入',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ]);
  }

  // ── Register form ─────────────────────────────────────────
  Widget _registerForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('建立帳號 🎉',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
              color: AppColors.textPrimary)),
      const SizedBox(height: 4),
      const Text('加入探索諸羅，開始你的嘉義旅程',
          style: TextStyle(color: AppColors.textHint, fontSize: 13)),
      const SizedBox(height: 22),
      TextField(
        controller: _nicknameCtrl,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '暱稱',
          prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '電子郵件',
          prefixIcon: Icon(Icons.email_outlined, size: 18),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _passwordCtrl,
        obscureText: !_registerPwVisible,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: '密碼（至少 6 個字元）',
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
          suffixIcon: IconButton(
            icon: Icon(
              _registerPwVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18),
            onPressed: () => setState(() => _registerPwVisible = !_registerPwVisible),
          ),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _confirmCtrl,
        obscureText: !_confirmPwVisible,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _doRegister(),
        decoration: InputDecoration(
          labelText: '確認密碼',
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
          suffixIcon: IconButton(
            icon: Icon(
              _confirmPwVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18),
            onPressed: () => setState(() => _confirmPwVisible = !_confirmPwVisible),
          ),
        ),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity, height: 50,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _doRegister,
          child: _isLoading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('建立帳號',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ]);
  }

  // ── Social button ─────────────────────────────────────────
  Widget _socialBtn(String label, String icon, Color color) =>
    OutlinedButton(
      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label — 即將推出'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      )),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600, fontSize: 14)),
      ]),
    );
}
