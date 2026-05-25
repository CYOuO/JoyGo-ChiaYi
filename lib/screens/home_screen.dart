import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/static_data_cache.dart';
import '../widgets/common_widgets.dart' show SectionHeader, SpotRatingSection, TapFeedback;
import 'search_screen.dart';
import 'notifications_screen.dart';
import 'news_transport_screens.dart';
import 'camera_screen.dart';
import 'weather_screen.dart';
import 'news_transport_screens.dart' show TransportScreen, NewsScreen;
import 'map_screen.dart' show MapScreen;

// ── HTML entity/tag cleaner (mirrors the one in news_transport_screens) ──
String _cleanHtml(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  var s = raw;
  s = s.replaceAll('&nbsp;',  ' ');
  s = s.replaceAll('&amp;',   '&');
  s = s.replaceAll('&lt;',    '<');
  s = s.replaceAll('&gt;',    '>');
  s = s.replaceAll('&quot;',  '"');
  s = s.replaceAll('&#39;',   "'");
  s = s.replaceAll('&hellip;','…');
  s = s.replaceAll('&mdash;', '—');
  s = s.replaceAll('&ndash;', '–');
  s = s.replaceAll(RegExp(r'<br\s*/?>',    caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</?p[^>]*>',   caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'),      '');
  s = s.replaceAll(RegExp(r'[ \t]{2,}'),   ' ');
  s = s.replaceAll(RegExp(r'\n{3,}'),      '\n\n');
  return s.trim();
}


// ── News cache JSON helpers (top-level, references private _GovItem) ──────
Map<String, dynamic> _govItemToJson(_GovItem n) => {
  'title': n.title, 'date': n.date, 'location': n.location,
  'summary': n.summary, 'url': n.url, 'imageUrl': n.imageUrl,
  'isEvent': n.isEvent,
};
_GovItem _govItemFromJson(Map<String, dynamic> m) => _GovItem(
  title:    m['title']    as String? ?? '',
  date:     m['date']     as String? ?? '',
  location: m['location'] as String?,
  summary:  m['summary']  as String?,
  url:      m['url']      as String?,
  imageUrl: m['imageUrl'] as String?,
  isEvent:  m['isEvent']  as bool?   ?? false,
);

/// Slide-up + fade route — replaces MaterialPageRoute for a modern feel.
PageRoute<void> _goRoute(Widget screen) => PageRouteBuilder<void>(
  pageBuilder: (_, __, ___) => screen,
  transitionsBuilder: (_, anim, __, child) => FadeTransition(
    opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
    child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
  transitionDuration: const Duration(milliseconds: 270),
  reverseTransitionDuration: const Duration(milliseconds: 210),
);

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  final void Function(int)? onSwitchTab;   // ← 切換底部 tab
  final VoidCallback? onGoToTripCalendar;  // ← 直接跳到行程→行事曆 tab

  const HomeScreen({super.key, this.onOpenDrawer, this.onSwitchTab,
                    this.onGoToTripCalendar});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _bannerController = PageController();
  int _currentBanner = 0;
  int _unreadCount = 3;

  // ── Government news / events (replaces fake DummyData.news)
  List<_GovItem> _newsItems = [];
  bool _newsLoading = true;
  bool _newsError   = false;
  Timer? _autoScrollTimer;

  // ── 使用者位置（供附近排序用）────────────────────────────
  Position? _myPos;

  // ── Restaurants (雞肉飯) from Firestore ──────────────────
  List<_RestaurantItem> _restaurants = [];
  bool _restaurantsLoading = true;

  // ── Nearby spots (from multiple collections) ──────────────
  List<_NearbySpotItem> _nearbySpots = [];
  bool _nearbyLoading = true;
  String _nearbyFilter = '全部'; // 全部 | TDX景點 | 好店 | 寵物友善 | 飲料店
  static const _kNearbyFilters = ['全部', 'TDX景點', '好店', '寵物友善', '飲料店'];

  // ── News cache ────────────────────────────────────────────
  static const _kNewsCacheKey   = 'home_news_v1';
  static const _kNewsCacheTsKey = 'home_news_ts_v1';
  static const _kNewsCacheTTLMs = 30 * 60 * 1000; // 30 minutes

  static const _kEventsUrl =
      'https://data.chiayi.gov.tw/opendata/api/getResource'
      '?oid=33c3225e-f786-4eaf-8b9c-774cc39c72e0'
      '&rid=a809167f-bba6-475d-9dfe-33b4ea7749f6';
  static const _kNewsUrl =
      'https://data.chiayi.gov.tw/opendata/api/getResource'
      '?oid=6dcaf207-e99b-4846-bd72-c334ce0d4b59'
      '&rid=87d4b27c-07c3-4546-815d-1e733dfd9497';

  @override
  void initState() {
    super.initState();
    _fetchLocation();   // 先取位置，再排序餐廳
    _fetchNews();
    _fetchRestaurants();
    _fetchNearbySpots();
  }

  /// 取得使用者位置（用於餐廳、附近景點距離排序）
  Future<void> _fetchLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      _myPos = pos;
      // 位置取得後重新排序（如果資料已載入）
      if (_restaurants.isNotEmpty) _sortRestaurantsByProximity();
      if (_nearbySpots.isNotEmpty) _sortNearbyByProximity();
    } catch (_) {} // 失敗不影響 app 正常使用
  }

  /// 依距離排序餐廳（就地排序 + setState）
  void _sortRestaurantsByProximity() {
    if (_myPos == null) return;
    final lat = _myPos!.latitude;
    final lng = _myPos!.longitude;
    final sorted = [..._restaurants];
    sorted.sort((a, b) {
      if (a.lat == null || a.lng == null) return 1;
      if (b.lat == null || b.lng == null) return -1;
      final da = Geolocator.distanceBetween(lat, lng, a.lat!, a.lng!);
      final db = Geolocator.distanceBetween(lat, lng, b.lat!, b.lng!);
      return da.compareTo(db);
    });
    if (mounted) setState(() => _restaurants = sorted);
  }

  /// 依距離排序附近景點（就地排序 + setState）
  void _sortNearbyByProximity() {
    if (_myPos == null) return;
    final lat = _myPos!.latitude;
    final lng = _myPos!.longitude;
    final sorted = [..._nearbySpots];
    sorted.sort((a, b) {
      if (a.lat == null || a.lng == null) return 1;
      if (b.lat == null || b.lng == null) return -1;
      final da = Geolocator.distanceBetween(lat, lng, a.lat!, a.lng!);
      final db = Geolocator.distanceBetween(lat, lng, b.lat!, b.lng!);
      return da.compareTo(db);
    });
    if (mounted) setState(() => _nearbySpots = sorted);
  }

  @override
  void dispose() {
    _bannerController.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  // ── Fetch real news+events (with SharedPreferences cache) ────────────────
  Future<void> _fetchNews() async {
    if (!mounted) return;

    final prefs  = await SharedPreferences.getInstance();
    final ts     = prefs.getInt(_kNewsCacheTsKey) ?? 0;
    final cached = prefs.getString(_kNewsCacheKey);
    final age    = DateTime.now().millisecondsSinceEpoch - ts;

    // ── Show cached data instantly (no loading spinner) ──────────────────
    if (cached != null && cached.isNotEmpty) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((m) => _govItemFromJson(m as Map<String, dynamic>))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() { _newsItems = list; _newsLoading = false; _newsError = false; });
          _startAutoScroll();
          if (age < _kNewsCacheTTLMs) return; // cache still fresh — skip network
          // cache stale: refresh silently in background (no loading indicator)
        }
      } catch (_) { /* corrupt cache — fall through to network */ }
    }

    // ── Network fetch (loading only shown when no cached data yet) ────────
    if (mounted && _newsItems.isEmpty) {
      setState(() { _newsLoading = true; _newsError = false; });
    }

    try {
      final results = await Future.wait([
        _fetchNewsOne(_kEventsUrl, isEvent: true),
        _fetchNewsOne(_kNewsUrl,   isEvent: false),
      ]).timeout(const Duration(seconds: 12));
      final combined = [...results[0], ...results[1]]
        ..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      final fresh = combined.take(20).toList();
      setState(() { _newsItems = fresh; _newsLoading = false; _newsError = false; });
      if (_autoScrollTimer == null || !_autoScrollTimer!.isActive) _startAutoScroll();
      // ── Persist to cache ─────────────────────────────────────────────────
      try {
        await prefs.setString(_kNewsCacheKey,
            jsonEncode(fresh.map(_govItemToJson).toList()));
        await prefs.setInt(_kNewsCacheTsKey,
            DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    } catch (_) {
      if (mounted && _newsItems.isEmpty) {
        setState(() { _newsError = true; _newsLoading = false; });
      }
      // If we already have cached data, fail silently (don't flash error)
    }
  }

  // ── Fetch restaurants — cache-first ───────────────────────
  Future<void> _fetchRestaurants() async {
    // 1. 嘗試從本地快取立即顯示
    final cached = await StaticDataCache.load('restaurants');
    if (cached.isNotEmpty) {
      final list = cached
          .map(_restaurantFromDoc)
          .where((r) => r.name.isNotEmpty)
          .toList();
      if (mounted) setState(() { _restaurants = list; _restaurantsLoading = false; });
    }

    // 2. 若快取是新鮮的就不再打網路
    final stale = await StaticDataCache.isStale('restaurants');
    if (!stale && cached.isNotEmpty) return;

    // 3. 快取不存在或已過期 → 背景 refresh（有快取時不顯示 loading）
    if (cached.isEmpty && mounted) setState(() => _restaurantsLoading = true);
    final fresh = await StaticDataCache.refresh('restaurants');
    if (fresh.isEmpty) {
      if (mounted) setState(() => _restaurantsLoading = false);
      return;
    }
    var list = fresh
        .map(_restaurantFromDoc)
        .where((r) => r.name.isNotEmpty)
        .toList();
    if (_myPos != null) _sortListByProximity(list);
    if (mounted) setState(() { _restaurants = list; _restaurantsLoading = false; });
  }

  /// 就地依距離排序（不 setState，呼叫端自行決定）
  void _sortListByProximity(List<_RestaurantItem> list) {
    if (_myPos == null) return;
    final lat = _myPos!.latitude, lng = _myPos!.longitude;
    list.sort((a, b) {
      if (a.lat == null || a.lng == null) return 1;
      if (b.lat == null || b.lng == null) return -1;
      return Geolocator.distanceBetween(lat, lng, a.lat!, a.lng!)
          .compareTo(Geolocator.distanceBetween(lat, lng, b.lat!, b.lng!));
    });
  }

  /// 從快取 Map 還原 _RestaurantItem
  _RestaurantItem _restaurantFromDoc(Map<String, dynamic> d) {
    final images = (d['images'] as List?)?.whereType<String>().toList() ?? [];
    // 嘗試解析座標（GeoPoint 已由 StaticDataCache 還原）
    double? lat, lng;
    final loc = d['location'];
    if (loc is GeoPoint && loc.latitude > 21 && loc.latitude < 26) {
      lat = loc.latitude; lng = loc.longitude;
    } else {
      for (final k in ['lat','latitude','緯度']) {
        final v = d[k]; if (v is num) { lat = v.toDouble(); break; }
      }
      for (final k in ['lng','longitude','經度']) {
        final v = d[k]; if (v is num) { lng = v.toDouble(); break; }
      }
    }
    return _RestaurantItem(
      id:        d['__id']?.toString() ?? '',
      name:      d['name']?.toString() ?? '',
      rating:    (d['rating'] as num?)?.toDouble() ?? 0,
      tags:      (d['tags'] as List?)?.whereType<String>().toList() ?? [],
      imageUrl:  images.isNotEmpty ? images.first : '',
      allImages: images,
      address:   d['address']?.toString() ?? '',
      shortDesc: d['shortDesc']?.toString() ?? '',
      price:     d['price']?.toString() ?? '',
      openTime:  d['time']?.toString() ?? '',
      lat: lat, lng: lng,
    );
  }

  // ── 附近景點 key 常數（共用於 cache load 和 refresh 解析）──────
  static const _nameKeys = [
    'name','Name','店家名稱','業者名稱','名稱','店名',
    '公共場所名稱','場所名稱','地點','停車場名稱','單位名稱','中文單位名稱',
  ];
  static const _addrKeys = [
    'address','Address','地址','加油站地址','營業地址',
    '設置地點','場所地址','路段',
  ];
  static const _imgKeys = ['imageUrl','image','Pic','pic','圖片','thumbnail'];
  static const _descKeys = [
    'description','Description','簡介','產品特色','場所描述','特色介紹','備註','內容',
  ];
  static const _latKeys = ['緯度','緯度坐標','地點LAT','Latitude','POINT_Y','lat'];
  static const _lngKeys = ['經度','經度坐標','地點LNG','Longitude','POINT_X','lng'];

  // ── Fetch nearby spots — cache-first ───────────────────────
  Future<void> _fetchNearbySpots() async {
    const cols = {
      'tdx_spots':            'TDX景點',
      'good_shops':           '好店',
      'pet_friendly_shops':   '寵物友善',
      'excellent_drink_shops':'飲料店',
    };

    // 1. 從快取立即顯示
    final cachedLists = await Future.wait(
      cols.entries.map((e) => _loadNearbyCache(e.key, e.value)),
    );
    final cachedAll = cachedLists.expand((x) => x).toList()..shuffle();
    if (cachedAll.isNotEmpty && mounted) {
      setState(() { _nearbySpots = cachedAll; _nearbyLoading = false; });
    }

    // 2. 任一集合 stale（或沒快取）才去 refresh
    final staleCheck = await Future.wait(
      cols.keys.map(StaticDataCache.isStale),
    );
    final anyStale = staleCheck.any((s) => s);
    if (!anyStale && cachedAll.isNotEmpty) return;

    if (cachedAll.isEmpty && mounted) setState(() => _nearbyLoading = true);

    final freshLists = await Future.wait(
      cols.entries.map((e) => _refreshNearby(e.key, e.value)),
    );
    final freshAll = freshLists.expand((x) => x).toList()..shuffle();
    if (freshAll.isNotEmpty && mounted) {
      setState(() { _nearbySpots = freshAll; _nearbyLoading = false; });
    } else if (mounted) {
      setState(() => _nearbyLoading = false);
    }
  }

  /// 從快取讀取一個集合並解析成 _NearbySpotItem
  Future<List<_NearbySpotItem>> _loadNearbyCache(String col, String cat) async {
    final docs = await StaticDataCache.load(col);
    return docs
        .map((d) => _nearbyFromDoc(d, cat))
        .whereType<_NearbySpotItem>()
        .toList();
  }

  /// 向 Firestore refresh 一個集合並解析成 _NearbySpotItem
  Future<List<_NearbySpotItem>> _refreshNearby(String col, String cat) async {
    final docs = await StaticDataCache.refresh(col);
    return docs
        .map((d) => _nearbyFromDoc(d, cat))
        .whereType<_NearbySpotItem>()
        .toList();
  }

  /// 從 Map（快取或 Firestore doc.data()）解析 _NearbySpotItem。
  /// name 空的回 null（用 whereType 過濾掉）。
  _NearbySpotItem? _nearbyFromDoc(Map<String, dynamic> d, String cat) {
    // id
    final id = d['__id']?.toString() ?? '';
    // name
    String name = '';
    for (final k in _nameKeys) {
      final v = d[k]?.toString() ?? '';
      if (v.isNotEmpty) { name = v; break; }
    }
    if (name.isEmpty) return null;
    // address
    String address = '';
    for (final k in _addrKeys) {
      final v = d[k]?.toString() ?? '';
      if (v.isNotEmpty) { address = v; break; }
    }
    // image
    String imageUrl = '';
    for (final k in _imgKeys) {
      final v = d[k];
      if (v is String && v.isNotEmpty) { imageUrl = v; break; }
      if (v is List && v.isNotEmpty) { imageUrl = v.first.toString(); break; }
    }
    // description
    String desc = '';
    for (final k in _descKeys) {
      final v = d[k]?.toString().trim() ?? '';
      if (v.length > 5) { desc = v; break; }
    }
    // lat/lng
    double? lat, lng;
    final loc = d['location'];
    if (loc is GeoPoint &&
        loc.latitude > 21 && loc.latitude < 26 &&
        loc.longitude > 119 && loc.longitude < 123) {
      lat = loc.latitude;
      lng = loc.longitude;
    } else {
      double? toNum(dynamic v) {
        if (v is double) return v;
        if (v is int)    return v.toDouble();
        if (v is String) return double.tryParse(v.trim());
        return null;
      }
      for (final k in _latKeys) {
        final n = toNum(d[k]);
        if (n != null && n > 21 && n < 26) { lat = n; break; }
      }
      for (final k in _lngKeys) {
        final n = toNum(d[k]);
        if (n != null && n > 119 && n < 123) { lng = n; break; }
      }
    }
    return _NearbySpotItem(
      id: id, name: name, category: cat,
      address: address, imageUrl: imageUrl,
      description: desc, lat: lat, lng: lng,
    );
  }

  Future<List<_GovItem>> _fetchNewsOne(
      String url, {required bool isEvent}) async {
    try {
      final res = await http.get(Uri.parse(url),
          headers: {'Accept': 'application/json'});
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['result'] is List) {
        list = data['result'] as List;
      } else if (data is Map && data['records'] is List) {
        list = data['records'] as List;
      } else {
        list = [];
      }
      return list.whereType<Map>().map((m) {
        final raw   = Map<String, dynamic>.from(m);
        // Use actual API field names first, then fallbacks
        final title = _pickField(raw, [
          'title',        // actual API field (both events & news)
          '標題','活動名稱','名稱','Title',
        ]) ?? '無標題';
        final dateStr = isEvent
            ? _pickField(raw, ['ActiveStart','ActiveEnd','發布日期','活動開始日期','日期','date','Date']) ?? ''
            : _pickField(raw, ['PostDate','發布日期','日期','date','Date','建立時間']) ?? '';
        final sum  = _pickField(raw, [
          'Content',      // actual API field
          '內容','摘要','描述','活動說明','summary','content','description',
        ]);
        final postUnit = _pickField(raw, ['PostUnit','發布單位','主辦單位']);
        final imgUrl   = _pickField(raw, ['Pic','Thumbnail','圖片']);
        final link     = _pickField(raw, ['Source','連結','url','URL','link','詳細連結']);
        return _GovItem(
          title:    title,
          date:     _shortDateStr(dateStr),
          location: postUnit, // reuse location slot for PostUnit
          summary:  sum,
          url:      link,
          imageUrl: imgUrl,
          isEvent:  isEvent,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static String? _pickField(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  static String _shortDateStr(String s) {
    if (s.isEmpty) return '';
    final m = RegExp(r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})').firstMatch(s);
    if (m != null) return '${m.group(1)}/${m.group(2)!.padLeft(2,'0')}/${m.group(3)!.padLeft(2,'0')}';
    return s.length > 10 ? s.substring(0, 10) : s;
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_newsItems.isEmpty) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_currentBanner + 1) % _newsItems.length;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _goSearch() => Navigator.push(context, _goRoute(const SearchScreen()));
  void _goNotifications() => Navigator.push(
    context,
    _goRoute(const NotificationsScreen()),
  ).then((_) => setState(() => _unreadCount = 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar ──
          SliverAppBar(
            expandedHeight: 155,
            floating: false,
            pinned: true,
            backgroundColor: context.appPrimaryDark,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
              onPressed: widget.onOpenDrawer,
            ),
            actions: [
              // Notification bell with badge
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: _goNotifications,
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        child: Center(
                          child: Text('$_unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.search_rounded, color: Colors.white),
                onPressed: _goSearch,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Builder(builder: (ctx) {
                final p  = ctx.appPrimary;
                final pd = ctx.appPrimaryDark;
                final pm = Color.lerp(p, Colors.white, 0.25) ?? p;
                return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [pm, p, pd],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(right: -40, top: -30,
                      child: Container(width: 160, height: 160,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.07)))),
                    Positioned(right: 20, top: 20,
                      child: Container(width: 80, height: 80,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05)))),
                    Positioned(left: -20, bottom: -20,
                      child: Container(width: 110, height: 110,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06)))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 70, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('探索諸羅',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                              color: Colors.white, letterSpacing: 2)),
                          const SizedBox(height: 4),
                          Text('嘉義・在地旅遊全攻略',
                            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85), letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ],
                ),
              );   // closes return Container(
              }),  // closes Builder(builder: (ctx) {
            ),     // closes FlexibleSpaceBar(background:
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWeatherCard(),
                _buildQuickAccessGrid(),
                _buildTransportSection(),
                _buildNewsBanner(),
                _buildNearbyChickenRice(),
                _buildNearbySpots(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Weather ──
  Widget _buildWeatherCard() {
    final primary  = context.appPrimary;
    final skyBlue  = const Color(0xFF7AB8CC);
    return TapFeedback(
      onTap: () => Navigator.push(context, _goRoute(const WeatherScreen())),
      child: Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [skyBlue, primary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('嘉義市', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                const Text('⛅ 多雲時晴', style: TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 12),
                Row(children: [
                  _wInfo('💧', '75%'),
                  const SizedBox(width: 14),
                  _wInfo('💨', '12km/h'),
                  const SizedBox(width: 14),
                  _wInfo('☀️', 'UV 8'),
                ]),
              ],
            ),
          ),
          Column(children: [
            const Text('32°', style: TextStyle(color: Colors.white, fontSize: 50, fontWeight: FontWeight.w200)),
            Text('體感 35°', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
          ]),
        ],
      ),
    )); // closes TapFeedback child
  }

  Widget _wInfo(String icon, String v) => Row(children: [
    Text(icon, style: const TextStyle(fontSize: 11)),
    const SizedBox(width: 2),
    Text(v, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600)),
  ]);

  Widget _quickRow(List<_QuickItem> rowItems) {
    return Row(
      children: rowItems.asMap().entries.map((e) {
        final isLast = e.key == rowItems.length - 1;
        return Expanded(child: Container(
          margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(right: 10),
          child: TapFeedback(
            onTap: e.value.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: e.value.color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(e.value.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 5),
                Text(e.value.label, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ]),
            ),
          ),
        ));
      }).toList(),
    );
  }

  // ── Quick Access Grid ── 每個按鈕都有真實跳轉 ──
  Widget _buildQuickAccessGrid() {
    final items = [
      _QuickItem('🗺️', '地圖探索', const Color(0xFFE6F0E6), () => widget.onSwitchTab?.call(1)),
      _QuickItem('🗓️', '行程管理', const Color(0xFFF5EFE6), () => widget.onSwitchTab?.call(2)),
      _QuickItem('💸', '旅遊分帳', const Color(0xFFEDF5ED), () => widget.onSwitchTab?.call(3)),
      _QuickItem('👥', '旅遊社群', const Color(0xFFEBEFF2), () => widget.onSwitchTab?.call(4)),
      _QuickItem('📅', '活動行事曆', const Color(0xFFF0EBF5),
        () => widget.onGoToTripCalendar?.call()),
      _QuickItem('🚌', '交通動態', const Color(0xFFE8F0F5),
        () => Navigator.push(context, _goRoute(const TransportScreen()))),
      _QuickItem('🎖️', '集章成就', const Color(0xFFF5F0E8), () => widget.onSwitchTab?.call(5)),
      _QuickItem('📸', '打卡相機', const Color(0xFFF0EDF5),
        () => Navigator.push(context, _goRoute(const CameraScreen()))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: SectionHeader(title: '快速導覽'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _quickRow(items.sublist(0, 4)),
              const SizedBox(height: 10),
              _quickRow(items.sublist(4, 8)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Transport ──
  Widget _buildTransportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: SectionHeader(
            title: '交通動態',
            actionText: '更多',
            onAction: () => Navigator.push(context, _goRoute(const TransportScreen())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: _transportCard('🚌', '市區公車', '紅幹線', '3 分鐘', const Color(0xFFC4856A), 0)),
              const SizedBox(width: 10),
              Expanded(child: _transportCard('🚲', 'YouBike', '火車站', '8 輛可借', const Color(0xFF5B8A5F), 1)),
              const SizedBox(width: 10),
              Expanded(child: _transportCard('🚂', '台鐵', '嘉→台北', '14:05', const Color(0xFF88B8C8), 2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _transportCard(String icon, String type, String line, String info, Color color, int tabIdx) {
    return TapFeedback(
      onTap: () => Navigator.push(context, _goRoute(TransportScreen(initialTab: tabIdx))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(type, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          Text(line, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(info, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('點此查看 ›', style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── News Banner (real government API data, auto-scroll) ──
  Widget _buildNewsBanner() {
    return Builder(builder: (ctx) {
      final primary = ctx.appPrimary;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: SectionHeader(
              title: '最新消息',
              actionText: _newsError ? '重試' : '全部',
              onAction: _newsError
                  ? _fetchNews
                  : () => Navigator.push(context, _goRoute(const NewsScreen())),
            ),
          ),

          // ── Loading state
          if (_newsLoading)
            SizedBox(
              height: 90,
              child: Center(
                child: CircularProgressIndicator(
                    color: primary, strokeWidth: 2.5)),
            )

          // ── Error / empty state
          else if (_newsError || _newsItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GestureDetector(
                onTap: _newsError ? _fetchNews : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceWarm,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(children: [
                    const Text('📭', style: TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      _newsError ? '載入失敗，點此重試' : '目前無最新消息',
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 13),
                    )),
                    if (_newsError)
                      Icon(Icons.refresh_rounded, color: primary, size: 20),
                  ]),
                ),
              ),
            )

          // ── Carousel with real data
          else ...[
            SizedBox(
              height: 110,
              child: PageView.builder(
                controller: _bannerController,
                onPageChanged: (i) => setState(() => _currentBanner = i),
                itemCount: _newsItems.length,
                itemBuilder: (_, index) {
                  final item = _newsItems[index];
                  final catColor = item.isEvent
                      ? const Color(0xFF00838F)
                      : const Color(0xFF1565C0);
                  final catEmoji = item.isEvent ? '🏮' : '📰';
                  final catLabel = item.isEvent ? '活動' : '新聞';
                  final subtitle = _cleanHtml(item.summary ?? item.location ?? '');
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TapFeedback(
                      onTap: () => _showNewsDetail(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceWarm,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
                          boxShadow: [BoxShadow(
                              color: AppColors.cardShadow,
                              blurRadius: 6,
                              offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(child: Text(catEmoji,
                                  style: const TextStyle(fontSize: 22))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: catColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(catLabel,
                                        style: TextStyle(
                                            color: catColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  const Spacer(),
                                  Text(item.date,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textHint)),
                                ]),
                                const SizedBox(height: 7),
                                Text(item.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                        height: 1.4),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(subtitle,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textHint,
                                          height: 1.3),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ],
                            )),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_newsItems.length, (i) =>
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentBanner ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _currentBanner
                        ? primary
                        : AppColors.textHint.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    });
  }

  void _showNewsDetail(_GovItem item) {
    final catColor = item.isEvent
        ? const Color(0xFF00838F)
        : const Color(0xFF1565C0);
    final catLabel = item.isEvent ? '活動' : '新聞';
    final cleanedSummary = _cleanHtml(item.summary);

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
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              // Handle
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)))),
              // Category chip
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(catLabel,
                      style: TextStyle(
                          color: catColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                if (item.date.isNotEmpty)
                  Text(item.date,
                      style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              // Title
              Text(item.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary, height: 1.4)),
              if (item.location != null && item.location!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.business_rounded, size: 13, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Expanded(child: Text(item.location!,
                      style: const TextStyle(color: AppColors.textHint, fontSize: 12))),
                ]),
              ],
              const Divider(height: 24),
              // Body — cleaned text, selectable so user can long-press copy
              if (cleanedSummary.isNotEmpty)
                SelectableText(cleanedSummary,
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textSecondary, height: 1.85)),
              const SizedBox(height: 20),
              // Source URL — open + copy buttons
              if (item.url != null && item.url!.isNotEmpty) ...[
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final raw = item.url!.trim();
                          final uri = Uri.parse(
                            raw.startsWith('http') ? raw : 'https://$raw',
                          );
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('無法開啟連結'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('開啟原始連結'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: item.url!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已複製連結'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('複製'),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Nearby chicken rice (雞肉飯) ──────────────────────────
  Widget _buildNearbyChickenRice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: SectionHeader(
            title: '附近雞肉飯',
            actionText: '查看地圖',
            onAction: () => widget.onSwitchTab?.call(1),
          ),
        ),
        SizedBox(
          height: 220,
          child: _restaurantsLoading
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 4,
                  itemBuilder: (_, __) => _restaurantShimmer(),
                )
              : _restaurants.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🍗', style: TextStyle(fontSize: 36)),
                          const SizedBox(height: 8),
                          Text('暫無資料', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _restaurants.length,
                      itemBuilder: (_, i) => _restaurantCard(_restaurants[i]),
                    ),
        ),
      ],
    );
  }

  Widget _restaurantCard(_RestaurantItem r) {
    final primary = context.appPrimary;
    return TapFeedback(
      onTap: () => _showRestaurantDetail(r),
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: r.imageUrl.isNotEmpty
                  ? Image.network(
                      r.imageUrl,
                      height: 115,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 115,
                        color: AppColors.surfaceMoss,
                        child: const Center(child: Text('🍗', style: TextStyle(fontSize: 36))),
                      ),
                    )
                  : Container(
                      height: 115,
                      color: AppColors.surfaceMoss,
                      child: const Center(child: Text('🍗', style: TextStyle(fontSize: 36))),
                    ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 13, color: AppColors.accentStraw),
                      const SizedBox(width: 2),
                      Text(
                        r.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                      if (r.tags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(width: 1, height: 10, color: AppColors.divider),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r.tags.first,
                            style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (r.address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      r.address,
                      style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _restaurantShimmer() {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMoss,
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }

  void _showRestaurantDetail(_RestaurantItem r) {
    final ctx = context;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RestaurantDetailSheet(
        r: r,
        onViewOnMap: (r.lat != null && r.lng != null)
            ? () {
                Navigator.of(ctx).pop();
                MapScreen.focusNotifier.value = (
                  lat: r.lat!,
                  lng: r.lng!,
                  catKey: MapScreen.catKeyChiayiFood,
                );
                widget.onSwitchTab?.call(1);
              }
            : null,
      ),
    );
  }

  // ── Nearby spots (multi-source) ──────────────────────────
  Widget _buildNearbySpots() {
    final primary = context.appPrimary;
    final filtered = _nearbyFilter == '全部'
        ? _nearbySpots
        : _nearbySpots.where((s) => s.category == _nearbyFilter).toList();
    // Show at most 6 items to keep the section compact
    final shown = filtered.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: SectionHeader(
            title: '附近景點',
            actionText: '地圖',
            onAction: () => widget.onSwitchTab?.call(1),
          ),
        ),
        // ── Filter chips ──
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _kNearbyFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _kNearbyFilters[i];
              final active = f == _nearbyFilter;
              return GestureDetector(
                onTap: () => setState(() => _nearbyFilter = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? primary : AppColors.surfaceWarm,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? primary : AppColors.divider),
                  ),
                  child: Text(f,
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppColors.textSecondary,
                    )),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // ── List rows ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _nearbyLoading
              ? Column(children: List.generate(4, (_) => _nearbyRowShimmer()))
              : filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('此分類暫無資料',
                          style: TextStyle(color: AppColors.textHint, fontSize: 13))),
                    )
                  : Column(
                      children: shown.map((s) => _nearbyRow(s)).toList(),
                    ),
        ),
      ],
    );
  }

  static const _kCatEmoji = {
    'TDX景點': '🏛️',
    '好店':   '🏪',
    '寵物友善': '🐾',
    '飲料店':  '🧋',
  };
  static const _kCatColor = {
    'TDX景點': Color(0xFF00897B),
    '好店':   Color(0xFF6A1B9A),
    '寵物友善': Color(0xFFAD1457),
    '飲料店':  Color(0xFF0277BD),
  };

  Widget _nearbyRow(_NearbySpotItem s) {
    final primary = context.appPrimary;
    final catColor = _kCatColor[s.category] ?? primary;
    final catEmoji = _kCatEmoji[s.category] ?? '📍';
    return TapFeedback(
      onTap: () => _showNearbySpotDetail(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(children: [
          // Emoji bubble
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(catEmoji,
                style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          // Name + category + address
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(s.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(s.category,
                      style: TextStyle(fontSize: 9, color: catColor,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              if (s.address.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 11, color: AppColors.textHint),
                  const SizedBox(width: 3),
                  Expanded(child: Text(s.address,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ],
          )),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textHint, size: 18),
        ]),
      ),
    );
  }

  Widget _nearbyRowShimmer() => Container(
    height: 66,
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceMoss,
      borderRadius: BorderRadius.circular(14),
    ),
  );

  // ── Nearby spot detail sheet ──────────────────────────────
  void _showNearbySpotDetail(_NearbySpotItem s) {
    final catColor = _kCatColor[s.category] ?? context.appPrimary;
    final catEmoji = _kCatEmoji[s.category] ?? '📍';
    final hasMap   = s.lat != null && s.lng != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: s.description.isNotEmpty ? 0.60 : 0.48,
        maxChildSize: 0.92,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // Handle
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              )),

              // Icon + name + category chip
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(child: Text(catEmoji, style: const TextStyle(fontSize: 26))),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s.category,
                        style: TextStyle(fontSize: 11, color: catColor, fontWeight: FontWeight.w700)),
                    ),
                  ],
                )),
              ]),

              // Address
              if (s.address.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.address,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4))),
                ]),
              ],

              // Description
              if (s.description.isNotEmpty) ...[
                const Divider(height: 28),
                const Text('簡介',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text(s.description,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.75)),
              ],

              const SizedBox(height: 20),

              // Jump-to-map button
              if (hasMap)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      // 傳 catKey 讓地圖自動開啟對應圖層
                      final catKey = const {
                        'TDX景點':  MapScreen.catKeyTdxSpot,
                        '好店':     MapScreen.catKeyGoodShop,
                        '寵物友善': MapScreen.catKeyPetShop,
                        '飲料店':   MapScreen.catKeyDrinkShop,
                      }[s.category];
                      MapScreen.focusNotifier.value = (
                        lat: s.lat!, lng: s.lng!, catKey: catKey,
                      );
                      widget.onSwitchTab?.call(1);
                    },
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: const Text('在地圖上查看'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: catColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      widget.onSwitchTab?.call(1);
                    },
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: const Text('前往地圖探索'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: catColor,
                      side: BorderSide(color: catColor),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

              // Rating & notes
              SpotRatingSection(placeId: 'nearby_${s.id}'),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Restaurant Detail Sheet with image carousel ───────────────
class _RestaurantDetailSheet extends StatefulWidget {
  final _RestaurantItem r;
  final VoidCallback? onViewOnMap;
  const _RestaurantDetailSheet({required this.r, this.onViewOnMap});
  @override
  State<_RestaurantDetailSheet> createState() => _RestaurantDetailSheetState();
}

class _RestaurantDetailSheetState extends State<_RestaurantDetailSheet> {
  int _imgIndex = 0;
  final _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final primary = Theme.of(context).colorScheme.primary;
    final hasImages = r.allImages.isNotEmpty;
    return DraggableScrollableSheet(
      initialChildSize: hasImages ? 0.75 : 0.55,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.zero,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 0),
              child: Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Image carousel
            if (hasImages)
              Stack(
                children: [
                  SizedBox(
                    height: 220,
                    child: PageView.builder(
                      controller: _pageCtrl,
                      itemCount: r.allImages.length,
                      onPageChanged: (i) => setState(() => _imgIndex = i),
                      itemBuilder: (_, i) => Image.network(
                        r.allImages[i],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.surfaceMoss,
                          child: const Center(
                              child: Text('🍗', style: TextStyle(fontSize: 52))),
                        ),
                      ),
                    ),
                  ),
                  if (r.allImages.length > 1)
                    Positioned(
                      bottom: 10, right: 0, left: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(r.allImages.length, (i) =>
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _imgIndex == i ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _imgIndex == i
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )),
                      ),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      ),
                      Row(children: [
                        const Icon(Icons.star_rounded, size: 18, color: AppColors.accentStraw),
                        const SizedBox(width: 2),
                        Text(r.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                      ]),
                    ],
                  ),
                  if (r.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: r.tags.map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Color.lerp(primary, Colors.white, 0.85)!,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Color.lerp(primary, Colors.white, 0.5)!),
                        ),
                        child: Text(t, style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                      )).toList(),
                    ),
                  ],
                  if (r.shortDesc.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(r.shortDesc, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                  ],
                  const SizedBox(height: 12),
                  if (r.address.isNotEmpty) _detailRow(Icons.location_on_outlined, r.address, primary),
                  if (r.openTime.isNotEmpty) _detailRow(Icons.access_time_outlined, r.openTime, primary),
                  if (r.price.isNotEmpty) _detailRow(Icons.monetization_on_outlined, r.price, primary),
                  // 在地圖上查看（有座標才顯示）
                  if (widget.onViewOnMap != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onViewOnMap,
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label: const Text('在地圖上查看'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(color: primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  SpotRatingSection(placeId: 'restaurant_${r.id}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, Color primary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ── Quick item model ──
class _QuickItem {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  _QuickItem(this.icon, this.label, this.color, this.onTap);
}

// ── _RestaurantItem: Firestore restaurants collection ────────
class _RestaurantItem {
  final String id;
  final String name;
  final double rating;
  final List<String> tags;
  final String imageUrl;        // first image (for card thumbnail)
  final List<String> allImages; // all images (for carousel)
  final String address;
  final String shortDesc;
  final String price;
  final String openTime;
  final double? lat;
  final double? lng;
  const _RestaurantItem({
    required this.id,
    required this.name,
    required this.rating,
    required this.tags,
    required this.imageUrl,
    required this.allImages,
    required this.address,
    required this.shortDesc,
    required this.price,
    required this.openTime,
    this.lat,
    this.lng,
  });
}

// ── _NearbySpotItem: nearby spot from multiple collections ──
class _NearbySpotItem {
  final String id;
  final String name;
  final String category;    // TDX景點 | 好店 | 寵物友善 | 飲料店
  final String address;
  final String imageUrl;
  final String description; // 簡介 / 特色 (may be empty)
  final double? lat;
  final double? lng;
  const _NearbySpotItem({
    required this.id, required this.name, required this.category,
    required this.address, required this.imageUrl,
    this.description = '', this.lat, this.lng,
  });
}

// ── _GovItem: government news/event data model ──────────────
class _GovItem {
  final String  title;
  final String  date;
  final String? location;   // PostUnit for both events & news
  final String? summary;
  final String? url;        // Source link
  final String? imageUrl;   // Pic / Thumbnail
  final bool    isEvent;    // true = 活動, false = 新聞
  const _GovItem({
    required this.title,
    required this.date,
    this.location,
    this.summary,
    this.url,
    this.imageUrl,
    required this.isEvent,
  });
}
