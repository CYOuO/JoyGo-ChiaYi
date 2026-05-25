import 'package:flutter/material.dart';
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

  String get _categoryIcon {
    switch (widget.category) {
      case 'restaurant':
        return '🍜';
      case 'attraction':
        return '🏛️';
      case 'hotel':
        return '🏨';
      case 'youbike':
        return '🚲';
      case 'aed':
        return '❤️';
      default:
        return '📍';
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
                        child: Text(
                          _categoryIcon,
                          style: const TextStyle(fontSize: 40),
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
                      child: Text(
                        _categoryIcon,
                        style: const TextStyle(fontSize: 12),
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
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
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
  final String icon;
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
    // ignore: unused_local_variable
    final mist    = Color.lerp(primary, Colors.white, 0.88) ?? AppColors.primaryMist;
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
            Text(icon, style: const TextStyle(fontSize: 14)),
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
//  Persists to SharedPreferences keyed by placeId.
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
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rating        = prefs.getInt(_rKey) ?? 0;
      _noteCtrl.text = prefs.getString(_nKey) ?? '';
      _loading       = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rating > 0) {
      await prefs.setInt(_rKey, _rating);
    } else {
      await prefs.remove(_rKey);
    }
    final note = _noteCtrl.text.trim();
    if (note.isNotEmpty) {
      await prefs.setString(_nKey, note);
    } else {
      await prefs.remove(_nKey);
    }
    if (!mounted) return;
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
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
