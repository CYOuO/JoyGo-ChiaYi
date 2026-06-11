import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

  // Map<spotId, visitCount> — 每位使用者分開儲存到 Firestore
  Map<String, int> _visitedSpots = {};
  // 最近打卡的 spotId（排序用）
  String? _lastCheckedInSpotId;

  // 連續打卡天數
  int _streak = 0;
  String _lastCheckinDate = '';
  // 總打卡天數（所有有打卡的不重複日期）
  Set<String> _allCheckinDates = {};

  // GPS auto check-in
  StreamSubscription<Position>? _posStream;
  Position? _stampPos;
  final Map<String, DateTime> _lastCheckinTime = {};

  // 打卡照片牆
  List<String> _photoPaths = [];
  bool _photosLoading = true;

  Offset _cameraFabOffset = const Offset(16, 16);

  static const _kCheckinRadius = 100.0;
  static const _kCheckinCooldown = Duration(hours: 1); // 同一景點 1 小時內不重複打卡
  // Streak / dates 仍存本機（不需跨裝置）
  static const _kStreakKey   = 'stamp_streak_v1';
  static const _kLastDateKey = 'stamp_last_date_v1';
  static const _kAllDatesKey = 'stamp_all_dates_v1';

  // 涵蓋嘉義縣市 + 鄰近雲林、台南部分區域
  static final _chiayiBounds = LatLngBounds(
    const LatLng(22.85, 120.05), // 南至台南北邊
    const LatLng(23.90, 121.10), // 北至雲林南邊 + 阿里山區
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
    // 切換到打卡照片 tab 時自動重新整理
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _loadPhotos();
      }
    });
  }

  Future<void> _loadPhotos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final paths = await CameraScreen.getSavedPhotoPaths(uid: uid);
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

  // ── Firestore 路徑：users/{uid}/stamps ──────────────────────
  CollectionReference<Map<String, dynamic>>? get _stampsRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('stamps');
  }

  Future<void> _loadVisited() async {
    // ① 先從 Firestore 載入（每人分開）
    final ref = _stampsRef;
    if (ref != null) {
      try {
        final snap = await ref.get();
        final map = <String, int>{};
        for (final doc in snap.docs) {
          final d = doc.data();
          map[doc.id] = (d['visitCount'] as num?)?.toInt() ?? 1;
          // 載入冷卻時間
          final ts = d['lastCheckin'];
          if (ts is Timestamp) _lastCheckinTime[doc.id] = ts.toDate();
        }
        if (mounted) setState(() => _visitedSpots = map);
      } catch (_) {}
    }

    // ② 從 SharedPreferences 載入打卡統計（streak / dates）
    final prefs = await SharedPreferences.getInstance();
    _streak = prefs.getInt(_kStreakKey) ?? 0;
    _lastCheckinDate = prefs.getString(_kLastDateKey) ?? '';
    final allDatesRaw = prefs.getStringList(_kAllDatesKey) ?? [];
    _allCheckinDates = allDatesRaw.toSet();

    if (mounted) setState(() {});
  }

  Future<void> _saveVisited() async {
    // ① 存 streak / dates 到 SharedPreferences（裝置本機）
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kStreakKey, _streak);
    await prefs.setString(_kLastDateKey, _lastCheckinDate);
    await prefs.setStringList(_kAllDatesKey, _allCheckinDates.toList());

    // ② 同步打卡資料到 Firestore（每人分開）
    final ref = _stampsRef;
    if (ref != null) {
      final batch = FirebaseFirestore.instance.batch();
      for (final entry in _visitedSpots.entries) {
        if (entry.value <= 0) continue;
        final ts = _lastCheckinTime[entry.key];
        batch.set(ref.doc(entry.key), {
          'visitCount': entry.value,
          if (ts != null) 'lastCheckin': Timestamp.fromDate(ts),
        }, SetOptions(merge: true));
      }
      try { await batch.commit(); } catch (_) {}
    }

    _syncLeaderboard();
  }

  void _updateStreak() {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_lastCheckinDate == today) return;
    _allCheckinDates.add(today); // 記錄這天有打卡
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
      setState(() {
        _visitedSpots[spot.id] = newCount;
        _lastCheckedInSpotId = spot.id; // 讓此景點排最前
      });
      _saveVisited();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('「${spot.name}」自動打卡成功！第 $newCount 次造訪'),
        backgroundColor: _getSpotColor(spot.id, newCount),
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
        title: Builder(builder: (bCtx) {
          final p = Theme.of(bCtx).colorScheme.primary;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            DoodleCircle(color: p.withValues(alpha: 0.18), size: 18,
              child: Icon(Icons.star_rounded, size: 11, color: p)),
            const SizedBox(width: 6),
            const Text('集章成就', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            DoodleHeart(color: p.withValues(alpha: 0.55), size: 10),
          ]);
        }),
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
          isScrollable: true,
          tabAlignment: TabAlignment.start,
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
                  MaterialPageRoute(builder: (_) => const CameraScreen()))
                  .then((_) => _loadPhotos()),
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
      return NotebookBackground(
        lineColor: primary.withValues(alpha: 0.06),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DoodleCircle(color: primary.withValues(alpha: 0.12), size: 90,
              child: Icon(Icons.camera_alt_rounded, size: 40, color: primary.withValues(alpha: 0.5))),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              DoodleHeart(color: primary.withValues(alpha: 0.4), size: 12),
              const SizedBox(width: 6),
              DoodleHeart(color: primary.withValues(alpha: 0.3), size: 9),
            ]),
            const SizedBox(height: 12),
            const Text('還沒有打卡照片', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('拍下你的探索瞬間\n儲存後就會出現在這裡！',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.6)),
            const SizedBox(height: 20),
            StitchedBox(
              color: primary.withValues(alpha: 0.08),
              stitchColor: primary.withValues(alpha: 0.30),
              radius: 20, inset: 4, dashWidth: 4, dashGap: 3,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()))
                    .then((_) => _loadPhotos()),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.camera_alt_rounded, size: 18, color: primary),
                  const SizedBox(width: 8),
                  Text('開啟相機', style: TextStyle(color: primary, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
          ]),
        ),
      );
    }

    return NotebookBackground(
      lineColor: primary.withValues(alpha: 0.06),
      child: Column(children: [
        // ── 手帳風標題 ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            DoodleCircle(color: primary.withValues(alpha: 0.15), size: 30,
              child: Icon(Icons.photo_camera_rounded, size: 16, color: primary)),
            const SizedBox(width: 8),
            Text('打卡回憶 ${_photoPaths.length} 張',
              style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            DoodleHeart(color: primary.withValues(alpha: 0.45), size: 11),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()))
                  .then((_) => _loadPhotos()),
              child: StitchedBox(
                color: primary.withValues(alpha: 0.08),
                stitchColor: primary.withValues(alpha: 0.25),
                radius: 20, inset: 3, dashWidth: 4, dashGap: 3, stitchStrokeWidth: 1.0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_a_photo_rounded, size: 14, color: primary),
                  const SizedBox(width: 4),
                  Text('拍照', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        JournalDivider(color: primary.withValues(alpha: 0.18)),
        const SizedBox(height: 4),
        // ── 拍立得風格照片牆 ────────────────────────────────
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14,
              // 拍立得比例：寬:高 ≈ 3:4，加底部留白後 ≈ 0.72
              childAspectRatio: 0.72,
            ),
            itemCount: _photoPaths.length,
            itemBuilder: (ctx, i) {
              final path = _photoPaths[i];
              final file = File(path);
              // 每張略微隨機旋轉，模擬拍立得散落
              final angle = (i % 5 == 0 ? -0.025 : i % 5 == 1 ? 0.02 : i % 5 == 2 ? -0.015 : i % 5 == 3 ? 0.025 : 0.01);
              return SlideUpFadeIn(
                index: i, staggerDelay: const Duration(milliseconds: 30),
                child: GestureDetector(
                  onTap: () => _showPhotoDetail(ctx, path),
                  onLongPress: () => _confirmDeletePhoto(ctx, path, i),
                  child: Transform.rotate(
                    angle: angle,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(2, 4)),
                          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1)),
                        ],
                      ),
                      child: Column(children: [
                        // 上方留白（拍立得頂部白邊）
                        const SizedBox(height: 8),
                        // 左右留白包住照片
                        Expanded(child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: file.existsSync()
                                ? Image.file(file, fit: BoxFit.cover, width: double.infinity)
                                : Container(color: primary.withValues(alpha: 0.08),
                                    child: Icon(Icons.broken_image_outlined, color: AppColors.textHint, size: 24)),
                          ),
                        )),
                        // 拍立得底部大留白 + 可愛裝飾
                        _PolaroidBottom(index: i, primary: primary),
                        const SizedBox(height: 6),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _confirmDeletePhoto(BuildContext ctx, String path, int index) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Text('刪除照片', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        content: const Text('確定要刪除這張拍立得照片嗎？此動作無法還原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final key = CameraScreen.photoPathsKeyForUid(uid);
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(key) ?? [];
    paths.remove(path);
    await prefs.setStringList(key, paths);
    // 嘗試刪除本機檔案
    try { File(path).deleteSync(); } catch (_) {}
    if (mounted) setState(() => _photoPaths = List.from(paths));
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
    // 已打卡景點排最前，最近打卡的排第一；未打卡的排後面
    final spots = List<Spot>.from(_realSpots)
      ..sort((a, b) {
        final va = _visitedSpots[a.id] ?? 0;
        final vb = _visitedSpots[b.id] ?? 0;
        if (va > 0 && vb == 0) return -1;
        if (va == 0 && vb > 0) return 1;
        if (va > 0 && vb > 0) {
          // 最近打卡的排最前
          if (a.id == _lastCheckedInSpotId) return -1;
          if (b.id == _lastCheckedInSpotId) return 1;
          final ta = _lastCheckinTime[a.id] ?? DateTime(2000);
          final tb = _lastCheckinTime[b.id] ?? DateTime(2000);
          return tb.compareTo(ta);
        }
        return 0;
      });
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
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Theme.of(context).colorScheme.primary,
                             Color.lerp(Theme.of(context).colorScheme.primary, const Color(0xFF90CAF9), 0.45)!],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Stack(children: [
                  // 右上角裝飾
                  Positioned(top: -6, right: -6,
                    child: DoodleHeart(color: Colors.white.withValues(alpha: 0.18), size: 40)),
                  Positioned(bottom: 0, right: 20,
                    child: DoodleCircle(color: Colors.white.withValues(alpha: 0.10), size: 30, child: const SizedBox())),
                  Column(
                  children: [
                    Row(
                      children: [
                        DoodleCircle(color: Colors.white.withValues(alpha: 0.22), size: 50,
                          child: const Icon(Icons.map_rounded, size: 26, color: Colors.white)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Text('嘉義探索進度',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(width: 6),
                                DoodleHeart(color: Colors.white.withValues(alpha: 0.7), size: 12),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                '$visitedCount / $total 個景點已踩點',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        DoodleCircle(
                          color: Colors.white.withValues(alpha: 0.22),
                          size: 52,
                          child: Text(
                            '${((visitedCount / total.clamp(1, 9999)) * 100).toInt()}%',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 手繪感進度條
                    Stack(children: [
                      Container(height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        )),
                      FractionallySizedBox(
                        widthFactor: total > 0 ? (visitedCount / total).clamp(0.0, 1.0) : 0,
                        child: Container(height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 6)],
                          )),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      // 連續打卡
                      if (_streak > 0) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_streak >= 7 ? Icons.local_fire_department_rounded : Icons.trending_up_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text('連續 $_streak 天${_streak >= 30 ? ' 傳說！' : _streak >= 7 ? ' 厲害！' : ''}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      if (_streak > 0 && _allCheckinDates.isNotEmpty) const SizedBox(width: 8),
                      // 累計打卡天數
                      if (_allCheckinDates.isNotEmpty) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text('累計 ${_allCheckinDates.length} 天打卡',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ]),
                  ],
                ),  // Column
                ]), // Stack children
              ),    // Container
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

                final stampC = _getSpotColor(spot.id, visitCount);
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
                                    color: stampC,
                                    width: 3,
                                  ),
                                ),
                              ),
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: stampC.withValues(alpha: 0.18),
                                ),
                                child: Center(
                                  child: Icon(_spotIconData(spot.category), size: 24, color: stampC.withValues(alpha: 0.9)),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: stampC,
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
                              color: stampC,
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

  // 馬卡龍色系印章色盤（每個景點有唯一的柔和色彩）
  static const _kStampMacaronColors = [
    Color(0xFFE8A598), // 珊瑚粉
    Color(0xFF9FC5E8), // 天空藍
    Color(0xFFA8D5BA), // 薄荷綠
    Color(0xFFFFD966), // 奶油黃
    Color(0xFFB7A4D1), // 薰衣草紫
    Color(0xFFF4B8C1), // 玫瑰粉
    Color(0xFF8BC4D4), // 粉藍
    Color(0xFFC5E0B4), // 抹茶綠
    Color(0xFFFFB347), // 橘杏
    Color(0xFFD4A5C9), // 藕紫
  ];

  /// 根據景點 ID 取得馬卡龍顏色；造訪次數越多顏色越深
  Color _getSpotColor(String spotId, int visitCount) {
    if (visitCount == 0) return AppColors.textHint;
    final base = _kStampMacaronColors[spotId.hashCode.abs() % _kStampMacaronColors.length];
    if (visitCount >= 5) return Color.lerp(base, Colors.brown.shade700, 0.22)!;
    if (visitCount >= 3) return Color.lerp(base, Colors.black, 0.10)!;
    return base;
  }

  /// 相容舊有呼叫（無景點 ID 場合，依造訪次數返回固定色）
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
    final unlocked = achievements.where((a) => a.isUnlocked).length;
    final primary = Theme.of(context).colorScheme.primary;

    return NotebookBackground(
      lineColor: primary.withValues(alpha: 0.07),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── 手帳風標題頁首 ──────────────────────────────
          JournalPageHeader(
            title: '成就徽章 — 探索嘉義的旅行紀錄',
            color: primary,
          ),
          const SizedBox(height: 12),

          // ── 三格統計（紙條貼紙風格）──────────────────────
          Row(children: [
            _achieveStatJournal('$unlocked', '已解鎖', const Color(0xFFC09848), Icons.star_rounded),
            const SizedBox(width: 10),
            _achieveStatJournal('${achievements.length - unlocked}', '進行中', const Color(0xFF8878B0), Icons.hourglass_top_rounded),
            const SizedBox(width: 10),
            _achieveStatJournal('${achievements.length}', '全部', const Color(0xFF6A9888), Icons.emoji_events_rounded),
          ]),
          const SizedBox(height: 8),

          JournalDivider(color: primary.withValues(alpha: 0.25)),
          const SizedBox(height: 12),

          // ── 成就清單 ────────────────────────────────────
          ...achievements.map((a) => _buildAchievementCardJournal(a)),
        ],
      ),
    );
  }

  Widget _achieveStatJournal(String value, String label, Color color, IconData icon) {
    return Expanded(
      child: StitchedBox(
        color: color.withValues(alpha: 0.08),
        stitchColor: color.withValues(alpha: 0.30),
        radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _buildAchievementCardJournal(Achievement achievement) {
    final primary = Theme.of(context).colorScheme.primary;
    final iconColor = achievement.isUnlocked
        ? _achievementIconColor(achievement)
        : AppColors.textHint.withValues(alpha: 0.5);

    Color rarityColor;
    String rarityLabel;
    String raritySticker;
    switch (achievement.rarity) {
      case 'gold':
        rarityColor = const Color(0xFFC09848); rarityLabel = '珍稀'; raritySticker = '✦';
        break;
      case 'silver':
        rarityColor = const Color(0xFF8878B0); rarityLabel = '稀有'; raritySticker = '◈';
        break;
      case 'special':
        rarityColor = const Color(0xFFB86878); rarityLabel = '限定'; raritySticker = '★';
        break;
      default:
        rarityColor = const Color(0xFFAA7860); rarityLabel = '收藏'; raritySticker = '◆';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SlideUpFadeIn(
        child: _AchievementCardAnimated(
          achievement: achievement,
          rarityColor: rarityColor,
          rarityLabel: rarityLabel,
          raritySticker: raritySticker,
          iconColor: iconColor,
          primary: primary,
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

  void _showStampDetail(BuildContext context, Spot spot, int visitCount) {
    final isVisited = visitCount > 0;
    final stampColor = _getSpotColor(spot.id, visitCount);

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
    final primary = Theme.of(context).colorScheme.primary;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('leaderboard')
          .orderBy('stampCount', descending: true).limit(20).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return NotebookBackground(
          lineColor: primary.withValues(alpha: 0.06),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DoodleCircle(color: primary.withValues(alpha: 0.12), size: 72,
              child: Icon(Icons.emoji_events_rounded, size: 36, color: primary.withValues(alpha: 0.5))),
            const SizedBox(height: 16),
            const Text('還沒有人上榜！', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('快去集章吧 ✨', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
          ])),
        );
        final myUid = FirebaseAuth.instance.currentUser?.uid;

        // top-3 顏色 & 圖示
        const podiumColors = [Color(0xFFC09848), Color(0xFF8878B0), Color(0xFFAA7860)];
        const podiumIcons  = [Icons.emoji_events_rounded, Icons.workspace_premium_rounded, Icons.military_tech_rounded];
        const podiumBg     = [Color(0xFFFFF8E6), Color(0xFFF2EFF8), Color(0xFFFFF0EC)];
        const podiumLabel  = ['🥇 第一', '🥈 第二', '🥉 第三'];

        return NotebookBackground(
          lineColor: primary.withValues(alpha: 0.06),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              JournalPageHeader(title: '探索排行榜 — 嘉義旅人競技場', color: primary),
              const SizedBox(height: 14),
              JournalDivider(color: primary.withValues(alpha: 0.20)),
              const SizedBox(height: 12),

              ...docs.asMap().entries.map((e) {
                final i = e.key;
                final d = e.value.data();
                final isMe = e.value.id == myUid;
                final count = d['stampCount'] as int? ?? 0;
                final streak = d['streak'] as int? ?? 0;
                final name = d['displayName'] as String? ?? '匿名旅人';
                final photo = d['photoURL'] as String? ?? '';
                final isTop3 = i < 3;

                return SlideUpFadeIn(
                  index: i,
                  staggerDelay: const Duration(milliseconds: 50),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: isTop3
                      ? StitchedBox(
                          color: podiumBg[i],
                          stitchColor: podiumColors[i].withValues(alpha: 0.35),
                          radius: 18, inset: 4, dashWidth: 4, dashGap: 3,
                          padding: const EdgeInsets.all(14),
                          child: _leaderRow(ctx, i, d, isMe, isTop3: true,
                            medalIcon: podiumIcons[i], medalColor: podiumColors[i],
                            podiumLabel: podiumLabel[i], name: name, photo: photo,
                            count: count, streak: streak, primary: primary),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isMe ? primary.withValues(alpha: 0.07) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: isMe ? Border.all(color: primary.withValues(alpha: 0.25)) : null,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                          ),
                          child: _leaderRow(ctx, i, d, isMe, isTop3: false,
                            name: name, photo: photo, count: count, streak: streak, primary: primary),
                        ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _leaderRow(BuildContext ctx, int i, Map<String, dynamic> d, bool isMe, {
    required bool isTop3, required String name, required String photo,
    required int count, required int streak, required Color primary,
    IconData? medalIcon, Color? medalColor, String? podiumLabel,
  }) {
    final mc = medalColor ?? AppColors.textHint;
    return Row(children: [
      // 排名
      SizedBox(width: 36, child: isTop3
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(medalIcon!, color: mc, size: 24),
              Text(podiumLabel!, style: TextStyle(fontSize: 9, color: mc, fontWeight: FontWeight.w700)),
            ])
          : Text('${i + 1}', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHint))),
      const SizedBox(width: 10),
      // 頭貼
      DoodleCircle(
        color: (isTop3 ? mc : primary).withValues(alpha: 0.18),
        size: isTop3 ? 48 : 40,
        child: ClipOval(
          child: photo.isNotEmpty
              ? Image.network(photo, width: isTop3 ? 48 : 40, height: isTop3 ? 48 : 40, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, size: 20, color: AppColors.textHint))
              : Icon(Icons.person_rounded, size: 20, color: AppColors.textHint),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: isTop3 ? 15 : 14,
            color: isMe ? primary : AppColors.textPrimary))),
          if (isMe) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text('我', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (streak > 0) Row(children: [
          Icon(Icons.local_fire_department_rounded, size: 11,
              color: streak >= 7 ? const Color(0xFFFF6B2B) : AppColors.textHint),
          const SizedBox(width: 2),
          Text('連續 $streak 天', style: TextStyle(
            fontSize: 11,
            color: streak >= 7 ? const Color(0xFFFF6B2B) : AppColors.textHint)),
        ]),
      ])),
      // 景點數
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('$count', style: TextStyle(
          fontSize: isTop3 ? 22 : 18, fontWeight: FontWeight.w900,
          color: isTop3 ? mc : (isMe ? primary : AppColors.textPrimary))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('景點', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
          if (isTop3) ...[
            const SizedBox(width: 2),
            DoodleHeart(color: mc.withValues(alpha: 0.6), size: 10),
          ],
        ]),
      ]),
    ]);
  }

  Widget _buildMiniMapTab() {
    final spots = _realSpots;
    final primary = Theme.of(context).colorScheme.primary;
    final visitedCount = _visitedSpots.keys.where((k) => (_visitedSpots[k] ?? 0) > 0).length;

    // 嘉義市中心作為初始中心
    const center = LatLng(23.4801, 120.4515);

    return Column(
      children: [
        // ── 手帳風圖例 bar ──────────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: StitchedBox(
            color: primary.withValues(alpha: 0.04),
            stitchColor: primary.withValues(alpha: 0.18),
            radius: 14, inset: 3, dashWidth: 4, dashGap: 3.5, stitchStrokeWidth: 1.0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              // 踩點進度
              DoodleCircle(color: primary.withValues(alpha: 0.15), size: 28,
                child: Icon(Icons.map_rounded, size: 14, color: primary)),
              const SizedBox(width: 8),
              Text('$visitedCount/${spots.length}', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: primary)),
              const SizedBox(width: 4),
              const Text('踩點', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              _legendItem(Colors.grey.shade400, '未踩'),
              const SizedBox(width: 8),
              _legendItem(AppColors.stampBronze, '1-2次'),
              const SizedBox(width: 8),
              _legendItem(AppColors.stampSilver, '3-4次'),
              const SizedBox(width: 8),
              _legendItem(AppColors.stampGold, '5+'),
              const Spacer(),
              // GPS 狀態
              GestureDetector(
                onTap: _stampPos != null
                    ? () => _miniMapCtrl.move(
                        LatLng(_stampPos!.latitude, _stampPos!.longitude), 15.5)
                    : null,
                child: DoodleCircle(
                  color: (_stampPos != null ? primary : AppColors.textHint).withValues(alpha: 0.15),
                  size: 28,
                  child: Icon(
                    _stampPos != null ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                    size: 14,
                    color: _stampPos != null ? primary : AppColors.textHint,
                  ),
                ),
              ),
            ]),
          ),
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
                        initialZoom: 11.0,
                        minZoom: 9.0,
                        maxZoom: 18.0,
                        cameraConstraint: CameraConstraint.containCenter(
                          bounds: _chiayiBounds,
                        ),
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        // 底圖：CartoDB Voyager（彩色普通地圖，有黃綠藍）
                        TileLayer(
                          urlTemplate:
                              'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                          userAgentPackageName:
                              'com.chiayicity.explore_chiayi',
                          maxZoom: 19,
                        ),
                        // 白色遮罩 + 打卡圓形鏤空（讓已打卡範圍顯示彩色地圖）
                        _WhiteRevealLayer(
                          spots: spots,
                          visitedSpots: _visitedSpots,
                        ),
                        // 景點 Markers
                        MarkerLayer(
                          markers: spots.map((spot) {
                            final count = _visitedSpots[spot.id] ?? 0;
                            final color = count > 0
                                ? _getSpotColor(spot.id, count)
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
                  ? _getSpotColor(spot.id, count)
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
                          color: count > 0 ? _getSpotColor(spot.id, count) : AppColors.textHint),
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

// ── 地圖白色遮罩 + 已打卡鏤空揭示層 ──────────────────────────
class _WhiteRevealLayer extends StatelessWidget {
  final List<Spot> spots;
  final Map<String, int> visitedSpots;
  const _WhiteRevealLayer({required this.spots, required this.visitedSpots});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final visited = spots
        .where((s) => (visitedSpots[s.id] ?? 0) > 0)
        .map((s) => (LatLng(s.lat, s.lng), visitedSpots[s.id]!))
        .toList();
    return IgnorePointer(
      child: CustomPaint(
        painter: _RevealPainter(camera: camera, visited: visited),
        size: Size.infinite,
      ),
    );
  }
}

class _RevealPainter extends CustomPainter {
  final MapCamera camera;
  final List<(LatLng, int)> visited;
  _RevealPainter({required this.camera, required this.visited});

  @override
  void paint(Canvas canvas, Size size) {
    // 白色半透明遮罩 layer（讓未打卡區顯示淡白）
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xCCFFFFFF), // ~80% 白色
    );

    // 對已打卡景點：用 dstOut 打透明洞，讓底圖彩色地圖透出
    final holePaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20); // 邊緣柔化

    for (final (latlng, count) in visited) {
      final pt = camera.latLngToScreenPoint(latlng);
      final meters = count >= 5 ? 500.0 : count >= 3 ? 380.0 : 260.0;
      // 將公尺轉為螢幕像素
      final mpp = 156543.03392 *
          math.cos(latlng.latitude * math.pi / 180) /
          math.pow(2, camera.zoom);
      final px = (meters / mpp).clamp(20.0, 600.0);
      canvas.drawCircle(Offset(pt.x.toDouble(), pt.y.toDouble()), px, holePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.camera != camera || old.visited.length != visited.length;
}

// ── 成就卡片（帶動畫）──────────────────────────────────────
class _AchievementCardAnimated extends StatefulWidget {
  final Achievement achievement;
  final Color rarityColor;
  final String rarityLabel;
  final String raritySticker;
  final Color iconColor;
  final Color primary;

  const _AchievementCardAnimated({
    required this.achievement,
    required this.rarityColor,
    required this.rarityLabel,
    required this.raritySticker,
    required this.iconColor,
    required this.primary,
  });

  @override
  State<_AchievementCardAnimated> createState() => _AchievementCardAnimatedState();
}

class _AchievementCardAnimatedState extends State<_AchievementCardAnimated>
    with TickerProviderStateMixin {
  late final AnimationController _iconCtrl;
  late final AnimationController _barCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _iconScale;
  late final Animation<double> _barFill;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    // Icon bounce
    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _iconScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.92).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 30),
    ]).animate(_iconCtrl);

    // Animated progress bar fill
    _barCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _barFill = Tween<double>(
      begin: 0,
      end: (widget.achievement.progress / widget.achievement.total).clamp(0.0, 1.0),
    ).animate(CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic));

    // Pulse for rarity sticker on unlocked
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Delay by stagger based on achievement index
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) {
        _barCtrl.forward();
        if (widget.achievement.isUnlocked) _iconCtrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    _barCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final rc = widget.rarityColor;
    final ic = widget.iconColor;
    final p = widget.primary;

    return StitchedBox(
      color: a.isUnlocked ? ic.withValues(alpha: 0.06) : AppColors.surface,
      stitchColor: a.isUnlocked ? ic.withValues(alpha: 0.32) : AppColors.textHint.withValues(alpha: 0.12),
      radius: 18, inset: 5, dashWidth: 5, dashGap: 3,
      padding: const EdgeInsets.all(14),
      child: Stack(children: [
        // 右上角稀有度貼紙（解鎖後會脈衝）
        Positioned(
          top: 0, right: 0,
          child: a.isUnlocked
              ? AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Transform.scale(
                    scale: _pulse.value,
                    child: _rarityBadge(a, rc, true),
                  ),
                )
              : _rarityBadge(a, rc, false),
        ),

        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 圖示印章（解鎖後有彈跳）
          AnimatedBuilder(
            animation: _iconScale,
            builder: (_, child) => Transform.scale(
              scale: a.isUnlocked ? _iconScale.value : 1.0,
              child: child,
            ),
            child: DoodleCircle(
              color: a.isUnlocked ? ic.withValues(alpha: 0.18) : AppColors.surfaceMoss,
              size: 60,
              child: a.isUnlocked
                  ? Text(a.icon, style: const TextStyle(fontSize: 28))
                  : Stack(alignment: Alignment.center, children: [
                      Text(a.icon,
                          style: TextStyle(fontSize: 22,
                              color: Colors.black.withValues(alpha: 0.07))),
                      Icon(Icons.lock_rounded, size: 22,
                          color: AppColors.textHint.withValues(alpha: 0.5)),
                    ]),
            ),
          ),
          const SizedBox(width: 12),

          // 文字區
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 50),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: a.isUnlocked ? AppColors.textPrimary : AppColors.textHint,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(a.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: a.isUnlocked ? AppColors.textSecondary : AppColors.textHint.withValues(alpha: 0.7),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),

                // 手繪感進度條（動畫填充）
                Stack(children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMoss,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _barFill,
                    builder: (_, __) => FractionallySizedBox(
                      widthFactor: _barFill.value,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            a.isUnlocked ? rc : p.withValues(alpha: 0.5),
                            a.isUnlocked ? rc.withValues(alpha: 0.7) : p.withValues(alpha: 0.35),
                          ]),
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: a.isUnlocked
                              ? [BoxShadow(color: rc.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 1))]
                              : [],
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),

                Row(children: [
                  Icon(
                    a.isUnlocked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 13,
                    color: a.isUnlocked ? rc : AppColors.textHint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    a.isUnlocked ? '已解鎖！' : '${a.progress} / ${a.total}',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: a.isUnlocked ? rc : AppColors.textHint,
                    ),
                  ),
                  if (a.isUnlocked) ...[
                    const SizedBox(width: 5),
                    DoodleHeart(color: rc.withValues(alpha: 0.75), size: 13),
                    const SizedBox(width: 3),
                    DoodleHeart(color: rc.withValues(alpha: 0.45), size: 10),
                  ],
                ]),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _rarityBadge(Achievement a, Color rc, bool unlocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: rc.withValues(alpha: unlocked ? 0.20 : 0.08),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
        boxShadow: unlocked
            ? [BoxShadow(color: rc.withValues(alpha: 0.25), blurRadius: 4)]
            : [],
      ),
      child: Text(
        '${widget.raritySticker} ${widget.rarityLabel}',
        style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w800,
          color: unlocked ? rc : AppColors.textHint,
        ),
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

// ─── 拍立得底部裝飾（每張有不同的可愛樣式）──────────────────
class _PolaroidBottom extends StatelessWidget {
  final int index;
  final Color primary;
  const _PolaroidBottom({required this.index, required this.primary});

  // 7 種底部樣式
  static const _kStyles = [
    'hearts',      // 愛心排列
    'stars',       // 星星串
    'flowers',     // 小花
    'label_chiayi', // 嘉義文字標籤
    'dots',        // 彩色圓點
    'music',       // 音符
    'label_travel', // 旅行文字標籤
  ];

  static const _kMacaronColors = [
    Color(0xFFE8A598), Color(0xFF9FC5E8), Color(0xFFA8D5BA),
    Color(0xFFFFD966), Color(0xFFB7A4D1), Color(0xFFF4B8C1),
    Color(0xFFFFB347), Color(0xFF87CEEB),
  ];

  @override
  Widget build(BuildContext context) {
    final style = _kStyles[index % _kStyles.length];
    final c1 = _kMacaronColors[index % _kMacaronColors.length];
    final c2 = _kMacaronColors[(index + 3) % _kMacaronColors.length];
    final c3 = _kMacaronColors[(index + 5) % _kMacaronColors.length];

    Widget content;
    switch (style) {
      case 'hearts':
        content = Row(mainAxisAlignment: MainAxisAlignment.center,
          children: ['♥', '♡', '♥', '♡', '♥'].asMap().entries.map((e) =>
            Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(e.value, style: TextStyle(
                fontSize: e.key == 2 ? 14 : 10,
                color: e.key % 2 == 0 ? c1 : c2.withValues(alpha: 0.6))))
          ).toList());
        break;
      case 'stars':
        content = Row(mainAxisAlignment: MainAxisAlignment.center,
          children: ['✦', '★', '✦', '★', '✦'].asMap().entries.map((e) =>
            Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(e.value, style: TextStyle(
                fontSize: e.key == 2 ? 13 : 9,
                color: e.key % 2 == 0 ? c2 : c3.withValues(alpha: 0.7))))
          ).toList());
        break;
      case 'flowers':
        content = Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['✿', '❀', '✾', '❀', '✿'].asMap().entries.map((e) =>
            Text(e.value, style: TextStyle(
              fontSize: e.key == 2 ? 14 : 10,
              color: [c1, c2, c3, c2, c1][e.key].withValues(alpha: 0.85)))
          ).toList());
        break;
      case 'label_chiayi':
        content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('✦', style: TextStyle(fontSize: 8, color: c1)),
          const SizedBox(width: 5),
          Text('嘉義回憶', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: primary.withValues(alpha: 0.65), letterSpacing: 1.2)),
          const SizedBox(width: 5),
          Text('✦', style: TextStyle(fontSize: 8, color: c1)),
        ]);
        break;
      case 'dots':
        content = Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(7, (k) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: k == 3 ? 10 : 7,
            height: k == 3 ? 10 : 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kMacaronColors[(index + k) % _kMacaronColors.length].withValues(alpha: 0.80)),
          )));
        break;
      case 'music':
        content = Row(mainAxisAlignment: MainAxisAlignment.center,
          children: ['♩', '♪', '♫', '♪', '♩'].asMap().entries.map((e) =>
            Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(e.value, style: TextStyle(
                fontSize: e.key == 2 ? 14 : 10,
                color: e.key % 2 == 0 ? c3 : c1)))
          ).toList());
        break;
      case 'label_travel':
      default:
        content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('☁', style: TextStyle(fontSize: 9, color: c2)),
          const SizedBox(width: 4),
          Text('旅行紀念', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: primary.withValues(alpha: 0.65), letterSpacing: 1.2)),
          const SizedBox(width: 4),
          Text('☁', style: TextStyle(fontSize: 9, color: c2)),
        ]);
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      child: content,
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
