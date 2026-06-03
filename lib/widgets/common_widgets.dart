import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

// ===== SPOT CARD =====
class SpotCard extends StatefulWidget {
  final String name;
  final String category;
  final double rating;
  final String imageUrl;
  final String address;
  final bool isLiked;
  final VoidCallback? onTap;
  final VoidCallback? onLike;

  const SpotCard({
    super.key,
    required this.name,
    required this.category,
    required this.rating,
    required this.imageUrl,
    required this.address,
    this.isLiked = false,
    this.onTap,
    this.onLike,
  });

  @override
  State<SpotCard> createState() => _SpotCardState();
}

class _SpotCardState extends State<SpotCard>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _liked = widget.isLiked;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.3)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleLike() {
    setState(() => _liked = !_liked);
    _controller.forward(from: 0);
    widget.onLike?.call();
  }

  IconData get _categoryIconData {
    switch (widget.category) {
      case 'restaurant':  return Icons.ramen_dining_rounded;
      case 'attraction':  return Icons.account_balance_rounded;
      case 'hotel':       return Icons.hotel_rounded;
      case 'youbike':     return Icons.pedal_bike_rounded;
      case 'aed':         return Icons.favorite_rounded;
      default:            return Icons.place_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  Image.network(
                    widget.imageUrl,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: AppColors.surfaceMoss,
                      child: Center(
                        child: Icon(
                          _categoryIconData,
                          size: 40,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        _categoryIconData,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _handleLike,
                      child: AnimatedBuilder(
                        animation: _scaleAnim,
                        builder: (context, child) => Transform.scale(
                          scale: _scaleAnim.value,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              _liked ? Icons.favorite : Icons.favorite_border,
                              size: 16,
                              color: _liked
                                  ? AppColors.error
                                  : AppColors.textHint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.accentStraw),
                      const SizedBox(width: 2),
                      Text(
                        widget.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.address,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== SECTION HEADER =====
// ══════════════════════════════════════════════════════════════
//  _BrushPainter — 在文字底部畫一條手感不規則的粗筆刷底色
//  模擬「先用麥克筆/毛筆刷一筆，再寫字上去」的感覺
// ══════════════════════════════════════════════════════════════
class _BrushPainter extends CustomPainter {
  final Color color;
  const _BrushPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 筆刷：硬邊，靠下，像螢光筆刷過文字下半截
    final path = Path();
    final top    = size.height * 0.60;
    final bottom = size.height * 0.95;

    path.moveTo(-2, top + 1);
    path.cubicTo(
      size.width * 0.25, top - 3,
      size.width * 0.60, top + 4,
      size.width + 3,    top,
    );
    path.lineTo(size.width + 3, bottom);
    path.cubicTo(
      size.width * 0.55, bottom + 3,
      size.width * 0.20, bottom - 2,
      -2, bottom + 1,
    );
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BrushPainter old) => old.color != color;
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brushColor = primary.withValues(alpha: 0.18);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          painter: _BrushPainter(color: brushColor),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0.3,
                shadows: [
                  Shadow(
                    color: primary.withValues(alpha: 0.15),
                    blurRadius: 0,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        if (actionText != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionText!,
              style: TextStyle(
                fontSize: 13,
                color: primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ===== CATEGORY CHIP =====
class CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primary : AppColors.surfaceMoss,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== CUSTOM APP BAR =====
class ChiayiAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;

  const ChiayiAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: AppColors.surfaceMoss,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  愛心評分 + 備註區塊（任何地點詳細頁共用）
//  已登入 → 儲存到 Firebase Firestore（users/{uid}/spot_ratings/{placeId}）
//  未登入 → 僅存到 SharedPreferences（本地）
// ═══════════════════════════════════════════════════════════

class SpotRatingSection extends StatefulWidget {
  final String placeId;
  const SpotRatingSection({super.key, required this.placeId});

  @override
  State<SpotRatingSection> createState() => _SpotRatingSectionState();
}

class _SpotRatingSectionState extends State<SpotRatingSection> {
  int  _rating  = 0; // 0 = unrated, 1–5
  final _noteCtrl = TextEditingController();
  bool _saved   = false;
  bool _loading = true;

  String get _rKey => 'spot_rating_${widget.placeId}';
  String get _nKey => 'spot_note_${widget.placeId}';

  /// 目前登入使用者（null = 未登入）
  User? get _user => FirebaseAuth.instance.currentUser;

  /// Firestore 文件路徑（登入後才有）
  DocumentReference<Map<String, dynamic>>? get _firestoreDoc {
    final uid = _user?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('spot_ratings')
        .doc(widget.placeId);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 優先從 Firebase 讀（已登入）
    final doc = _firestoreDoc;
    if (doc != null) {
      try {
        final snap = await doc.get();
        if (!mounted) return;
        if (snap.exists) {
          final d = snap.data()!;
          setState(() {
            _rating        = (d['rating'] as int?) ?? 0;
            _noteCtrl.text = (d['note'] as String?) ?? '';
            _loading       = false;
          });
          return;
        }
      } catch (_) { /* 讀取失敗 fall through 到 local */ }
    }
    // 未登入或 Firebase 讀取失敗 → 讀本地快取
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rating        = prefs.getInt(_rKey) ?? 0;
      _noteCtrl.text = prefs.getString(_nKey) ?? '';
      _loading       = false;
    });
  }

  Future<void> _save() async {
    final note = _noteCtrl.text.trim();

    // ── Firebase 儲存（已登入）──────────────────────────────
    final doc = _firestoreDoc;
    if (doc != null) {
      try {
        if (_rating == 0 && note.isEmpty) {
          await doc.delete();
        } else {
          await doc.set({
            'placeId':   widget.placeId,
            'rating':    _rating,
            'note':      note,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        // 同步更新本地快取方便離線讀取
        final prefs = await SharedPreferences.getInstance();
        if (_rating > 0) { await prefs.setInt(_rKey, _rating); }
        else              { await prefs.remove(_rKey); }
        if (note.isNotEmpty) { await prefs.setString(_nKey, note); }
        else                 { await prefs.remove(_nKey); }
        if (!mounted) return;
        setState(() => _saved = true);
        Future.delayed(const Duration(seconds: 2),
            () { if (mounted) setState(() => _saved = false); });
        return;
      } catch (_) { /* Firebase 失敗 fall through 到 local only */ }
    }

    // ── 未登入：只存 SharedPreferences ─────────────────────
    final prefs = await SharedPreferences.getInstance();
    if (_rating > 0) { await prefs.setInt(_rKey, _rating); }
    else             { await prefs.remove(_rKey); }
    if (note.isNotEmpty) { await prefs.setString(_nKey, note); }
    else                 { await prefs.remove(_nKey); }
    if (!mounted) return;
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2),
        () { if (mounted) setState(() => _saved = false); });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        // ── 評分標題
        Row(children: [
          const Icon(Icons.favorite_rounded, size: 15, color: AppColors.error),
          const SizedBox(width: 6),
          const Text('我的評分',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          if (_rating > 0) ...[
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() { _rating = 0; _saved = false; }),
              child: const Text('清除',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        // ── 5顆愛心
        Row(children: List.generate(5, (i) => GestureDetector(
          onTap: () => setState(() {
            _rating = (_rating == i + 1) ? 0 : i + 1; // tap same → clear
            _saved = false;
          }),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                _rating > i
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey('heart_${i}_${_rating > i}'),
                color: _rating > i ? AppColors.error : AppColors.textHint,
                size: 30,
              ),
            ),
          ),
        ))),
        const SizedBox(height: 14),
        // ── 備註標題
        Row(children: [
          const Icon(Icons.edit_note_rounded, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          const Text('備註',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        // ── 備註輸入框
        TextField(
          controller: _noteCtrl,
          maxLines: 3,
          minLines: 2,
          onChanged: (_) { if (_saved) setState(() => _saved = false); },
          decoration: InputDecoration(
            hintText: '記下你的感想、提醒或重要資訊…',
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.surfaceWarm,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primary, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ── 儲存按鈕
        SizedBox(
          width: double.infinity,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: ElevatedButton.icon(
              key: ValueKey(_saved),
              onPressed: _save,
              icon: Icon(
                  _saved ? Icons.check_circle_rounded : Icons.save_outlined,
                  size: 16),
              label: Text(_saved ? '已儲存' : '儲存評分與備註'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saved ? const Color(0xFF2E7D32) : primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  TapFeedback — iOS-style scale-down press feedback
//  Replace GestureDetector with this widget and pass onTap
//  here; the child scales to pressedScale on touch-down and
//  springs back to 1.0 on release.
// ═══════════════════════════════════════════════════════════

class TapFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  /// Scale applied while finger is down (default 0.95 ≈ iOS)
  final double pressedScale;

  const TapFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.95,
  });

  @override
  State<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<TapFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.pressedScale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) => _ctrl.forward();
  void _up(TapUpDetails _)     => _ctrl.reverse();
  void _cancel()               => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  WashiTapeDivider — 仿紙膠帶分隔線（半透明色帶 + 不規則邊緣）
// ═══════════════════════════════════════════════════════════

class WashiTapeDivider extends StatelessWidget {
  final Color? color;
  final double height;
  const WashiTapeDivider({super.key, this.color, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _WashiPainter(c),
      ),
    );
  }
}

class _WashiPainter extends CustomPainter {
  final Color color;
  const _WashiPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    // Slightly wavy top edge
    path.moveTo(0, 2);
    for (double x = 0; x < size.width; x += 12) {
      path.lineTo(x + 4, 0);
      path.lineTo(x + 8, 2.5);
      path.lineTo(x + 12, 0.5);
    }
    path.lineTo(size.width, size.height - 2);
    // Slightly wavy bottom edge
    for (double x = size.width; x > 0; x -= 14) {
      path.lineTo(x - 5, size.height);
      path.lineTo(x - 9, size.height - 2);
      path.lineTo(x - 14, size.height - 0.5);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WashiPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════
//  PolaroidCard — 仿拍立得風格的圖片卡（白邊 + 微微傾斜）
// ═══════════════════════════════════════════════════════════

class PolaroidCard extends StatelessWidget {
  final String imageUrl;
  final String? caption;
  final double tiltDegrees;
  final double width;

  const PolaroidCard({
    super.key,
    required this.imageUrl,
    this.caption,
    this.tiltDegrees = 0,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tiltDegrees * 3.14159 / 180,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(2, 4)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Image.network(imageUrl,
                width: width - 16, height: width - 16,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: width - 16, height: width - 16,
                  color: const Color(0xFFF0EDE8),
                  child: const Icon(Icons.photo_outlined, color: AppColors.textHint))),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Text(caption!,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            )
          else
            const SizedBox(height: 10),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ③ ShimmerBox — 通用骨架載入閃光元件
// ═══════════════════════════════════════════════════════════

class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final bool dark;
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.dark = false,
  });

  @override State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final base  = widget.dark ? const Color(0xFFE0E0E0) : const Color(0xFFEEEEEE);
    final shine = widget.dark ? const Color(0xFFF5F5F5) : const Color(0xFFFAFAFA);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end:   Alignment(_anim.value,     0),
            stops: const [0.0, 0.5, 1.0],
            colors: [base, shine, base],
          ),
        ),
      ),
    );
  }
}

// Shorthand skeleton layouts
class NewsCardSkeleton extends StatelessWidget {
  const NewsCardSkeleton({super.key});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ShimmerBox(width: 56, height: 18, radius: 6),
        Spacer(),
        ShimmerBox(width: 36, height: 12, radius: 4),
      ]),
      SizedBox(height: 10),
      ShimmerBox(height: 16, radius: 4),
      SizedBox(height: 6),
      ShimmerBox(width: 180, height: 14, radius: 4),
    ]),
  );
}

class TripCardSkeleton extends StatelessWidget {
  const TripCardSkeleton({super.key});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [const BoxShadow(color: Color(0x0A000000), blurRadius: 8)]),
    child: const Column(children: [
      ShimmerBox(height: 140, radius: 0),
      Padding(
        padding: EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ShimmerBox(width: 160, height: 18, radius: 5),
          SizedBox(height: 8),
          ShimmerBox(width: 100, height: 13, radius: 4),
          SizedBox(height: 12),
          Row(children: [
            Expanded(child: ShimmerBox(height: 36, radius: 10)),
            SizedBox(width: 8),
            Expanded(child: ShimmerBox(height: 36, radius: 10)),
          ]),
        ]),
      ),
    ]),
  );
}

class SpotCardSkeleton extends StatelessWidget {
  const SpotCardSkeleton({super.key});
  @override Widget build(BuildContext context) => Container(
    width: 200,
    margin: const EdgeInsets.only(right: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ShimmerBox(height: 120, radius: 0),
      Padding(padding: EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: 120, height: 15, radius: 4),
          SizedBox(height: 6),
          ShimmerBox(width: 80, height: 12, radius: 4),
        ],
      )),
    ]),
  );
}

class TransportCardSkeleton extends StatelessWidget {
  const TransportCardSkeleton({super.key});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ShimmerBox(width: 48, height: 20, radius: 6),
        SizedBox(width: 10),
        Expanded(child: ShimmerBox(height: 16, radius: 4)),
        SizedBox(width: 10),
        Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFE0E0E0)),
      ]),
      SizedBox(height: 10),
      ShimmerBox(height: 10, radius: 3),
      SizedBox(height: 6),
      ShimmerBox(width: 160, height: 10, radius: 3),
    ]),
  );
}

class StampGridSkeleton extends StatelessWidget {
  const StampGridSkeleton({super.key});
  @override Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3, childAspectRatio: 0.75, crossAxisSpacing: 12, mainAxisSpacing: 12),
    itemCount: 12,
    itemBuilder: (_, __) => Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        ShimmerBox(width: 64, height: 64, radius: 32),
        SizedBox(height: 8),
        ShimmerBox(width: 50, height: 11, radius: 4),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  ② IllustratedEmptyState — 插畫空頁面
// ═══════════════════════════════════════════════════════════

enum EmptyScene { trip, expense, notification, saved, community, map }

class IllustratedEmptyState extends StatefulWidget {
  final EmptyScene scene;
  final String title;
  final String body;
  final Widget? action;
  final Color? color;

  const IllustratedEmptyState({
    super.key,
    required this.scene,
    required this.title,
    required this.body,
    this.action,
    this.color,
  });

  @override State<IllustratedEmptyState> createState() => _IllustratedEmptyStateState();
}

class _IllustratedEmptyStateState extends State<IllustratedEmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _floatAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, _floatAnim.value), child: child),
            child: SizedBox(
              width: 180, height: 160,
              child: CustomPaint(
                painter: _EmptyScenePainter(scene: widget.scene, color: color),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.3)),
          const SizedBox(height: 8),
          Text(widget.body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.6)),
          if (widget.action != null) ...[const SizedBox(height: 20), widget.action!],
        ]),
      ),
    );
  }
}

class _EmptyScenePainter extends CustomPainter {
  final EmptyScene scene;
  final Color color;
  const _EmptyScenePainter({required this.scene, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    switch (scene) {
      case EmptyScene.trip:      _paintTrain(canvas, size); break;
      case EmptyScene.expense:   _paintPiggyBank(canvas, size); break;
      case EmptyScene.notification: _paintBell(canvas, size); break;
      case EmptyScene.saved:     _paintHeart(canvas, size); break;
      case EmptyScene.community: _paintBubbles(canvas, size); break;
      case EmptyScene.map:       _paintCompass(canvas, size); break;
    }
  }

  // ── Train (Trip) ────────────────────────────────────────
  void _paintTrain(Canvas canvas, Size s) {
    final c = color;
    final fill = Paint()..color = c.withValues(alpha: 0.12)..style = PaintingStyle.fill;
    final stroke = Paint()..color = c.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    final trackP = Paint()..color = c.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 2;

    // Mountains background
    final mPath = Path()
      ..moveTo(0, s.height * 0.7)
      ..lineTo(s.width * 0.2, s.height * 0.35)
      ..lineTo(s.width * 0.4, s.height * 0.7)
      ..moveTo(s.width * 0.35, s.height * 0.7)
      ..lineTo(s.width * 0.6, s.height * 0.25)
      ..lineTo(s.width * 0.85, s.height * 0.7);
    canvas.drawPath(mPath, Paint()..color = c.withValues(alpha: 0.10)..style = PaintingStyle.fill);
    canvas.drawPath(mPath, stroke..strokeWidth = 1.5);
    stroke.strokeWidth = 2.5;

    // Track
    canvas.drawLine(Offset(0, s.height * 0.78), Offset(s.width, s.height * 0.78), trackP);
    for (double x = 10; x < s.width; x += 18) {
      canvas.drawLine(Offset(x, s.height * 0.75), Offset(x, s.height * 0.81), trackP);
    }

    // Train body
    final trainRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width * 0.1, s.height * 0.52, s.width * 0.55, s.height * 0.24),
      const Radius.circular(8));
    canvas.drawRRect(trainRect, fill);
    canvas.drawRRect(trainRect, stroke);

    // Cab
    final cabRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width * 0.55, s.height * 0.56, s.width * 0.22, s.height * 0.20),
      const Radius.circular(6));
    canvas.drawRRect(cabRect, fill);
    canvas.drawRRect(cabRect, stroke);

    // Windows
    for (int i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s.width * (0.14 + i * 0.15), s.height * 0.57, s.width * 0.10, s.height * 0.10),
          const Radius.circular(3)),
        Paint()..color = c.withValues(alpha: 0.18));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s.width * (0.14 + i * 0.15), s.height * 0.57, s.width * 0.10, s.height * 0.10),
          const Radius.circular(3)),
        stroke..strokeWidth = 1.5);
      stroke.strokeWidth = 2.5;
    }

    // Wheels
    for (double x in [s.width * 0.18, s.width * 0.36, s.width * 0.54, s.width * 0.67]) {
      canvas.drawCircle(Offset(x, s.height * 0.78), 8, fill);
      canvas.drawCircle(Offset(x, s.height * 0.78), 8, stroke..strokeWidth = 2);
      stroke.strokeWidth = 2.5;
    }

    // Smoke puffs
    for (int i = 0; i < 3; i++) {
      final r = 6.0 + i * 4;
      canvas.drawCircle(
        Offset(s.width * 0.22 + i * 8, s.height * 0.42 - i * 8),
        r, Paint()..color = c.withValues(alpha: 0.08 - i * 0.02));
    }
  }

  // ── Piggy Bank (Expense) ────────────────────────────────
  void _paintPiggyBank(Canvas canvas, Size s) {
    final c = color;
    final fill = Paint()..color = c.withValues(alpha: 0.12);
    final stroke = Paint()..color = c.withValues(alpha: 0.55)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    final coinFill = Paint()..color = const Color(0xFFE8C46A).withValues(alpha: 0.5);

    // Body
    canvas.drawOval(Rect.fromCenter(center: Offset(s.width * 0.45, s.height * 0.58), width: s.width * 0.52, height: s.height * 0.42), fill);
    canvas.drawOval(Rect.fromCenter(center: Offset(s.width * 0.45, s.height * 0.58), width: s.width * 0.52, height: s.height * 0.42), stroke);

    // Snout
    canvas.drawOval(Rect.fromCenter(center: Offset(s.width * 0.68, s.height * 0.60), width: s.width * 0.18, height: s.height * 0.12), Paint()..color = c.withValues(alpha: 0.08));
    canvas.drawOval(Rect.fromCenter(center: Offset(s.width * 0.68, s.height * 0.60), width: s.width * 0.18, height: s.height * 0.12), stroke..strokeWidth = 1.8);
    stroke.strokeWidth = 2.5;

    // Nostrils
    canvas.drawCircle(Offset(s.width * 0.64, s.height * 0.61), 2.5, Paint()..color = c.withValues(alpha: 0.3));
    canvas.drawCircle(Offset(s.width * 0.72, s.height * 0.61), 2.5, Paint()..color = c.withValues(alpha: 0.3));

    // Eye
    canvas.drawCircle(Offset(s.width * 0.58, s.height * 0.50), 4, Paint()..color = c.withValues(alpha: 0.5));

    // Coin slot
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width * 0.36, s.height * 0.32, s.width * 0.18, 5), const Radius.circular(3)), stroke..strokeWidth = 2);
    stroke.strokeWidth = 2.5;

    // Legs
    for (double x in [s.width * 0.3, s.width * 0.42, s.width * 0.54]) {
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x, s.height * 0.74, s.width * 0.08, s.height * 0.15),
        const Radius.circular(5)), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x, s.height * 0.74, s.width * 0.08, s.height * 0.15),
        const Radius.circular(5)), stroke..strokeWidth = 1.8);
      stroke.strokeWidth = 2.5;
    }

    // Scattered coins
    for (final pos in [Offset(s.width * 0.08, s.height * 0.72), Offset(s.width * 0.82, s.height * 0.65), Offset(s.width * 0.85, s.height * 0.80)]) {
      canvas.drawCircle(pos, 11, coinFill);
      canvas.drawCircle(pos, 11, stroke..strokeWidth = 1.5);
      stroke.strokeWidth = 2.5;
    }

    // Zzz
    final textPainter = TextPainter(
      text: TextSpan(text: 'Zzz', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.withValues(alpha: 0.4))),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(s.width * 0.12, s.height * 0.22));
  }

  // ── Bell (Notification) ─────────────────────────────────
  void _paintBell(Canvas canvas, Size s) {
    final c = color;
    final fill = Paint()..color = c.withValues(alpha: 0.12);
    final stroke = Paint()..color = c.withValues(alpha: 0.55)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;

    // Bell body
    final bellPath = Path()
      ..moveTo(s.width * 0.50, s.height * 0.12)
      ..cubicTo(s.width * 0.32, s.height * 0.15, s.width * 0.18, s.height * 0.35, s.width * 0.15, s.height * 0.65)
      ..lineTo(s.width * 0.85, s.height * 0.65)
      ..cubicTo(s.width * 0.82, s.height * 0.35, s.width * 0.68, s.height * 0.15, s.width * 0.50, s.height * 0.12)
      ..close();
    canvas.drawPath(bellPath, fill);
    canvas.drawPath(bellPath, stroke);

    // Bell base
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width * 0.18, s.height * 0.64, s.width * 0.64, s.height * 0.07),
      const Radius.circular(4)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width * 0.18, s.height * 0.64, s.width * 0.64, s.height * 0.07),
      const Radius.circular(4)), stroke..strokeWidth = 2);
    stroke.strokeWidth = 2.5;

    // Clapper
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.77), s.width * 0.06, fill);
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.77), s.width * 0.06, stroke..strokeWidth = 2);
    stroke.strokeWidth = 2.5;

    // Stars
    for (final star in [Offset(s.width * 0.15, s.height * 0.18), Offset(s.width * 0.82, s.height * 0.24), Offset(s.width * 0.72, s.height * 0.10)]) {
      _drawStar(canvas, star, 6, c.withValues(alpha: 0.35));
    }

    // Moon
    final moonPath = Path()
      ..addOval(Rect.fromCenter(center: Offset(s.width * 0.88, s.height * 0.42), width: 22, height: 22))
      ..addOval(Rect.fromCenter(center: Offset(s.width * 0.96, s.height * 0.39), width: 20, height: 20));
    canvas.drawPath(moonPath, Paint()..color = c.withValues(alpha: 0.18)..blendMode = BlendMode.srcOver);
    canvas.drawArc(Rect.fromCenter(center: Offset(s.width * 0.88, s.height * 0.42), width: 22, height: 22), -0.8, 2.5, false, stroke..strokeWidth = 2);
    stroke.strokeWidth = 2.5;
  }

  // ── Heart Pin (Saved) ───────────────────────────────────
  void _paintHeart(Canvas canvas, Size s) {
    final c = color;
    final fill = Paint()..color = c.withValues(alpha: 0.12);
    final stroke = Paint()..color = c.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;

    // Map pin shape
    final pinPath = Path()
      ..addOval(Rect.fromCenter(center: Offset(s.width * 0.50, s.height * 0.38), width: s.width * 0.50, height: s.height * 0.48))
      ..moveTo(s.width * 0.50, s.height * 0.62)
      ..lineTo(s.width * 0.50, s.height * 0.82);
    canvas.drawPath(Path()
      ..addOval(Rect.fromCenter(center: Offset(s.width * 0.50, s.height * 0.38), width: s.width * 0.50, height: s.height * 0.48))
      ..moveTo(s.width * 0.38, s.height * 0.62)
      ..lineTo(s.width * 0.50, s.height * 0.82)
      ..lineTo(s.width * 0.62, s.height * 0.62), fill);
    canvas.drawPath(pinPath, stroke);

    // Heart inside pin
    _drawHeart(canvas, Offset(s.width * 0.50, s.height * 0.36), s.width * 0.14, c.withValues(alpha: 0.6));

    // Dotted trail of smaller pins
    for (int i = 1; i <= 3; i++) {
      final x = s.width * (0.15 + i * 0.18);
      final y = s.height * (0.72 + i * 0.04);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = c.withValues(alpha: 0.15 + i * 0.05));
    }

    // Sparkles
    _drawStar(canvas, Offset(s.width * 0.78, s.height * 0.18), 5, c.withValues(alpha: 0.4));
    _drawStar(canvas, Offset(s.width * 0.20, s.height * 0.22), 4, c.withValues(alpha: 0.3));
  }

  // ── Speech Bubbles (Community) ──────────────────────────
  void _paintBubbles(Canvas canvas, Size s) {
    final c = color;
    final fill1 = Paint()..color = c.withValues(alpha: 0.12);
    final fill2 = Paint()..color = c.withValues(alpha: 0.07);
    final stroke = Paint()..color = c.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;

    // Left bubble
    final b1 = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.04, s.height * 0.12, s.width * 0.50, s.height * 0.32),
        const Radius.circular(14)))
      ..moveTo(s.width * 0.14, s.height * 0.44)
      ..lineTo(s.width * 0.08, s.height * 0.56)
      ..lineTo(s.width * 0.26, s.height * 0.44);
    canvas.drawPath(b1, fill1);
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width * 0.04, s.height * 0.12, s.width * 0.50, s.height * 0.32),
      const Radius.circular(14)), stroke);

    // Right bubble
    final b2 = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.44, s.height * 0.46, s.width * 0.52, s.height * 0.30),
        const Radius.circular(14)))
      ..moveTo(s.width * 0.74, s.height * 0.76)
      ..lineTo(s.width * 0.88, s.height * 0.84)
      ..lineTo(s.width * 0.72, s.height * 0.76);
    canvas.drawPath(b2, fill2);
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width * 0.44, s.height * 0.46, s.width * 0.52, s.height * 0.30),
      const Radius.circular(14)), stroke..strokeWidth = 2);
    stroke.strokeWidth = 2.5;

    // Dots inside bubbles
    for (double x in [0.15, 0.28, 0.41]) {
      canvas.drawCircle(Offset(s.width * x, s.height * 0.28), 5, Paint()..color = c.withValues(alpha: 0.25));
    }
    for (double x in [0.54, 0.64, 0.74]) {
      canvas.drawCircle(Offset(s.width * x, s.height * 0.61), 4, Paint()..color = c.withValues(alpha: 0.18));
    }

    // Cherry blossom dots
    for (final pos in [Offset(s.width * 0.90, s.height * 0.10), Offset(s.width * 0.82, s.height * 0.90), Offset(s.width * 0.06, s.height * 0.78)]) {
      for (int i = 0; i < 5; i++) {
        final angle = i * 72 * 3.14159 / 180;
        canvas.drawCircle(Offset(pos.dx + 8 * cos(angle), pos.dy + 8 * sin(angle)), 3, Paint()..color = const Color(0xFFD4A8C7).withValues(alpha: 0.5));
      }
    }
  }

  // ── Compass (Map) ───────────────────────────────────────
  void _paintCompass(Canvas canvas, Size s) {
    final c = color;
    final fill = Paint()..color = c.withValues(alpha: 0.10);
    final stroke = Paint()..color = c.withValues(alpha: 0.55)..style = PaintingStyle.stroke..strokeWidth = 2.5;

    // Outer circle
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.50), s.width * 0.38, fill);
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.50), s.width * 0.38, stroke);

    // Inner ring
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.50), s.width * 0.22, fill..color = c.withValues(alpha: 0.06));
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.50), s.width * 0.22, stroke..strokeWidth = 1.5);
    stroke.strokeWidth = 2.5;

    // N/S/E/W labels
    for (final entry in [('N', 0.50, 0.10), ('S', 0.50, 0.90), ('E', 0.88, 0.50), ('W', 0.12, 0.50)]) {
      final tp = TextPainter(
        text: TextSpan(text: entry.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.withValues(alpha: 0.5))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(s.width * entry.$2 - tp.width / 2, s.height * entry.$3 - tp.height / 2));
    }

    // Needle (North red)
    final center = Offset(s.width * 0.50, s.height * 0.50);
    canvas.drawPath(Path()
      ..moveTo(center.dx, center.dy - s.height * 0.28)
      ..lineTo(center.dx - 8, center.dy)
      ..lineTo(center.dx, center.dy + s.height * 0.15)
      ..lineTo(center.dx + 8, center.dy)
      ..close(), Paint()..color = c.withValues(alpha: 0.55)..style = PaintingStyle.fill);

    // Center dot
    canvas.drawCircle(center, 6, Paint()..color = Colors.white);
    canvas.drawCircle(center, 6, stroke..strokeWidth = 2);
  }

  // ── Helpers ────────────────────────────────────────────
  void _drawStar(Canvas canvas, Offset center, double r, Color c) {
    final paint = Paint()..color = c..style = PaintingStyle.fill;
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 72 - 90) * 3.14159 / 180;
      final innerAngle = outerAngle + 36 * 3.14159 / 180;
      final pt = Offset(center.dx + r * cos(outerAngle), center.dy + r * sin(outerAngle));
      final pi = Offset(center.dx + r * 0.4 * cos(innerAngle), center.dy + r * 0.4 * sin(innerAngle));
      if (i == 0) path.moveTo(pt.dx, pt.dy); else path.lineTo(pt.dx, pt.dy);
      path.lineTo(pi.dx, pi.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Offset center, double r, Color c) {
    final path = Path()
      ..moveTo(center.dx, center.dy + r * 0.5)
      ..cubicTo(center.dx - r * 1.4, center.dy - r * 0.3, center.dx - r * 1.4, center.dy - r * 1.4, center.dx, center.dy - r * 0.6)
      ..cubicTo(center.dx + r * 1.4, center.dy - r * 1.4, center.dx + r * 1.4, center.dy - r * 0.3, center.dx, center.dy + r * 0.5)
      ..close();
    canvas.drawPath(path, Paint()..color = c..style = PaintingStyle.fill);
  }

  double cos(double radians) => math.cos(radians);
  double sin(double radians) => math.sin(radians);

  @override bool shouldRepaint(_EmptyScenePainter old) => old.color != color || old.scene != scene;
}
