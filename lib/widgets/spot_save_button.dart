import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/trip_service.dart';
import '../services/local_fav_service.dart';
import '../theme/app_theme.dart';

/// A heart/bookmark button that saves a spot.
/// Works for both logged-in users (Firebase) and guests (SharedPreferences).
class SpotSaveButton extends StatefulWidget {
  final String spotId;
  final String spotName;
  final String imageUrl;
  final double rating;
  final double size;
  final Color? bgColor;

  const SpotSaveButton({
    super.key,
    required this.spotId,
    required this.spotName,
    this.imageUrl = '',
    this.rating = 0.0,
    this.size = 16,
    this.bgColor,
  });

  @override
  State<SpotSaveButton> createState() => _SpotSaveButtonState();
}

class _SpotSaveButtonState extends State<SpotSaveButton> {
  bool _saved = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initState();
  }

  Future<void> _initState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snap = await TripService.savedSpotIdsStream().first;
      if (mounted) setState(() => _saved = snap.contains(widget.spotId));
    } else {
      await LocalFavService.load();
      if (mounted) setState(() => _saved = LocalFavService.isSaved(widget.spotId));
    }
  }

  Future<void> _toggle(BuildContext ctx) async {
    if (_busy) return;
    setState(() => _busy = true);
    final user = FirebaseAuth.instance.currentUser;
    bool nowSaved;
    try {
      if (user != null) {
        nowSaved = await TripService.toggleSavedSpot(
          widget.spotId,
          spotName: widget.spotName,
          imageUrl: widget.imageUrl,
          rating: widget.rating,
        );
      } else {
        nowSaved = await LocalFavService.toggle(widget.spotId);
      }
      if (mounted) {
        setState(() => _saved = nowSaved);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(nowSaved ? '已收藏「${widget.spotName}」' : '已取消收藏'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: nowSaved ? AppColors.error : AppColors.textSecondary,
          duration: const Duration(milliseconds: 1500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _saved ? AppColors.error : AppColors.textHint;
    final bg = widget.bgColor ?? Colors.white.withValues(alpha: 0.92);
    return GestureDetector(
      onTap: () => _toggle(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(widget.size * 0.44),
        decoration: BoxDecoration(
          color: _saved ? AppColors.error.withValues(alpha: 0.12) : bg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (c, a) => ScaleTransition(
            scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
            child: c,
          ),
          child: _busy
              ? SizedBox(
                  width: widget.size, height: widget.size,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
              : Icon(
                  _saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(_saved),
                  size: widget.size,
                  color: color,
                ),
        ),
      ),
    );
  }
}
