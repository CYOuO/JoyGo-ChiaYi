import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';
// dummy_data.dart removed — all spots now use SpotService.cached
import '../widgets/common_widgets.dart';
import '../services/trip_service.dart';
import '../services/local_fav_service.dart';
import '../services/spot_service.dart';
import '../models/spot.dart';
import '../theme/fabric_textures.dart';
import 'calendar_screen.dart';
import 'expense_screen.dart';
import 'community_screen.dart' show CreatePostPage;
import 'ai_planner_screen.dart';
import 'login_page.dart';
import 'map_screen.dart' as from_map;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Trip icon mapping ────────────────────────────────────────
// Maps emoji char OR named key → IconData (backward compat with Firestore)
IconData _tripIconFromKey(String key) {
  switch (key) {
    case 'map':   case '🗺️': return Icons.map_rounded;
    case 'flight':case '✈️': return Icons.flight_rounded;
    case 'train': case '🚂': return Icons.train_rounded;
    case 'beach': case '🏖️': case '🏝️': return Icons.beach_access_rounded;
    case 'mountain': case '🏔️': case '⛰️': case '🌄': return Icons.landscape_rounded;
    case 'flower': case '🌸': return Icons.local_florist_rounded;
    case 'ramen': case '🍜': return Icons.ramen_dining_rounded;
    case 'attractions': case '🎡': return Icons.attractions_rounded;
    case 'castle': case '🏯': case '🏛️': return Icons.account_balance_rounded;
    case 'night': case '🌃': case '🌙': return Icons.nightlight_round;
    case 'theater': case '🎭': return Icons.theater_comedy_rounded;
    case 'ski':   case '⛷️': return Icons.downhill_skiing_rounded;
    case 'camp':  case '🏕️': return Icons.cabin_rounded;
    case 'backpack': case '🎒': return Icons.backpack_rounded;
    case 'car':   case '🚗': return Icons.directions_car_rounded;
    case 'ship':  case '🚢': return Icons.directions_boat_rounded;
    case 'pets':  case '🐾': return Icons.pets_rounded;
    case 'music': case '🎵': return Icons.music_note_rounded;
    case 'camera': case '📸': case '📷': return Icons.camera_alt_rounded;
    case 'icecream': case '🍦': return Icons.icecream_rounded;
    case 'pool':  case '🏊': return Icons.pool_rounded;
    case 'palette': case '🎨': return Icons.palette_rounded;
    case 'sunset': case '🌅': return Icons.wb_twilight_rounded;
    case 'festival': case '🎪': return Icons.festival_rounded;
    case 'nature': case '🌿': case '🦋': return Icons.eco_rounded;
    case 'dive':  case '🤿': return Icons.scuba_diving_rounded;
    case 'taxi':  case '🛺': return Icons.local_taxi_rounded;
    default: return Icons.map_rounded;
  }
}

// Preset icons for trip icon picker
const _kTripIconPresets = <(String, IconData)>[
  ('map',         Icons.map_rounded),
  ('flight',      Icons.flight_rounded),
  ('train',       Icons.train_rounded),
  ('beach',       Icons.beach_access_rounded),
  ('mountain',    Icons.landscape_rounded),
  ('flower',      Icons.local_florist_rounded),
  ('ramen',       Icons.ramen_dining_rounded),
  ('attractions', Icons.attractions_rounded),
  ('castle',      Icons.account_balance_rounded),
  ('night',       Icons.nightlight_round),
  ('theater',     Icons.theater_comedy_rounded),
  ('ski',         Icons.downhill_skiing_rounded),
  ('camp',        Icons.cabin_rounded),
  ('backpack',    Icons.backpack_rounded),
  ('car',         Icons.directions_car_rounded),
  ('ship',        Icons.directions_boat_rounded),
  ('pets',        Icons.pets_rounded),
  ('music',       Icons.music_note_rounded),
  ('camera',      Icons.camera_alt_rounded),
  ('icecream',    Icons.icecream_rounded),
  ('pool',        Icons.pool_rounded),
  ('palette',     Icons.palette_rounded),
  ('sunset',      Icons.wb_twilight_rounded),
  ('festival',    Icons.festival_rounded),
  ('nature',      Icons.eco_rounded),
  ('dive',        Icons.scuba_diving_rounded),
  ('taxi',        Icons.local_taxi_rounded),
  ('family',      Icons.family_restroom_rounded),
  ('sports',      Icons.sports_rounded),
  ('photo',       Icons.photo_camera_rounded),
];

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
    // 即時監聽訪客收藏變動（SpotSaveButton 觸發）
    LocalFavService.notifier.addListener(_onGuestFavChanged);
  }

  void _onGuestFavChanged() {
    if (mounted) setState(() => _guestSavedIds = Set<String>.from(LocalFavService.notifier.value));
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
      final matches = SpotService.cached.where((s) => s.id == spotId);
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
        content: Text(context.read<AppSettingsProvider>().l10n.tripSyncMsg),
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
    LocalFavService.notifier.removeListener(_onGuestFavChanged);
    super.dispose();
  }

  void _addToCandidate(Spot s) {
    if (_candidates.any((c) => c.spot.id == s.id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.read<AppSettingsProvider>().l10n.tripAlreadyInList),
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
            Text(context.watch<AppSettingsProvider>().l10n.tripManage,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]);
        }),
        actions: [
          IconButton(
            icon: Icon(Icons.auto_awesome_rounded, color: primary),
            onPressed: () => _openAIPlanner(context),
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyTripsTab(),
          _buildSavedSpotsTab(),
          CalendarScreen(userTrips: _tripsForCalendar),
        ],
      ),
    );
  }

  // ── My Trips ── (uses StreamSubscription, no flicker)
  Widget _buildMyTripsTab() {
    if (_authUser == null) {
      final primary = Theme.of(context).colorScheme.primary;
      return Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.luggage_rounded, size: 38, color: primary.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 20),
          Text(context.watch<AppSettingsProvider>().l10n.tripLoginTitle,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primary)),
          const SizedBox(height: 10),
          Text(context.watch<AppSettingsProvider>().l10n.tripLoginDesc,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: primary.withValues(alpha: 0.65), height: 1.7)),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const LoginPage())),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(context.watch<AppSettingsProvider>().l10n.tripLoginBtn),
            ),
          ),
          const SizedBox(height: 14),
          Text(context.watch<AppSettingsProvider>().l10n.tripGuestHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: primary.withValues(alpha: 0.4), height: 1.5)),
        ]),
      ));
    }
    if (_tripsLoading) {
      return ListView(padding: const EdgeInsets.all(16),
        children: List.generate(3, (_) => const TripCardSkeleton()));
    }
    final trips = _firebaseTrips;
    if (trips.isEmpty) {
      final p = Theme.of(context).colorScheme.primary;
      return IllustratedEmptyState(
        scene: EmptyScene.trip,
        title: context.read<AppSettingsProvider>().l10n.tripNoTrip,
        body: context.read<AppSettingsProvider>().l10n.tripNoTripBody,
        color: p,
        action: ElevatedButton.icon(
          onPressed: () => _showCreateTrip(context),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(context.read<AppSettingsProvider>().l10n.tripCreateBtn),
          style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
      );
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
          _statCard(context.read<AppSettingsProvider>().l10n.tripStatPlanning, '${trips.where((t) => !t.isCompleted).length}', Icons.event_outlined, const Color(0xFFF5EFE6)),
          const SizedBox(width: 10),
          _statCard(context.read<AppSettingsProvider>().l10n.tripStatCompleted, '${trips.where((t) => t.isCompleted).length}', Icons.check_circle_outline_rounded, const Color(0xFFEDF5ED)),
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
                Text(context.read<AppSettingsProvider>().l10n.tripCountdownLabel, style: TextStyle(fontSize: 8, color: primary, fontWeight: FontWeight.w700)),
                Text('$daysLeft', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: primary, height: 1.0)),
                Text(context.read<AppSettingsProvider>().l10n.tripCountdownUnit, style: TextStyle(fontSize: 8, color: primary, fontWeight: FontWeight.w700)),
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
                child: Text(context.read<AppSettingsProvider>().l10n.tripNextTripLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
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
                Text('${trip.spots.where((s) => !s.startsWith('__DAY_')).length} 個景點 · ${trip.days} 天',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios_rounded, size: 9, color: Colors.white60),
                Text(context.read<AppSettingsProvider>().l10n.tripView, style: const TextStyle(color: Colors.white60, fontSize: 11)),
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
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () async {
              await TripService.setCompleted(trip.id, completed: !trip.isCompleted);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(trip.isCompleted ? '已恢復為規劃中' : '「${trip.title}」已完成 ✓'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ));
            },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: trip.isCompleted ? primary.withValues(alpha: 0.12) : AppColors.surfaceMoss,
                shape: BoxShape.circle,
                border: Border.all(
                  color: trip.isCompleted ? primary : AppColors.divider,
                  width: 1.5),
              ),
              child: Icon(
                trip.isCompleted ? Icons.check_rounded : Icons.check_rounded,
                size: 16,
                color: trip.isCompleted ? primary : AppColors.textHint),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => _TripReportPage(trip: trip, primary: primary))),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.auto_stories_rounded, size: 15, color: primary.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(width: 4),
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
                      // 點擊可切換完成狀態
                      GestureDetector(
                        onTap: () async {
                          await TripService.setCompleted(trip.id, completed: !trip.isCompleted);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(trip.isCompleted ? '已恢復為進行中' : '行程已標記完成 ✓'),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: trip.isCompleted ? p : AppColors.accentStraw,
                            borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(trip.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              size: 12, color: trip.isCompleted ? Colors.white : Color.lerp(p, Colors.black, 0.3)!),
                            const SizedBox(width: 4),
                            Text(trip.isCompleted ? '已完成' : '點此完成',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: trip.isCompleted ? Colors.white : Color.lerp(p, Colors.black, 0.3)!)),
                          ]),
                        ),
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
                    Text('${trip.days}天 · ${trip.spots.where((s) => !s.startsWith('__DAY_')).length} 個景點',
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
                      label: Text(context.read<AppSettingsProvider>().l10n.tripViewEdit),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: trip.isCompleted
                      ? OutlinedButton.icon(
                          onPressed: () async {
                            await TripService.setCompleted(trip.id, completed: false);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('「${trip.title}」已恢復為進行中'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ));
                          },
                          icon: const Icon(Icons.undo_rounded, size: 15),
                          label: Text(context.read<AppSettingsProvider>().l10n.tripRestoreProgress),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        )
                      : ElevatedButton.icon(
                          onPressed: () async {
                            await TripService.setCompleted(trip.id, completed: true);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('「${trip.title}」已標記為完成'),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ));
                          },
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                          label: Text(context.read<AppSettingsProvider>().l10n.tripMarkDone),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                      tooltip: '刪除行程',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Text(context.read<AppSettingsProvider>().l10n.tripDeleteTrip, style: const TextStyle(fontWeight: FontWeight.w800)),
                            content: Text(context.read<AppSettingsProvider>().l10n.tripDeleteTitle(trip.title)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.read<AppSettingsProvider>().l10n.cancel)),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(context.read<AppSettingsProvider>().l10n.delete, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && mounted) {
                          await TripService.deleteTrip(trip.id);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('行程已刪除'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      },
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

  void _openAIPlanner(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    List<String> globalSpots = [];
    if (uid != null) {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('candidates').orderBy('order').get();
      globalSpots = snap.docs.map((d) => d['spotName']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }

    final imported = <String, List<String>>{};
    for (var t in _firebaseTrips.where((t) => !t.isCompleted)) {
      // 🌟 保留天數標籤，讓 AI 準確知道原本行程有幾天
      imported[t.title] = t.spots;
    }

    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AIPlannerScreen(
        candidateSpots: globalSpots,
        importedTrips: imported.isNotEmpty ? imported : null,
        // 🌟 明確標示型別 (AiGeneratedTrip, String?) 解決型別報錯
        onSaveTrip: (AiGeneratedTrip aiTrip, String? targetTitle) async {
          List<String> aiSpots = [];
          for (var day in aiTrip.schedule) {
            aiSpots.add('__DAY_${day.day}__');
            for (var item in day.items) {
              if (item.transport == null && !item.isMeal) aiSpots.add(item.name);
            }
          }

          if (targetTitle != null && targetTitle != '一般候選清單') {
            try {
              final targetTrip = _firebaseTrips.firstWhere((t) => t.title == targetTitle);
              await TripService.updateTrip(targetTrip.id, {'spots': aiSpots, 'isCompleted': false});
              
              for (var day in aiTrip.schedule) {
                for (var item in day.items) {
                  if (item.transport == null && !item.isMeal) {
                    await TripService.setSpotTime(targetTrip.id, item.name, item.time);
                  }
                }
              }
            } catch (e) {
              await TripService.createTrip(title: aiTrip.title, startDate: DateTime.now(), spots: aiSpots);
            }
          } else {
            // 新建行程
            await TripService.createTrip(title: aiTrip.title, startDate: DateTime.now(), spots: aiSpots);
          }
        }
      )
    ));
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
            label: Text(context.read<AppSettingsProvider>().l10n.tripAddCandidates),
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
                onPressed: () => _openAIPlanner(context),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(context.read<AppSettingsProvider>().l10n.tripAISchedule),
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
    final catIconData = spot.category == 'restaurant'
        ? Icons.ramen_dining_rounded
        : spot.category == 'youbike'
            ? Icons.pedal_bike_rounded
            : Icons.account_balance_rounded;

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
            Icon(catIconData, size: 22, color: AppColors.textSecondary),
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
                // 使用 FutureBuilder 讀取真實景點
                child: FutureBuilder<List<Spot>>(
                  future: SpotService.loadAllSpots(),
                  builder: (futureCtx, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final spots = snap.data!;
                    return ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: spots.length,
                      itemBuilder: (itemCtx, i) {
                        final s = spots[i];
                        final already = _candidates.any((c) => c.spot.id == s.id);
                        final iconData = s.category == 'restaurant'
                            ? Icons.ramen_dining_rounded
                            : s.category == 'youbike'
                                ? Icons.pedal_bike_rounded
                                : Icons.account_balance_rounded;
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
                            leading: s.imageUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(s.imageUrl, width: 44, height: 44, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(iconData, size: 24, color: AppColors.textSecondary)),
                                  )
                                : Icon(iconData, size: 24, color: AppColors.textSecondary),
                            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Row(children: [
                              const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
                              Flexible(child: Text('  ${s.rating}  ·  ${s.address}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ]),
                            trailing: already
                              ? Icon(Icons.check_circle_rounded, color: p)
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: p, borderRadius: BorderRadius.circular(10)),
                                  child: const Text('加入', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                            onTap: already ? null : () {
                              _addToCandidate(s);
                              setState(() {});
                            },
                          ),
                        );
                      },
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

  // ── Saved spots ── Shows ALL saved spots
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
      // Guest: 用 LocalFavService metadata，不依賴 SpotService.cached
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: LocalFavService.getSavedSpotsData(),
        builder: (ctx, snap) {
          final rawGuest = snap.data ?? [];
          return _savedSpotsGridRaw(
            rawSpots: rawGuest,
            onUnsave: (spotId, spotName) async {
              await LocalFavService.toggleWithMeta(spotId, spotName: spotName);
              if (mounted) setState(() => _guestSavedIds.remove(spotId));
            },
            isGuest: true,
          );
        },
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
      return IllustratedEmptyState(
        scene: EmptyScene.saved,
        title: context.read<AppSettingsProvider>().l10n.tripNoSaved,
        body: isGuest
            ? '點地圖或景點旁的 ♡ 收藏，\n登入後自動同步到你的帳戶'
            : '到地圖或景點詳細頁點 ♡\n收藏後可以快速加入行程！',
        color: primary,
        action: isGuest
            ? OutlinedButton.icon(
                onPressed: () => Navigator.of(context, rootNavigator: true)
                    .push(MaterialPageRoute(builder: (_) => const LoginPage())),
                icon: const Icon(Icons.login_rounded, size: 16),
                label: const Text('立即登入同步'),
              )
            : null,
      );
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
  // ── 偏好 → 景點 category 映射 ────────────────────────────────
  static const _prefCategories = <int, List<String>>{
    0: ['attraction'],
    1: ['restaurant'],
    2: ['attraction', 'restaurant'],
    3: ['attraction'],
    4: ['attraction', 'youbike'],
    5: ['restaurant'],
  };

  // ── 根據偏好從 SpotService 快取過濾推薦景點 ─────────────────────
  List<Spot> _generateSuggestions(Set<int> selected) {
    final allSpots = SpotService.cached;
    if (selected.isEmpty) return allSpots.take(6).toList();
    final categories = selected
        .expand((i) => _prefCategories[i] ?? <String>[])
        .toSet();
    var spots = allSpots
        .where((s) => categories.contains(s.category))
        .toList();
    // 已在候選清單的排到後面
    spots.sort((a, b) {
      final aIn = _candidates.any((c) => c.spot.id == a.id) ? 1 : 0;
      final bIn = _candidates.any((c) => c.spot.id == b.id) ? 1 : 0;
      if (aIn != bIn) return aIn - bIn;
      return b.rating.compareTo(a.rating);
    });
    return spots.take(8).toList();
  }

  // ── 已移至 AIPlannerScreen ─────────────────────────────────
  // ignore: unused_element
  Widget _buildAIPanel_deprecated(BuildContext context) {
    const prefLabels = [
      (Icons.museum_rounded,          '文化歷史'),
      (Icons.ramen_dining_rounded,    '美食探索'),
      (Icons.family_restroom_rounded, '親子友善'),
      (Icons.landscape_rounded,       '自然生態'),
      (Icons.camera_alt_rounded,      '打卡拍照'),
      (Icons.nightlight_round,        '夜間活動'),
    ];
    final Set<int> initialSel = {0, 1};
    return StatefulBuilder(builder: (ctx, setPanel) {
      final selected  = Set<int>.from(initialSel);
      final primary   = Theme.of(ctx).colorScheme.primary;
      final mist      = Color.lerp(primary, Colors.white, 0.88)!;
      final suggested = _generateSuggestions(selected);
      bool generated  = false;

      return StatefulBuilder(builder: (ctx2, setPanel2) {
        return Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: MediaQuery.of(ctx2).size.height * 0.72,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
            ),
            child: Column(children: [
              Container(margin: const EdgeInsets.only(top: 12, bottom: 12),
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('AI 行程助手', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
                    Text('根據偏好推薦嘉義景點', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ]),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
                    onPressed: () => Navigator.pop(context)),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // 候選景點預覽
                    if (_candidates.isNotEmpty) ...[
                      Text('目前候選（${_candidates.length} 個）',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.surfaceMoss,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider)),
                        child: Column(children: _candidates.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Container(width: 20, height: 20,
                              decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                              child: Center(child: Text('${e.key+1}',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
                            const SizedBox(width: 8),
                            Text(e.value.spot.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                          ]),
                        )).toList()),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 偏好選擇
                    const Text('旅遊偏好（可複選）', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8,
                      children: prefLabels.asMap().entries.map((e) {
                        final isSel = selected.contains(e.key);
                        return GestureDetector(
                          onTap: () {
                            setPanel2(() {
                              isSel ? selected.remove(e.key) : selected.add(e.key);
                              generated = false;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? primary : AppColors.surfaceMoss,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isSel ? primary : AppColors.divider)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(e.value.$1, size: 13, color: isSel ? Colors.white : AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(e.value.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: isSel ? Colors.white : AppColors.textSecondary)),
                            ]),
                          ),
                        );
                      }).toList()),
                    const SizedBox(height: 20),

                    // 生成按鈕
                    ElevatedButton.icon(
                      onPressed: () => setPanel2(() => generated = true),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('生成景點建議'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                    ),

                    // 建議景點列表
                    if (generated) ...[
                      const SizedBox(height: 20),
                      Row(children: [
                        const Icon(Icons.recommend_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('為你推薦 ${_generateSuggestions(selected).length} 個景點',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: primary)),
                      ]),
                      const SizedBox(height: 10),
                      ..._generateSuggestions(selected).map((spot) {
                        final alreadyIn = _candidates.any((c) => c.spot.id == spot.id);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: alreadyIn ? mist : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: alreadyIn ? primary.withValues(alpha: 0.3) : AppColors.divider),
                          ),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(spot.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Row(children: [
                                const Icon(Icons.star_rounded, size: 12, color: AppColors.accentStraw),
                                Text(' ${spot.rating.toStringAsFixed(1)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                const SizedBox(width: 8),
                                Text(spot.address, style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ]),
                            ])),
                            const SizedBox(width: 8),
                            alreadyIn
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(10)),
                                  child: Text('已加入', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)))
                              : GestureDetector(
                                  onTap: () { _addToCandidate(spot); setPanel2(() {}); },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(10)),
                                    child: const Text('加入候選', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)))),
                          ]),
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
            ]),
          ),
        );
      });
    });
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
                  Flexible(child: Text(spotName,
                    textWidthBasis: TextWidthBasis.longestLine,
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary,
                      decoration: TextDecoration.underline,
                      decorationColor: primary.withValues(alpha: 0.38),
                      decorationThickness: 2.0,
                    ),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onUnsave(spotId, spotName),
                    child: Icon(Icons.favorite_rounded, size: 14, color: AppColors.error)),
                ])
              else
                Text(spotName,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary,
                    decoration: TextDecoration.underline,
                    decorationColor: primary.withValues(alpha: 0.38),
                    decorationThickness: 2.0,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
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

  // ── 從 Firestore 補讀景點描述（省下重複儲存全部 raw 欄位的需求）──
  static Future<String> _fetchFirestoreDesc(String spotId, String category) async {
    const cols = [
      'restaurants','tdx_spots','good_shops','excellent_restaurants',
      'excellent_drink_shops','pet_friendly_shops','tdx_hotels',
      'parking_lots','gas_stations','aed_locations','facilities',
    ];
    const descKeys = [
      'description','Description','shortDesc','Content','content',
      'descriptionDetail','簡介','產品特色','場所描述','特色介紹','備註','內容',
    ];
    String? col, docId;
    for (final c in cols) {
      if (spotId.startsWith('${c}_')) { col = c; docId = spotId.substring(c.length + 1); break; }
    }
    if (col == null) {
      const catMap = {
        'TDX景點': 'tdx_spots', '好店': 'good_shops', '餐廳': 'excellent_restaurants',
        '飲料店': 'excellent_drink_shops', '寵物友善': 'pet_friendly_shops',
        'chiayiFood': 'restaurants', 'chiayiFood_cat': 'restaurants',
      };
      col = catMap[category]; docId = spotId;
    }
    if (col == null || docId == null || docId.isEmpty) return '';
    try {
      final doc = await FirebaseFirestore.instance.collection(col).doc(docId).get();
      if (!doc.exists) return '';
      final d = doc.data()!;
      for (final k in descKeys) {
        final v = d[k]?.toString().trim() ?? '';
        if (v.length > 5) return v;
      }
    } catch (_) {}
    return '';
  }

  // ── 收藏景點詳情 sheet ────────────────────────────────────
  void _showSavedSpotDetail(
    BuildContext ctx,
    Map<String, dynamic> d,
    Color primary,
    Future<void> Function(String, String) onUnsave,
  ) {
    final spotId      = d['spotId']?.toString() ?? d['__id']?.toString() ?? '';
    final spotName    = d['spotName']?.toString() ?? '';
    final imageUrl    = d['imageUrl']?.toString() ?? '';
    final rating      = (d['rating'] as num?)?.toDouble() ?? 0.0;
    // 從 Firebase saved-spot 文件讀取額外資訊（新版儲存時一起存入）
    final fbDesc      = d['description']?.toString() ?? '';
    final fbAddress   = d['address']?.toString() ?? '';
    final fbCategory  = d['category']?.toString() ?? '';

    // 從 SpotService 快取補充更多資訊（精確 → 名稱 → 模糊）
    Spot? info;
    final cache = SpotService.cached;
    info ??= cache.where((s) => s.id == spotId).firstOrNull;
    info ??= cache.where((s) => s.name == spotName).firstOrNull;
    info ??= cache.where((s) => s.name.contains(spotName) || spotName.contains(s.name)).firstOrNull;

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
              // ── 類別標籤 ─────────────────────────────────────────
              Builder(builder: (_) {
                final cat = info?.category ?? fbCategory;
                if (cat.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(cat,
                      style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700))),
                );
              }),

              // ── 地址 ──────────────────────────────────────────────
              Builder(builder: (_) {
                final addr = info?.address ?? fbAddress;
                if (addr.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(child: Text(addr,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                  ]),
                );
              }),

              // ── 開放時間（SpotService 快取提供）──────────────────
              if (info != null && info.openHours.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Expanded(child: Text(info.openHours,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                ]),
              ],

              // ── 簡介（SpotService → Firebase → Firestore）────────
              FutureBuilder<String>(
                future: (info?.description ?? fbDesc).isNotEmpty
                    ? Future.value(info?.description ?? fbDesc)
                    : _fetchFirestoreDesc(spotId, fbCategory),
                builder: (_, snap) {
                  final desc = snap.data ?? fbDesc;
                  if (snap.connectionState != ConnectionState.done && desc.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))));
                  }
                  if (desc.isEmpty) {
                    final hasAnyInfo = (info?.address ?? fbAddress).isNotEmpty ||
                                       (info?.category ?? fbCategory).isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Divider(height: 16),
                      ]),
                    );
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Divider(height: 24),
                    const Text('關於此景點',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(desc,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.75)),
                  ]);
                }),
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
      isScrollControlled: true, // 🌟 允許自訂高度
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        // 🌟 限制最大高度為螢幕的 80%，避免溢位
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SingleChildScrollView( // 🌟 加入捲動功能
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
            Text('加入行程候選清單', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
            const SizedBox(height: 4),
            Text('「$spotName」將加入選定行程的候選清單',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(height: 14),

            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.accentStraw.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: const Center(child: Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.accentStraw))),
              title: const Text('一般候選清單', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('供 AI 助手全域自動排程使用', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              trailing: Icon(Icons.chevron_right_rounded, color: primary),
              onTap: () async {
                Navigator.pop(context);
                final matches = SpotService.cached.where((s) => s.id == spotId);
                if (matches.isNotEmpty) {
                  _addToCandidate(matches.first);
                } else {
                  TripService.addCandidate(spotId: spotId, spotName: spotName, category: '', order: 0);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('已加入一般候選清單 ✨'),
                    backgroundColor: primary, behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                }
              },
            ),
            const Divider(height: 8),

            ...trips.map((t) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Icon(_tripIconFromKey(t.icon), size: 20, color: primary))),
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
            _shareOpt(Icons.ios_share_rounded, '系統分享', primary, () {
              Navigator.pop(context);
              Share.share(shareText);
            }),
            _shareOpt(Icons.link_rounded, '複製連結', const Color(0xFF8FBF8F), () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: shareText));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('已複製到剪貼簿'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ));
            }),
            _shareOpt(Icons.group_rounded, '發布社群', AppColors.accentTerra, () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => CreatePostPage(
                  primary: Theme.of(context).colorScheme.primary,
                  defaultType: 'trip')));
            }),
            _shareOpt(Icons.edit_rounded, '邀請共編', AppColors.accentSand, () {
              Navigator.pop(context);
              Share.share(
                '邀請你一起共編「${trip.title}」行程！\n${trip.dateDisplay}\n\n透過「探索諸羅」App 一起規劃嘉義旅行！',
                subject: '行程共編邀請',
              );
            }),
          ]),
          const Divider(height: 24),
          // 旅行日報 — 獨立一行，更醒目
          GestureDetector(
            onTap: () { Navigator.pop(context); _showTripReport(context, trip); },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accentSky.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accentSky.withValues(alpha: 0.35))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.auto_stories_rounded, size: 18, color: AppColors.accentSky),
                const SizedBox(width: 8),
                Text('生成旅行日報', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accentSky.withValues(alpha: 0.9))),
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.accentSky.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('可截圖分享', style: TextStyle(fontSize: 9, color: AppColors.accentSky))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  // ── ① 旅行日報卡片 ──────────────────────────────────────────
  void _showTripReport(BuildContext context, FirebaseTrip trip) {
    final primary = Theme.of(context).colorScheme.primary;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _TripReportPage(trip: trip, primary: primary)));
  }

  Widget _shareOpt(IconData icon, String label, Color color, [VoidCallback? onTap]) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(width: 54, height: 54,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Icon(icon, size: 24, color: color))),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, height: 1.4)),
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

  final Map<int, GlobalKey> _dayKeys = {};
  final ScrollController _scheduleScrollCtrl = ScrollController();

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
    // 過濾掉天數標籤，只保留真實景點名稱給地圖/概覽用
    final cleanSpots = trip.spots.where((s) => !s.startsWith('__DAY_')).toList();
    final totalClean = cleanSpots.length;
    final spotsPerDayClean = totalClean == 0 ? 1 : (totalClean / days).ceil().clamp(1, totalClean);
    final daySpots = List.generate(days, (d) {
      if (totalClean == 0) return <String>[];
      final start = (d * spotsPerDayClean).clamp(0, totalClean);
      final end   = ((d + 1) * spotsPerDayClean).clamp(0, totalClean);
      return cleanSpots.sublist(start, end);
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
            icon: Icon(Icons.photo_camera_rounded, color: primary, size: 18),
            tooltip: '更換封面',
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: () => _changeCoverPhoto(context)),
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
                  onTap: () {
                    setState(() => _selectedDay = d);
                    // 🌟 點擊時自動滾動到對應的天數標籤位置
                    final dayMarkerInt = d + 1;
                    final key = _dayKeys[dayMarkerInt];
                    if (key != null && key.currentContext != null) {
                      Scrollable.ensureVisible(
                        key.currentContext!,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                        alignment: 0.02, // 留一點點上方邊距，視覺更舒服
                      );
                    } else if (_scheduleScrollCtrl.hasClients) {
                      // 🌟 備用機制：如果從來沒往下滑過（Context 尚未建立）
                      if (d == 0) {
                        _scheduleScrollCtrl.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
                      } else {
                        // 如果是要往下跳，強制先盲滑一段距離把底下的元件讀取出來
                        _scheduleScrollCtrl.animateTo(
                          _scheduleScrollCtrl.position.pixels + 600,
                          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut
                        );
                      }
                    }
                  },
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
              _buildScheduleList(primary),
              _buildMapMode(primary, trip, daySpots),  // 傳 daySpots，保證天數切割一致
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
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 6, shrinkWrap: true,
                childAspectRatio: 1,
                physics: const NeverScrollableScrollPhysics(),
                children: _kTripIconPresets.map(((String key, IconData icon) preset) => GestureDetector(
                  onTap: () async {
                    await TripService.setIcon(widget.trip.id, preset.$1);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: widget.trip.icon == preset.$1
                          ? primary.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: widget.trip.icon == preset.$1
                          ? Border.all(color: primary) : Border.all(color: Colors.transparent),
                    ),
                    child: Center(child: Icon(preset.$2, size: 24, color: widget.trip.icon == preset.$1 ? primary : AppColors.textSecondary)),
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
                      content: const Text('候選景點已加入行程'),
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
                    Text(context.read<AppSettingsProvider>().l10n.tripNoCandidates, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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

  // ── 更換封面照片 ──────────────────────────────────────────────
  Future<void> _changeCoverPhoto(BuildContext context) async {
    final primary = Theme.of(context).colorScheme.primary;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text('更換封面照片', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.photo_camera_rounded, color: primary),
            title: const Text('拍攝新照片'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded, color: primary),
            title: const Text('從相簿選取'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (file == null || !context.mounted) return;

    // 顯示上傳進度
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 12),
        const Text('正在上傳封面照片...'),
      ]),
      duration: const Duration(seconds: 10),
      behavior: SnackBarBehavior.floating,
    ));

    try {
      final ref = FirebaseStorage.instance
          .ref('trip_covers/${_trip.id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(file.path));
      final url = await ref.getDownloadURL();
      await TripService.updateTrip(_trip.id, {'coverUrl': url});
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('封面已更新 ✓'),
          backgroundColor: primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('上傳失敗，請稍後再試'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showMembersSheet(BuildContext ctx, FirebaseTrip trip, Color primary) {
    final user = FirebaseAuth.instance.currentUser;
    showModalBottomSheet(
      context: ctx, 
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // 允許內容變多時可以滾動
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
          
          // 1. 顯示行程建立者 (自己)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 20,
              backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              backgroundColor: primary.withValues(alpha: 0.15),
              child: user?.photoURL == null
                  ? Text(user?.displayName?.isNotEmpty == true ? user!.displayName![0] : '?',
                      style: TextStyle(fontSize: 16, color: primary, fontWeight: FontWeight.w800))
                  : null),
            title: Text(user?.displayName ?? '我', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('行程建立者', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('管理員', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
            ),
          ),

          // 2. 從資料庫即時拉取其他已加入的旅伴
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('trips').doc(trip.id).collection('companions').orderBy('addedAt').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return Column(
                children: snap.data!.docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final name = (d['name'] ?? '').toString();
                  final photo = (d['photoURL'] ?? d['photoUrl'] ?? '').toString();
                  final status = (d['status'] ?? 'manual').toString();
                  
                  // 顯示狀態標籤
                  final statusLabel = status == 'pending' ? '待確認' : status == 'dummy' ? '虛擬成員' : '同行旅伴';
                  final statusColor = status == 'pending' ? Colors.orange : status == 'dummy' ? Colors.grey : primary;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(radius: 20,
                      backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                      backgroundColor: primary.withValues(alpha: 0.15),
                      child: photo.isEmpty && name.isNotEmpty
                          ? Text(name[0], style: TextStyle(fontSize: 16, color: primary, fontWeight: FontWeight.w800))
                          : Icon(Icons.person_outline, color: primary)),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(statusLabel, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    trailing: status == 'pending' || status == 'dummy' ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700)),
                    ) : null,
                  );
                }).toList(),
              );
            },
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
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(trip: trip, primary: primary),
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

  // ══════════════════════════════════════════════════════════════
  // 1. 自動補齊天數標籤的輔助函式 (🌟 升級版：保證天數完整)
  List<String> _getNormalizedSpots() {
    final spots = _trip.spots;
    if (spots.isEmpty) return [];

    List<String> current = List.from(spots);

    // 🌟 強制過濾掉過去不小心存入的無效景點
    current.removeWhere((s) => 
      s == '交通' || s.startsWith('前往') || s.startsWith('搭乘') || 
      s.startsWith('步行') || s.startsWith('抵達') || s.startsWith('返回')
    );

    bool modified = false;

    // 如果完全沒有任何 __DAY_ 標籤，先進行平均分配
    if (!current.any((s) => s.startsWith('__DAY_'))) {
      current.clear();
      int perDay = (spots.length / _trip.days).ceil();
      if (perDay == 0) perDay = 1;
      int currentDay = 1;
      int count = 0;
      current.add('__DAY_1__');
      for (var spot in spots) {
        if (count >= perDay && currentDay < _trip.days) {
          currentDay++;
          current.add('__DAY_${currentDay}__');
          count = 0;
        }
        current.add(spot);
        count++;
      }
      modified = true;
    }

    // 🌟 關鍵修復：強制檢查並補齊所有天數標籤 (從 1 到 _trip.days)
    for (int d = 1; d <= _trip.days; d++) {
      String marker = '__DAY_${d}__';
      if (!current.contains(marker)) {
        current.add(marker); // 缺少的天數標籤直接加到最後面
        modified = true;
      }
    }

    if (modified) {
      // 延後到 build 結束後再寫，避免在 build 流程中觸發 setState/rebuild 迴圈
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TripService.updateTrip(_trip.id, {'spots': current});
      });
    }
    return current;
  }

  // ─── TSP 最短路徑排序 ──────────────────────────────────────────
  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// 最近鄰 TSP：從 [startLat/Lng] 出發，依序找最近未訪問景點
  /// 最近鄰 TSP：改用模糊比對，避免因字串不完全一致導致排序破裂
  static List<String> _nearestNeighborOrder(
    List<String> spots,
    double startLat,
    double startLng,
  ) {
    final mapped = <String>[];
    final unmapped = <String>[];

    // 分流：找得到座標的去排 TSP，找不到的（可能是自訂文字）排到最後
    for (var s in spots) {
      if (_lookupSpot(s) != null) mapped.add(s); else unmapped.add(s);
    }

    final result = <String>[];
    double curLat = startLat, curLng = startLng;
    final remaining = List<String>.from(mapped);

    while (remaining.isNotEmpty) {
      int bestIdx = 0;
      double bestDist = double.infinity;
      for (int i = 0; i < remaining.length; i++) {
        final s = _lookupSpot(remaining[i]);
        if (s != null) {
          final d = _haversineKm(curLat, curLng, s.lat, s.lng);
          if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
          }
        }
      }
      final chosen = remaining.removeAt(bestIdx);
      result.add(chosen);
      final cs = _lookupSpot(chosen);
      if (cs != null) { curLat = cs.lat; curLng = cs.lng; }
    }
    result.addAll(unmapped);
    return result;
  }

  bool _tspLoading = false;

  Future<void> _tspReorder() async {
    if (_tspLoading) return;
    setState(() => _tspLoading = true);
    try {
      final items = _getNormalizedSpots();
      // 取得乾淨景點（去掉 __DAY_X__ 標籤）
      final cleanSpots = items.where((s) => !s.startsWith('__DAY_')).toList();
      if (cleanSpots.isEmpty) return;

      final allSpots = SpotService.cached;
      final spotMap = <String, Spot>{for (final s in allSpots) s.name: s};

      // 找住宿景點（作為每天起終點）
      Spot? hotel;
      for (final name in cleanSpots) {
        final s = spotMap[name];
        if (s != null) {
          final cat = s.category.toLowerCase();
          final n = s.name;
          if (cat.contains('hotel') || cat.contains('hostel') ||
              n.contains('飯店') || n.contains('旅館') || n.contains('民宿') ||
              n.contains('旅店') || n.contains('酒店') || n.contains('青年旅') ||
              n.contains('villa') || n.contains('Villa') || n.contains('休閒農場')) {
            hotel = s;
            break;
          }
        }
      }

      // 去掉住宿，只對景點排序
      final visitSpots = cleanSpots.where((s) => s != hotel?.name).toList();

      // 起始座標（飯店 或 嘉義市中心）
      final startLat = hotel?.lat ?? 23.4780;
      final startLng = hotel?.lng ?? 120.4407;

      // 全域 TSP 排序
      final ordered = _nearestNeighborOrder(visitSpots, startLat, startLng);

      // 按天分組並插入 __DAY_X__ 標籤
      final days = _trip.days.clamp(1, 99);
      final perDay = (ordered.length / days).ceil().clamp(1, ordered.length);
      final result = <String>[];
      for (int d = 0; d < days; d++) {
        result.add('__DAY_${d + 1}__');
        final start = d * perDay;
        final end = ((d + 1) * perDay).clamp(0, ordered.length);
        if (start < ordered.length) result.addAll(ordered.sublist(start, end));
      }
      // 若有住宿，加回第一天開頭與最後一天結尾
      // (user 可自行拖曳，這裡不強制加入)

      await _rippleTimesBasedOnOrder(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已依最短路徑重新排序！'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _tspLoading = false);
    }
  }

  // ─── 距離輔助：兩景點間距離(km) ──────────────────────────────
  double _distBetweenSpots(String a, String b) {
    final cached = SpotService.cached;
    final sa = cached.firstWhere((s) => s.name == a, orElse: () => cached.first);
    final sb = cached.firstWhere((s) => s.name == b, orElse: () => cached.first);
    // 若 cached 空，預設 0
    if (SpotService.cached.isEmpty) return 0;
    return _haversineKm(sa.lat, sa.lng, sb.lat, sb.lng);
  }

  // 2. 全新支援拖曳的行程列表
  Widget _buildScheduleList(Color primary) {
    final items = _getNormalizedSpots();

    return NotebookBackground(
      lineColor: primary.withValues(alpha: 0.10),
      child: Stack(children: [
        const ScatteredDoodles(),
        Column(children: [
          // ── 智慧排序按鈕 ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              const Spacer(),
              GestureDetector(
                onTap: _tspLoading ? null : _tspReorder,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: _tspLoading ? 0.05 : 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_tspLoading)
                      SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: primary))
                    else
                      Icon(Icons.route_rounded, size: 14, color: primary),
                    const SizedBox(width: 6),
                    Text('智慧排序', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primary)),
                  ]),
                ),
              ),
            ]),
          ),

          // 行程已完成提示與退回按鈕
          if (_trip.isCompleted)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: primary.withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('此行程已完成', style: TextStyle(fontWeight: FontWeight.w700))),
                ElevatedButton.icon(
                  onPressed: () => TripService.setCompleted(_trip.id, completed: false),
                  icon: const Icon(Icons.edit_rounded, size: 14), label: const Text('退回編輯'),
                  style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                ),
              ]),
            ),
          
          // 🌟 這裡換成 ReorderableListView 來支援跨天拖曳
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _scheduleScrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              itemCount: items.length + 1,
              onReorder: (oldIndex, newIndex) {
                final items = _getNormalizedSpots();
                if (items[oldIndex].startsWith('__DAY_')) return;
                if (newIndex > oldIndex) newIndex -= 1;
                if (newIndex >= items.length || items[newIndex].startsWith('__DAY_')) return;

                final item = items.removeAt(oldIndex);
                items.insert(newIndex, item);
                
                // 🌟 當手動拖曳換位時，根據新順序自動推算時間！
                _rippleTimesBasedOnOrder(items);
              },
              itemBuilder: (context, index) {
                final items = _getNormalizedSpots();
                // 🌟 如果是最後一項，產生底部大空白，確保不管景點多短，天數都能順利置頂
                if (index == items.length) {
                  return SizedBox(key: const ValueKey('bottom_spacer'), height: MediaQuery.of(context).size.height * 0.75);
                }
                
                final spot = items[index];
                if (spot.startsWith('__DAY_')) {
                  final dayStr = spot.replaceAll('__DAY_', '').replaceAll('__', '');
                  final dayInt = int.tryParse(dayStr) ?? 1;
                  _dayKeys[dayInt] ??= GlobalKey(); // 確保每個天數都有獨立的 key

                  return AlwaysKeepAliveWidget(
                    key: ValueKey(spot),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: Row(
                        key: _dayKeys[dayInt], // 🌟 將 key 綁定在這裡，讓系統可以定位
                        children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: Text('第 $dayStr 天', style: TextStyle(fontWeight: FontWeight.w800, color: primary)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Container(height: 1, color: primary.withValues(alpha: 0.1))),
                      ]),
                    ),
                  );
                }
                // 判斷下一個 item 是否在同一天（用於顯示交通連結）
                final nextIdx = index + 1;
                final items2 = _getNormalizedSpots();
                final String? nextSpot = (nextIdx < items2.length && !items2[nextIdx].startsWith('__DAY_'))
                    ? items2[nextIdx] : null;
                return Container(
                  key: ValueKey(spot),
                  margin: const EdgeInsets.only(bottom: 4),
                  child: _buildScheduleCard(spot, primary, nextSpot: nextSpot),
                );
              },
            ),
          ),
        ]),
      ]),
    );
  }

  // 3. 景點卡片
  // 3. 景點卡片
  Widget _buildScheduleCard(String spot, Color primary, {String? nextSpot}) {
    String rawTime = _trip.spotTimes[spot] ?? '';
    final parts = rawTime.split('|');
    String time = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : '--:--';
    String duration = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : '60';
    String tMode = parts.length > 2 ? parts[2] : '';
    String tNote = parts.length > 3 ? parts[3] : '';
    final bool hasNext = nextSpot != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 50,
              child: Column(children: [
                GestureDetector(
                  onTap: () async {
                    final cur = time == '--:--' ? TimeOfDay.now() : TimeOfDay(hour: int.parse(time.split(':')[0]), minute: int.parse(time.split(':')[1]));
                    final sel = await showTimePicker(context: context, initialTime: cur);
                    if (sel != null && mounted) {
                      final newTime = '${sel.hour.toString().padLeft(2, '0')}:${sel.minute.toString().padLeft(2, '0')}';
                      _updateSpotTimeAndRipple(spot, newTime, duration);
                    }
                  },
                  child: Text(time, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: primary)),
                ),
                const SizedBox(height: 6),
                Container(width: 2, height: 52, color: primary.withValues(alpha: 0.15)),
              ]),
            ),
            Expanded(
              child: StitchedBox(
                color: Colors.white, stitchColor: primary.withValues(alpha: 0.25),
                radius: 16, inset: 4, dashWidth: 4, dashGap: 3.5,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(spot, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  ])),
                  IconButton(icon: const Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20), onPressed: () => _showSpotOptions(spot)),
                ]),
              ),
            ),
          ],
        ),
        // ── 交通連結標籤（兩景點之間） ────────────────────
        if (hasNext) _buildTransportConnector(spot, nextSpot, primary, time, duration, tMode, tNote),
        if (!hasNext) const SizedBox(height: 8),
      ],
    );
  }

  /// 景點間的交通連結小標籤
  Widget _buildTransportConnector(String from, String to, Color primary, String time, String duration, String tMode, String tNote) {
    IconData icon;
    String label;
    
    if (tMode.isNotEmpty || tNote.isNotEmpty) {
      icon = _getTransportIcon(tMode);
      label = tNote.isNotEmpty ? tNote : _getTransportLabel(tMode);
    } else {
      // 🌟 自動距離估算與待選填備案
      double dist = 0;
      bool foundCoord = false;
      
      if (SpotService.cached.isNotEmpty) {
        try { 
           final sa = _lookupSpot(from);
           final sb = _lookupSpot(to);
           if (sa != null && sb != null) {
              dist = _haversineKm(sa.lat, sa.lng, sb.lat, sb.lng);
              foundCoord = true;
           }
        } catch (_) {}
      }

      if (!foundCoord) {
        icon = Icons.help_outline_rounded;
        label = '交通方式待選填 (點此設定)';
      } else if (dist < 0.5) {
        icon = Icons.directions_walk_rounded;
        label = dist < 0.05 ? '步行前往' : '步行約 ${(dist * 1000).round()} 公尺';
      } else if (dist < 3.5) {
        icon = Icons.directions_bike_rounded;
        label = '騎車約 ${dist.toStringAsFixed(1)} 公里';
      } else {
        icon = Icons.directions_car_rounded;
        label = '車程約 ${dist.toStringAsFixed(1)} 公里';
      }
    }

    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Column(children: [
            Container(width: 2, height: 10, color: primary.withValues(alpha: 0.15)),
            Icon(icon, size: 13, color: primary.withValues(alpha: 0.55)),
            Container(width: 2, height: 10, color: primary.withValues(alpha: 0.15)),
          ]),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _showTransportEditSheet(from, time, duration, tMode, tNote),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary.withValues(alpha: 0.75)), overflow: TextOverflow.ellipsis, maxLines: 1)),
                const SizedBox(width: 4),
                Icon(Icons.edit_rounded, size: 10, color: primary.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getTransportIcon(String mode) {
    switch (mode) {
      case 'walk': return Icons.directions_walk_rounded;
      case 'bike': return Icons.directions_bike_rounded;
      case 'bus': return Icons.directions_bus_rounded;
      case 'train': return Icons.train_rounded;
      case 'hsr': return Icons.speed_rounded;
      case 'car': return Icons.directions_car_rounded;
      case 'taxi': return Icons.local_taxi_rounded;
      default: return Icons.directions_car_rounded;
    }
  }

  String _getTransportLabel(String mode) {
    switch (mode) {
      case 'walk': return '步行';
      case 'bike': return '腳踏車';
      case 'bus': return '公車';
      case 'train': return '火車';
      case 'hsr': return '高鐵';
      case 'car': return '自駕';
      case 'taxi': return '計程車';
      default: return '交通方式';
    }
  }

  void _showTransportEditSheet(String spot, String time, String duration, String currentMode, String currentNote) {
    String selectedMode = currentMode.isEmpty ? 'car' : currentMode;
    final noteCtrl = TextEditingController(text: currentNote);
    final primary = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  const Text('編輯前往下一站的交通', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: ['walk', 'bike', 'bus', 'train', 'car', 'taxi'].map((m) {
                      final isSel = selectedMode == m;
                      return ChoiceChip(
                        label: Text(_getTransportLabel(m)),
                        avatar: Icon(_getTransportIcon(m), size: 16, color: isSel ? Colors.white : primary),
                        selected: isSel,
                        selectedColor: primary,
                        backgroundColor: AppColors.surfaceMoss,
                        labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600),
                        onSelected: (v) => setModalState(() => selectedMode = m),
                        showCheckmark: false,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: '交通備註 (如：搭乘 7322 號公車)',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(
                        onPressed: () {
                          TripService.setSpotTime(_trip.id, spot, '$time|$duration||');
                          Navigator.pop(ctx);
                        },
                        child: const Text('恢復自動估算'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton(
                        onPressed: () {
                          TripService.setSpotTime(_trip.id, spot, '$time|$duration|$selectedMode|${noteCtrl.text.trim()}');
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: primary),
                        child: const Text('儲存', style: TextStyle(color: Colors.white)),
                      )),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  void _showSpotOptions(String spot) {
    final primary = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: const BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('設定預算'),
            onTap: () {
              Navigator.pop(context);
              _showSpotBudgetSheet(spot, primary);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text('從行程移除', style: TextStyle(color: AppColors.error)),
            onTap: () {
              Navigator.pop(context);
              final newSpots = List<String>.from(_trip.spots)..remove(spot);
              TripService.updateTrip(_trip.id, {'spots': newSpots});
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('已移除 $spot'),
                behavior: SnackBarBehavior.floating,
              ));
            },
          ),
        ]),
      ),
    );
  }

  // 🌟 核心功能 1：當設定特定時間/長度時，重新依時間排序，並產生漣漪推算
  // 🌟 核心功能 1：當設定特定時間/長度時，重新依時間排序，並產生漣漪推算
  Future<void> _updateSpotTimeAndRipple(String targetSpot, String newTime, String duration) async {
    Map<String, String> times = Map.from(_trip.spotTimes);
    // 🌟 保護原有的交通資料不被洗掉
    String oldRaw = times[targetSpot] ?? '';
    final parts = oldRaw.split('|');
    String tMode = parts.length > 2 ? parts[2] : '';
    String tNote = parts.length > 3 ? parts[3] : '';
    times[targetSpot] = '$newTime|$duration|$tMode|$tNote';

    List<String> currentSpots = _getNormalizedSpots();
    List<String> newSpots = [];
    List<String> tempDaySpots = [];
    
    for (int i = 0; i < currentSpots.length; i++) {
      final s = currentSpots[i];
      if (s.startsWith('__DAY_')) {
        if (tempDaySpots.isNotEmpty) {
          tempDaySpots.sort((a, b) {
            final timeA = times[a]?.split('|').first ?? '23:59';
            final timeB = times[b]?.split('|').first ?? '23:59';
            if (timeA == '--:--') return 1;
            if (timeB == '--:--') return -1;
            return timeA.compareTo(timeB);
          });
          newSpots.addAll(tempDaySpots);
          tempDaySpots.clear();
        }
        newSpots.add(s);
      } else {
        tempDaySpots.add(s);
      }
    }
    if (tempDaySpots.isNotEmpty) {
      tempDaySpots.sort((a, b) {
        final timeA = times[a]?.split('|').first ?? '23:59';
        final timeB = times[b]?.split('|').first ?? '23:59';
        if (timeA == '--:--') return 1;
        if (timeB == '--:--') return -1;
        return timeA.compareTo(timeB);
      });
      newSpots.addAll(tempDaySpots);
    }

    _rippleTimesBasedOnOrder(newSpots, timesToUse: times);
  }

  // 🌟 核心功能 2：根據現有排序（包含拖曳後），由上往下自動疊加時間
  Future<void> _rippleTimesBasedOnOrder(List<String> orderedSpots, {Map<String, String>? timesToUse}) async {
    Map<String, String> times = Map.from(timesToUse ?? _trip.spotTimes);
    DateTime? calcTime;
    
    for (String s in orderedSpots) {
      if (s.startsWith('__DAY_')) {
        calcTime = null; // 換天重設
        continue;
      }
      String raw = times[s] ?? '';
      final parts = raw.split('|');
      String tStr = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : '--:--';
      int dur = parts.length > 1 && parts[1].isNotEmpty ? int.tryParse(parts[1]) ?? 60 : 60;
      // 🌟 保護原有的交通資料不被洗掉
      String tMode = parts.length > 2 ? parts[2] : '';
      String tNote = parts.length > 3 ? parts[3] : '';

      if (calcTime != null) {
        if (tStr == '--:--' || tStr.isEmpty) {
          // 沒有手動設定時間 → 用漣漪推算填入
          tStr = '${calcTime.hour.toString().padLeft(2, '0')}:${calcTime.minute.toString().padLeft(2, '0')}';
          times[s] = '$tStr|$dur|$tMode|$tNote';
          calcTime = calcTime.add(Duration(minutes: dur));
        } else {
          // 有手動設定時間 → 保留使用者設定，以此為新基準往後推
          final spotDt = DateTime(2000, 1, 1, int.parse(tStr.split(':')[0]), int.parse(tStr.split(':')[1]));
          calcTime = spotDt.add(Duration(minutes: dur));
        }
      } else if (tStr != '--:--' && tStr.isNotEmpty) {
        // 第一個有設定時間的景點，成為當天的基準點
        calcTime = DateTime(2000, 1, 1, int.parse(tStr.split(':')[0]), int.parse(tStr.split(':')[1]));
        calcTime = calcTime.add(Duration(minutes: dur));
      }
    }

    setState(() {
      _trip.spots.clear();
      _trip.spots.addAll(orderedSpots);
      _trip.spotTimes.addAll(times);
    });

    await TripService.updateTrip(_trip.id, {
      'spots': orderedSpots,
      'spotTimes': times,
    });
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

  // 座標查詢（精確 → 模糊 → SpotService 快取）
  static Spot? _lookupSpot(String name) {
    final cache = SpotService.cached;
    return cache.where((s) => s.name == name).firstOrNull
        ?? cache.where((s) => s.name.contains(name) || name.contains(s.name)).firstOrNull;
  }

  List<LatLng> _spotsToLatLngs(List<String> names) {
    return names.map((name) {
      final s = _lookupSpot(name);
      if (s != null) return LatLng(s.lat, s.lng);
      // Hash spot name → unique fallback so Day 1 & Day 2 markers don't overlap
      final h = name.codeUnits.fold(0, (int p, int e) => p * 31 + e).abs();
      return LatLng(23.470 + (h % 50) * 0.0007, 120.440 + ((h ~/ 50) % 50) * 0.0007);
    }).toList();
  }

  Widget _buildMapMode(Color primary, FirebaseTrip trip, List<List<String>> daySpots) {
    // ── 用與概覽完全相同的 daySpots 切割，保證 marker 一致 ─────
    final List<String> filteredNames;
    if (_mapDayFilter == null) {
      // 全部：flatten daySpots 保持順序
      filteredNames = daySpots.expand((d) => d).toList();
    } else {
      final d = _mapDayFilter!.clamp(0, daySpots.length - 1);
      filteredNames = daySpots[d];
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
            // 各天（顯示日期 + 景點數）
            ...List.generate(daySpots.length, (d) {
              final dayDate = trip.startDate.add(Duration(days: d));
              final label = '${dayDate.month}/${dayDate.day}';
              final count = daySpots[d].length;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _mapFilterChip(
                    'Day ${d + 1}  $label${count > 0 ? " ($count)" : ""}',
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
                // 每次 dayFilter 變更就整個重建，確保地圖中心跟著移
                key: ValueKey('map_${_mapDayFilter ?? "all"}_${filteredNames.join(",")}'),
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
                Text(context.read<AppSettingsProvider>().l10n.tripNoSpotDay(_mapDayFilter != null),
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
          // AI 排程入口
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: TripService.tripCandidatesStream(trip.id),
            builder: (_, snap) {
              final items = snap.data ?? [];
              return GestureDetector(
                onTap: () {
                  final candidateSpots = items.map((m) => m['spotName']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
                  final imported = {trip.title: trip.spots}; // 💡 傳入當前行程作為預設匯入
                  
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AIPlannerScreen(
                      candidateSpots: candidateSpots,
                      importedTrips: imported,
                      // 🌟 同樣明確標示型別，並給第二個參數命名為 targetTitle
                      onSaveTrip: (AiGeneratedTrip aiTrip, String? targetTitle) async {
                        // 💡 修正：變數名稱是 _trip (有底線)
                        await TripService.updateTrip(_trip.id, {
                          'spots': aiTrip.spots,
                          'isCompleted': false, 
                        });
                        
                        // 將 AI 產生的時間自動匯入
                        for (var d in aiTrip.schedule) {
                          for (var item in d.items) {
                            if (item.transport == null && !item.isMeal) {
                              await TripService.setSpotTime(_trip.id, item.name, item.time);
                            }
                          }
                        }
                      }
                    )
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primary.withValues(alpha: 0.25))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, size: 12, color: primary),
                    const SizedBox(width: 4),
                    Text('精靈排程', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
                  ]),
                ),
              );
            },
          ),
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
                          // 🌟 準確尋找對應天數的位置並安插
                          List<String> currentSpots = _getNormalizedSpots();
                          String nextDayMarker = '__DAY_${d + 2}__'; // 尋找下一天的標籤
                          
                          int insertIdx = currentSpots.length; // 預設放在最後
                          if (currentSpots.contains(nextDayMarker)) {
                             insertIdx = currentSpots.indexOf(nextDayMarker); // 放在下一天之前
                          }
                          
                          currentSpots.insert(insertIdx, spotName);
                          
                          // 移除候選，並透過推算系統更新行程 (這樣時間才會立刻連動)
                          await TripService.removeTripCandidate(trip.id, item['spotId'].toString());
                          await _rippleTimesBasedOnOrder(currentSpots);
                          
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
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Theme.of(ctx).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
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
  String _selectedIcon = 'map';
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
                showModalBottomSheet(
                  context: context, backgroundColor: Colors.transparent,
                  builder: (_) => StatefulBuilder(builder: (ctx, setSB) => Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('選擇圖標', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: _kTripIconPresets.take(20).map((preset) => GestureDetector(
                        onTap: () { setState(() => _selectedIcon = preset.$1); Navigator.pop(context); },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _selectedIcon == preset.$1 ? primary.withValues(alpha: 0.12) : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                            border: _selectedIcon == preset.$1 ? Border.all(color: primary) : null),
                          child: Icon(preset.$2, size: 26, color: _selectedIcon == preset.$1 ? primary : AppColors.textSecondary)),
                      )).toList()),
                    ]),
                  )),
                );
              },
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withValues(alpha: 0.2))),
                child: Center(child: Icon(_tripIconFromKey(_selectedIcon), size: 28, color: primary)),
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

// ════════════════════════════════════════════════════════════════
// 邀請旅伴 Sheet（Email 搜尋 + 已邀成員列表）
// ════════════════════════════════════════════════════════════════
class _InviteSheet extends StatefulWidget {
  final FirebaseTrip trip;
  final Color primary;
  const _InviteSheet({required this.trip, required this.primary});
  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _emailCtrl = TextEditingController();
  final _dummyNameCtrl = TextEditingController();
  bool _searching = false;
  bool _notFound = false;
  Map<String, dynamic>? _foundUser;
  bool _adding = false;
  bool _addingDummy = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _tripId => widget.trip.id;
  Color get _primary => widget.primary;

  Future<void> _search() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _searching = true; _notFound = false; _foundUser = null; });
    try {
      var q = await _db.collection('users').where('email', isEqualTo: email).limit(1).get();
      if (q.docs.isEmpty) {
        q = await _db.collection('users').where('emailAddress', isEqualTo: email).limit(1).get();
      }
      if (q.docs.isEmpty) {
        setState(() { _searching = false; _notFound = true; });
      } else {
        final d = q.docs.first.data();
        setState(() { _searching = false; _foundUser = {...d, 'uid': q.docs.first.id}; });
      }
    } catch (_) {
      setState(() { _searching = false; _notFound = true; });
    }
  }

  Future<void> _invite() async {
    if (_adding || _foundUser == null) return;
    setState(() => _adding = true);
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final foundUid = _foundUser!['uid'] as String;
    final name = (_foundUser!['nickname'] ?? _foundUser!['displayName'] ?? _foundUser!['name'] ?? '').toString();
    final email = (_foundUser!['email'] ?? _foundUser!['emailAddress'] ?? '').toString();
    final photo = (_foundUser!['photoURL'] ?? _foundUser!['photoUrl'] ?? '').toString();

    final docRef = await _db.collection('trips').doc(_tripId).collection('companions').add({
      'name': name, 'email': email, 'uid': foundUid, 'photoURL': photo,
      'status': 'pending', 'addedBy': myUid, 'addedAt': FieldValue.serverTimestamp(),
    });
    // 通知對方
    final myDoc = await _db.collection('users').doc(myUid).get();
    final myName = myDoc.data()?['nickname'] ?? myDoc.data()?['displayName'] ?? '旅伴';
    try {
      await _db.collection('users').doc(foundUid).collection('invitations').doc(docRef.id).set({
        'tripId': _tripId, 'companionId': docRef.id, 'fromUid': myUid,
        'fromName': myName, 'tripTitle': widget.trip.title,
        'status': 'pending', 'sentAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    setState(() { _adding = false; _foundUser = null; _emailCtrl.clear(); _notFound = false; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已送出邀請給 $name'),
      backgroundColor: _primary, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _remove(String companionId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('移除旅伴', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('確定移除「$name」嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.collection('trips').doc(_tripId).collection('companions').doc(companionId).delete();
    }
  }

  Future<void> _addDummy() async {
    final name = _dummyNameCtrl.text.trim();
    if (name.isEmpty || _addingDummy) return;
    setState(() => _addingDummy = true);
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _db.collection('trips').doc(_tripId).collection('companions').add({
      'name': name, 'email': '', 'uid': '', 'photoURL': '',
      'status': 'dummy', 'addedBy': myUid, 'addedAt': FieldValue.serverTimestamp(),
    });
    _dummyNameCtrl.clear();
    setState(() => _addingDummy = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已新增虛擬旅伴「$name」'),
      backgroundColor: _primary, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  void dispose() { _emailCtrl.dispose(); _dummyNameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 把手
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)))),
          // 標題
          Row(children: [
            Icon(Icons.group_add_rounded, color: _primary, size: 22),
            const SizedBox(width: 8),
            Text('邀請旅伴加入', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _primary)),
          ]),
          const SizedBox(height: 4),
          Text('「${widget.trip.title}」', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
          const SizedBox(height: 20),

          // Email 輸入列
          Row(children: [
            Expanded(
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: '輸入旅伴的 Email',
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  filled: true, fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _searching ? null : _search,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _searching
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('搜尋', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),

          // 搜尋結果
          if (_notFound) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(child: Text('找不到此 Email 的使用者', style: TextStyle(fontSize: 13, color: Colors.orange))),
              ]),
            ),
          ],
          if (_foundUser != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primary.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _primary.withValues(alpha: 0.15),
                  backgroundImage: (_foundUser!['photoURL'] ?? _foundUser!['photoUrl'] ?? '').toString().isNotEmpty
                      ? NetworkImage((_foundUser!['photoURL'] ?? _foundUser!['photoUrl']).toString()) : null,
                  child: (_foundUser!['photoURL'] ?? _foundUser!['photoUrl'] ?? '').toString().isEmpty
                      ? Text(
                          ((_foundUser!['nickname'] ?? _foundUser!['displayName'] ?? '?').toString()).isNotEmpty
                              ? (_foundUser!['nickname'] ?? _foundUser!['displayName'] ?? '?').toString()[0]
                              : '?',
                          style: TextStyle(color: _primary, fontWeight: FontWeight.w800))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((_foundUser!['nickname'] ?? _foundUser!['displayName'] ?? '未知').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text((_foundUser!['email'] ?? _foundUser!['emailAddress'] ?? '').toString(),
                      style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                ])),
                ElevatedButton(
                  onPressed: _adding ? null : _invite,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: _adding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('邀請', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          // 虛擬旅伴（沒有 App 帳號）
          Text('新增虛擬旅伴', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _primary)),
          const SizedBox(height: 4),
          const Text('沒有 App 帳號的同伴，輸入名字即可加入', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _dummyNameCtrl,
                decoration: InputDecoration(
                  hintText: '例如：小明、阿強',
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                  filled: true, fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (_) => _addDummy(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _addingDummy ? null : _addDummy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _addingDummy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('新增', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          Text('目前旅伴', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _primary)),
          const SizedBox(height: 8),

          // 旅伴列表
          StreamBuilder<QuerySnapshot>(
            stream: _db.collection('trips').doc(_tripId).collection('companions').orderBy('addedAt').snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Icon(Icons.person_outline_rounded, size: 18, color: _primary.withValues(alpha: 0.4)),
                    const SizedBox(width: 8),
                    Text('尚未邀請任何旅伴', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                  ]),
                );
              }
              return Column(
                children: snap.data!.docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final name = (d['name'] ?? '').toString();
                  final email = (d['email'] ?? '').toString();
                  final photo = (d['photoURL'] ?? d['photoUrl'] ?? '').toString();
                  final status = (d['status'] ?? 'manual').toString();
                  final statusLabel = status == 'pending' ? '待確認' : status == 'confirmed' ? '已加入' : '外部';
                  final statusColor = status == 'pending' ? Colors.orange : status == 'confirmed' ? Colors.green : AppColors.textHint;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: _primary.withValues(alpha: 0.12),
                      backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                      child: photo.isEmpty
                          ? Text(name.isNotEmpty ? name[0] : '?',
                              style: TextStyle(color: _primary, fontWeight: FontWeight.w800, fontSize: 13))
                          : null,
                    ),
                    title: Row(children: [
                      Flexible(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                        child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    subtitle: email.isNotEmpty
                        ? Text(email, style: const TextStyle(fontSize: 11, color: AppColors.textHint))
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error, size: 20),
                      onPressed: () => _remove(doc.id, name),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ① 旅行日報 — 一鍵生成可分享的旅行總結卡
// ════════════════════════════════════════════════════════════════
class _TripReportPage extends StatefulWidget {
  final FirebaseTrip trip;
  final Color primary;
  const _TripReportPage({required this.trip, required this.primary});
  @override State<_TripReportPage> createState() => _TripReportPageState();
}

class _TripReportPageState extends State<_TripReportPage> {
  final _repaintKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/trip_report.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '我的嘉義旅行日報 — ${widget.trip.title}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失敗：$e'), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    final trip = widget.trip;
    final dark = Color.lerp(p, Colors.black, 0.25)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('旅行日報', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.ios_share_rounded, size: 16),
              label: Text(_sharing ? '生成中…' : '分享'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(children: [
          // ── 可截圖的卡片區域（SketchyBorder 在外，不入鏡）──
          SketchyBorderBox(
            borderColor: p.withValues(alpha: 0.30),
            strokeWidth: 1.4,
            padding: EdgeInsets.zero,
            seed: trip.title.hashCode,
            child: RepaintBoundary(
            key: _repaintKey,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(color: p.withValues(alpha: 0.16), blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // ── 波浪 Header ──
                  ClipPath(
                    clipper: _ReportWaveClipper(),
                    child: Container(
                      height: 168,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: [p, dark, Color.lerp(p, const Color(0xFF80DEEA), 0.3)!])),
                      child: Stack(children: [
                        // 裝飾圓
                        Positioned(right: -18, top: -18,
                          child: Container(width: 110, height: 110,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.09)))),
                        Positioned(left: -10, bottom: 20,
                          child: Container(width: 70, height: 70,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)))),
                        // 手繪點綴
                        Positioned(top: 18, right: 60,
                          child: DoodleHeart(color: Colors.white.withValues(alpha: 0.20), size: 12)),
                        Positioned(top: 50, right: 28,
                          child: DoodleLightning(color: Colors.white.withValues(alpha: 0.15), size: 9)),
                        // 封面圖（淡顯）
                        if (trip.coverUrl != null)
                          Positioned.fill(child: Opacity(opacity: 0.20,
                            child: Image.network(trip.coverUrl!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
                        // 文字內容
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.30))),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(_tripIconFromKey(trip.icon), size: 12, color: Colors.white.withValues(alpha: 0.95)),
                                const SizedBox(width: 5),
                                Text('旅 行 日 報', style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
                              ]),
                            ),
                            const SizedBox(height: 8),
                            Text(trip.title, style: const TextStyle(
                              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.2),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 5),
                            Text(trip.dateDisplay, style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78), fontSize: 12)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  // ── 統計貼紙列 ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(children: [
                      _statSticker(Icons.calendar_today_rounded, '${trip.days}', '天', const Color(0xFFCB9E5A)),
                      const SizedBox(width: 10),
                      _statSticker(Icons.place_rounded, '${trip.spots.where((s) => !s.startsWith('__DAY_')).length}', '景點', const Color(0xFF8AAEC4)),
                      const SizedBox(width: 10),
                      _statSticker(
                        trip.isCompleted ? Icons.check_circle_rounded : Icons.pending_rounded,
                        trip.isCompleted ? '✓' : '…',
                        trip.isCompleted ? '完成' : '規劃中', const Color(0xFF7AAA8A)),
                    ]),
                  ),
                  // ── 景點清單（筆記本風格）──
                  if (trip.spots.isNotEmpty) Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        DoodleLightning(color: p.withValues(alpha: 0.55), size: 9),
                        const SizedBox(width: 6),
                        Text('行程景點', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: p, letterSpacing: 1.2)),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.withValues(alpha: 0.12)),
                        ),
                        child: Column(children: [
                          ...trip.spots.asMap().entries.map((e) {
                            const macaronColors = [
                              Color(0xFFD08878), Color(0xFFCB9E5A),
                              Color(0xFF8AAEC4), Color(0xFF8878B0),
                              Color(0xFF7AAA8A), Color(0xFFB86878),
                            ];
                            final mc = macaronColors[e.key % macaronColors.length];
                            return Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Row(children: [
                              Container(
                                width: 20, height: 20,
                                decoration: BoxDecoration(
                                  color: mc.withValues(alpha: 0.12),
                                  border: Border.all(color: mc.withValues(alpha: 0.50)),
                                  borderRadius: BorderRadius.circular(6)),
                                child: Center(child: Text('${e.key + 1}',
                                  style: TextStyle(color: mc, fontSize: 9, fontWeight: FontWeight.w900)))),
                              const SizedBox(width: 10),
                              Expanded(child: Text(e.value,
                                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600))),
                              if (e.key < trip.spots.length - 1)
                                Container(width: 1, height: 10, color: AppColors.divider),
                            ]),
                          );
                          }),
                        ]),
                      ),
                    ]),
                  ),
                  // ── Washi-tape 裝飾色條 ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Row(children: [
                        Expanded(child: Container(height: 4, color: const Color(0xFFD08878).withValues(alpha: 0.70))),
                        Expanded(child: Container(height: 4, color: const Color(0xFFCB9E5A).withValues(alpha: 0.70))),
                        Expanded(child: Container(height: 4, color: const Color(0xFF8AAEC4).withValues(alpha: 0.70))),
                        Expanded(child: Container(height: 4, color: const Color(0xFF8878B0).withValues(alpha: 0.70))),
                        Expanded(child: Container(height: 4, color: const Color(0xFF7AAA8A).withValues(alpha: 0.70))),
                        Expanded(child: Container(height: 4, color: const Color(0xFFB86878).withValues(alpha: 0.70))),
                      ]),
                    ),
                  ),
                  // ── 底部落款 ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    child: Row(children: [
                      Expanded(child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            p.withValues(alpha: 0.07), p.withValues(alpha: 0.03)]),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.withValues(alpha: 0.14))),
                        child: Row(children: [
                          DoodleHeart(color: p.withValues(alpha: 0.6), size: 9),
                          const SizedBox(width: 8),
                          Text('探索諸羅 · 嘉義旅遊', style: TextStyle(
                            fontSize: 11, color: p, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text(trip.dateDisplay.split('～').first.trim(),
                            style: TextStyle(fontSize: 9, color: p.withValues(alpha: 0.55))),
                        ]),
                      )),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          ),
        ]),
      ),
    );
  }

  Widget _statSticker(IconData icon, String value, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color, height: 1.0)),
        Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ── 旅行日報波浪裁切器 ─────────────────────────────────────────
class _ReportWaveClipper extends CustomClipper<ui.Path> {
  @override
  ui.Path getClip(Size s) {
    final base = s.height - 28.0;
    final path = ui.Path()..lineTo(0, base + 4);
    path.cubicTo(s.width * 0.28, base - 20, s.width * 0.62, base + 24, s.width, base);
    path.lineTo(s.width, 0);
    path.lineTo(0, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_ReportWaveClipper old) => false;
}

// ════════════════════════════════════════════════════════════════
// Utility
// ════════════════════════════════════════════════════════════════
class AlwaysKeepAliveWidget extends StatefulWidget {
  final Widget child;
  const AlwaysKeepAliveWidget({super.key, required this.child});

  @override
  State<AlwaysKeepAliveWidget> createState() => _AlwaysKeepAliveWidgetState();
}

class _AlwaysKeepAliveWidgetState extends State<AlwaysKeepAliveWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 🌟 告訴 Flutter：永遠不要回收這個元件！

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必須呼叫
    return widget.child;
  }
}