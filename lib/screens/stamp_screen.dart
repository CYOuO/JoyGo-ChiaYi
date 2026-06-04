import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../widgets/common_widgets.dart' show StampGridSkeleton;
import '../models/spot.dart';
import '../services/spot_service.dart';
import 'camera_screen.dart';

class StampScreen extends StatefulWidget {
  final int initialTab;
  const StampScreen({super.key, this.initialTab = 0});

  @override
  State<StampScreen> createState() => _StampScreenState();
}

class _StampScreenState extends State<StampScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _miniMapCtrl = MapController();

  // 真實景點（從 Firestore 載入）
  List<Spot> _realSpots = [];
  bool _spotsLoading = true;

  // Map<spotId, visitCount> — 持久化到 SharedPreferences
  Map<String, int> _visitedSpots = {};
  static const _kVisitedKey = 'stamp_visited_v1';

  // 連續打卡天數
  int _streak = 0;
  String _lastCheckinDate = '';
  static const _kStreakKey = 'stamp_streak_v1';
  static const _kLastDateKey = 'stamp_last_date_v1';

  // GPS auto check-in
  StreamSubscription<Position>? _posStream;
  Position? _stampPos;
  final Map<String, DateTime> _lastCheckinTime = {};

  // 打卡照片牆
  List<String> _photoPaths = [];
  bool _photosLoading = true;

  Offset _cameraFabOffset = const Offset(16, 16);

  static const _kCheckinRadius = 100.0;
  static const _kCheckinCooldown = Duration(minutes: 5);

  static final _chiayiBounds = LatLngBounds(
    const LatLng(23.25, 120.10),
    const LatLng(23.75, 121.00),
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5, vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
    );
    _loadVisited();
    _loadRealSpots();
    _startLocationWatch();
    _loadPhotos();
    _initLastKnownPosition();
  }

  Future<void> _loadPhotos() async {
    final paths = await CameraScreen.getSavedPhotoPaths();
    if (mounted) setState(() { _photoPaths = paths; _photosLoading = false; });
  }

  // 快速顯示上次已知位置給地圖用
  Future<void> _initLastKnownPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) setState(() => _stampPos = last);
    } catch (_) {}
  }

  Future<void> _loadVisited() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kVisitedKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) setState(() => _visitedSpots = decoded.map((k, v) => MapEntry(k, v as int)));
    }
    _streak = prefs.getInt(_kStreakKey) ?? 0;
    _lastCheckinDate = prefs.getString(_kLastDateKey) ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _saveVisited() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVisitedKey, jsonEncode(_visitedSpots));
    await prefs.setInt(_kStreakKey, _streak);
    await prefs.setString(_kLastDateKey, _lastCheckinDate);
    _syncLeaderboard();
  }

  void _updateStreak() {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_lastCheckinDate == today) return;
    final yesterday = now.subtract(const Duration(days: 1));
    final yStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    if (_lastCheckinDate == yStr) {
      _streak++;
    } else {
      _streak = 1;
    }
    _lastCheckinDate = today;
  }

  Future<void> _syncLeaderboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final count = _visitedSpots.values.where((v) => v > 0).length;
    try {
      await FirebaseFirestore.instance.collection('leaderboard').doc(user.uid).set({
        'displayName': user.displayName ?? '匿名探索者',
        'photoURL': user.photoURL ?? '',
        'stampCount': count,
        'streak': _streak,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _loadRealSpots() async {
    final spots = await SpotService.loadAllSpots();
    if (mounted) setState(() { _realSpots = spots; _spotsLoading = false; });
  }

  @override
  void dispose() {
    _posStream?.cancel();
    _miniMapCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── GPS auto check-in ──────────────────────────────────────

  Future<void> _startLocationWatch() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    _posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_checkAutoCheckin);
  }

  void _checkAutoCheckin(Position pos) {
    if (!mounted) return;
    setState(() => _stampPos = pos);
    final now = DateTime.now();

    for (final spot in _realSpots) {
      final dist = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, spot.lat, spot.lng);
      if (dist > _kCheckinRadius) continue;

      final last = _lastCheckinTime[spot.id];
      if (last != null && now.difference(last) < _kCheckinCooldown) continue;

      HapticFeedback.heavyImpact();
      _lastCheckinTime[spot.id] = now;
      final newCount = (_visitedSpots[spot.id] ?? 0) + 1;
      _updateStreak();
      setState(() => _visitedSpots[spot.id] = newCount);
      _saveVisited();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('「${spot.name}」自動打卡成功！第 $newCount 次造訪'),
        backgroundColor: _getStampColor(newCount),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          '集章成就',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary),
            onPressed: () => _showHowTo(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: primary,
          tabs: const [
            Tab(text: '景點印章'),
            Tab(text: '打卡照片'),
            Tab(text: '成就徽章'),
            Tab(text: '排行榜'),
            Tab(text: '小地圖'),
          ],
        ),
      ),
      body: LayoutBuilder(builder: (ctx, constraints) {
        return Stack(children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildStampTab(),
              _buildPhotoWallTab(),
              _buildAchievementTab(),
              _buildLeaderboardTab(),
              _buildMiniMapTab(),
            ],
          ),
          // ── 可拖曳相機按鈕（所有 tab 共用）──────────────────
          Positioned(
            right: _cameraFabOffset.dx,
            bottom: _cameraFabOffset.dy,
            child: GestureDetector(
              onTap: () => Navigator.push(ctx,
                  MaterialPageRoute(builder: (_) => const CameraScreen())),
              onPanUpdate: (d) {
                setState(() {
                  final newDx = (_cameraFabOffset.dx - d.delta.dx)
                      .clamp(8.0, constraints.maxWidth - 60);
                  final newDy = (_cameraFabOffset.dy - d.delta.dy)
                      .clamp(8.0, constraints.maxHeight - 60);
                  _cameraFabOffset = Offset(newDx, newDy);
                });
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  // ── 打卡照片牆 ──────────────────────────────────────────────
  Widget _buildPhotoWallTab() {
    final primary = Theme.of(context).colorScheme.primary;
    if (_photosLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_photoPaths.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(Icons.camera_alt_rounded, size: 38, color: primary.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          const Text('還沒有打卡照片', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('拍下你的探索瞬間\n儲存後就會出現在這裡！',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.6)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()))
                .then((_) => _loadPhotos()),
            icon: const Icon(Icons.camera_alt_rounded, size: 18),
            label: const Text('開啟相機'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary, foregroundColor: Colors.white,
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ]),
      );
    }

    return Column(children: [
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Text('共 ${_photoPaths.length} 張照片',
            style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()))
                .then((_) => _loadPhotos()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_a_photo_rounded, size: 14, color: primary),
                const SizedBox(width: 4),
                Text('拍照', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4,
          ),
          itemCount: _photoPaths.length,
          itemBuilder: (ctx, i) {
            final path = _photoPaths[i];
            final file = File(path);
            return GestureDetector(
              onTap: () => _showPhotoDetail(ctx, path),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(
                        color: primary.withValues(alpha: 0.08),
                        child: Icon(Icons.broken_image_outlined, color: AppColors.textHint, size: 24),
                      ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  void _showPhotoDetail(BuildContext ctx, String path) {
    final file = File(path);
    if (!file.existsSync()) return;
    showDialog(
      context: ctx,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildStampTab() {
    if (_spotsLoading) return const StampGridSkeleton();
    final spots = _realSpots;
    final visitedCount = _visitedSpots.keys.where((k) => (_visitedSpots[k] ?? 0) > 0).length;
    final total = spots.length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // Progress header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Theme.of(context).colorScheme.primary,
                             Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.35)!],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.map_rounded, size: 32, color: Colors.white),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '嘉義探索進度',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$visitedCount / $total 個景點已踩點',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${((visitedCount / total) * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total > 0 ? visitedCount / total : 0,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                        minHeight: 8,
                      ),
                    ),
                    if (_streak > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_streak >= 7 ? Icons.local_fire_department_rounded : Icons.trending_up_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text('連續打卡 $_streak 天${_streak >= 30 ? ' — 傳說級！' : _streak >= 14 ? ' — 超級！' : _streak >= 7 ? ' — 厲害！' : _streak >= 3 ? ' — 加油！' : ''}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final spot = spots[index];
                final visitCount = _visitedSpots[spot.id] ?? 0;
                final isVisited = visitCount > 0;

                final stampC = _getStampColor(visitCount);
                return SlideUpFadeIn(
                  index: index,
                  staggerDelay: const Duration(milliseconds: 40),
                  child: GestureDetector(
                  onTap: () => _showStampDetail(context, spot, visitCount),
                  child: StitchedBox(
                    color: isVisited ? AppColors.surface : AppColors.surfaceMoss.withValues(alpha: 0.5),
                    stitchColor: isVisited ? stampC.withValues(alpha: 0.40) : AppColors.divider,
                    radius: 20, inset: 5, dashWidth: 4, dashGap: 3,
                    boxShadow: isVisited ? [BoxShadow(color: stampC.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))] : null,
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isVisited) ...[
                          // Stamp design
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _getStampColor(visitCount),
                                    width: 3,
                                  ),
                                ),
                              ),
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getStampColor(visitCount)
                                      .withOpacity(0.15),
                                ),
                                child: Center(
                                  child: Icon(_spotIconData(spot.category), size: 24, color: AppColors.textSecondary),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: _getStampColor(visitCount),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$visitCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          // Unvisited - grey
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.textHint.withOpacity(0.1),
                              border: Border.all(
                                color: AppColors.textHint.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0,      0,      0,      1, 0,
                                ]),
                                child: Icon(_spotIconData(spot.category), size: 24, color: AppColors.textHint),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            spot.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isVisited
                                  ? AppColors.textPrimary
                                  : AppColors.textHint,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVisited) ...[
                          const SizedBox(height: 2),
                          Text(
                            '✓ 已踩點',
                            style: TextStyle(
                              fontSize: 10,
                              color: _getStampColor(visitCount),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ));
              },
              childCount: spots.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.75,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStampColor(int visitCount) {
    if (visitCount >= 5) return AppColors.stampGold;
    if (visitCount >= 3) return AppColors.stampSilver;
    return AppColors.stampBronze;
  }

  IconData _spotIconData(String category) {
    switch (category) {
      case 'restaurant': return Icons.ramen_dining_rounded;
      case 'attraction': return Icons.account_balance_rounded;
      case 'hotel':      return Icons.hotel_rounded;
      case 'youbike':    return Icons.pedal_bike_rounded;
      default:           return Icons.place_rounded;
    }
  }


  List<Achievement> _computeAchievements() {
    final spots = _realSpots;
    final visited = _visitedSpots.entries.where((e) => e.value > 0).length;

    final restaurantCount = spots
        .where((s) => s.category == 'restaurant' && (_visitedSpots[s.id] ?? 0) > 0)
        .length;

    final alishanCount = spots
        .where((s) => s.name.contains('阿里山') && (_visitedSpots[s.id] ?? 0) > 0)
        .length;
    final alishanTotal = spots.where((s) => s.name.contains('阿里山')).length.clamp(1, 999);

    final chickenRiceCount = spots
        .where((s) => (s.name.contains('雞肉飯') || s.name.contains('火雞')) && (_visitedSpots[s.id] ?? 0) > 0)
        .length;
    final chickenRiceTotal = spots.where((s) => s.name.contains('雞肉飯') || s.name.contains('火雞')).length.clamp(1, 999);

    final attractionCount = spots
        .where((s) => s.category == 'attraction' && (_visitedSpots[s.id] ?? 0) > 0)
        .length;

    List<Achievement> result = [];
    int unlockedSoFar = 0;

    final defs = <(String id, String title, String desc, String icon, int progress, int total, String rarity)>[
      ('1', '諸羅初探者', '完成第一個景點打卡', '🗺️', visited.clamp(0, 1), 1, 'bronze'),
      ('2', '美食獵人', '到訪 5 間餐廳', '🍜', restaurantCount.clamp(0, 5), 5, 'silver'),
      ('3', '阿里山征服者', '打卡所有阿里山景點', '⛰️', alishanCount.clamp(0, alishanTotal), alishanTotal, 'gold'),
      ('4', '火雞飯控', '造訪嘉義雞肉飯店家', '🦃', chickenRiceCount.clamp(0, chickenRiceTotal), chickenRiceTotal, 'bronze'),
      ('5', '嘉義通', '解鎖 50 個景點', '🏆', visited.clamp(0, 50), 50, 'gold'),
      ('6', '景點達人', '到訪 10 個觀光景點', '🌙', attractionCount.clamp(0, 10), 10, 'silver'),
      ('8', '雞肉飯巡禮', '吃遍所有嘉義雞肉飯', '🍗', chickenRiceCount.clamp(0, chickenRiceTotal), chickenRiceTotal, 'gold'),
      ('s3', '三日不懈', '連續打卡 3 天', '🗺️', _streak.clamp(0, 3), 3, 'bronze'),
      ('s7', '一週勇者', '連續打卡 7 天', '🗺️', _streak.clamp(0, 7), 7, 'silver'),
      ('s14', '半月征途', '連續打卡 14 天', '🗺️', _streak.clamp(0, 14), 14, 'gold'),
      ('s30', '月月不停', '連續打卡 30 天', '🗺️', _streak.clamp(0, 30), 30, 'special'),
    ];

    for (final d in defs) {
      final isUnlocked = d.$5 >= d.$6;
      if (isUnlocked) unlockedSoFar++;
      result.add(Achievement(
        id: d.$1, title: d.$2, description: d.$3, icon: d.$4,
        isUnlocked: isUnlocked, progress: d.$5, total: d.$6, rarity: d.$7,
      ));
    }
    // 守護者成就
    result.add(Achievement(
      id: '7', title: '特別獎：諸羅守護者', description: '達成所有成就',
      icon: '👑', isUnlocked: unlockedSoFar >= defs.length,
      progress: unlockedSoFar.clamp(0, defs.length), total: defs.length, rarity: 'special',
    ));
    return result;
  }

  Widget _buildAchievementTab() {
    final achievements = _computeAchievements();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Achievement stats
        Row(
          children: [
            _achieveStat('已解鎖', '${achievements.where((a) => a.isUnlocked).length}', const Color(0xFFC09848)),
            const SizedBox(width: 12),
            _achieveStat('進行中', '${achievements.where((a) => !a.isUnlocked).length}', const Color(0xFF8878B0)),
            const SizedBox(width: 12),
            _achieveStat('總成就', '${achievements.length}', const Color(0xFF6A9888)),
          ],
        ),
        const SizedBox(height: 20),
        // Achievement list
        ...achievements.map((achievement) => _buildAchievementCard(achievement)),
      ],
    );
  }

  Widget _achieveStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Map achievement icon → unique display color
  static Color _achievementIconColor(Achievement a) {
    switch (a.iconData) {
      case Icons.map_rounded:            return const Color(0xFF3A86C8);
      case Icons.ramen_dining_rounded:   return const Color(0xFFE07040);
      case Icons.landscape_rounded:      return const Color(0xFF5A9F6A);
      case Icons.restaurant_rounded:     return const Color(0xFFD45A5A);
      case Icons.emoji_events_rounded:   return const Color(0xFFCFA84C);
      case Icons.nightlight_round:       return const Color(0xFF5A5AAF);
      case Icons.workspace_premium_rounded: return const Color(0xFFBF4090);
      case Icons.lunch_dining_rounded:   return const Color(0xFFD4784A);
      default:                           return const Color(0xFF8A9CC5);
    }
  }

  Widget _buildAchievementCard(Achievement achievement) {
    final iconColor = achievement.isUnlocked
        ? _achievementIconColor(achievement)
        : AppColors.textHint;
    Color rarityColor;
    String rarityLabel;

    switch (achievement.rarity) {
      case 'gold':
        rarityColor = const Color(0xFFC09848);  // 沉穩焦糖金
        rarityLabel = '黃金';
        break;
      case 'silver':
        rarityColor = const Color(0xFF8878B0);  // 煙燻薰衣草
        rarityLabel = '白銀';
        break;
      case 'special':
        rarityColor = const Color(0xFFB86878);  // 玫瑰深粉
        rarityLabel = '特別';
        break;
      default:
        rarityColor = const Color(0xFFAA7860);  // 赤陶棕
        rarityLabel = '青銅';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: achievement.isUnlocked
              ? iconColor.withOpacity(0.35)
              : AppColors.surfaceMoss,
          width: achievement.isUnlocked ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: achievement.isUnlocked
                ? iconColor.withOpacity(0.12)
                : AppColors.cardShadow,
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: achievement.isUnlocked
                  ? iconColor.withOpacity(0.12)
                  : AppColors.surfaceMoss,
              shape: BoxShape.circle,
              border: Border.all(
                color: achievement.isUnlocked ? iconColor.withOpacity(0.6) : AppColors.textHint.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: achievement.isUnlocked
                  ? Icon(achievement.iconData, size: 26, color: iconColor)
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(achievement.iconData, size: 26, color: Colors.black.withOpacity(0.12)),
                        const Icon(Icons.lock_rounded,
                            color: AppColors.textHint, size: 20),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        achievement.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: achievement.isUnlocked
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: rarityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        rarityLabel,
                        style: TextStyle(
                          color: rarityColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: achievement.progress / achievement.total,
                    backgroundColor: AppColors.surfaceMoss,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      achievement.isUnlocked ? rarityColor : Theme.of(context).colorScheme.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.isUnlocked
                      ? '已完成！'
                      : '${achievement.progress} / ${achievement.total}',
                  style: TextStyle(
                    fontSize: 11,
                    color: achievement.isUnlocked ? rarityColor : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showStampDetail(BuildContext context, Spot spot, int visitCount) {
    final isVisited = visitCount > 0;
    final stampColor = _getStampColor(visitCount);

    // Calculate current distance to spot (if location known)
    double? _rawDist;
    String? distLabel;
    if (_stampPos != null) {
      _rawDist = Geolocator.distanceBetween(
        _stampPos!.latitude, _stampPos!.longitude, spot.lat, spot.lng);
      distLabel = _rawDist < 1000
          ? '距你 ${_rawDist.toStringAsFixed(0)} 公尺'
          : '距你 ${(_rawDist / 1000).toStringAsFixed(1)} 公里';
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isVisited) ...[
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: stampColor, width: 3),
                    color: stampColor.withOpacity(0.1),
                  ),
                  child: Center(child: Icon(_spotIconData(spot.category), size: 36, color: stampColor)),
                ),
                const SizedBox(height: 12),
                Text('✓ 已踩點 $visitCount 次',
                  style: TextStyle(color: stampColor, fontWeight: FontWeight.w700, fontSize: 16)),
              ] else ...[
                const Icon(Icons.lock_rounded, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                const Text('尚未踩點',
                  style: TextStyle(color: AppColors.textHint, fontWeight: FontWeight.w700, fontSize: 16)),
              ],
              const SizedBox(height: 8),
              Text(spot.name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
                textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(spot.address,
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                textAlign: TextAlign.center),
              if (distLabel != null) ...[
                const SizedBox(height: 6),
                Text(distLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: (_rawDist != null && _rawDist < _kCheckinRadius)
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  )),
              ],
              const SizedBox(height: 20),
              // GPS auto check-in notice
              Builder(builder: (bCtx) {
                final p = Theme.of(bCtx).colorScheme.primary;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.gps_fixed_rounded, size: 16, color: p),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '走到景點 100 公尺範圍內，\nApp 將自動幫你打卡！',
                          style: TextStyle(
                            fontSize: 12,
                            color: p,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                child: const Text('關閉'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('leaderboard')
          .orderBy('stampCount', descending: true).limit(20).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('還沒有人上榜！快去集章吧', style: TextStyle(color: AppColors.textHint)));
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final isMe = docs[i].id == myUid;
            final count = d['stampCount'] as int? ?? 0;
            final streak = d['streak'] as int? ?? 0;
            final name = d['displayName'] as String? ?? '匿名';
            final photo = d['photoURL'] as String? ?? '';
            final medal = i == 0 ? Icons.emoji_events_rounded : i == 1 ? Icons.workspace_premium_rounded : i == 2 ? Icons.military_tech_rounded : null;
            final medalColor = i == 0 ? const Color(0xFFC09848) : i == 1 ? const Color(0xFF8878B0) : const Color(0xFFAA7860);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMe ? Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.08) : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: isMe ? Border.all(color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.3)) : null,
              ),
              child: Row(children: [
                SizedBox(width: 28, child: medal != null
                    ? Icon(medal, color: medalColor, size: 22)
                    : Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHint))),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 18,
                  backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                  backgroundColor: AppColors.surfaceMoss,
                  child: photo.isEmpty ? const Icon(Icons.person_rounded, size: 18, color: AppColors.textHint) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isMe ? Theme.of(ctx).colorScheme.primary : AppColors.textPrimary)),
                  if (streak > 0) Text('連續 $streak 天', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: i < 3 ? medalColor : AppColors.textPrimary)),
                  const Text('景點', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                ]),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniMapTab() {
    final spots = _realSpots;

    // 嘉義市中心作為初始中心
    const center = LatLng(23.4801, 120.4515);

    return Column(
      children: [
        // ── 圖例 ──────────────────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            _legendItem(Colors.grey.shade400, '未踩點'),
            const SizedBox(width: 12),
            _legendItem(AppColors.stampBronze, '1-2次'),
            const SizedBox(width: 12),
            _legendItem(AppColors.stampSilver, '3-4次'),
            const SizedBox(width: 12),
            _legendItem(AppColors.stampGold, '5次+'),
            const Spacer(),
            // GPS 狀態（點擊跳到自己位置）
            GestureDetector(
              onTap: _stampPos != null
                  ? () => _miniMapCtrl.move(
                      LatLng(_stampPos!.latitude, _stampPos!.longitude),
                      15.5)
                  : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _stampPos != null
                      ? Icons.gps_fixed_rounded
                      : Icons.gps_not_fixed_rounded,
                  size: 14,
                  color: _stampPos != null
                      ? Theme.of(context).colorScheme.primary
                      : AppColors.textHint,
                ),
                const SizedBox(width: 3),
                Text(
                  _stampPos != null ? '定位' : '...',
                  style: TextStyle(
                    fontSize: 10,
                    color: _stampPos != null
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ]),
        ),

        // ── 可互動集章地圖（可愛色調）────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: FlutterMap(
                      mapController: _miniMapCtrl,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 12.5,
                        minZoom: 10.0,
                        maxZoom: 18.0,
                        cameraConstraint: CameraConstraint.containCenter(
                          bounds: _chiayiBounds,
                        ),
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        // CartoDB Light — 淡白清爽風格（與 YouBike/公車地圖一致）
                        TileLayer(
                          urlTemplate:
                              'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                          userAgentPackageName:
                              'com.chiayicity.explore_chiayi',
                          maxZoom: 19,
                        ),
                        // 景點 Markers
                        MarkerLayer(
                          markers: spots.map((spot) {
                            final count = _visitedSpots[spot.id] ?? 0;
                            final color = count > 0
                                ? _getStampColor(count)
                                : Colors.grey.shade400;
                            return Marker(
                              point: LatLng(spot.lat, spot.lng),
                              width: 48,
                              height: 56,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                onTap: () =>
                                    _showStampDetail(context, spot, count),
                                child: _StampMarker(
                                  icon: _spotIconData(spot.category),
                                  color: color,
                                  count: count,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        // 使用者位置藍點
                        if (_stampPos != null)
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(
                                  _stampPos!.latitude, _stampPos!.longitude),
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade500,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.blue.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ]),
                      ],
                    ),
                  ),
                ),

          ),
        ),

        // ── 景點卡片橫列（點擊跳到地圖標記）──────────────────
        Container(
          height: 116,
          color: AppColors.surface,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: spots.length,
            itemBuilder: (_, i) {
              final spot  = spots[i];
              final count = _visitedSpots[spot.id] ?? 0;
              final color = count > 0
                  ? _getStampColor(count)
                  : Colors.grey.shade400;
              return GestureDetector(
                onTap: () {
                  // 跳到地圖上的標記
                  _miniMapCtrl.move(LatLng(spot.lat, spot.lng), 15.5);
                },
                onLongPress: () => _showStampDetail(context, spot, count),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 78,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(
                        alpha: count > 0 ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: color.withValues(
                            alpha: count > 0 ? 0.5 : 0.25)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_spotIconData(spot.category), size: 20,
                          color: count > 0 ? _getStampColor(count) : AppColors.textHint),
                      const SizedBox(height: 3),
                      Text(
                        spot.name,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: color),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (count > 0)
                        Text('×$count',
                            style: TextStyle(
                                fontSize: 9,
                                color: color,
                                fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ],
  );


  void _showHowTo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '如何集章？',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _howToStep('1', '前往景點', '實際到訪景點，開啟App定位'),
            _howToStep('2', '掃描/拍照', '使用打卡相機拍照留念'),
            _howToStep('3', '驗證成功', '系統確認位置，印章立即點亮！'),
            _howToStep('4', '累積次數', '同一景點多次造訪，印章顏色越來越深'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _howToStep(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(num, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textHint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 集章地圖 Marker（可愛印章風格）──────────────────────────
class _StampMarker extends StatelessWidget {
  final IconData icon;
  final Color  color;
  final int    count;
  const _StampMarker({
    required this.icon,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final visited    = count > 0;
    final lightColor = Color.lerp(color, Colors.white, visited ? 0.72 : 0.88)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // 主圓形
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: lightColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: visited ? color : Colors.grey.shade300,
                  width: visited ? 2.5 : 1.5,
                ),
                boxShadow: visited
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18,
                  color: visited ? color : Colors.grey.shade400),
            ),
            // 次數 Badge
            if (count > 0)
              Positioned(
                top: -3, right: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '×$count',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        // 針尖
        CustomPaint(
          size: const Size(8, 5),
          painter: _StampPinTail(
              color: visited ? color : Colors.grey.shade400),
        ),
      ],
    );
  }
}

class _StampPinTail extends CustomPainter {
  final Color color;
  const _StampPinTail({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant _StampPinTail old) => old.color != color;
}
