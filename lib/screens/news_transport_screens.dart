import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:animated_digit/animated_digit.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../widgets/common_widgets.dart' show TransportCardSkeleton;
import '../services/rail_service.dart';
import '../services/bus_notification_service.dart';
import 'map_screen.dart';
export 'news_screen.dart' show NewsScreen;

String _formatTime(String t) {
  if (t.isEmpty || t == '--:--') return '--:--';
  if (t.length >= 5) return t.substring(0, 5);
  return t;
}

// ═══════════════════════════════════════════════════════════════
//  TRANSPORT SCREEN  ─ 日記手繪風，搭配 AppColors 色票
// ═══════════════════════════════════════════════════════════════

// 附近路線卡片循環配色（與主題 palette 一致）
const _kRouteColors = [
  Color(0xFF5B8FAF), Color(0xFF5B8A5F), Color(0xFF4A7A5A),
  Color(0xFF88B8C8), Color(0xFFC4856A), Color(0xFFB06090),
  Color(0xFFB07A30), Color(0xFF7B6BAE),
];

class TransportScreen extends StatefulWidget {
  final int initialTab;
  final void Function(int)? onSwitchTab;
  const TransportScreen({super.key, this.initialTab = 0, this.onSwitchTab});
  @override State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Timer? _countdown, _debounce;
  int _secs = 30;
  int _busTick = 0;
  // Bus
  String _busCity = 'Chiayi', _busRoute = '';
  int _busSubTab = 0;          // 0=搜尋路線, 1=搜尋站牌
  String _busStopQuery = '';
  List<String> _busStopRoutes = [];
  bool _busSearching = false;
  final _busCtrl = TextEditingController();
  Future<Map<String, dynamic>>? _busFuture;
  // 附近站牌（GPS）
  List<Map<String, dynamic>>? _nearbyStops;
  bool _nearbyLoading = false;
  String? _nearbyError; // 'permission_denied' | 'gps_error' | 'backend_error' | null
  // 計算屬性：根據其他 state 自動推導，不需要手動設值
  String get _busMode {
    if (_busStopQuery.isNotEmpty) return 'stop';
    if (_busFuture != null || _busRoute.isNotEmpty) return 'route';
    return 'idle';
  }

  // YouBike
  Future<Map<String, dynamic>>? _ybFuture;
  String _ybSearch = '';
  Position? _ybPosition;
  bool _ybLocating = false;

  // TRA
  Future<Map<String, dynamic>>? _traLive;
  List<Map<String, dynamic>>? _traTrains;
  bool _traLoading = false;
  String? _traError, _traUpdateTime;
  int _traPage = 0;
  static const _kTraPerPage = 5;
  late final PageController _traPageCtrl = PageController();

  // Alishan
  List<Map<String, dynamic>>? _aliDocs;
  bool _aliLoading = false;

  // THSR
  List<Map<String, dynamic>>? _thsrTrains;
  bool _thsrLoading = false;
  String? _thsrError;

  static const _traStations = {
    '基隆': '0900', '台北': '1000', '桃園': '1080', '新竹': '1210',
    '竹南': '1250', '苗栗': '3160', '豐原': '3230', '台中': '3300',
    '彰化': '3360', '員林': '3390', '斗六': '3470', '斗南': '3480',
    '大林': '4050', '民雄': '4060', '嘉北': '4070', '嘉義': '4080',
    '水上': '4090', '南靖': '4100', '新營': '4120', '台南': '4220',
    '新左營': '4320', '高雄': '4400', '屏東': '4310',
  };
  String _traO = '嘉義', _traD = '台北';

  static const _thsrStations = {
    '南港': '0990', '台北': '1000', '板橋': '1010', '桃園': '1020',
    '新竹': '1030', '苗栗': '1035', '台中': '1040', '彰化': '1043',
    '雲林': '1047', '嘉義': '1050', '台南': '1060', '左營': '1070',
  };
  String _thsrO = '嘉義', _thsrD = '台北';

  static const _aliStations = [
    '嘉義', '北門', '鹿麻產', '竹崎', '木履寮', '樟腦寮', '獨立山',
    '梨園寮', '交力坪', '水社寮', '奮起湖', '多林', '十字路', '神木', '沼平', '阿里山',
  ];
  String _aliO = '嘉義', _aliD = '奮起湖';

  String get _today {
    final n = DateTime.now().toUtc().add(const Duration(hours: 8));
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));
    _tabCtrl.addListener(_onTab);
    _loadTab(_tabCtrl.index);
    _startTimer();
  }

  void _onTab() {
    if (_tabCtrl.indexIsChanging) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() { _secs = 30; _loadTab(_tabCtrl.index); });
    });
  }

  Future<void> _fetchNearbyStops() async {
    if (_nearbyLoading) return;
    setState(() { _nearbyLoading = true; _nearbyError = null; });

    // ── Step 1: GPS ──────────────────────────────────────────────
    Position pos;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() { _nearbyLoading = false; _nearbyError = 'permission_denied'; });
        return;
      }
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
    } catch (e) {
      debugPrint('GPS error: $e');
      if (mounted) setState(() { _nearbyLoading = false; _nearbyError = 'gps_error'; });
      return;
    }

    // ── Step 2: 後端 API（GPS 已成功）────────────────────────────
    try {
      final res = await RailService.getNearbyBusStops(_busCity, pos.latitude, pos.longitude, radius: 800);
      if (!mounted) return;
      final data = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() { _nearbyStops = data; _nearbyLoading = false; });
    } catch (e) {
      debugPrint('Nearby API error: $e');
      // GPS 成功但後端失敗 → 顯示空清單 + 後端錯誤提示
      if (mounted) setState(() { _nearbyLoading = false; _nearbyStops = []; _nearbyError = 'backend_error'; });
    }
  }

  Future<void> _fetchYbLocation() async {
    if (_ybLocating || _ybPosition != null) return;
    setState(() => _ybLocating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { if (mounted) setState(() => _ybLocating = false); return; }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() { _ybPosition = pos; _ybLocating = false; });
    } catch (_) { if (mounted) setState(() => _ybLocating = false); }
  }

  void _loadTab(int i) {
    if (!mounted) return;
    setState(() {
      switch (i) {
        case 0: if (_busRoute.isNotEmpty) _busFuture = RailService.getBusDynamic(_busCity, _busRoute); break;
        case 1: _ybFuture ??= RailService.getYoubikeData(); break;
        case 2:
          _traLive ??= RailService.getTraLiveBoard(_traStations[_traO]!);
          if (_traTrains == null && !_traLoading) _fetchTra();
          break;
        case 3: if (_aliDocs == null && !_aliLoading) _fetchAli(); break;
        case 4: if (_thsrTrains == null && !_thsrLoading) _fetchThsr(); break;
      }
    });
    if (i == 0 && _nearbyStops == null && !_nearbyLoading) _fetchNearbyStops();
    if (i == 1) _fetchYbLocation();
  }

  Future<void> _fetchTra({bool auto = false}) async {
    if (_traO == _traD) { if (!auto) setState(() { _traTrains = []; _traLoading = false; _traError = '請選擇不同的起迄站'; }); return; }
    if (!mounted) return;
    if (!auto) setState(() { _traLoading = true; _traError = null; _traTrains = []; });
    try {
      final res = await RailService.queryTra(origin: _traO, dest: _traD, trainDate: _today);
      if (mounted) { setState(() { _traTrains = (res['data'] as List).map((d) => Map<String, dynamic>.from(d as Map)).toList(); _traUpdateTime = res['updateTime'] as String?; _traLoading = false; _traPage = 0; }); if (_traPageCtrl.hasClients) _traPageCtrl.jumpToPage(0); }
    } catch (_) { if (mounted && !auto) setState(() { _traLoading = false; _traError = '無法連線，請稍候重試'; }); }
  }

  Future<void> _fetchThsr({bool auto = false}) async {
    if (_thsrO == _thsrD) { if (!auto) setState(() { _thsrTrains = []; _thsrLoading = false; _thsrError = '請選擇不同的起迄站'; }); return; }
    if (!mounted) return;
    if (!auto) setState(() { _thsrLoading = true; _thsrError = null; _thsrTrains = []; });
    try {
      final res = await RailService.queryThsr(origin: _thsrO, dest: _thsrD, trainDate: _today);
      if (mounted) setState(() { _thsrTrains = (res['data'] as List).map((d) => Map<String, dynamic>.from(d as Map)).toList(); _thsrLoading = false; });
    } catch (_) { if (mounted && !auto) setState(() { _thsrLoading = false; _thsrError = '無法連線，請稍候重試'; }); }
  }

  Future<void> _fetchAli({bool auto = false}) async {
    if (!mounted) return;
    if (!auto) setState(() => _aliLoading = true);
    try {
      final r = await RailService.fetchAlishanSchedules();
      if (mounted) setState(() { _aliDocs = r; _aliLoading = false; });
    } catch (_) { if (mounted && !auto) setState(() => _aliLoading = false); }
  }

  void _startTimer() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secs <= 1) {
          _secs = 35;
          final i = _tabCtrl.index;
          
          if (i == 0) {
            // 🌟 發送無感更新信號
            _busTick++; 
            if (_busMode == 'route' && _busRoute.isNotEmpty) {
              _busFuture = RailService.getBusDynamic(_busCity, _busRoute);
            }
          }
          else if (i == 1) _ybFuture = RailService.getYoubikeData();
          else if (i == 2) { _traLive = RailService.getTraLiveBoard(_traStations[_traO]!); _fetchTra(auto: true); }
          else if (i == 3) _fetchAli(auto: true);
          else if (i == 4) _fetchThsr(auto: true);
        } else { _secs--; }
      });
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose(); _countdown?.cancel(); _debounce?.cancel();
    _busCtrl.dispose(); _traPageCtrl.dispose();
    super.dispose();
  }

  // ── 模式配色 helpers ─────────────────────────────────────────
  static const _tabIcons  = [Icons.directions_bus_rounded, Icons.directions_bike_rounded, Icons.train_rounded, Icons.landscape_rounded, Icons.directions_railway_filled_rounded];
  static const _tabNames  = ['公車', 'YouBike', '台鐵', '阿里山', '高鐵'];
  static const _tabTitles = ['公車動態查詢', 'YouBike 租借站', '台鐵時刻查詢', '阿里山森林鐵路', '高鐵時刻查詢'];

  @override
  Widget build(BuildContext context) {
    final idx = _tabCtrl.index;
    final primary = context.appPrimary;
    final mist = context.appMist;
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: canPop ? 0 : 20,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 16, height: 22, child: Stack(children: [
            Positioned(left: 0, top: 3,
                child: Container(width: 8, height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: primary))),
            Positioned(left: 6, top: 12,
                child: Container(width: 5, height: 5,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.35)))),
          ])),
          const SizedBox(width: 6),
          Text(_tabTitles[idx],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        actions: [
          // 阿里山(3)/高鐵(4) 為固定時刻表，不顯示倒數
          if (idx < 3)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: mist, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.access_time_rounded, size: 12, color: primary),
                    const SizedBox(width: 3),
                    AnimatedDigitWidget(
                      value: _secs,
                      textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primary),
                      duration: const Duration(milliseconds: 400),
                    ),
                    Text('s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primary)),
                  ]),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(78),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SizedBox(
                height: 70,
                child: Row(
                  children: List.generate(5, (i) {
                    final isSelected = idx == i;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () { _tabCtrl.animateTo(i); setState(() {}); },
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: isSelected ? primary : mist,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(_tabIcons[i],
                                color: isSelected
                                    ? Colors.white
                                    : primary.withValues(alpha: 0.55),
                                size: 22),
                          ),
                          const SizedBox(height: 5),
                          Text(_tabNames[i],
                              style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600,
                                color: isSelected ? primary : AppColors.textHint,
                              )),
                        ]),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_builtBus(), _buildYb(), _buildTra(), _buildAli(), _buildThsr()],
      ),
    );
  }

  // ─── BUS ────────────────────────────────────────────────────
  Future<void> _searchByStop(String q) async {
    if (q.isEmpty) return;
    setState(() => _busSearching = true);
    final routes = await RailService.getBusByStop(_busCity, q);
    if (!mounted) return;
    setState(() { _busSearching = false; _busStopQuery = q; _busStopRoutes = routes; _busFuture = null; _busRoute = ''; });
  }

  Widget _builtBus() {
    return _buildBusIdle();
  }

  Widget _buildBusIdle() {
    final c = context.appPrimary;
    final isChiayi = _busCity == 'Chiayi';

    // 熱門搜尋路線（含顏色標示）
    final hotRoutes = isChiayi
        ? [('中山幹線', const Color(0xFF7878F0)), ('忠孝新民幹線', const Color(0xFF5B7CE8)),]
        : [('7329', const Color(0xFF5B9ECC)), ('7308', const Color(0xFF3D9E74)),];


    return ListView(padding: EdgeInsets.zero, children: [
      // ── 搜尋卡片（縫線風格）─────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: StitchedBox(
          color: Color.lerp(context.appMist, Colors.white, 0.55)!,
          stitchColor: c.withValues(alpha: 0.30),
          radius: 20, inset: 4, dashWidth: 4, dashGap: 3,
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 底線 Tabs
          Row(children: [
            _BusUnderTab('搜尋路線', 0, _busSubTab, c, () => setState(() => _busSubTab = 0)),
            _BusUnderTab('搜尋站牌', 1, _busSubTab, c, () => setState(() => _busSubTab = 1)),
          ]),
          // 搜尋框（全寬，無插圖遮擋）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              controller: _busCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _busSubTab == 0
                    ? '搜尋公車路線（如：中山幹線）'
                    : '搜尋站牌名稱（如：嘉義火車站）',
                hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
                prefixIcon: _busSearching
                    ? Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c)))
                    : const Icon(Icons.search_rounded, size: 18, color: Color(0xFFB8B8C8)),
                filled: true, fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: _busCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () => setState(() => _busCtrl.clear()))
                    : null,
              ),
              onChanged: (v) => setState(() {}),
              onSubmitted: (v) {
                if (_busSubTab == 0) { setState(() { _busRoute = v; _busFuture = RailService.getBusDynamic(_busCity, v); }); }
                else { _searchByStop(v); }
              },
            ),
          ),
          // 熱門搜尋（單行橫向滑動）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 0, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('熱門搜尋',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textHint)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: hotRoutes.asMap().entries.map((e) {
                  final i = e.key;
                  final (name, rColor) = e.value;
                  return Padding(
                    padding: EdgeInsets.only(right: i < hotRoutes.length - 1 ? 8 : 16),
                    child: GestureDetector(
                      onTap: () { _busCtrl.text = name; setState(() { _busRoute = name; _busFuture = RailService.getBusDynamic(_busCity, name); }); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(color: rColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                        child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: rColor)),
                      ),
                    ),
                  );
                }).toList()),
              ),
            ]),
          ),
        ]),
      )),
      // 城市切換
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Row(children: [
          _CityToggle(value: _busCity, onChanged: (v) {
            setState(() {
              _busCity = v; _busRoute = ''; _busStopQuery = ''; _busStopRoutes = [];
              _busCtrl.clear(); _busFuture = null;
              _nearbyStops = null; _nearbyLoading = false; _nearbyError = null;
            });
            _fetchNearbyStops();
          }),
          const Spacer(),
          const Text('支援全縣市公車', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
        ]),
      ),
      // ── 搜尋中 ──────────────────────────────────────────────────
      if (_busSearching)
        Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: c))),

      // ── 站牌搜尋結果（inline，不跳頁）──────────────────────────
      if (!_busSearching && _busMode == 'stop') ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(children: [
            Icon(Icons.place_rounded, size: 15, color: c),
            const SizedBox(width: 6),
            Expanded(child: Text(
              _busStopRoutes.isEmpty
                  ? '找不到站牌「$_busStopQuery」，請確認名稱'
                  : '「$_busStopQuery」停靠 ${_busStopRoutes.length} 條路線 — 點卡片展開即時到站',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
            )),
            if (_busStopRoutes.isNotEmpty)
              GestureDetector(
                onTap: () => widget.onSwitchTab?.call(1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('地圖', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                ),
              ),
          ]),
        ),
        if (_busStopRoutes.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))]),
            child: Column(children: _busStopRoutes.asMap().entries.map((e) {
              final i = e.key; final route = e.value;
              return _BusNearbyCard(name: route, direction: '點擊展開即時到站', via: '', color: c, isLast: i == _busStopRoutes.length - 1, city: _busCity,tick: _busTick);
            }).toList()),
          ),
      ],

      // ── 路線搜尋結果（inline，不跳頁）──────────────────────────
      if (!_busSearching && _busMode == 'route')
        FutureBuilder<Map<String, dynamic>>(
          future: _busFuture,
          builder: (ctx, snap) {
            if (!snap.hasData && snap.connectionState == ConnectionState.waiting)
              return Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: c)));
            if (!snap.hasData || snap.hasError)
              return Padding(padding: const EdgeInsets.all(20), child: _Hint(icon: Icons.wifi_off_rounded, color: c, text: '無法取得資料，請確認後端服務是否啟動'));
            var all = (snap.data!['data'] as List? ?? []).cast<Map<String, dynamic>>();
            if (all.isEmpty) return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Hint(icon: Icons.search_off_rounded, color: c, text: '查無路線「$_busRoute」\n若輸入的是站牌名稱，請改用「搜尋站牌」'),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() { _busSubTab = 1; _busFuture = null; _busRoute = ''; _busCtrl.clear(); }),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                    child: Text('切換至搜尋站牌', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c))),
                ),
              ]),
            );
            String getZh(dynamic field) => (field is Map) ? (field['Zh_tw']?.toString() ?? '') : (field?.toString() ?? '');
            final seen = <String>{};
            all = all.where((s) {
              final sub = getZh(s['SubRouteName']);
              final stopN = getZh(s['StopName']);
              final uid = s['StopUID'] ?? stopN;
              return seen.add('$sub:${s['Direction']}:$uid');
            }).toList();

            // 以 direction+SubRouteName 分組，同一支線同一方向為一張卡
            final groups = <String, List<Map<String, dynamic>>>{};
            for (final stop in all) {
              final subRoute = getZh(stop['SubRouteName']);
              final dir = stop['Direction'] as int? ?? 0;
              groups.putIfAbsent('$dir:$subRoute', () => []).add(stop);
            }

            final sortedKeys = groups.keys.toList()..sort();
            for (final k in sortedKeys) {
              groups[k]!.sort((a, b) => (a['StopSequence'] as int? ?? 0).compareTo(b['StopSequence'] as int? ?? 0));
            }
            return Column(mainAxisSize: MainAxisSize.min, children: [
              if ((snap.data!['updateTime'] as String? ?? '').isNotEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 4), child: _UpdTime(snap.data!['updateTime'] as String)),
              ...sortedKeys.asMap().entries.map((e) => Padding(
                padding: EdgeInsets.fromLTRB(16, e.key == 0 ? 4 : 0, 16, 8),
                child: SlideUpFadeIn(index: e.key, child: _BusCard(stops: groups[e.value]!, onSwitchTab: widget.onSwitchTab)),
              )),
            ]);
          },
        ),

      // ── 附近路線（GPS 即時資料，只在 idle 時顯示）──────────────
      if (_busMode == 'idle') ...[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(children: [
          const Text('附近路線',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(width: 6),
          const Icon(Icons.gps_fixed_rounded, size: 13, color: AppColors.textHint),
          const SizedBox(width: 4),
          Expanded(child: Text(
            _nearbyLoading ? '定位中…' :
            _nearbyError == 'permission_denied' ? '開啟定位以顯示' :
            _nearbyError == 'gps_error' ? '定位失敗，點右重試' :
            _nearbyError == 'backend_error' ? '後端未啟動' :
            _nearbyStops == null ? '開啟定位以顯示' :
            _nearbyStops!.isEmpty ? '附近 800m 無路線' :
            '附近 ${_nearbyStops!.map((s) => s["RouteName"]).toSet().length} 條路線',
            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
          )),
          GestureDetector(
            onTap: _fetchNearbyStops,
            child: Text('重新定位',
                style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      // 狀態卡：定位中
      if (_nearbyLoading)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: context.appMist, borderRadius: BorderRadius.circular(10)),
                child: Padding(padding: const EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2.5, color: c))),
              const SizedBox(width: 12),
              const Text('正在取得您的位置…', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
            ]),
          ),
        )
      // 狀態卡：無權限或 GPS 失敗（backend_error 走下面的空清單流程）
      else if ((_nearbyError == 'permission_denied' || _nearbyError == 'gps_error') || _nearbyStops == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: GestureDetector(
            onTap: _fetchNearbyStops,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.primaryMist, borderRadius: BorderRadius.circular(10)),
                  child: Icon(_nearbyError == 'permission_denied'
                      ? Icons.location_off_rounded : Icons.location_searching_rounded,
                      size: 18, color: c)),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  _nearbyError == 'permission_denied'
                      ? '點此開啟定位服務以查看附近站牌'
                      : '無法取得位置，點此重試',
                  style: const TextStyle(fontSize: 13, color: AppColors.textHint),
                )),
              ]),
            ),
          ),
        )
      // 附近無路線 或 後端錯誤
      else if (_nearbyStops!.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: GestureDetector(
            onTap: _nearbyError == 'backend_error' ? _fetchNearbyStops : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
              child: Row(children: [
                Icon(
                  _nearbyError == 'backend_error' ? Icons.cloud_off_rounded : Icons.directions_bus_outlined,
                  size: 18, color: AppColors.textHint),
                const SizedBox(width: 12),
                Text(
                  _nearbyError == 'backend_error'
                      ? '後端服務未啟動，點此重試'
                      : '附近 800 公尺內無公車路線',
                  style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
              ]),
            ),
          ),
        )
      // 真實路線卡片（縫線風格）
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: StitchedBox(
            color: Color.lerp(context.appMist, Colors.white, 0.50)!,
            stitchColor: c.withValues(alpha: 0.30),
            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
            padding: EdgeInsets.zero,
          child: Column(children: _nearbyStops!.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value;
            final rName = s['RouteName'] as String? ?? '';
            final stopName = s['StopName'] as String? ?? '';
            
            // 🌟 讀取後端算好的起訖點，組合出「起點 ➔ 終點」
            final origin = s['Origin'] as String? ?? '';
            final dest = s['Destination'] as String? ?? '';
            final fallbackDir = (s['Direction'] as int? ?? 0) == 0 ? '去程' : '返程';
            final dirText = origin.isNotEmpty && dest.isNotEmpty ? '$origin ➔ $dest' : fallbackDir;
            
            final rColor = _kRouteColors[rName.hashCode.abs() % _kRouteColors.length];
            return _BusNearbyCard(
              name: rName, 
              direction: dirText, // 這裡將會顯示 嘉義火車站 ➔ 蘭潭校區
              via: stopName, 
              color: rColor,
              isLast: i == _nearbyStops!.length - 1, city: _busCity, tick: _busTick,
            );
          }).toList()),
        )),
      // ETA 圖例
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Wrap(spacing: 16, runSpacing: 6, children: [
          _EtaDot(AppColors.success, '即將進站（0-5 分）'),
          _EtaDot(AppColors.warning, '將進站（6-15 分）'),
          _EtaDot(AppColors.textHint, '未發車（15 分以上）'),
        ]),
      ),
      ], // end if (_busMode == 'idle')

      const SizedBox(height: 20),
    ]);
  }

  // ─── YOUBIKE ───────────────────────────────────────────────────
  double _ybDist(Map<String, dynamic> s) {
    if (_ybPosition == null || s['lat'] == null || s['lng'] == null) return double.infinity;
    return Geolocator.distanceBetween(_ybPosition!.latitude, _ybPosition!.longitude, (s['lat'] as num).toDouble(), (s['lng'] as num).toDouble());
  }

  Widget _buildYb() {
    return Column(children: [
      // ── 小地圖（使用者位置 + YouBike 站點）────────────────────
      SizedBox(
        height: 230,
        child: Stack(children: [
          if (_ybPosition != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _ybFuture,
              builder: (ctx, snap) {
                final stations = (snap.data?['data'] as List? ?? []).cast<Map<String, dynamic>>();
                final center = LatLng(_ybPosition!.latitude, _ybPosition!.longitude);
                // 過濾附近 1.5km 站點才放到地圖（避免全台站點塞滿）
                final nearby = stations.where((s) {
                  if (s['lat'] == null || s['lng'] == null) return false;
                  return _ybDist(s) <= 1500;
                }).toList();
                final markers = [
                  // 使用者位置（藍點 + 光暈）
                  Marker(point: center, width: 26, height: 26,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(width: 26, height: 26, decoration: BoxDecoration(color: context.appPrimary.withValues(alpha: 0.20), shape: BoxShape.circle)),
                      Container(width: 14, height: 14, decoration: BoxDecoration(color: context.appPrimary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5))),
                    ])),
                  // YouBike 站點（顯示站名 + 可借數量）
                  ...nearby.map((s) {
                    final avail = (s['GeneralBikes'] as int? ?? 0) + (s['ElectricBikes'] as int? ?? 0);
                    final name = (s['station_name'] ?? '').toString().replaceAll(RegExp(r'YouBike\d+\.0_'), '');
                    final hasAvail = avail > 0;
                    final color = hasAvail ? AppColors.primary : AppColors.textHint;
                    return Marker(
                      point: LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
                      width: 72, height: 52,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: color, borderRadius: BorderRadius.circular(8),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: Text('$avail 輛', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(4)),
                          constraints: const BoxConstraints(maxWidth: 72),
                          child: Text(name, style: const TextStyle(fontSize: 8, color: AppColors.textPrimary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                        ),
                      ]),
                    );
                  }),
                ];
                return FlutterMap(
                  // key 讓 position 更新時地圖重建並重新對準
                  key: ValueKey('${_ybPosition!.latitude},${_ybPosition!.longitude}'),
                  options: MapOptions(initialCenter: center, initialZoom: 16.5),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.chiayicity.explore_chiayi',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                );
              },
            )
          else
            Container(
              color: AppColors.surfaceMoss,
              child: Center(child: _ybLocating
                  ? Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: context.appPrimary, strokeWidth: 2), const SizedBox(height: 8), const Text('定位中…', style: TextStyle(color: AppColors.textHint, fontSize: 12))])
                  : GestureDetector(onTap: _fetchYbLocation, child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.location_on_rounded, color: AppColors.textHint, size: 28), SizedBox(height: 4), Text('點此開啟定位', style: TextStyle(color: AppColors.textHint, fontSize: 12))]))),
            ),
        ]),
      ),
      // ── 搜尋框 ────────────────────────────────────────────────
      Builder(builder: (ctx) {
        final yp = ctx.appPrimary;
        return Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜尋站點名稱...',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: yp),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: yp, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
            onChanged: (v) => setState(() => _ybSearch = v),
          ),
        );
      }),
      Expanded(child: _ybFuture == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<Map<String, dynamic>>(
              future: _ybFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) return const Center(child: CircularProgressIndicator());
                final all = (snap.data?['data'] as List? ?? []).cast<Map<String, dynamic>>();
                if (all.isEmpty) return const Center(child: Text('目前沒有車位資料'));
                // 依距離排序（有定位時）
                var stations = _ybSearch.trim().isEmpty ? List.of(all) : all.where((s) => (s['station_name'] ?? s['station_uid'] ?? '').toString().contains(_ybSearch.trim())).toList();
                if (_ybPosition != null) stations.sort((a, b) => _ybDist(a).compareTo(_ybDist(b)));
                return Column(children: [
                  if ((snap.data!['updateTime'] as String? ?? '').isNotEmpty)
                    Padding(padding: const EdgeInsets.fromLTRB(16,6,16,2), child: _UpdTime(snap.data!['updateTime'] as String, end: true)),
                  Expanded(child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    itemCount: stations.length,
                    itemBuilder: (ctx, i) {
                      final yp = context.appPrimary;
                      final ym = context.appMist;
                      final s = stations[i];
                      final gen = s['GeneralBikes'] as int? ?? 0;
                      final elec = s['ElectricBikes'] as int? ?? 0;
                      final ret = s['AvailableReturnBikes'] as int? ?? 0;
                      final total = gen + elec;
                      final good = total > 5;
                      var name = (s['station_name'] ?? s['station_uid'] ?? '').toString().replaceAll(RegExp(r'YouBike\d+\.0_'), '');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () {
                            if (s['lat'] != null && s['lng'] != null) {
                              Navigator.popUntil(ctx, (r) => r.isFirst);
                              MapScreen.focusNotifier.value = (lat: (s['lat'] as num).toDouble(), lng: (s['lng'] as num).toDouble(), catKey: MapScreen.catKeyYouBike);
                              widget.onSwitchTab?.call(1);
                            }
                          },
                          child: StitchedBox(
                            color: Color.lerp(ym, Colors.white, 0.45)!,
                            stitchColor: yp.withValues(alpha: 0.35),
                            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              Container(width: 42, height: 42, decoration: BoxDecoration(color: yp.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.directions_bike_rounded, size: 22, color: yp)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  _Tag('普 $gen', AppColors.accentSky),
                                  const SizedBox(width: 4),
                                  _Tag('電 $elec', AppColors.accentTerra),
                                ]),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('可借 ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: good ? yp : AppColors.error)),
                                  AnimatedDigitWidget(value: total, textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: good ? yp : AppColors.error), duration: const Duration(milliseconds: 500)),
                                  Text(' 輛', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: good ? yp : AppColors.error)),
                                ]),
                                Text('可還 $ret 格', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                              ]),
                            ]),
                          ),
                        ),
                      );
                    },
                  )),
                ]);
              },
            )),
    ]);
  }

  // ─── TRA ───────────────────────────────────────────────────────
  Widget _buildTra() {
    final trains = _traTrains ?? [];
    final totalPages = trains.isEmpty ? 0 : (trains.length / _kTraPerPage).ceil();

    return Column(children: [
      // ── 固定 header（OD + 即時看板）────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(children: [
          _ODCard(origin: _traO, dest: _traD, stations: _traStations.keys.toList(), bg: context.appMist, acc: context.appPrimary,
            onO: (v) { setState(() { _traO = v; _traLive = RailService.getTraLiveBoard(_traStations[v]!); }); _fetchTra(); },
            onD: (v) { setState(() => _traD = v); _fetchTra(); },
            onSwap: () { setState(() { final t = _traO; _traO = _traD; _traD = t; _traLive = RailService.getTraLiveBoard(_traStations[_traO]!); }); _fetchTra(); },
          ),
          const SizedBox(height: 10),
          if ((_traUpdateTime ?? '').isNotEmpty) _UpdTime(_traUpdateTime!),
          if (_traLive != null) FutureBuilder<Map<String, dynamic>>(
            future: _traLive,
            builder: (ctx, snap) => _LiveBoard(
              station: _traO,
              trains: snap.data?['data'] as List? ?? [],
              updateTime: snap.data?['updateTime'] as String? ?? '',
            ),
          ),
          const SizedBox(height: 10),
        ]),
      ),
      // ── 車次翻頁區 ───────────────────────────────────────────────
      if (_traLoading)
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => const Padding(padding: EdgeInsets.fromLTRB(14, 0, 14, 10), child: TransportCardSkeleton()))))
      else if (_traError != null)
        Expanded(child: Center(child: Text(_traError!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))))
      else if (trains.isEmpty)
        Expanded(child: _Hint(icon: Icons.train_rounded, color: context.appPrimary, text: '此區間今日無直達班次'))
      else ...[
        Expanded(
          child: PageView.builder(
            controller: _traPageCtrl,
            onPageChanged: (p) => setState(() => _traPage = p),
            itemCount: totalPages,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (ctx, pageIdx) {
              final pageTrains = trains.skip(pageIdx * _kTraPerPage).take(_kTraPerPage).toList();
              return AnimatedBuilder(
                animation: _traPageCtrl,
                builder: (ctx, child) {
                  double offset = 0;
                  try { if (_traPageCtrl.hasClients && _traPageCtrl.position.haveDimensions) offset = _traPageCtrl.page! - pageIdx; } catch (_) {}
                  final clamped = offset.abs().clamp(0.0, 1.0);
                  // 離開頁繞左邊緣折入（負 Y），進來頁繞右邊緣展開（正 Y）
                  final angle = -(offset < 0 ? -1 : 1) * clamped * (math.pi / 2);
                  final alignment = offset > 0 ? Alignment.centerLeft : Alignment.centerRight;
                  return Transform(
                    alignment: alignment,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angle),
                    child: Opacity(
                      opacity: (1.0 - clamped * 0.30).clamp(0.0, 1.0),
                      child: child,
                    ),
                  );
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  physics: const NeverScrollableScrollPhysics(),
                  children: pageTrains.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RailCard(
                      no: e.value['train_no']?.toString() ?? '',
                      type: e.value['train_type_name']?.toString() ?? '',
                      dep: e.value['departure_time']?.toString() ?? '',
                      arr: e.value['arrival_time']?.toString() ?? '',
                      origin: _traO, dest: _traD, date: _today, isThsr: false,
                      stops: e.value['stops'] is List ? (e.value['stops'] as List) : [],
                    ).animate(key: ValueKey('${e.value['train_no']}_$_traPage'))
                     .fadeIn(delay: (e.key * 50).ms, duration: 250.ms)
                     .slideY(begin: 0.08, end: 0, delay: (e.key * 50).ms, duration: 250.ms),
                  )).toList(),
                ),
              );
            },
          ),
        ),
        // 頁碼列
        if (totalPages > 1) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _PageBtn(icon: Icons.chevron_left_rounded, enabled: _traPage > 0,
              onTap: () { final p = _traPage - 1; setState(() => _traPage = p); _traPageCtrl.animateToPage(p, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic); }),
            const SizedBox(width: 14),
            ...List.generate(totalPages, (i) => GestureDetector(
              onTap: () { setState(() => _traPage = i); _traPageCtrl.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _traPage == i ? 22 : 8, height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: _traPage == i ? context.appPrimary : AppColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            )),
            const SizedBox(width: 14),
            _PageBtn(icon: Icons.chevron_right_rounded, enabled: _traPage < totalPages - 1,
              onTap: () { final p = _traPage + 1; setState(() => _traPage = p); _traPageCtrl.animateToPage(p, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic); }),
          ]),
        ),
      ],
    ]);
  }

  // ─── ALISHAN ───────────────────────────────────────────────────
  Widget _buildAli() {
    final valid = <Map<String, dynamic>>[];
    if (_aliDocs != null && _aliO != _aliD) {
      for (final d in _aliDocs!) {
        try {
          final raw = d['stopTimes'] ?? d['StopTimes'] ?? d['stops'] ?? d['Stops'];
          if (raw == null || raw is! List) continue;
          final stops = raw.map((s) => Map<dynamic, dynamic>.from(s as Map)).toList()
            ..sort((a, b) => ((a['StopSequence'] as num?)?.toInt() ?? 0).compareTo((b['StopSequence'] as num?)?.toInt() ?? 0));
          final oIdx = stops.indexWhere((s) => (s['StationName'] ?? '').toString().contains(_aliO));
          final dIdx = stops.indexWhere((s) => (s['StationName'] ?? '').toString().contains(_aliD));
          if (oIdx != -1 && dIdx != -1 && oIdx < dIdx)
            valid.add({'no': (d['TrainNo'] ?? d['trainNo'] ?? '').toString(), 'dep': (stops[oIdx]['DepartureTime'] ?? '--:--').toString(), 'arr': (stops[dIdx]['ArrivalTime'] ?? '--:--').toString(), 'stops': stops});
        } catch (_) {}
      }
      valid.sort((a, b) => (a['dep'] as String).compareTo(b['dep'] as String));
    }
    return ListView(padding: const EdgeInsets.all(14), children: [
      _ODCard(origin: _aliO, dest: _aliD, stations: _aliStations, bg: context.appMist, acc: context.appPrimary,
        onO: (v) => setState(() => _aliO = v), onD: (v) => setState(() => _aliD = v),
        onSwap: () => setState(() { final t = _aliO; _aliO = _aliD; _aliD = t; }),
      ),
      const SizedBox(height: 12),
      if (_aliLoading) ...List.generate(3, (i) => const TransportCardSkeleton())
      else if (_aliO == _aliD) Center(child: Text('請選擇不同的起迄站', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)))
      else if (valid.isEmpty) _Hint(icon: Icons.forest_rounded, color: context.appPrimary, text: '此區間今日無直達班次')
      else ...valid.map((t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _AliCard(train: t, origin: _aliO, dest: _aliD))),
    ]);
  }

  // ─── THSR ──────────────────────────────────────────────────────
  Widget _buildThsr() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      _ODCard(origin: _thsrO, dest: _thsrD, stations: _thsrStations.keys.toList(), bg: context.appMist, acc: context.appPrimary,
        onO: (v) { setState(() => _thsrO = v); _fetchThsr(); },
        onD: (v) { setState(() => _thsrD = v); _fetchThsr(); },
        onSwap: () { setState(() { final t = _thsrO; _thsrO = _thsrD; _thsrD = t; }); _fetchThsr(); },
      ),
      const SizedBox(height: 12),
      if (_thsrLoading) ...List.generate(3, (i) => const TransportCardSkeleton())
      else if (_thsrError != null) Center(child: Text(_thsrError!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)))
      else if (_thsrTrains == null || _thsrTrains!.isEmpty)
        _Hint(icon: Icons.directions_railway_filled_rounded, color: context.appPrimary, text: '此區間今日無直達班次')
      else
        ..._thsrTrains!.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SlideUpFadeIn(index: e.key, child: _RailCard(no: e.value['TrainNo']?.toString() ?? '', type: '高鐵', dep: e.value['DepartureTime']?.toString() ?? '', arr: e.value['ArrivalTime']?.toString() ?? '', origin: _thsrO, dest: _thsrD, date: _today, isThsr: true, stops: e.value['stops'] is List ? (e.value['stops'] as List) : [])),
        )),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════
// 小元件
// ═══════════════════════════════════════════════════════════════

// 城市切換
class _CityToggle extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;
  const _CityToggle({required this.value, required this.onChanged});
  @override Widget build(BuildContext context) {
    final primary = context.appPrimary;
    return Container(
      height: 34,
      decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _pill('嘉義市', 'Chiayi', primary),
        _pill('嘉義縣', 'ChiayiCounty', primary),
      ]),
    );
  }
  Widget _pill(String label, String val, Color c) => GestureDetector(
    onTap: () => onChanged(val),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: value == val ? c : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: value == val ? Colors.white : AppColors.textSecondary)),
    ),
  );
}

// 小標籤
class _Tag extends StatelessWidget {
  final String text; final Color color;
  const _Tag(this.text, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}

// 更新時間
class _UpdTime extends StatelessWidget {
  final String time; final bool end;
  const _UpdTime(this.time, {this.end = false});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
      const Icon(Icons.update_rounded, size: 12, color: AppColors.textHint),
      const SizedBox(width: 4),
      Text('最後更新 $time', style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
    ]),
  );
}

// 空狀態
class _Hint extends StatelessWidget {
  final IconData icon; final Color color; final String text;
  const _Hint({required this.icon, required this.color, required this.text});
  @override Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      StitchedBox(
        color: Color.lerp(color, Colors.white, 0.8)!,
        stitchColor: color.withValues(alpha: 0.4),
        radius: 36, inset: 4, dashWidth: 4, dashGap: 3,
        padding: const EdgeInsets.all(20),
        child: Icon(icon, size: 38, color: color.withValues(alpha: 0.7)),
      ),
      const SizedBox(height: 14),
      Text(text, style: const TextStyle(color: AppColors.textHint, fontSize: 13), textAlign: TextAlign.center),
    ])),
  );
}

// OD 選擇器（筆記本膠帶風格）
class _ODCard extends StatelessWidget {
  final String origin, dest;
  final List<String> stations;
  final Color bg, acc;
  final void Function(String) onO, onD;
  final VoidCallback onSwap;
  const _ODCard({required this.origin, required this.dest, required this.stations, required this.bg, required this.acc, required this.onO, required this.onD, required this.onSwap});

  @override
  Widget build(BuildContext context) {
    final cardBg = Color.lerp(bg, Colors.white, 0.55)!;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: acc.withValues(alpha: 0.18), width: 1),
        boxShadow: [BoxShadow(color: acc.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Stack(children: [
        // 膠帶裝飾（左上角斜貼）
        Positioned(top: -2, left: 14, child: Transform.rotate(angle: -0.08, child: Container(
          width: 46, height: 14,
          decoration: BoxDecoration(
            color: acc.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(3),
          ),
        ))),
        // 右上角小花裝飾
        Positioned(top: 8, right: 12, child: Text('✿', style: TextStyle(fontSize: 14, color: acc.withValues(alpha: 0.4)))),
        // 右下角小熊 emoji 裝飾
        Positioned(bottom: 6, right: 10, child: Text('🐻', style: const TextStyle(fontSize: 18))),
        // 主內容
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('出發站', style: TextStyle(fontSize: 10, color: acc, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              DropdownButton<String>(
                value: origin, isExpanded: true, underline: const SizedBox(),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: acc, size: 18),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.textPrimary),
                items: stations.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))).toList(),
                onChanged: (v) { if (v != null) onO(v); },
              ),
            ])),
            GestureDetector(
              onTap: onSwap,
              child: Container(
                width: 36, height: 36, margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: acc.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(Icons.swap_horiz_rounded, color: acc, size: 20),
              ),
            ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('抵達站', style: TextStyle(fontSize: 10, color: acc, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              DropdownButton<String>(
                value: dest, isExpanded: true, underline: const SizedBox(),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: acc, size: 18),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.textPrimary),
                items: stations.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))).toList(),
                onChanged: (v) { if (v != null) onD(v); },
              ),
            ])),
          ]),
        ),
      ]),
    );
  }
}

// 台鐵即時看板（亮色日記風）
class _LiveBoard extends StatelessWidget {
  final String station, updateTime;
  final List<dynamic> trains;
  const _LiveBoard({required this.station, required this.trains, required this.updateTime});
  @override Widget build(BuildContext context) {
    final p = context.appPrimary;
    final m = context.appMist;
    if (trains.isEmpty) {
      return StitchedBox(
        color: Color.lerp(m, Colors.white, 0.55)!,
        stitchColor: p.withValues(alpha: 0.35),
        radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 15, color: p),
          const SizedBox(width: 8),
          Text('$station 目前暫無即時進站資訊', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      );
    }
    return StitchedBox(
      color: Color.lerp(m, Colors.white, 0.4)!,
      stitchColor: p.withValues(alpha: 0.4),
      radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.departure_board_rounded, size: 16, color: p),
          const SizedBox(width: 6),
          Text('$station 即將進站', style: TextStyle(color: p, fontWeight: FontWeight.w800, fontSize: 13)),
          const Spacer(),
          if (updateTime.isNotEmpty) Text(updateTime, style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
        ]),
        Divider(color: p.withValues(alpha: 0.2), height: 14),
        ...trains.map((t) {
          final delay = t['delay_time'] as int? ?? 0;
          return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            Expanded(flex: 3, child: Text('${t['train_type_name'] ?? ''} ${t['train_no'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
            Expanded(flex: 1, child: Text(t['direction'] == 0 ? '順行' : '逆行', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
            Text(_formatTime(t['schedule_departure_time']?.toString() ?? ''), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: (delay == 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(delay == 0 ? '準點' : '晚 $delay 分', style: TextStyle(color: delay == 0 ? AppColors.success : AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ]));
        }),
      ]),
    );
  }
}

// 公車站牌卡（縫線、timeline）
class _BusCard extends StatefulWidget {
  final List<Map<String, dynamic>> stops;
  final void Function(int)? onSwitchTab;
  const _BusCard({required this.stops, this.onSwitchTab});
  @override State<_BusCard> createState() => _BusCardState();
}
class _BusCardState extends State<_BusCard> {
  bool _expanded = false;
  bool _showMap = false;
  List<Map<String, dynamic>>? _busPositions;

  String _etaText(Map s) {
    final status = s['StopStatus'] as int? ?? 0;
    final eta = s['EstimateTime'] as int?;
    
    if (status == 1) {
      // 1. 嘗試直接解析 TDX 提供的 NextBusTime 字串
      final nbt = s['NextBusTime'] as String? ?? '';
      if (nbt.isNotEmpty) {
        if (nbt.contains('T')) {
          try {
            final parts = nbt.split('T');
            if (parts.length > 1 && parts[1].length >= 5) {
              return '${parts[1].substring(0, 5)} 預計';
            }
          } catch (_) {}
        } else if (nbt.length >= 5) {
          return '${nbt.substring(0, 5)} 預計'; // 相容只傳回時間的格式
        }
      }
      
      // 2. 前端魔法：如果是市區公車沒給時間字串，但有給「預估秒數」，我們自己換算成時刻！
      if (eta != null && eta > 0) {
        final arrTime = DateTime.now().add(Duration(seconds: eta));
        final hh = arrTime.hour.toString().padLeft(2, '0');
        final mm = arrTime.minute.toString().padLeft(2, '0');
        return '$hh:$mm 預計';
      }
      
      return '尚未發車';
    }
    
    if (status == 2) return '交管停靠';
    if (status == 3) return '末班已過';
    if (status == 4) return '今日停駛';
    if (eta == null) return '資料更新中';
    if (eta == 0) return '進站中';
    final m = eta ~/ 60;
    return m <= 1 ? '即將進站' : '$m 分鐘';
  }

  Color _etaColor(Map s, Color primary) {
    final status = s['StopStatus'] as int? ?? 0;
    if (status == 1) {
      final nbt = s['NextBusTime'] as String? ?? '';
      final eta = s['EstimateTime'] as int?;
      return (nbt.isNotEmpty || (eta != null && eta > 0)) ? primary : AppColors.textHint;
    }
    if (status != 0 && status != 1) return AppColors.textHint;
    final eta = s['EstimateTime'] as int? ?? 9999;
    if (eta <= 60) return AppColors.success;
    if (eta <= 300) return AppColors.warning;
    return primary;
  }
  bool _showPlate(Map s) {
    if ((s['StopStatus'] as int? ?? 0) != 0) return false;
    final eta = s['EstimateTime'] as int? ?? 9999;
    final plate = s['PlateNumb'] as String? ?? '';
    return eta <= 120 && plate.isNotEmpty && plate != '尚未發車' && plate != '-1';
  }

  @override Widget build(BuildContext context) {
    final p = context.appPrimary;
    final m = context.appMist;
    final stops = widget.stops;
    final dir = (stops.first['Direction'] as int? ?? 0) == 0 ? '去程' : '返程';
    String getZh(dynamic field) => (field is Map) ? (field['Zh_tw']?.toString() ?? '') : (field?.toString() ?? '');

    final subRouteName = getZh(stops.first['SubRouteName']);
    final origin = getZh(stops.first['StopName']).isEmpty ? '起點' : getZh(stops.first['StopName']);
    final dest = getZh(stops.last['StopName']).isEmpty ? '終點' : getZh(stops.last['StopName']);

    return StitchedBox(
      color: Color.lerp(m, Colors.white, 0.45)!,
      stitchColor: p.withValues(alpha: 0.35),
      radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(padding: const EdgeInsets.fromLTRB(14, 13, 12, 13), child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: p.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: Text(dir, style: TextStyle(color: p, fontSize: 11, fontWeight: FontWeight.w700))),
              if (subRouteName.isNotEmpty) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: p.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(5)),
                    child: Text(subRouteName, style: TextStyle(color: p, fontSize: 10, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(child: Row(children: [
                Flexible(child: Text(origin, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.textHint)),
                Flexible(child: Text(dest, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
              ])),
              Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.textHint),
            ])),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: p.withValues(alpha: 0.15)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Column(children: List.generate(stops.length, (i) {
                final s = stops[i];
                final isLast = i == stops.length - 1;
                final etaText = _etaText(s);
                final etaColor = _etaColor(s, p);
                final showP = _showPlate(s);
                final plate = s['PlateNumb'] as String? ?? '';
                final imminent = (s['EstimateTime'] as int? ?? 9999) <= 120 && (s['StopStatus'] as int? ?? 0) == 0;

                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 18, child: Column(children: [
                    Container(width: imminent ? 13 : 9, height: imminent ? 13 : 9, decoration: BoxDecoration(shape: BoxShape.circle, color: imminent ? etaColor : Colors.white, border: Border.all(color: imminent ? etaColor : AppColors.textHint.withValues(alpha: 0.4), width: imminent ? 2.5 : 1.5))),
                    if (!isLast) Container(width: 1.5, height: 28, color: AppColors.divider),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Padding(padding: EdgeInsets.only(bottom: isLast ? 0 : 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(getZh(s['StopName']), style: TextStyle(fontSize: 13, fontWeight: imminent ? FontWeight.w800 : FontWeight.w500, color: imminent ? AppColors.textPrimary : AppColors.textSecondary))),
                      if ((s['EstimateTime'] as int? ?? 0) > 180 && (s['StopStatus'] as int? ?? 0) == 0)
                        GestureDetector(
                          onTap: () async {
                            final subRoute = getZh(stops.first['SubRouteName']);
                            await BusNotificationService.scheduleBusArrival(
                              routeName: subRoute.isNotEmpty ? subRoute : '公車',
                              stopName: getZh(s['StopName']),
                              etaSeconds: s['EstimateTime'] as int,
                              notifyBeforeMinutes: 3,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('已設定到站提醒：${getZh(s['StopName'])}（約 ${(s['EstimateTime'] as int) ~/ 60} 分鐘後）'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              duration: const Duration(seconds: 3),
                            ));
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.notifications_none_rounded, size: 16, color: p.withValues(alpha: 0.6)),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Text(etaText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: etaColor)),
                    ]),
                    if (showP) ...[
                      const SizedBox(height: 3),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.directions_bus_rounded, size: 11, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(plate, style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w700)),
                      ])),
                    ],
                  ]))),
                ]);
              })),
            ),
            // 公車即時位置地圖按鈕
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: GestureDetector(
                onTap: () async {
                  if (_showMap) { setState(() => _showMap = false); return; }
                  setState(() => _showMap = true);
                  if (_busPositions != null) return;
                  final routeName = getZh(stops.first['SubRouteName']).isNotEmpty ? getZh(stops.first['SubRouteName']) : '';
                  if (routeName.isEmpty) return;
                  final res = await RailService.getBusGpsPositions('Chiayi', routeName);
                  if (mounted) setState(() => _busPositions = (res['data'] as List? ?? []).cast<Map<String, dynamic>>());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: p.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_showMap ? Icons.list_rounded : Icons.map_rounded, size: 14, color: p),
                    const SizedBox(width: 6),
                    Text(_showMap ? '收合地圖' : '公車即時位置', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p)),
                  ]),
                ),
              ),
            ),
            if (_showMap) _buildBusGpsMap(stops),
          ],
        ]),
      ),
    );
  }

  bool _gpsRefreshing = false;

  Future<void> _refreshGps() async {
    String getZh(dynamic field) => (field is Map) ? (field['Zh_tw']?.toString() ?? '') : (field?.toString() ?? '');
    final routeName = getZh(widget.stops.first['SubRouteName']);
    if (routeName.isEmpty) return;
    setState(() => _gpsRefreshing = true);
    final res = await RailService.getBusGpsPositions('Chiayi', routeName);
    if (mounted) setState(() {
      _busPositions = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      _gpsRefreshing = false;
    });
  }

  Widget _buildBusGpsMap(List<Map<String, dynamic>> stops) {
    final gp = context.appPrimary;
    const defaultCenter = LatLng(23.4801, 120.4500);
    final busMarkers = (_busPositions ?? []).map((b) {
      final lat = b['Lat'] as double? ?? 0;
      final lng = b['Lng'] as double? ?? 0;
      if (lat == 0 || lng == 0) return null;
      return Marker(
        point: LatLng(lat, lng),
        width: 36, height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: gp,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: gp.withValues(alpha: 0.5), blurRadius: 8)],
          ),
          child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 16),
        ),
      );
    }).whereType<Marker>().toList();

    final center = busMarkers.isNotEmpty
        ? busMarkers.first.point
        : defaultCenter;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      child: SizedBox(
        height: 200,
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 13.5),
            children: [
              TileLayer(urlTemplate: 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png', userAgentPackageName: 'com.chiayicity.explore_chiayi'),
              MarkerLayer(markers: busMarkers),
            ],
          ),
          if (busMarkers.isEmpty)
            const Center(child: Text('暫無公車位置資料', style: TextStyle(color: AppColors.textHint, fontSize: 12))),
          Positioned(
            right: 8, bottom: 8,
            child: GestureDetector(
              onTap: _gpsRefreshing ? null : _refreshGps,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)]),
                child: _gpsRefreshing
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: gp))
                    : Icon(Icons.refresh_rounded, size: 16, color: gp),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// 台鐵 / 高鐵班次卡（筆記本打孔＋膠帶風格）
class _RailCard extends StatefulWidget {
  final String no, type, dep, arr, origin, dest, date;
  final bool isThsr;
  final List<dynamic> stops;
  const _RailCard({required this.no, required this.type, required this.dep, required this.arr, required this.origin, required this.dest, required this.date, required this.isThsr, required this.stops});
  @override State<_RailCard> createState() => _RailCardState();
}


class _RailCardState extends State<_RailCard> {
  bool _expanded = false;
  bool _starred = false;
  List<dynamic>? _stops;
  bool _loading = false;

  Color get _acc {
    if (widget.isThsr) return const Color(0xFFC4856A); // 陶土橘
    final t = widget.type;
    if (t.contains('自強'))  return const Color(0xFF5B7FAF); // 天藍
    if (t.contains('太魯閣')) return const Color(0xFF3A9E8A); // 青綠
    if (t.contains('普悠瑪')) return const Color(0xFF7B6BAE); // 淡紫
    if (t.contains('莒光'))  return const Color(0xFFB07A30); // 暖木棕
    return const Color(0xFF5E8C6E); // 區間 / 其他 — 固定苔蘚綠
  }
  Color get _bg => context.appMist;

  // 標籤背景 = 車種強調色的淡色版，同車種永遠一致
  Color get _tapeColor => _acc.withValues(alpha: 0.14);

  @override void initState() { super.initState(); _stops = widget.stops.isNotEmpty ? widget.stops : null; }

  Future<void> _loadStops() async {
    if (_stops != null) return;
    setState(() => _loading = true);
    try {
      final res = widget.isThsr ? await RailService.getThsrTrainStops(widget.no, widget.date) : await RailService.getTraTrainStops(widget.no, widget.date);
      if (mounted) setState(() { _stops = res['data'] as List<dynamic>?; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override Widget build(BuildContext context) {
    final c = _acc;
    final cardBg = Color.lerp(_bg, Colors.white, 0.5)!;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── 左側打孔環（筆記本效果）
      SizedBox(width: 18, child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: List.generate(3, (i) => Padding(
          padding: EdgeInsets.only(top: i == 0 ? 16.0 : 14.0),
          child: Container(
            width: 13, height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background,
              border: Border.all(color: AppColors.divider, width: 1.5),
            ),
          ),
        )),
      )),
      const SizedBox(width: 6),
      // ── 主卡片
      Expanded(child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.15), width: 1),
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(children: [
            // ── 膠帶標籤（左上角斜貼）
            Stack(children: [
              // 卡片主體 header
              InkWell(
                onTap: () { setState(() => _expanded = !_expanded); if (_expanded && _stops == null) _loadStops(); },
                child: Padding(padding: const EdgeInsets.fromLTRB(14, 14, 12, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 頂部：列車標籤 + 星星
                  Row(children: [
                    // 膠帶標籤（班次）
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _tapeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${widget.type} ${widget.no}', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    // 星星收藏按鈕
                    GestureDetector(
                      onTap: () => setState(() => _starred = !_starred),
                      child: Icon(
                        _starred ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 22,
                        color: _starred ? const Color(0xFFFFCC44) : AppColors.textHint,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.textHint, size: 18),
                  ]),
                  const SizedBox(height: 12),
                  // 出發 ── 圖示 ── 抵達
                  Row(children: [
                    // 出發時間（強調色大字）
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_formatTime(widget.dep), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: c, letterSpacing: -0.5)),
                      Text(widget.origin, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    ]),
                    // 虛線 + 火車圖示
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(children: [
                        Row(children: [
                          Container(width: 5, height: 5, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                          Expanded(child: LayoutBuilder(builder: (ctx, bc) {
                            final w = bc.maxWidth;
                            return CustomPaint(size: Size(w, 1.5), painter: _DashedLinePainter(color: c.withValues(alpha: 0.35)));
                          })),
                          Icon(widget.isThsr ? Icons.directions_railway_filled_rounded : Icons.train_rounded, size: 16, color: c),
                          Expanded(child: LayoutBuilder(builder: (ctx, bc) {
                            final w = bc.maxWidth;
                            return CustomPaint(size: Size(w, 1.5), painter: _DashedLinePainter(color: c.withValues(alpha: 0.35)));
                          })),
                          Container(width: 5, height: 5, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                        ]),
                        const SizedBox(height: 4),
                        // 行駛時間
                        Builder(builder: (ctx) {
                          final depParts = _formatTime(widget.dep).split(':');
                          final arrParts = _formatTime(widget.arr).split(':');
                          if (depParts.length == 2 && arrParts.length == 2) {
                            final depMin = (int.tryParse(depParts[0]) ?? 0) * 60 + (int.tryParse(depParts[1]) ?? 0);
                            final arrMin = (int.tryParse(arrParts[0]) ?? 0) * 60 + (int.tryParse(arrParts[1]) ?? 0);
                            final diff = arrMin - depMin;
                            if (diff > 0) {
                              final h = diff ~/ 60, m = diff % 60;
                              final label = h > 0 ? '約 $h 小時 $m 分' : '約 $m 分';
                              return Text(label, style: TextStyle(fontSize: 10, color: c.withValues(alpha: 0.7), fontWeight: FontWeight.w600));
                            }
                          }
                          return const SizedBox.shrink();
                        }),
                      ]),
                    )),
                    // 抵達時間（深色）
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(_formatTime(widget.arr), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -0.5, color: AppColors.textPrimary)),
                      Text(widget.dest, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    ]),
                  ]),
                ])),
              ),
            ]),
            // ── 展開：停靠站
            if (_expanded) ...[
              Divider(height: 1, color: c.withValues(alpha: 0.15)),
              if (_loading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
              else if (_stops == null || _stops!.isEmpty)
                Padding(padding: const EdgeInsets.all(14), child: Column(children: [
                  const Text('無法取得停靠站資料', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                  TextButton.icon(onPressed: _loadStops, icon: const Icon(Icons.refresh, size: 15), label: const Text('重試')),
                ]))
              else Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: Column(children: _stops!.map((s) {
                  final name = (s['StationName'] ?? s['stationName'] ?? '').toString();
                  final time = _formatTime((s['ArrivalTime'] ?? s['DepartureTime'] ?? '').toString());
                  final isTarget = name.contains(widget.origin) || name.contains(widget.dest);
                  final isLast = s == _stops!.last;
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 18, child: Column(children: [
                      Container(width: isTarget ? 13 : 9, height: isTarget ? 13 : 9, decoration: BoxDecoration(shape: BoxShape.circle, color: isTarget ? c : Colors.white, border: Border.all(color: isTarget ? c : AppColors.divider, width: isTarget ? 2.5 : 1.5))),
                      if (!isLast) Container(width: 1.5, height: 22, color: AppColors.divider),
                    ])),
                    const SizedBox(width: 10),
                    Expanded(child: Padding(padding: EdgeInsets.only(bottom: isLast ? 0 : 4), child: Row(children: [
                      Expanded(child: Text(name, style: TextStyle(fontSize: 13, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w500, color: isTarget ? AppColors.textPrimary : AppColors.textSecondary))),
                      Text(time, style: TextStyle(fontSize: 12, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w400, color: isTarget ? AppColors.textPrimary : AppColors.textHint)),
                    ]))),
                  ]);
                }).toList()),
              ),
            ],
          ]),
        ),
      )),
    ]);
  }
}

// 虛線 Painter（用於班次卡內部連線）
class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.5..strokeCap = StrokeCap.round;
    double x = 0;
    const dash = 4.0, gap = 3.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset((x + dash).clamp(0, size.width), size.height / 2), paint);
      x += dash + gap;
    }
  }
  @override bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

// 阿里山卡
class _AliCard extends StatefulWidget {
  final Map<String, dynamic> train; final String origin, dest;
  const _AliCard({required this.train, required this.origin, required this.dest});
  @override State<_AliCard> createState() => _AliCardState();
}
class _AliCardState extends State<_AliCard> {
  bool _expanded = false;
  @override Widget build(BuildContext context) {
    final p = context.appPrimary;
    final m = context.appMist;
    final stops = widget.train['stops'] as List<dynamic>? ?? [];
    return StitchedBox(
      color: Color.lerp(m, Colors.white, 0.45)!,
      stitchColor: p.withValues(alpha: 0.4),
      radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: [
          Container(height: 4, decoration: BoxDecoration(color: p, borderRadius: const BorderRadius.vertical(top: Radius.circular(15)))),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: p.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('🚃', style: TextStyle(fontSize: 16)),
                Text(widget.train['no']?.toString() ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w800)),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: p.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Text('觀光列車', style: TextStyle(color: p, fontSize: 10, fontWeight: FontWeight.w700))), const Spacer(), Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.textHint)]),
                const SizedBox(height: 8),
                Row(children: [
                  Text(_formatTime(widget.train['dep']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.textPrimary)),
                  Expanded(child: Container(height: 1, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 10))),
                  Text(_formatTime(widget.train['arr']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.textPrimary)),
                ]),
              ])),
            ])),
          ),
          if (_expanded && stops.isNotEmpty) ...[
            Divider(height: 1, color: p.withValues(alpha: 0.15)),
            Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 16), child: Column(children: stops.map((s) {
              final name = (s['StationName'] ?? s['stationName'] ?? '').toString();
              final time = _formatTime((s['ArrivalTime'] ?? s['arrivalTime'] ?? '').toString());
              final isTarget = name.contains(widget.origin) || name.contains(widget.dest);
              final isLast = s == stops.last;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 18, child: Column(children: [
                  Container(width: isTarget ? 13 : 9, height: isTarget ? 13 : 9, decoration: BoxDecoration(shape: BoxShape.circle, color: isTarget ? p : Colors.white, border: Border.all(color: isTarget ? p : AppColors.divider, width: isTarget ? 2.5 : 1.5))),
                  if (!isLast) Container(width: 1.5, height: 22, color: AppColors.divider),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Padding(padding: EdgeInsets.only(bottom: isLast ? 0 : 4), child: Row(children: [
                  Expanded(child: Text(name, style: TextStyle(fontSize: 13, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w500, color: isTarget ? AppColors.textPrimary : AppColors.textSecondary))),
                  Text(time, style: TextStyle(fontSize: 12, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w400, color: isTarget ? AppColors.textPrimary : AppColors.textHint)),
                ]))),
              ]);
            }).toList())),
          ],
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 公車 UI 新元件（對標參考圖）
// ═══════════════════════════════════════════════════════════════

/// 底線樣式 sub-tab（搜尋路線 / 搜尋站牌）
class _BusUnderTab extends StatelessWidget {
  final String label;
  final int index, current;
  final Color color;
  final VoidCallback onTap;
  const _BusUnderTab(this.label, this.index, this.current, this.color, this.onTap);
  @override Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
            color: current == index ? color : Colors.transparent, width: 2,
          )),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: current == index ? color : AppColors.textHint)),
      ),
    ),
  );
}


/// 附近路線卡片（Stateful，點擊展開即時 ETA）
class _BusNearbyCard extends StatefulWidget {
  final String name, direction, via, city;
  final Color color;
  final bool isLast;
  final int tick; 
  const _BusNearbyCard({required this.name, required this.direction, required this.via,
    required this.color, required this.isLast, required this.city, required this.tick});
  @override State<_BusNearbyCard> createState() => _BusNearbyCardState();
}
class _BusNearbyCardState extends State<_BusNearbyCard> {
  bool _expanded = false;
  Future<Map<String, dynamic>>? _future;
  @override
  void didUpdateWidget(_BusNearbyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick && _expanded) {
      setState(() {
        _future = RailService.getBusDynamic(widget.city, widget.name);
      });
    }
  }
  void _toggle() {
    if (!_expanded && _future == null) {
      _future = RailService.getBusDynamic(widget.city, widget.name);
    }
    setState(() => _expanded = !_expanded);
  }

  String _etaText(Map s) {
    final status = s['StopStatus'] as int? ?? 0;
    final eta = s['EstimateTime'] as int?;
    
    if (status == 1) {
      // 1. 嘗試直接解析 TDX 提供的 NextBusTime 字串
      final nbt = s['NextBusTime'] as String? ?? '';
      if (nbt.isNotEmpty) {
        if (nbt.contains('T')) {
          try {
            final parts = nbt.split('T');
            if (parts.length > 1 && parts[1].length >= 5) {
              return '${parts[1].substring(0, 5)} 預計';
            }
          } catch (_) {}
        } else if (nbt.length >= 5) {
          return '${nbt.substring(0, 5)} 預計';
        }
      }
      
      // 2. 前端魔法：如果沒給字串，但有給「預估秒數」，自己換算成時刻！
      if (eta != null && eta > 0) {
        final arrTime = DateTime.now().add(Duration(seconds: eta));
        final hh = arrTime.hour.toString().padLeft(2, '0');
        final mm = arrTime.minute.toString().padLeft(2, '0');
        return '$hh:$mm 預計';
      }
      
      return '尚未發車';
    }
    
    if (status == 2) return '交管停靠';
    if (status == 3) return '末班已過';
    if (status == 4) return '今日停駛';
    if (eta == null) return '---';
    if (eta == 0) return '進站中';
    final m = eta ~/ 60;
    return m <= 1 ? '即將進站' : '$m 分';
  }

  Color _etaColor(Map s) {
    final status = s['StopStatus'] as int? ?? 0;
    if (status == 1) {
      final nbt = s['NextBusTime'] as String? ?? '';
      final eta = s['EstimateTime'] as int?;
      // 只要有任何一種預計時間的線索，就套用卡片專屬色
      return (nbt.isNotEmpty || (eta != null && eta > 0)) ? widget.color : AppColors.textHint;
    }
    if (status != 0 && status != 1) return AppColors.textHint;
    final eta = s['EstimateTime'] as int? ?? 9999;
    if (eta <= 60)  return AppColors.success;
    if (eta <= 300) return AppColors.warning;
    return AppColors.textHint;
  }

  @override Widget build(BuildContext context) {
    final c = widget.color;
    final isLast = widget.isLast && !_expanded;
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(width: 5, decoration: BoxDecoration(color: c,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          bottomLeft: Radius.circular(isLast ? 16 : 0)))),
      Expanded(child: Column(children: [
        GestureDetector(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                child: Text(widget.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.direction, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (widget.via.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('附近：${widget.via}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                ],
              ])),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textHint, size: 20)),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, indent: 14, endIndent: 14, color: AppColors.divider),
          FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (ctx, snap) {
              if (!snap.hasData) return Padding(padding: const EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: ctx.appPrimary, strokeWidth: 2)));
              final all = (snap.data!['data'] as List? ?? []).cast<Map<String, dynamic>>();
              
              String getZh(dynamic field) => (field is Map) ? (field['Zh_tw']?.toString() ?? '') : (field?.toString() ?? '');
              
              // 1. 先濾出特定方向
              final allDir0 = all.where((s) => (s['Direction'] as int? ?? 0) == 0).toList();
              
              // 2. 解決「合起來」問題：取得第一種子路線名稱作為基準，濾掉其他分支
              final firstSubRoute = allDir0.isNotEmpty ? getZh(allDir0.first['SubRouteName']) : '';
              
              // 3. 確保只排序並顯示同一條子路線的站牌
              final dir = allDir0.where((s) => getZh(s['SubRouteName']) == firstSubRoute).toList()
                ..sort((a, b) => (a['StopSequence'] as int? ?? 0).compareTo(b['StopSequence'] as int? ?? 0));
                
              if (dir.isEmpty) return Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Text('無法取得即時資訊', style: TextStyle(fontSize: 12, color: AppColors.textHint)));
              
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(children: dir.take(10).map((s) {
                  final etaTxt = _etaText(s);
                  final etaClr = _etaColor(s);
                  final isImm = (s['EstimateTime'] as int? ?? 9999) <= 120 && (s['StopStatus'] as int? ?? 0) == 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 8, top: 1),
                        decoration: BoxDecoration(color: etaClr, shape: BoxShape.circle)),
                      Expanded(child: Text(getZh(s['StopName']), style: TextStyle(fontSize: 12, fontWeight: isImm ? FontWeight.w700 : FontWeight.w400, color: isImm ? AppColors.textPrimary : AppColors.textSecondary))),
                      Text(etaTxt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: etaClr)),
                    ]),
                  );
                }).toList()),
              );
            },
          ),
        ],
        if (!widget.isLast) const Divider(height: 1, indent: 14, endIndent: 14, color: AppColors.divider),
      ])),
    ]));
  }
}

/// 翻頁按鈕（台鐵）
class _PageBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageBtn({required this.icon, required this.enabled, required this.onTap});
  @override Widget build(BuildContext context) {
    final c = enabled ? context.appPrimary : AppColors.divider;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: c),
      ),
    );
  }
}

/// ETA 圖例小點
class _EtaDot extends StatelessWidget {
  final Color color;
  final String label;
  const _EtaDot(this.color, this.label);
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
  ]);
}