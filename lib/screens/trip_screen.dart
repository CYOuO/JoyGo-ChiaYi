import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';
import '../models/dummy_data.dart';
import '../widgets/common_widgets.dart';
import '../services/trip_service.dart';
import '../theme/fabric_textures.dart';
import 'calendar_screen.dart';
import 'expense_screen.dart';
import 'map_screen.dart' as from_map;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TRIP SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class TripScreen extends StatefulWidget {
  /// When incremented, _TripScreenState jumps to the calendar tab (index 3).
  final ValueNotifier<int>? calendarTrigger;
  const TripScreen({super.key, this.calendarTrigger});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showAIPanel = false;

  // ── Auth — initialized synchronously from currentUser in initState ──────
  User? _authUser;

  // Firebase trips — updated via StreamSubscription (no StreamBuilder flicker)
  List<FirebaseTrip> _firebaseTrips = [];
  bool _tripsLoading = true;
  StreamSubscription<List<FirebaseTrip>>? _tripsSub;

  // 候選清單（本地狀態 + Firebase 同步）
  final List<_CandidateSpot> _candidates = [];

  // 訪客收藏景點（SharedPreferences，登入後同步到 Firebase）
  Set<String> _guestSavedIds = {};
  // 收藏景點分類篩選
  String _savedFilter = '全部';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.calendarTrigger?.addListener(_onCalendarTrigger);

    _authUser = FirebaseAuth.instance.currentUser;
    if (_authUser != null) _subscribeToTrips();

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) setState(() => _authUser = user);
      if (user != null) {
        _subscribeToTrips();
        if (_guestSavedIds.isNotEmpty && mounted) {
          _syncGuestFavoritesToFirebase(user);
        }
      } else {
        _tripsSub?.cancel();
        _tripsSub = null;
        if (mounted) setState(() { _firebaseTrips = []; _tripsLoading = false; });
      }
    });

    _loadGuestFavorites();
  }

  void _subscribeToTrips() {
    _tripsSub?.cancel();
    _tripsSub = TripService.tripsStream().listen(
      (trips) {
        if (mounted) setState(() { _firebaseTrips = trips; _tripsLoading = false; });
      },
      onError: (_) {
        if (mounted) setState(() => _tripsLoading = false);
      },
    );
  }

  Future<void> _loadGuestFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList('guest_saved_spots') ?? []).toSet();
    if (mounted) setState(() => _guestSavedIds = ids);
  }

  Future<bool> _toggleGuestFavorite(Spot s) async {
    final isNowSaved = !_guestSavedIds.contains(s.id);
    setState(() => isNowSaved ? _guestSavedIds.add(s.id) : _guestSavedIds.remove(s.id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('guest_saved_spots', _guestSavedIds.toList());
    return isNowSaved;
  }

  Future<void> _syncGuestFavoritesToFirebase(User user) async {
    final toSync = Set<String>.from(_guestSavedIds);
    if (toSync.isEmpty) return;
    for (final spotId in toSync) {
      final matches = DummyData.spots.where((s) => s.id == spotId);
      if (matches.isNotEmpty) {
        final s = matches.first;
        await TripService.toggleSavedSpot(spotId, spotName: s.name, imageUrl: s.imageUrl, rating: s.rating);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('guest_saved_spots');
    if (mounted) {
      setState(() => _guestSavedIds = {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${toSync.length} 個收藏景點已同步到你的帳戶'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _onCalendarTrigger() {
    // Now tab 2 = 行事曆 (after removing candidates tab)
    if (_tabController.index != 2) {
      _tabController.animateTo(2);
    } else {
      setState(() {});
    }
  }

  /// Build trip list for the calendar from Firebase trips.
  List<({String title, DateTime date, DateTime? endDate})> get _tripsForCalendar =>
      _firebaseTrips.map((t) => (
        title:   t.title,
        date:    t.startDate,
        endDate: t.endDate,
      )).toList();

  @override
  void dispose() {
    widget.calendarTrigger?.removeListener(_onCalendarTrigger);
    _tabController.dispose();
    _tripsSub?.cancel();
    super.dispose();
  }

  void _addToCandidate(Spot s) {
    if (_candidates.any((c) => c.spot.id == s.id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${s.name} 已在候選清單中'),
        backgroundColor: AppColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _candidates.add(_CandidateSpot(spot: s)));
    // Sync to Firebase (non-blocking)
    TripService.addCandidate(
      spotId:   s.id,
      spotName: s.name,
      category: s.category,
      order:    _candidates.length - 1,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已將「${s.name}」加入候選清單 ✓'),
      backgroundColor: Theme.of(context).colorScheme.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: '查看清單',
        textColor: Colors.white,
        onPressed: () => _tabController.animateTo(1),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 20,
        title: Builder(builder: (ctx) {
          final p = Theme.of(ctx).colorScheme.primary;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 22, child: Stack(children: [
              Positioned(left: 0, top: 3, child: Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p))),
              Positioned(left: 6, top: 12, child: Container(width: 5, height: 5,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: p.withValues(alpha: 0.35)))),
            ])),
            const SizedBox(width: 2),
            const Text('行程管理',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]);
        }),
        actions: [
          IconButton(
            icon: Icon(Icons.auto_awesome_rounded, color: primary),
            onPressed: () => setState(() => _showAIPanel = !_showAIPanel),
            tooltip: 'AI 行程助手',
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, color: primary),
            onPressed: () => _showCreateTrip(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primary,
          indicatorColor: primary,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: [
            Tab(text: context.watch<AppSettingsProvider>().l10n.tripMyTrips),
            Tab(text: context.watch<AppSettingsProvider>().l10n.tripSaved),
            Tab(text: context.watch<AppSettingsProvider>().l10n.tripCalendar),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildMyTripsTab(),
              _buildSavedSpotsTab(),
              CalendarScreen(userTrips: _tripsForCalendar),
            ],
          ),
          if (_showAIPanel) _buildAIPanel(context),
        ],
      ),
    );
  }

  // ── My Trips ── (uses StreamSubscription, no flicker)
  Widget _buildMyTripsTab() {
    if (_authUser == null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          const Text('請先登入', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('登入後才能建立和管理行程', style: TextStyle(color: AppColors.textHint)),
        ],
      ));
    }
    if (_tripsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final trips = _firebaseTrips;
    if (trips.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 56, color: AppColors.textHint.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text('還沒有行程', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('點右上角 + 建立第一個行程！', style: TextStyle(color: AppColors.textHint)),
        ],
      ));
    }
    final now = DateTime.now();
    final upcoming = trips
        .where((t) => !t.isCompleted && t.startDate.isAfter(now))
        .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final nextTrip = upcoming.isNotEmpty ? upcoming.first : null;

    // 把下一趟抽出，其餘的行程顯示為緊湊列表
    final otherTrips = trips.where((t) => t != nextTrip).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // ── 下一趟旅程倒數 Banner ─────────────────────────
        if (nextTrip != null) ...[
          _buildCountdownBanner(nextTrip),
          const SizedBox(height: 20),
        ],
        // ── 統計 ──────────────────────────────────────────
        Row(children: [
          _statCard('規劃中', '${trips.where((t) => !t.isCompleted).length}', Icons.event_outlined, const Color(0xFFF5EFE6)),
          const SizedBox(width: 10),
          _statCard('已完成', '${trips.where((t) => t.isCompleted).length}', Icons.check_circle_outline_rounded, const Color(0xFFEDF5ED)),
          const SizedBox(width: 10),
          _statCard('總景點', '${trips.fold(0, (s, t) => s + t.spots.length)}', Icons.place_outlined, const Color(0xFFEBEFF2)),
        ]),
        if (otherTrips.isNotEmpty) ...[
          const WashiTapeDivider(color: Color(0x18D4A574)),
          SectionHeader(title: '我的行程'),
          const SizedBox(height: 10),
          ...otherTrips.map((t) => _buildCompactTripRow(t)),
        ],
      ],
    );
  }

  // ── 下一趟旅程倒數 Banner ─────────────────────────────────────
  Widget _buildCountdownBanner(FirebaseTrip trip) {
    final primary = Theme.of(context).colorScheme.primary;
    final daysLeft = trip.startDate.difference(DateTime.now()).inDays;
    return GestureDetector(
      onTap: () => _showFirebaseTripDetail(context, trip),
      child: SketchyBorderBox(
        borderColor: primary.withValues(alpha: 0.35),
        strokeWidth: 1.2,
        padding: EdgeInsets.zero,
        seed: trip.id.hashCode,
        child: Container(
        height: 196,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
            color: primary.withValues(alpha: 0.2),
            blurRadius: 16, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // Cover
          Image.network(
            trip.coverUrl ?? 'https://picsum.photos/seed/${trip.id}/600/400',
            width: double.infinity, height: 196, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: Color.lerp(primary, Colors.black, 0.3)!),
          ),
          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight, end: Alignment.bottomLeft,
                colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.72)],
              ),
            ),
          ),
          // Countdown bubble (top right) — hand-drawn circle
          Positioned(top: 14, right: 14, child: DoodleCircle(
            size: 64,
            color: primary.withValues(alpha: 0.6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle),
              padding: const EdgeInsets.all(6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('倒數', style: TextStyle(fontSize: 8, color: primary, fontWeight: FontWeight.w700)),
                Text('$daysLeft', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: primary, height: 1.0)),
                Text('天', style: TextStyle(fontSize: 8, color: primary, fontWeight: FontWeight.w700)),
              ]),
            ),
          )),
          // Trip info (bottom)
          Positioned(left: 16, right: 90, bottom: 16, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('下一趟旅程', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 6),
              Text(trip.title,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.2),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(trip.dateDisplay,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.place_rounded, size: 11, color: Colors.white60),
                const SizedBox(width: 3),
                Text('${trip.spots.length} 個景點 · ${trip.days} 天',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios_rounded, size: 9, color: Colors.white60),
                const Text('查看', style: TextStyle(color: Colors.white60, fontSize: 11)),
              ]),
            ],
          )),
        ]),
      ),
      ),
    );
  }

  Widget _buildCompactTripRow(FirebaseTrip trip) {
    final primary = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();
    final isPast = trip.startDate.isBefore(now);
    final statusColor = trip.isCompleted ? primary : AppColors.accentStraw;
    final statusLabel = trip.isCompleted ? '已完成' : (isPast ? '進行中' : '規劃中');
    return GestureDetector(
      onTap: () => _showFirebaseTripDetail(context, trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 6)],
        ),
        child: Row(children: [
          // 縮圖
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              trip.coverUrl ?? 'https://picsum.photos/seed/${trip.id}/100/100',
              width: 60, height: 60, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 60, height: 60,
                color: primary.withValues(alpha: 0.12),
                child: Icon(Icons.map_outlined, color: primary.withValues(alpha: 0.4), size: 28)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trip.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(trip.dateDisplay,
              style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(statusLabel,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: trip.isCompleted ? primary : Color.lerp(AppColors.accentStraw, Colors.black, 0.3)!)),
              ),
            ]),
          ])),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 18),
        ]),
      ),
    );
  }

  Widget _buildFirebaseTripCard(FirebaseTrip trip) {
    final now = DateTime.now();
    final daysLeft = trip.startDate.difference(now).inDays;
    final isPast = trip.startDate.isBefore(now);
    return GestureDetector(
      onTap: () => _showFirebaseTripDetail(context, trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(children: [
                Image.network(
                  trip.coverUrl ?? 'https://picsum.photos/seed/${trip.id}/600/200',
                  height: 130, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 130,
                    color: Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.88)!,
                    child: Center(child: Icon(Icons.map_outlined, size: 40,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)))),
                ),
                Container(
                  height: 130,
                  decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)]))),
                Positioned(top: 10, right: 10,
                  child: Builder(builder: (bCtx) {
                    final p = Theme.of(bCtx).colorScheme.primary;
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!trip.isCompleted && !isPast && daysLeft >= 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(20)),
                          child: Text('$daysLeft 天後',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: trip.isCompleted ? p : AppColors.accentStraw,
                          borderRadius: BorderRadius.circular(20)),
                        child: Text(trip.isCompleted ? '已完成' : '規劃中',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: trip.isCompleted ? Colors.white : Color.lerp(p, Colors.black, 0.3)!)),
                      ),
                    ]);
                  }),
                ),
                Positioned(bottom: 10, left: 14,
                  child: Text(trip.title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(trip.dateDisplay, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const Spacer(),
                    Text('${trip.days}天 · ${trip.spots.length}個景點',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  if (trip.spots.isNotEmpty)
                    Wrap(spacing: 6, runSpacing: 4,
                      children: trip.spots.take(3).map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.divider)),
                        child: Text(s, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                      )).toList()),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => _showFirebaseTripDetail(context, trip),
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: const Text('查看 / 編輯'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: trip.isCompleted
                      ? ElevatedButton.icon(
                          onPressed: () => _showShareOptions(context, trip),
                          icon: const Icon(Icons.share_rounded, size: 15),
                          label: const Text('分享'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        )
                      : ElevatedButton.icon(
                          onPressed: () async {
                            await TripService.setCompleted(trip.id, completed: true);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('「${trip.title}」已標記為完成 ✅'),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ));
                          },
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                          label: const Text('標記完成'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFirebaseTripDetail(BuildContext context, FirebaseTrip trip) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _FirebaseTripDetailPage(trip: trip)));
  }

  Widget _statCard(String label, String val, IconData icon, Color color) {
    final stitchColor = AppColors.textSecondary.withValues(alpha: 0.3);
    return Expanded(child: StitchedBox(
      color: color,
      stitchColor: stitchColor,
      radius: 14,
      inset: 4,
      dashWidth: 4,
      dashGap: 3,
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Icon(icon, size: 22, color: AppColors.textSecondary),
        const SizedBox(height: 3),
        Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ]),
    ));
  }

  // ── Candidates Tab ── 拖移排序 + 加入入口 ──
  Widget _buildCandidatesTab() {
    return Column(
      children: [
        // 說明 banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(
              '長按拖移 ☰ 可調整順序，或點「加入景點」從地圖選取，\n再點「AI 幫我排程」自動最佳化！',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, height: 1.5),
            )),
          ]),
        ),
        // 加入景點按鈕
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () => _showAddCandidateSheet(context),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('＋ 加入景點到候選清單'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 拖移列表
        Expanded(
          child: _candidates.isEmpty
              ? _emptyCandidates()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _candidates.length,
                  onReorder: (oldI, newI) {
                    if (newI > oldI) newI--;
                    setState(() {
                      final item = _candidates.removeAt(oldI);
                      _candidates.insert(newI, item);
                    });
                    HapticFeedback.lightImpact();
                    // Sync order to Firebase
                    TripService.reorderCandidates(_candidates.map((c) => c.spot.id).toList());
                  },
                  itemBuilder: (_, i) {
                    final c = _candidates[i];
                    return _candidateItem(c, i);
                  },
                ),
        ),
        // Bottom actions
        if (_candidates.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => setState(() => _showAIPanel = true),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('AI 最佳排程'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: () => _convertToTrip(context),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('轉為行程'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )),
            ]),
          ),
      ],
    );
  }

  Widget _candidateItem(_CandidateSpot c, int index) {
    final spot = c.spot;
    final catIcon = spot.category == 'restaurant' ? '🍜'
        : spot.category == 'youbike' ? '🚲' : '🏛️';

    return Container(
      key: ValueKey(spot.id),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Order number
            Builder(builder: (bCtx) => Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: Theme.of(bCtx).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text('${index + 1}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
            )),
            const SizedBox(width: 8),
            Text(catIcon, style: const TextStyle(fontSize: 22)),
          ],
        ),
        title: Text(spot.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
        subtitle: Row(children: [
          const Icon(Icons.access_time_rounded, size: 11, color: AppColors.textHint),
          Text('  ${spot.openHours}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(width: 8),
          const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
          Text('  ${spot.rating}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
              onPressed: () {
                final spotId = _candidates[index].spot.id;
                setState(() => _candidates.removeAt(index));
                TripService.removeCandidate(spotId);
              },
              tooltip: '移除',
            ),
            const Icon(Icons.drag_handle_rounded, color: AppColors.textHint, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _emptyCandidates() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.playlist_add_outlined, size: 52, color: AppColors.textHint),
          const SizedBox(height: 12),
          const Text('候選清單是空的', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('點上方按鈕加入想去的景點', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showAddCandidateSheet(context),
            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
            label: const Text('加入景點'),
          ),
        ],
      ),
    );
  }

  // ── Add candidate sheet（從景點清單選） ──
  void _showAddCandidateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('選擇景點加入候選清單', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: DummyData.spots.length,
                  itemBuilder: (itemCtx, i) {
                    final s = DummyData.spots[i];
                    final already = _candidates.any((c) => c.spot.id == s.id);
                    final icon = s.category == 'restaurant' ? '🍜'
                        : s.category == 'youbike' ? '🚲' : '🏛️';
                    final p = Theme.of(itemCtx).colorScheme.primary;
                    final mist = Color.lerp(p, Colors.white, 0.88)!;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: already ? mist : AppColors.surfaceWarm,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: already ? p.withValues(alpha: 0.3) : AppColors.divider),
                      ),
                      child: ListTile(
                        leading: Text(icon, style: const TextStyle(fontSize: 24)),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Row(children: [
                          const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
                          Text('  ${s.rating}  ·  ${s.address}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                        trailing: Builder(builder: (bCtx) {
                          final p = Theme.of(bCtx).colorScheme.primary;
                          return already
                            ? Icon(Icons.check_circle_rounded, color: p)
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: p, borderRadius: BorderRadius.circular(10)),
                                child: const Text('加入', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              );
                        }),
                        onTap: already ? null : () {
                          _addToCandidate(s);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Saved spots ── Shows ALL saved spots (map spots + DummyData spots)
  Widget _buildSavedSpotsTab() {
    final user = _authUser;
    if (user != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: TripService.savedSpotsDataStream(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final rawSpots = snap.data ?? [];
          return _savedSpotsGridRaw(
            rawSpots: rawSpots,
            onUnsave: (spotId, spotName) async {
              await TripService.toggleSavedSpot(spotId, spotName: spotName);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('已取消收藏「$spotName」'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ));
            },
            isGuest: false,
          );
        },
      );
    } else {
      // Guest: show DummyData spots filtered by local IDs
      final savedSpots = DummyData.spots.where((s) => _guestSavedIds.contains(s.id)).toList();
      final rawGuest = savedSpots.map((s) => {
        'spotId': s.id, 'spotName': s.name,
        'imageUrl': s.imageUrl, 'rating': s.rating,
      }).toList();
      return _savedSpotsGridRaw(
        rawSpots: rawGuest,
        onUnsave: (spotId, spotName) async {
          final s = DummyData.spots.firstWhere((x) => x.id == spotId, orElse: () => DummyData.spots.first);
          await _toggleGuestFavorite(s);
        },
        isGuest: true,
      );
    }
  }

  Widget _savedSpotsGridRaw({
    required List<Map<String, dynamic>> rawSpots,
    required Future<void> Function(String spotId, String spotName) onUnsave,
    required bool isGuest,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    if (rawSpots.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark_border_rounded, size: 52, color: AppColors.textHint),
            const SizedBox(height: 12),
            const Text('還沒有收藏景點',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              isGuest
                  ? '點地圖或首頁景點旁的收藏鍵，\n登入後會自動同步到你的帳戶'
                  : '在地圖、首頁點景點旁的收藏鍵，\n方便之後加入行程！',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textHint, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ));
    }
    // Derive categories from spot names (simple keyword matching)
    String _categorize(Map<String, dynamic> d) {
      final name = (d['spotName']?.toString() ?? '').toLowerCase();
      if (name.contains('雞肉飯') || name.contains('餐') || name.contains('飯') ||
          name.contains('食') || name.contains('小吃')) return '美食';
      if (name.contains('park') || name.contains('公園') || name.contains('山') ||
          name.contains('森林') || name.contains('步道')) return '自然';
      if (name.contains('廟') || name.contains('寺') || name.contains('古蹟') ||
          name.contains('文化') || name.contains('美術')) return '文化';
      return '其他';
    }
    final categories = {'全部', ...rawSpots.map(_categorize)};
    final filtered = _savedFilter == '全部'
        ? rawSpots
        : rawSpots.where((d) => _categorize(d) == _savedFilter).toList();

    return Column(children: [
      // ── 收藏頁標題 ─────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Row(children: [
          Text('收藏景點（${rawSpots.length}）',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (isGuest) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Text('訪客模式', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
      // Category filter chips
      if (categories.length > 2)
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            children: categories.map((c) {
              final sel = _savedFilter == c;
              return GestureDetector(
                onTap: () => setState(() => _savedFilter = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: sel ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? primary : AppColors.divider)),
                  child: Text(c, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),
        ),
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Text('沒有「$_savedFilter」類的收藏',
                style: const TextStyle(color: AppColors.textHint, fontSize: 13)))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: [
                      for (int i = 0; i < filtered.length; i += 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _savedSpotMasonryCard(filtered[i], primary, onUnsave, context, i),
                        ),
                    ])),
                    const SizedBox(width: 10),
                    Expanded(child: Column(children: [
                      for (int i = 1; i < filtered.length; i += 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _savedSpotMasonryCard(filtered[i], primary, onUnsave, context, i),
                        ),
                    ])),
                  ],
                ),
              ),
      ),
    ]);
  }

  // ── AI Panel ──
  Widget _buildAIPanel(BuildContext context) {
    final prefs = ['🏛️ 文化歷史','🍜 美食探索','👨‍👩‍👧 親子友善','⛰️ 自然生態','📸 打卡拍照','🌙 夜間活動'];
    final selected = {0, 1};
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.66,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
        ),
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 12, bottom: 14),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Builder(builder: (bCtx) => Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Theme.of(bCtx).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.textSecondary))),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI 行程助手', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
                Text('由 Gemini AI 驅動', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              ]),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
                onPressed: () => setState(() => _showAIPanel = false)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Candidate preview
                if (_candidates.isNotEmpty) ...[
                  const Text('候選景點（共 ${0} 個）', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider)),
                    child: Column(
                      children: _candidates.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Builder(builder: (bCtx) => Container(width: 20, height: 20,
                            decoration: BoxDecoration(color: Theme.of(bCtx).colorScheme.primary, shape: BoxShape.circle),
                            child: Center(child: Text('${e.key+1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))))),
                          const SizedBox(width: 8),
                          Text(e.value.spot.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        ]),
                      )).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('旅遊偏好', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8,
                  children: prefs.asMap().entries.map((e) {
                    final isSel = selected.contains(e.key);
                    return GestureDetector(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? Theme.of(context).colorScheme.primary : AppColors.surfaceMoss,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSel ? Theme.of(context).colorScheme.primary : AppColors.divider)),
                        child: Text(e.value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : AppColors.textSecondary)),
                      ),
                    );
                  }).toList()),
                const SizedBox(height: 16),
                const Text('旅遊天數', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                _AIDaysSlider(),
                const SizedBox(height: 4),
                const SizedBox(height: 16),
                // Free-text requirements ABOVE AI preview
                const Text('詳細需求（選填）', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                const TextField(
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '例如：希望行程輕鬆不趕，想吃道地小吃，有小孩同行，避免山路...',
                    hintStyle: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // AI result preview
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.88)!,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.smart_toy_outlined, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('AI 建議預覽', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      _candidates.isEmpty
                          ? '請先加入景點到候選清單，AI 會依照開放時間與距離幫您安排最佳順序。'
                          : '📍 Day 1\n${_candidates.asMap().entries.map((e) => '${_timeSlot(e.key)} ${e.value.spot.name}').join('\n')}\n\n💡 已根據開放時間與距離最佳化順序，步行距離約 3.2km！',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.7)),
                  ]),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('生成 AI 行程建議'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 收藏景點：雜誌瀑布流風格 ────────────────────────────────
  Widget _savedSpotMasonryCard(
    Map<String, dynamic> d,
    Color primary,
    Future<void> Function(String, String) onUnsave,
    BuildContext ctx,
    int index,
  ) {
    final spotId   = d['spotId']?.toString() ?? d['__id']?.toString() ?? '';
    final spotName = d['spotName']?.toString() ?? '';
    final imageUrl = d['imageUrl']?.toString() ?? '';
    final rating   = (d['rating'] as num?)?.toDouble() ?? 0.0;
    final hasImage = imageUrl.isNotEmpty;
    final imgH     = hasImage ? (index.isEven ? 150.0 : 190.0) : 0.0;

    return GestureDetector(
      onTap: () => _showSavedSpotDetail(ctx, d, primary, onUnsave),
      child: StitchedBox(
      color: Colors.white,
      stitchColor: primary.withValues(alpha: 0.22),
      radius: 16, inset: 4, dashWidth: 4, dashGap: 3.5,
      boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasImage)
            Stack(children: [
              Image.network(imageUrl,
                width: double.infinity, height: imgH, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              // 愛心取消收藏 — 右上角
              Positioned(top: 6, right: 6, child: GestureDetector(
                onTap: () => onUnsave(spotId, spotName),
                child: Container(padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle),
                  child: Icon(Icons.favorite_rounded, size: 14, color: AppColors.error)))),
              // +行程 — 右下角
              Positioned(bottom: 6, right: 6, child: GestureDetector(
                onTap: () => _showAddToTripSheet(ctx, spotId, spotName),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('+行程', style: TextStyle(fontSize: 9, color: primary, fontWeight: FontWeight.w700))))),
            ]),
          Padding(
            padding: EdgeInsets.fromLTRB(10, hasImage ? 8 : 12, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!hasImage)
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(spotName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Container(height: 2, width: 32,
                      decoration: BoxDecoration(color: primary.withValues(alpha: 0.30), borderRadius: BorderRadius.circular(1))),
                  ])),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onUnsave(spotId, spotName),
                    child: Icon(Icons.favorite_rounded, size: 14, color: AppColors.error)),
                ])
              else
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(spotName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Container(height: 2, width: 32,
                    decoration: BoxDecoration(color: primary.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(1))),
                ]),
              const SizedBox(height: 5),
              Row(children: [
                if (rating > 0) ...[
                  DoodleHeart(color: AppColors.error.withValues(alpha: 0.70), size: 10),
                  const SizedBox(width: 3),
                  Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ],
                if (!hasImage) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showAddToTripSheet(ctx, spotId, spotName),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
                      child: Text('+行程', style: TextStyle(fontSize: 9, color: primary, fontWeight: FontWeight.w700)))),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    ), // StitchedBox
    ); // GestureDetector
  }

  // ── 收藏景點詳情 sheet ────────────────────────────────────
  void _showSavedSpotDetail(
    BuildContext ctx,
    Map<String, dynamic> d,
    Color primary,
    Future<void> Function(String, String) onUnsave,
  ) {
    final spotId   = d['spotId']?.toString() ?? d['__id']?.toString() ?? '';
    final spotName = d['spotName']?.toString() ?? '';
    final imageUrl = d['imageUrl']?.toString() ?? '';
    final rating   = (d['rating'] as num?)?.toDouble() ?? 0.0;

    // 嘗試從 DummyData 補充更多資訊
    Spot? info;
    try { info = DummyData.spots.firstWhere((s) => s.id == spotId || s.name == spotName); } catch (_) {}

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.60, maxChildSize: 0.92, minChildSize: 0.40,
        builder: (sheetCtx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: ListView(controller: scroll, padding: EdgeInsets.zero, children: [
            // 圖片
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Image.network(imageUrl, height: 200, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 120, color: primary.withValues(alpha: 0.08))),
              )
            else
              Container(
                height: 90,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Center(child: Icon(Icons.place_rounded, size: 40, color: primary.withValues(alpha: 0.3)))),

            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 把手
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
              // 名稱 + 評分
              Row(children: [
                Expanded(child: Text(spotName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                if (rating > 0) ...[
                  const Icon(Icons.star_rounded, size: 16, color: AppColors.accentStraw),
                  const SizedBox(width: 3),
                  Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ]),
              const SizedBox(height: 8),
              // 詳細資訊（從 DummyData 補充）
              if (info != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(info.category,
                    style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700))),
                const SizedBox(height: 12),
                if (info.address.isNotEmpty) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Expanded(child: Text(info.address,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                ]),
                if (info.openHours.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(child: Text(info.openHours,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                  ]),
                ],
                if (info.description.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text('關於此景點',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Text(info.description,
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.75)),
                ],
              ] else ...[
                // 無 DummyData 對應時，至少顯示說明
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMoss,
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textHint),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '此景點的詳細資訊尚未建立。\n可前往地圖查看位置或導航。',
                      style: const TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.6))),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              // 操作按鈕
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetCtx);
                    await onUnsave(spotId, spotName);
                  },
                  icon: const Icon(Icons.favorite_border_rounded, size: 16),
                  label: const Text('取消收藏'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error)),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _showAddToTripSheet(ctx, spotId, spotName);
                  },
                  icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                  label: const Text('加入候選'),
                  style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white),
                )),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }

  // ignore: unused_element
  List<Widget> _buildSavedSpotsRows(
    List<Map<String, dynamic>> spots,
    Color primary,
    Future<void> Function(String, String) onUnsave,
    BuildContext ctx,
  ) {
    final rows = <Widget>[];
    for (int i = 0; i < spots.length; i += 2) {
      final left  = _savedSpotCard(spots[i], primary, onUnsave, ctx);
      final right = i + 1 < spots.length
          ? _savedSpotCard(spots[i + 1], primary, onUnsave, ctx)
          : const Expanded(child: SizedBox.shrink());
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(width: 10), right],
        ),
      ));
      rows.add(const SizedBox(height: 10));
    }
    return rows;
  }

  Widget _savedSpotCard(
    Map<String, dynamic> d,
    Color primary,
    Future<void> Function(String, String) onUnsave,
    BuildContext ctx,
  ) {
    final spotId   = d['spotId']?.toString() ?? d['__id']?.toString() ?? '';
    final spotName = d['spotName']?.toString() ?? '';
    final imageUrl = d['imageUrl']?.toString() ?? '';
    final rating   = (d['rating'] as num?)?.toDouble() ?? 0.0;
    final hasImage = imageUrl.isNotEmpty;

    if (!hasImage) {
      // ── 無圖：緊湊文字卡片 ──
      return Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 5)],
        ),
        child: Row(children: [
          Icon(Icons.place_outlined, size: 22, color: primary.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spotName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            if (rating > 0) Row(children: [
              const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
              Text(' ${rating.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ])),
          Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              onTap: () => onUnsave(spotId, spotName),
              child: Icon(Icons.favorite_rounded, size: 16, color: AppColors.error)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _showAddToTripSheet(ctx, spotId, spotName),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6)),
                child: Text('加入行程',
                  style: TextStyle(fontSize: 9, color: primary, fontWeight: FontWeight.w700)),
              )),
          ]),
        ]),
      ));
    }

    // ── 有圖：圖片滿版，文字疊在底部 ──
    return Expanded(child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(fit: StackFit.passthrough, children: [
        Image.network(imageUrl,
          width: double.infinity, height: 160, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 160, color: primary.withValues(alpha: 0.1),
            child: Icon(Icons.place_outlined, size: 36, color: primary.withValues(alpha: 0.3)))),
        // 漸層遮罩
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)])),
            padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(spotName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              if (rating > 0) Row(children: [
                const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
                Text(' ${rating.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            ]),
          )),
        // 取消收藏
        Positioned(top: 8, right: 8,
          child: GestureDetector(
            onTap: () => onUnsave(spotId, spotName),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
              child: Icon(Icons.favorite_rounded, size: 15, color: AppColors.error)))),
        // 加入行程
        Positioned(top: 8, left: 8,
          child: GestureDetector(
            onTap: () => _showAddToTripSheet(ctx, spotId, spotName),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8)),
              child: Builder(builder: (bCtx) {
                final p = Theme.of(bCtx).colorScheme.primary;
                return Text('＋行程',
                  style: TextStyle(fontSize: 10, color: p, fontWeight: FontWeight.w700));
              }),
            ))),
      ]),
    ));
  }

  // ── 加到特定行程候選清單 sheet ────────────────────────────────
  void _showAddToTripSheet(BuildContext context, String spotId, String spotName) {
    final primary = Theme.of(context).colorScheme.primary;
    final trips = _firebaseTrips.where((t) => !t.isCompleted).toList();
    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('請先建立行程'), behavior: SnackBarBehavior.floating));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          Text('加入行程候選清單', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
          const SizedBox(height: 4),
          Text('「$spotName」將加入選定行程的候選清單',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
          const SizedBox(height: 14),
          ...trips.map((t) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(t.icon, style: const TextStyle(fontSize: 20)))),
            title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(t.dateDisplay, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            trailing: Icon(Icons.chevron_right_rounded, color: primary),
            onTap: () async {
              Navigator.pop(context);
              await TripService.addTripCandidate(t.id,
                spotId: spotId, spotName: spotName, category: '', order: 0);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('已加入「${t.title}」的候選清單'),
                backgroundColor: primary, behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
            },
          )),
        ]),
      ),
    );
  }

  String _timeSlot(int i) {
    final slots = ['09:00','10:30','12:00','13:30','15:00','17:00','19:00'];
    return slots[i % slots.length];
  }

  void _convertToTrip(BuildContext ctx) {
    if (_candidates.isEmpty) return;
    final spots = _candidates.map((c) => c.spot.name).toList();
    // Save to Firebase and clear candidates
    TripService.createTrip(
      title: '新行程（從候選清單建立）',
      startDate: DateTime.now(),
      spots: spots,
    );
    setState(() => _candidates.clear());
    // Clear Firebase candidates too
    for (final c in spots) {
      TripService.removeCandidate(c);
    }
    _tabController.animateTo(0);
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: const Text('已成功建立行程'),
      backgroundColor: Theme.of(ctx).colorScheme.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showCreateTrip(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _CreateTripPage(
        onCreated: () {
          // Stream will auto-update; just switch to the trips tab
          _tabController.animateTo(0);
        },
      ),
    ));
  }

  void _showShareOptions(BuildContext context, FirebaseTrip trip) {
    final primary = Theme.of(context).colorScheme.primary;
    final shareText = '我的行程：${trip.title}\n${trip.dateDisplay}\n${trip.spots.length} 個景點\n\n透過「探索諸羅」App 查看更多嘉義旅遊資訊！';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('分享行程', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _shareOptIcon(Icons.ios_share_rounded, '系統\n分享', primary, () {
              Navigator.pop(context);
              Share.share(shareText);
            }),
            _shareOptIcon(Icons.link_rounded, '複製\n連結', const Color(0xFF8FBF8F), () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: shareText));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('已複製到剪貼簿'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ));
            }),
            _shareOptIcon(Icons.group_rounded, '發布到\n社群', AppColors.accentTerra, () {
              Navigator.pop(context);
              // Navigate to create post
            }),
            _shareOptIcon(Icons.edit_rounded, '邀請\n共編', AppColors.accentSand, () {}),
          ]),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _shareOpt(String icon, String label, Color color) => GestureDetector(
    child: Column(children: [
      Container(width: 58, height: 58,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 26)))),
      const SizedBox(height: 7),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4)),
    ]),
  );

  Widget _shareOptIcon(IconData icon, String label, Color color, [VoidCallback? onTap]) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(width: 58, height: 58,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Icon(icon, size: 28, color: color))),
      const SizedBox(height: 7),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4)),
    ]),
  );
}

// ── Models ──
class _CandidateSpot {
  final Spot spot;
  _CandidateSpot({required this.spot});
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TRIP DETAIL PAGE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ── Trip Detail Page（參考圖：行程概覽 | 地圖模式 + Day 選擇器 + 時間軸）──
class _TripDetailPage extends StatefulWidget {
  final FirebaseTrip trip;
  const _TripDetailPage({required this.trip});
  @override
  State<_TripDetailPage> createState() => _TripDetailPageState();
}

// Alias used by _showFirebaseTripDetail
typedef _FirebaseTripDetailPage = _TripDetailPage;

class _TripDetailPageState extends State<_TripDetailPage>
    with SingleTickerProviderStateMixin {
  int _selectedDay = 0;
  late final TabController _tabCtrl;
  late final PageController _pageCtrl;
  bool _programmaticPageChange = false;

  // 即時行程資料（由 tripDocStream 更新，候選加入後概覽自動刷新）
  late FirebaseTrip _trip;
  StreamSubscription<FirebaseTrip?>? _tripSub;
  // 候選景點快取（在概覽顯示「待加入」提示）
  List<Map<String, dynamic>> _pendingCandidates = [];
  StreamSubscription<List<Map<String, dynamic>>>? _candidatesSub;

  // 概覽：使用者自訂時間 + 景點排序 + 預算
  final Map<String, String> _spotTimes   = {};
  final Map<String, int>    _spotBudgets = {};
  List<String> _orderedSpots = [];

  // 地圖：日期篩選（null = 全部, 0 = Day1, 1 = Day2, ...）
  int? _mapDayFilter;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _tabCtrl = TabController(length: 4, vsync: this);
    _pageCtrl = PageController();
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) return;
      _programmaticPageChange = true;
      _pageCtrl.animateToPage(_tabCtrl.index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)
        .then((_) => _programmaticPageChange = false);
    });

    _orderedSpots = List<String>.from(widget.trip.spots);
    // 從 Firebase 讀取已存的時間 / 預算
    _spotTimes.addAll(widget.trip.spotTimes);
    _spotBudgets.addAll(widget.trip.spotBudgets);

    // 監聽行程文件 → 景點加入後概覽即時更新
    _tripSub = TripService.tripDocStream(widget.trip.id).listen((t) {
      if (t != null && mounted) setState(() {
        _trip = t;
        for (final s in t.spots) {
          if (!_orderedSpots.contains(s)) _orderedSpots.add(s);
        }
        _orderedSpots.removeWhere((s) => !t.spots.contains(s));
        // 同步 Firebase 的時間設定（只補沒有的）
        for (final e in t.spotTimes.entries) {
          _spotTimes.putIfAbsent(e.key, () => e.value);
        }
      });
    });
    // 監聽候選景點 → 在概覽底部顯示「待加入」預覽
    _candidatesSub = TripService.tripCandidatesStream(widget.trip.id).listen((items) {
      if (mounted) setState(() => _pendingCandidates = items);
    });
  }

  @override
  void dispose() {
    _tripSub?.cancel();
    _candidatesSub?.cancel();
    _tabCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip    = _trip;   // 用即時資料（由 tripDocStream 更新）
    final primary = Theme.of(context).colorScheme.primary;

    final totalSpots = trip.spots.length;
    final days = trip.days.clamp(1, 99);
    final spotsPerDay = totalSpots == 0 ? 1
        : (totalSpots / days).ceil().clamp(1, totalSpots);
    final daySpots = List.generate(days, (d) {
      if (totalSpots == 0) return <String>[];
      final start = (d * spotsPerDay).clamp(0, totalSpots);
      final end   = ((d + 1) * spotsPerDay).clamp(0, totalSpots);
      return trip.spots.sublist(start, end);
    });

    // Build the user's real avatar
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: Flexible(child: Text(trip.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          overflow: TextOverflow.ellipsis)),
        actions: [
          // Member avatars (overlapping circles)
          GestureDetector(
            onTap: () => _showMembersSheet(context, trip, primary),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 14,
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  backgroundColor: primary.withValues(alpha: 0.15),
                  child: user?.photoURL == null
                      ? Text(user?.displayName?.isNotEmpty == true ? user!.displayName![0] : '?',
                          style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w800))
                      : null),
                Container(
                  margin: const EdgeInsets.only(left: 2),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primary.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.white, width: 1.5)),
                  child: Icon(Icons.add_rounded, size: 12, color: primary)),
              ]),
            ),
          ),
          IconButton(
            icon: Icon(Icons.share_rounded, color: primary, size: 18),
            tooltip: '分享邀請',
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: () => _showInviteSheet(context, trip, primary)),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        // ── Silky animated tab bar ──────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: primary,
            unselectedLabelColor: AppColors.textHint,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2.5,
            dividerHeight: 0,
            tabs: const [
              Tab(text: '概覽', height: 36),
              Tab(text: '地圖', height: 36),
              Tab(text: '候選', height: 36),
              Tab(text: '記帳', height: 36),
            ],
          ),
        ),

        // ── Day timeline (horizontal date ribbon) ───────────────
        if (_tabCtrl.index == 0 && days > 1)
          Container(
            height: 46,
            color: AppColors.surface,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              itemCount: days,
              itemBuilder: (_, d) {
                final selected = d == _selectedDay;
                final dayDate = trip.startDate.add(Duration(days: d));
                final weekday = ['日','一','二','三','四','五','六'][dayDate.weekday % 7];
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = d),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    width: 44,
                    decoration: BoxDecoration(
                      color: selected ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(12)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(weekday,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                            color: selected ? Colors.white70 : AppColors.textHint)),
                      Text('${dayDate.day}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : AppColors.textPrimary)),
                    ]),
                  ),
                );
              },
            ),
          ),

        // ── Swipeable content ───────────────────────────────────
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            onPageChanged: (i) {
              if (!_programmaticPageChange) _tabCtrl.animateTo(i);
              setState(() {});
            },
            children: [
              _buildScheduleList(daySpots[_selectedDay.clamp(0, daySpots.length - 1)], primary),
              _buildMapMode(primary, trip),
              _buildCandidatesTab(primary, trip),
              _buildExpenseTab(primary, trip),
            ],
          ),
        ),
      ]),
    );
  }

  void _showIconPicker(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // 預設圖標列表（保留供快速選擇）
    const presetIcons = [
      '🗺️','✈️','🚂','🏖️','🏔️','🌸','🍜','🎡','🏯','🌃',
      '🏝️','🎭','⛷️','🤿','🎪','🌄','🏕️','🎒','🚗','🚢',
      '🐾','🎵','📸','🍦','🏊','🎨','🌅','🛺','🦋','🌿',
    ];
    final customCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
              Text('選擇行程圖標', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
              const SizedBox(height: 4),
              Text('選擇預設圖標，或輸入任意文字 / 符號自訂',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              const SizedBox(height: 14),
              // 自訂輸入
              Row(children: [
                Expanded(child: TextField(
                  controller: customCtrl,
                  maxLength: 4,
                  decoration: InputDecoration(
                    hintText: '輸入任意圖標，例如：⛩️ 或「海」',
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primary)),
                  ),
                )),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final val = customCtrl.text.trim();
                    if (val.isEmpty) return;
                    await TripService.setIcon(widget.trip.id, val);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  child: const Text('套用'),
                ),
              ]),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text('快速選擇', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textHint)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 6, shrinkWrap: true,
                childAspectRatio: 1,
                physics: const NeverScrollableScrollPhysics(),
                children: presetIcons.map((emoji) => GestureDetector(
                  onTap: () async {
                    await TripService.setIcon(widget.trip.id, emoji);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: widget.trip.icon == emoji
                          ? primary.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: widget.trip.icon == emoji
                          ? Border.all(color: primary) : Border.all(color: Colors.transparent),
                    ),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
                  ),
                )).toList(),
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _showTripActionSheet(BuildContext context, Color primary) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          // Candidates
          _actionTile(context, Icons.list_alt_rounded, '候選清單', '為這趟行程管理想去的景點', primary,
            () { Navigator.pop(context); _showTripCandidatesSheet(context, primary); }),
          const Divider(height: 1),
          // Add spot to schedule
          _actionTile(context, Icons.add_location_alt_outlined, '加入景點到行程', '直接加入時間軸', primary, () => Navigator.pop(context)),
          const Divider(height: 1),
          // Expense
          _actionTile(context, Icons.receipt_long_outlined, '行程記帳', '記錄這趟旅程的花費', primary, () => Navigator.pop(context)),
        ]),
      ),
    );
  }

  Widget _actionTile(BuildContext ctx, IconData icon, String title, String subtitle, Color primary, VoidCallback onTap) {
    return ListTile(
      leading: Container(width: 40, height: 40,
        decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: primary, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
      onTap: onTap,
    );
  }

  void _showTripCandidatesSheet(BuildContext context, Color primary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Text('候選清單', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: primary)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    await TripService.convertCandidatesToSpots(widget.trip.id);
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('候選景點已加入行程 ✅'),
                      backgroundColor: primary, behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                  },
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: const Text('全部加入行程'),
                  style: OutlinedButton.styleFrom(foregroundColor: primary, side: BorderSide(color: primary)),
                ),
              ])),
            Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: TripService.tripCandidatesStream(widget.trip.id),
              builder: (ctx, snap) {
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.playlist_add_rounded, size: 48, color: AppColors.textHint.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    const Text('還沒有候選景點', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    const Text('在地圖或收藏景點加入', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                  ]));
                }
                return ReorderableListView.builder(
                  scrollController: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  onReorder: (o, n) async {
                    if (n > o) n--;
                    final ids = items.map((m) => m['spotId'].toString()).toList();
                    final id = ids.removeAt(o);
                    ids.insert(n, id);
                    await TripService.reorderTripCandidates(widget.trip.id, ids);
                  },
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return Container(
                      key: ValueKey(item['spotId']),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceWarm,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider)),
                      child: Row(children: [
                        Container(width: 26, height: 26,
                          decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Text('${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)))),
                        const SizedBox(width: 12),
                        Expanded(child: Text(item['spotName']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 18),
                          onPressed: () => TripService.removeTripCandidate(widget.trip.id, item['spotId'].toString())),
                        const Icon(Icons.drag_handle_rounded, color: AppColors.textHint, size: 20),
                      ]),
                    );
                  },
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  // (Unused — kept for compatibility; TabBar replaces these)
  // ignore: unused_element
  Widget _viewTab(String label, int idx, Color primary) {
    final selected = _tabCtrl.index == idx;
    return GestureDetector(
      onTap: () => _tabCtrl.animateTo(idx),
      child: Column(children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
            color: selected ? primary : AppColors.textHint),
          child: Text(label),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 2.5, width: selected ? 52 : 0,
          decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2)),
        ),
      ]),
    );
  }

  // ignore: unused_element
  Widget _pillTab(String label, int idx, Color primary) {
    final sel = _tabCtrl.index == idx;
    return Expanded(child: GestureDetector(
      onTap: () => _tabCtrl.animateTo(idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: sel ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11)),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel ? Colors.white : AppColors.textHint)),
      ),
    ));
  }

  void _showMembersSheet(BuildContext ctx, FirebaseTrip trip, Color primary) {
    final user = FirebaseAuth.instance.currentUser;
    showModalBottomSheet(
      context: ctx, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          Text('行程成員', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: primary)),
          const SizedBox(height: 16),
          ListTile(
            leading: CircleAvatar(radius: 20,
              backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              backgroundColor: primary.withValues(alpha: 0.15),
              child: user?.photoURL == null
                  ? Text(user?.displayName?.isNotEmpty == true ? user!.displayName![0] : '?',
                      style: TextStyle(fontSize: 16, color: primary, fontWeight: FontWeight.w800))
                  : null),
            title: Text(user?.displayName ?? '我',
              style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('行程建立者', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Text('管理員', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
            ),
          ),
          const Divider(height: 24),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () { Navigator.pop(ctx); _showInviteSheet(ctx, trip, primary); },
            icon: const Icon(Icons.person_add_rounded, size: 16),
            label: const Text('邀請成員加入'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          )),
        ]),
      ),
    );
  }

  void _showInviteSheet(BuildContext ctx, FirebaseTrip trip, Color primary) {
    final shareText = '加入我的行程「${trip.title}」！\n${trip.dateDisplay}\n\n透過「探索諸羅」App 一起規劃旅行！';
    showModalBottomSheet(
      context: ctx, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          Text('邀請加入行程', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: primary)),
          const SizedBox(height: 6),
          Text('「${trip.title}」', style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _inviteOpt(Icons.qr_code_rounded, 'QR Code', primary, () {
              Navigator.pop(ctx);
              _showQRDialog(ctx, shareText, primary);
            }),
            _inviteOpt(Icons.link_rounded, '複製連結', primary, () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: shareText));
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: const Text('已複製邀請連結'),
                behavior: SnackBarBehavior.floating, backgroundColor: primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
            }),
            _inviteOpt(Icons.ios_share_rounded, '系統分享', primary, () {
              Navigator.pop(ctx);
              Share.share(shareText);
            }),
          ]),
        ]),
      ),
    );
  }

  Widget _inviteOpt(IconData icon, String label, Color primary, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Column(children: [
      Container(width: 56, height: 56,
        decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, size: 26, color: primary)),
      const SizedBox(height: 6),
      Text(label, style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
    ]));
  }

  void _showQRDialog(BuildContext ctx, String text, Color primary) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('掃描加入行程', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
        const SizedBox(height: 16),
        Container(
          width: 200, height: 200,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primary.withValues(alpha: 0.2))),
          child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.qr_code_2_rounded, size: 120, color: primary),
            const SizedBox(height: 8),
            Text('QR Code 預覽', style: TextStyle(fontSize: 11, color: primary)),
          ])),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () { Navigator.pop(ctx); Share.share(text); },
          child: const Text('分享此邀請'),
        )),
      ]),
    ));
  }

  Widget _buildScheduleList(List<String> spots, Color primary) {
    // ── Empty state ──────────────────────────────────────────
    if (spots.isEmpty && _pendingCandidates.isEmpty) {
      return NotebookBackground(
        lineColor: primary.withValues(alpha: 0.10),
        child: Stack(children: [
          const ScatteredDoodles(),
          Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            DoodleCircle(color: primary.withValues(alpha: 0.18), size: 72,
              child: Icon(Icons.add_location_alt_outlined, size: 32, color: primary.withValues(alpha: 0.5))),
            const SizedBox(height: 14),
            const Text('這天還沒有景點', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('到「候選」頁加入景點', style: TextStyle(fontSize: 12, color: primary.withValues(alpha: 0.6))),
          ])),
        ]),
      );
    }

    const defaultTimes = ['09:00','10:30','13:00','15:00','18:00','20:00'];
    const images = [
      'https://picsum.photos/seed/spot1/120/80',
      'https://picsum.photos/seed/spot2/120/80',
      'https://picsum.photos/seed/spot3/120/80',
      'https://picsum.photos/seed/spot4/120/80',
    ];

    // 用 _orderedSpots 過濾出當天景點，保留排序
    final dayOrdered = _orderedSpots.where(spots.contains).toList();

    return NotebookBackground(
      lineColor: primary.withValues(alpha: 0.10),
      child: Stack(children: [
        const ScatteredDoodles(),
        Column(children: [
          // ── 頁首裝飾 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(children: [
              HandDrawnUnderline(
                color: primary.withValues(alpha: 0.28),
                child: Text('今日行程',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primary)),
              ),
              const Spacer(),
              DoodleHeart(color: primary.withValues(alpha: 0.40), size: 10),
              const SizedBox(width: 4),
              Text('${dayOrdered.length} 個景點  長按可拖排',
                style: TextStyle(fontSize: 10, color: primary.withValues(alpha: 0.55))),
            ]),
          ),

          // ── 可拖排序的景點清單 ────────────────────────────
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              itemCount: dayOrdered.length,
              onReorder: (o, n) {
                if (n > o) n--;
                setState(() {
                  final moved = dayOrdered.removeAt(o);
                  dayOrdered.insert(n, moved);
                  // 把重排後的 dayOrdered 寫回 _orderedSpots
                  for (var i = 0; i < dayOrdered.length; i++) {
                    final globalIdx = _orderedSpots.indexOf(dayOrdered[i]);
                    if (globalIdx != -1) {
                      _orderedSpots.removeAt(globalIdx);
                      _orderedSpots.insert(i, dayOrdered[i]);
                    }
                  }
                });
                HapticFeedback.lightImpact();
                // 儲存排序到 Firebase（debounce-free，直接存）
                TripService.updateSpotOrder(_trip.id, _orderedSpots);
              },
              itemBuilder: (_, i) {
                final name = dayOrdered[i];
                final time = _spotTimes[name] ?? defaultTimes[i % defaultTimes.length];
                final img  = images[i % images.length];
                return _buildScheduleItem(key: ValueKey(name),
                  name: name, time: time, img: img, index: i, primary: primary);
              },
            ),
          ),

          // ── 候選待加入預覽 ───────────────────────────────
          if (_pendingCandidates.isNotEmpty) ...[
            JournalDivider(color: primary, label: '候選待加入'),
            SizedBox(
              height: 44.0 * _pendingCandidates.take(3).length.toDouble(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                children: [
                  ..._pendingCandidates.take(3).map((item) {
                    final nm = item['spotName']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: primary.withValues(alpha: 0.18)),
                        ),
                        child: Row(children: [
                          Icon(Icons.bookmark_border_rounded, size: 13, color: primary.withValues(alpha: 0.45)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(nm,
                            style: TextStyle(fontSize: 12, color: primary.withValues(alpha: 0.60),
                                fontStyle: FontStyle.italic),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text('候選', style: TextStyle(fontSize: 9, color: primary.withValues(alpha: 0.40))),
                        ]),
                      ),
                    );
                  }),
                  if (_pendingCandidates.length > 3)
                    Text('…還有 ${_pendingCandidates.length - 3} 個',
                      style: TextStyle(fontSize: 10, color: primary.withValues(alpha: 0.40))),
                ],
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _buildScheduleItem({
    required Key key,
    required String name,
    required String time,
    required String img,
    required int index,
    required Color primary,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // 可點擊的時間標籤 ──────────────
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: int.tryParse(time.split(':')[0]) ?? 9,
                minute: int.tryParse(time.split(':')[1]) ?? 0,
              ),
            );
            if (picked != null && mounted) {
              final t = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}';
              setState(() => _spotTimes[name] = t);
              TripService.setSpotTime(_trip.id, name, t);
            }
          },
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(time,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: primary)),
          ),
        ),
        const SizedBox(width: 6),
        // 手繪圓點（無連線） ────────────
        DoodleCircle(color: primary.withValues(alpha: 0.50), size: 12,
          child: Container(
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(color: primary, shape: BoxShape.circle))),
        const SizedBox(width: 8),
        // 景點卡片 ──────────────────────
        Expanded(child: GestureDetector(
          onTap: () => _showSpotBudgetSheet(name, primary),
          child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.07),
                blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              // 預算顯示
              Row(children: [
                Icon(Icons.payments_outlined, size: 11, color: primary.withValues(alpha: 0.55)),
                const SizedBox(width: 3),
                Text(
                  _spotBudgets.containsKey(name)
                      ? 'NT\$ ${_spotBudgets[name]}'
                      : '點此設定預算',
                  style: TextStyle(
                    fontSize: 10,
                    color: _spotBudgets.containsKey(name)
                        ? primary : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  )),
              ]),
            ])),
            if (index % 2 == 0) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(img, width: 52, height: 52, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => SizedBox(width: 52, height: 52,
                    child: Icon(Icons.image_outlined, color: primary.withValues(alpha: 0.3)))),
              ),
            ],
          ]),
          ),
        )),
        // 拖把手
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(Icons.drag_handle_rounded, color: AppColors.textHint, size: 18)),
      ]),
    );
  }

  static const _kChiayiCenter = LatLng(23.480, 120.449);

  Future<void> _openNavigation(String spotName) async {
    final spot = _lookupSpot(spotName);

    // 策略 1：geo: 導航 URI（Android 原生 + Google Maps App 均支援）
    if (spot != null) {
      final geoUri = Uri.parse(
          'geo:${spot.lat},${spot.lng}'
          '?q=${spot.lat},${spot.lng}(${Uri.encodeComponent(spotName)})');
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    // 策略 2：Google Maps 網頁路線規劃（有座標）
    if (spot != null) {
      final webNav = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${spot.lat},${spot.lng}'
        '&travelmode=driving',
      );
      if (await canLaunchUrl(webNav)) {
        await launchUrl(webNav, mode: LaunchMode.externalApplication);
        return;
      }
      // fallback：在 App 內開啟網頁
      await launchUrl(webNav, mode: LaunchMode.inAppWebView);
      return;
    }

    // 策略 3：Google Maps 名稱搜尋
    final searchUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent('$spotName 嘉義')}',
    );
    if (await canLaunchUrl(searchUri)) {
      await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(searchUri, mode: LaunchMode.inAppWebView);
    }
  }

  // 座標查詢（精確 → 模糊 → 嘉義市區佔位）
  static Spot? _lookupSpot(String name) {
    try { return DummyData.spots.firstWhere((s) => s.name == name); } catch (_) {}
    try { return DummyData.spots.firstWhere(
      (s) => s.name.contains(name) || name.contains(s.name)); } catch (_) {}
    return null;
  }

  static const _kFallbackLats = [23.480, 23.483, 23.477, 23.486, 23.474];
  static const _kFallbackLngs = [120.449, 120.453, 120.444, 120.458, 120.441];

  List<LatLng> _spotsToLatLngs(List<String> names) {
    int fbIdx = 0;
    return names.map((name) {
      final s = _lookupSpot(name);
      if (s != null) return LatLng(s.lat, s.lng);
      final pt = LatLng(_kFallbackLats[fbIdx % _kFallbackLats.length],
                        _kFallbackLngs[fbIdx % _kFallbackLngs.length]);
      fbIdx++;
      return pt;
    }).toList();
  }

  Widget _buildMapMode(Color primary, FirebaseTrip trip) {
    final days = trip.days.clamp(1, 99);
    final totalSpots = trip.spots.length;
    final spotsPerDay = totalSpots == 0 ? 1
        : (totalSpots / days).ceil().clamp(1, totalSpots);

    // ── 根據日期篩選器決定顯示哪些景點（用 _orderedSpots）──────
    // 確保 _orderedSpots 包含所有 trip.spots（可能因 Firebase 更新而增加）
    final effectiveOrder = _orderedSpots.isNotEmpty
        ? _orderedSpots.where(trip.spots.contains).toList()
        : List<String>.from(trip.spots);

    final List<String> filteredNames;
    if (_mapDayFilter == null) {
      filteredNames = effectiveOrder;
    } else {
      final d = _mapDayFilter!;
      final start = (d * spotsPerDay).clamp(0, effectiveOrder.length);
      final end   = ((d + 1) * spotsPerDay).clamp(0, effectiveOrder.length);
      filteredNames = effectiveOrder.isEmpty ? [] : effectiveOrder.sublist(start, end);
    }

    final spotLatLngs = _spotsToLatLngs(filteredNames);

    final mapCenter = spotLatLngs.isNotEmpty
        ? LatLng(
            spotLatLngs.map((p) => p.latitude).reduce((a, b) => a + b) / spotLatLngs.length,
            spotLatLngs.map((p) => p.longitude).reduce((a, b) => a + b) / spotLatLngs.length,
          )
        : _kChiayiCenter;

    return Column(children: [
      // ── 日期篩選器 Chip 列 ──────────────────────────────────
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          children: [
            // 全部
            _mapFilterChip('全部', _mapDayFilter == null, primary,
                () => setState(() => _mapDayFilter = null)),
            const SizedBox(width: 6),
            // 各天
            ...List.generate(days, (d) {
              final dayDate = trip.startDate.add(Duration(days: d));
              final label = '${dayDate.month}/${dayDate.day}';
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _mapFilterChip('Day ${d + 1}  $label',
                    _mapDayFilter == d, primary,
                    () => setState(() => _mapDayFilter = d)),
              );
            }),
          ],
        ),
      ),
      // ── Mini-map with polylines ───────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: SketchyBorderBox(
          borderColor: primary.withValues(alpha: 0.30),
          strokeWidth: 1.2,
          seed: trip.id.hashCode,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 210,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: mapCenter,
                  initialZoom: spotLatLngs.length > 1 ? 13.5 : 13.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag)),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.chiayicity.explore_chiayi',
                    maxZoom: 18),
                  // ── 景點連線 ──
                  if (spotLatLngs.length > 1)
                    PolylineLayer(polylines: [
                      Polyline(
                        points: spotLatLngs,
                        color: primary.withValues(alpha: 0.55),
                        strokeWidth: 2.8,
                      ),
                    ]),
                  // ── 編號 Marker ──
                  MarkerLayer(markers: [
                    ...List.generate(spotLatLngs.length, (i) => Marker(
                      point: spotLatLngs[i],
                      width: 30, height: 36,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.40), blurRadius: 6)]),
                          child: Center(child: Text('${i + 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)))),
                        Container(width: 2, height: 5, color: primary),
                      ]),
                    )),
                  ]),
                ],
              ), // FlutterMap
            ), // SizedBox
          ), // ClipRRect
        ), // SketchyBorderBox
      ), // Padding
      // ── Spot count label ──────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Row(children: [
          DoodleHeart(color: primary.withValues(alpha: 0.60), size: 11),
          const SizedBox(width: 5),
          Text('${filteredNames.length} 個景點', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary)),
          const Spacer(),
          Text('點導航可開啟 Google Maps', style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
        ]),
      ),
      // ── Spot list with real navigation ────────────────────
      Expanded(
        child: filteredNames.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_location_alt_outlined, size: 48, color: primary.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(_mapDayFilter != null ? '這天還沒有景點' : '還沒有景點',
                    style: const TextStyle(color: AppColors.textHint)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: filteredNames.length,
                itemBuilder: (ctx, i) {
                  final spotName = filteredNames[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
                    child: Row(children: [
                      Container(width: 28, height: 28,
                        decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(9)),
                        child: Center(child: Text('${i+1}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(spotName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary))),
                      GestureDetector(
                        onTap: () => _openNavigation(spotName),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.navigation_rounded, size: 13, color: primary),
                            const SizedBox(width: 3),
                            Text('導航', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ]),
                  );
                }),
      ),
    ]);
  }

  /// 景點預算輸入 bottom sheet
  void _showSpotBudgetSheet(String spotName, Color primary) {
    final ctrl = TextEditingController(
        text: _spotBudgets.containsKey(spotName)
            ? '${_spotBudgets[spotName]}' : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(spotName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('設定此景點的預算', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                prefixText: 'NT\$ ',
                hintText: '例如：500',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primary, width: 2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () {
                  setState(() => _spotBudgets.remove(spotName));
                  TripService.setSpotBudget(_trip.id, spotName, 0);
                  Navigator.pop(context);
                },
                child: const Text('清除'),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () {
                  final v = int.tryParse(ctrl.text.trim());
                  if (v != null && v > 0) {
                    setState(() => _spotBudgets[spotName] = v);
                    TripService.setSpotBudget(_trip.id, spotName, v);
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: primary),
                child: const Text('儲存', style: TextStyle(color: Colors.white)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _mapFilterChip(String label, bool active, Color primary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? primary : AppColors.divider),
          boxShadow: active
              ? [BoxShadow(color: primary.withValues(alpha: 0.25), blurRadius: 6)]
              : [],
        ),
        child: Text(label,
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  // ── Candidates tab ─────────────────────────────────────────
  Widget _buildCandidatesTab(Color primary, FirebaseTrip trip) {
    final days = trip.days.clamp(1, 99);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          HandDrawnUnderline(
            color: primary.withValues(alpha: 0.28),
            child: Text('候選景點', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primary)),
          ),
          const Spacer(),
          DoodleHeart(color: primary.withValues(alpha: 0.35), size: 9),
        ]),
      ),
      StitchedBox(
        color: primary.withValues(alpha: 0.04),
        stitchColor: primary.withValues(alpha: 0.25),
        radius: 12,
        inset: 4, dashWidth: 4, dashGap: 3,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          DoodleLightning(color: primary.withValues(alpha: 0.6), size: 10),
          const SizedBox(width: 8),
          Expanded(child: Text('長按拖移排序，點 ＋ 按鈕加入指定天的行程',
            style: TextStyle(fontSize: 11, color: primary, height: 1.3))),
          DoodleHeart(color: primary.withValues(alpha: 0.40), size: 9),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: TripService.tripCandidatesStream(trip.id),
        builder: (ctx, snap) {
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.playlist_add_rounded, size: 48, color: primary.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              const Text('還沒有候選景點', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('在收藏景點中按「+行程」', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            ]));
          }
          return Column(children: [
            Expanded(child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: items.length,
              onReorder: (o, n) async {
                if (n > o) n--;
                final ids = items.map((m) => m['spotId'].toString()).toList();
                final id = ids.removeAt(o);
                ids.insert(n, id);
                await TripService.reorderTripCandidates(trip.id, ids);
              },
              itemBuilder: (_, i) {
                final item = items[i];
                final spotName = item['spotName']?.toString() ?? '';
                return StitchedBox(
                  key: ValueKey(item['spotId']),
                  color: Colors.white,
                  stitchColor: primary.withValues(alpha: 0.22),
                  radius: 14, inset: 4, dashWidth: 4, dashGap: 3.5,
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.06), blurRadius: 6)],
                  child: Row(children: [
                    DoodleCircle(color: primary.withValues(alpha: 0.50), size: 28,
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                        child: Center(child: Text('${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(spotName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    // Add to specific day
                    SizedBox(
                      height: 30,
                      child: PopupMenuButton<int>(
                        icon: Icon(Icons.add_circle_outline_rounded, size: 20, color: primary),
                        tooltip: '加入行程',
                        padding: EdgeInsets.zero,
                        itemBuilder: (_) => List.generate(days, (d) {
                          final dayDate = trip.startDate.add(Duration(days: d));
                          return PopupMenuItem(value: d,
                            child: Text('Day ${d+1} (${dayDate.month}/${dayDate.day})'));
                        }),
                        onSelected: (d) async {
                          await TripService.addSpotToTrip(trip.id, spotName);
                          await TripService.removeTripCandidate(trip.id, item['spotId'].toString());
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('「$spotName」已加入 Day ${d+1}'),
                            backgroundColor: primary, behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textHint),
                      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                      padding: EdgeInsets.zero,
                      onPressed: () => TripService.removeTripCandidate(trip.id, item['spotId'].toString())),
                    const Icon(Icons.drag_handle_rounded, color: AppColors.textHint, size: 18),
                  ]),
                ); // StitchedBox
              },
            )),
            // Batch add all button
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () async {
                    await TripService.convertCandidatesToSpots(trip.id);
                    if (mounted) {
                      _tabCtrl.animateTo(0);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('全部候選景點已加入行程'),
                        backgroundColor: primary, behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                    }
                  },
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                  label: const Text('全部加入行程'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                )),
              ),
          ]);
        },
      )),
    ]);
  }

  Widget _buildExpenseTab(Color primary, FirebaseTrip trip) {
    return ExpenseScreen(embedded: true, tripId: trip.id);
  }
}

// ── AI Days Slider Widget ──
class _AIDaysSlider extends StatefulWidget {
  const _AIDaysSlider();
  @override
  State<_AIDaysSlider> createState() => _AIDaysSliderState();
}

class _AIDaysSliderState extends State<_AIDaysSlider> {
  double _days = 2;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return Column(children: [
      Row(children: [
        const Text('1天', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
        Expanded(
          child: Slider(
            value: _days,
            min: 1,
            max: 14,
            divisions: 13,
            label: '${_days.round()} 天',
            activeColor: primary,
            onChanged: (v) => setState(() => _days = v),
          ),
        ),
        const Text('14天', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
      ]),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: mist,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_today_rounded, size: 14, color: primary),
          const SizedBox(width: 6),
          Text('已選擇：${_days.round()} 天',
            style: TextStyle(fontWeight: FontWeight.w800, color: primary, fontSize: 14)),
        ]),
      ),
    ]);
  }
}

// ── Trip Detail Edit Stop ──
extension _TripDetailEdit on _TripDetailPageState {
  void _showEditStop(BuildContext ctx, int idx, Map<String, String> s) {
    final costCtrl = TextEditingController(text: s['cost'] ?? '');
    final noteCtrl = TextEditingController(text: s['note'] ?? '');
    showModalBottomSheet(
      context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('編輯：${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            TextField(controller: costCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '預估花費（元）',
                prefixIcon: Icon(Icons.payments_outlined, size: 18),
                hintText: '例如：500')),
            const SizedBox(height: 12),
            TextField(controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '備註 / 注意事項',
                prefixIcon: Icon(Icons.note_outlined, size: 18),
                hintText: '例如：建議早點到、需要預約...')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                s['cost'] = costCtrl.text;
                s['note'] = noteCtrl.text;
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              child: const Text('儲存'),
            ),
          ]),
        ),
      ),
    );
  }

  void _showTimePicker(BuildContext ctx, int idx, Map<String, String> s) async {
    final picked = await showTimePicker(
      context: ctx,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: '設定到達時間',
      builder: (ctx, child) => child!,
    );
    if (picked != null) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        s['time'] = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}';
      });
    }
  }
}

// ── Change Cover Image ──
void _showChangeCover(BuildContext ctx) {
  final covers = [
    'https://picsum.photos/seed/cover1/600/200',
    'https://picsum.photos/seed/cover2/600/200',
    'https://picsum.photos/seed/cover3/600/200',
    'https://picsum.photos/seed/alishan/600/200',
    'https://picsum.photos/seed/chiayi/600/200',
    'https://picsum.photos/seed/food/600/200',
  ];
  showModalBottomSheet(
    context: ctx, backgroundColor: Colors.transparent,
    builder: (_) => Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('選擇封面圖片', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: covers.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: 160, margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(covers[i], fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceMoss)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: const Text('從相簿選取'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
        ),
      ]),
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CREATE TRIP PAGE — Firebase 儲存，有日曆日期選擇器
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _CreateTripPage extends StatefulWidget {
  final VoidCallback? onCreated;
  const _CreateTripPage({this.onCreated});
  @override
  State<_CreateTripPage> createState() => _CreateTripPageState();
}

class _CreateTripPageState extends State<_CreateTripPage> {
  final _titleCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedIcon = '🗺️';
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: '選擇開始日期',
    );
    if (d != null) {
      setState(() {
        _startDate = d;
        if (_endDate != null && _endDate!.isBefore(d)) _endDate = d;
      });
    }
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: _startDate ?? DateTime(2024),
      lastDate: DateTime(2030),
      helpText: '選擇結束日期',
    );
    if (d != null) setState(() => _endDate = d);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入行程名稱'), behavior: SnackBarBehavior.floating));
      return;
    }
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請選擇開始日期'), behavior: SnackBarBehavior.floating));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先登入'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _saving = true);
    try {
      await TripService.createTrip(
        title: _titleCtrl.text.trim(),
        startDate: _startDate!,
        endDate: _endDate,
        icon: _selectedIcon,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated?.call();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('行程「${_titleCtrl.text.trim()}」建立成功'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('建立失敗: $e'), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '點擊選擇';
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('建立新行程', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('建立', style: TextStyle(fontWeight: FontWeight.w800, color: primary, fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 行程名稱
          // ── 圖標選擇 ──────────────────────────────────────────
          Row(children: [
            GestureDetector(
              onTap: () {
                final icons = ['🗺️','✈️','🚂','🏖️','🏔️','🌸','🍜','🎡','🏯','🌃',
                               '🏝️','🎭','⛷️','🤿','🎪','🌄','🏕️','🎒','🚗','🚢'];
                showModalBottomSheet(
                  context: context, backgroundColor: Colors.transparent,
                  builder: (_) => Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('選擇圖標', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: icons.map((e) => GestureDetector(
                        onTap: () { setState(() => _selectedIcon = e); Navigator.pop(context); },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _selectedIcon == e ? primary.withValues(alpha: 0.12) : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                            border: _selectedIcon == e ? Border.all(color: primary) : null),
                          child: Text(e, style: const TextStyle(fontSize: 26))),
                      )).toList()),
                    ]),
                  ),
                );
              },
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withValues(alpha: 0.2))),
                child: Center(child: Text(_selectedIcon, style: const TextStyle(fontSize: 28))),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: TextField(
              controller: _titleCtrl,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: '行程名稱（例如：嘉義三日遊）',
                hintStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textHint),
                border: InputBorder.none, filled: false),
            )),
          ]),
          const Divider(height: 24),

          // 日期選擇
          const Text('行程日期', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _DatePickerTile(
              label: '開始日期',
              value: _formatDate(_startDate),
              icon: Icons.flight_takeoff_rounded,
              primary: primary,
              onTap: _pickStart,
              isSet: _startDate != null,
            )),
            const SizedBox(width: 12),
            Expanded(child: _DatePickerTile(
              label: '結束日期',
              value: _formatDate(_endDate),
              icon: Icons.flight_land_rounded,
              primary: primary,
              onTap: _pickEnd,
              isSet: _endDate != null,
              subtitle: _endDate == null ? '選填，單日行程可不填' : null,
            )),
          ]),

          if (_startDate != null && _endDate != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.calendar_month_rounded, size: 16, color: primary),
                const SizedBox(width: 8),
                Text(
                  '共 ${_endDate!.difference(_startDate!).inDays + 1} 天行程',
                  style: TextStyle(fontWeight: FontWeight.w800, color: primary, fontSize: 15),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            '建立行程後，可在行程詳細頁面加入景點，或在候選清單轉換為行程。',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.6),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : const Text('建立行程', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color primary;
  final VoidCallback onTap;
  final bool isSet;
  final String? subtitle;

  const _DatePickerTile({
    required this.label, required this.value, required this.icon,
    required this.primary, required this.onTap, required this.isSet,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSet ? primary.withValues(alpha: 0.06) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSet ? primary.withValues(alpha: 0.35) : AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: isSet ? primary : AppColors.textHint),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: isSet ? primary : AppColors.textHint)),
          ]),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: isSet ? AppColors.textPrimary : AppColors.textHint)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
          ],
        ]),
      ),
    );
  }
}
