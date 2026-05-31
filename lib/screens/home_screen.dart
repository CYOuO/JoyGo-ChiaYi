import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../services/static_data_cache.dart';
import 'settings_screen.dart';
import 'expense_screen.dart';
import '../widgets/common_widgets.dart' show SectionHeader, SpotRatingSection, TapFeedback, WashiTapeDivider, PolaroidCard;
import '../widgets/spot_save_button.dart';
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

// ── 首頁色系 ───────────────────────────────────────────────────
// _kWarmBg 不再是 const，由 Theme 動態取得（隨主題主色染色）
const _kCardBg = Color(0xFFFFFFFF); // 浮動白卡
const _kCardRadius    = 22.0;
const _kCardShadow    = [
  BoxShadow(
    color: Color(0x14C09060),
    blurRadius: 20,
    offset: Offset(0, 6),
    spreadRadius: -2,
  ),
];

/// 浮動白色卡片容器 — 參考「奶酪單詞」風格
Widget _warmSection({
  required Widget child,
  EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(16, 0, 16, 0),
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  return Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(_kCardRadius),
      boxShadow: _kCardShadow,
    ),
    child: child,
  );
}

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

// ══════════════════════════════════════════════════════════════
//  波浪裁切器 — 底端不規則大波浪（三段正弦疊加，製造有機感）
// ══════════════════════════════════════════════════════════════
class _WaveClipper extends CustomClipper<Path> {
  final double animValue;
  const _WaveClipper(this.animValue);

  @override
  Path getClip(Size s) {
    final base = s.height - 48.0;
    final p = Path()..lineTo(0, base + 8);
    p.cubicTo(
      s.width * 0.25, base - 14,
      s.width * 0.75, base + 22,
      s.width,        base + 4,
    );
    p.lineTo(s.width, 0);
    p.lineTo(0, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(_WaveClipper old) => old.animValue != animValue;
}

// ── 第二層波浪線 Painter（純描邊，增加層次感）─────────────────
class _WaveLinePainter extends CustomPainter {
  final Color color;
  const _WaveLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size s) {
    // 比主波浪高 24px，略不同相位，製造雙層浪效果
    final base = s.height - 72.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(0, base + 6);
    // 與主波浪控制點相反（右高左低），形成交錯感
    path.cubicTo(
      s.width * 0.30, base - 10,
      s.width * 0.70, base + 18,
      s.width,        base + 2,
    );
    canvas.drawPath(path, paint);

    // 更高的第三層（更細更淡）
    final base2 = s.height - 90.0;
    final paint2 = Paint()
      ..color = color.withValues(alpha: color.a * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final path2 = Path()..moveTo(0, base2 + 4);
    path2.cubicTo(
      s.width * 0.35, base2 - 8,
      s.width * 0.65, base2 + 14,
      s.width,        base2,
    );
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant _WaveLinePainter old) => old.color != color;
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _bannerController = PageController();
  int _currentBanner = 0;
  int _unreadCount   = 3;
  Timer? _autoScrollTimer;

  // ── Government news / events
  List<_GovItem> _newsItems = [];
  bool _newsLoading = true;
  bool _newsError   = false;

  // ── 使用者位置（供附近排序用）────────────────────────────
  Position? _myPos;

  // ── Restaurants (雞肉飯) from Firestore ──────────────────
  List<_RestaurantItem> _restaurants = [];
  bool _restaurantsLoading = true;
  // Flip-card PageController for restaurant carousel
  final PageController _restaurantPageCtrl =
      PageController(viewportFraction: 0.82);

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
    _restaurantPageCtrl.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_newsItems.isEmpty) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_currentBanner + 1) % _newsItems.length;
      _bannerController.animateToPage(next,
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
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
            .where((item) => item.title.isNotEmpty && item.title != '無標題')
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() { _newsItems = list; _newsLoading = false; _newsError = false; });
          _startAutoScroll();
          if (age < _kNewsCacheTTLMs) return;
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
      final fresh = combined
          .where((item) => item.title.isNotEmpty && item.title != '無標題')
          .take(5).toList();
      setState(() { _newsItems = fresh; _newsLoading = false; _newsError = false; });
      _startAutoScroll();
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

  void _goSearch() => Navigator.push(context, _goRoute(const SearchScreen()));
  void _goNotifications() => Navigator.push(
    context, _goRoute(const NotificationsScreen()),
  ).then((_) => setState(() => _unreadCount = 0));

  @override
  Widget build(BuildContext context) {
    final primary = context.appPrimary;
    final dark    = context.appPrimaryDark;
    final light   = Color.lerp(primary, Colors.white, 0.38) ?? primary;

    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar：bg 與 Scaffold 同色，讓波浪裁切角落透出底色 ──
          SliverAppBar(
            expandedHeight: 295,
            floating: false,
            pinned: true,
            backgroundColor: bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: null,
            automaticallyImplyLeading: false,
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: _goNotifications,
                      child: Container(
                        width: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: HugeIcon(icon: HugeIcons.strokeRoundedNotification01,
                              color: AppColors.textPrimary, size: 20),
                        ),
                      ),
                    ),
                    if (_unreadCount > 0)
                      const Positioned(
                        right: 0, top: 0,
                        child: _PulsingDot(),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
                child: GestureDetector(
                  onTap: () => Navigator.push(context, _goRoute(const SettingsScreen())),
                  child: Container(
                    width: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: HugeIcon(icon: HugeIcons.strokeRoundedSettings01,
                          color: AppColors.textPrimary, size: 20),
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              // ── 靜態波浪 ──────────────────────────────────────────
              background: ClipPath(
                clipper: const _WaveClipper(0.35),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [light, primary, dark],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // ── 第二層波浪線（層次感）────────────────────
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _WaveLinePainter(
                            color: Colors.white.withValues(alpha: 0.22)),
                        ),
                      ),
                      // ── 裝飾圓：大圓靜態，小圓輕微呼吸動畫 ────────
                      _StaticCircle(right: -40, top: -30, size: 190, alpha: 0.10),
                      _AnimatedCircle(right: 30, top: 28,  size: 75,  alpha: 0.07,
                          duration: const Duration(seconds: 4), scaleTo: 1.18),
                      _AnimatedCircle(left: -25, bottom: 55, size: 120, alpha: 0.09,
                          duration: const Duration(seconds: 5), scaleTo: 1.12, reverse: true),
                      _AnimatedCircle(left: 60,  bottom: 30, size: 50,  alpha: 0.06,
                          duration: const Duration(seconds: 3), scaleTo: 1.25),
                      // ── 內容：標題 + 天氣副標 + 搜尋框 ──────────
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 90),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 主標題（Joy 右上角加三條線）
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        const TextSpan(
                                          text: '去嘉義找',
                                          style: TextStyle(
                                            fontSize: 31,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            height: 1.1,
                                            letterSpacing: 2.0,
                                          ),
                                        ),
                                        TextSpan(
                                          text: 'Joy',
                                          style: GoogleFonts.pacifico(
                                            fontSize: 36,
                                            color: Colors.white,
                                            height: 1.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Joy 右上角裝飾線條（定位在 Joy 字右上）
                                  Positioned(
                                    right: -28,
                                    top: -12,
                                    child: CustomPaint(
                                      size: const Size(30, 28),
                                      painter: _JoyStrokesPainter(
                                        color: Colors.white.withValues(alpha: 0.75),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // ── 天氣：無框散排 ──
                              GestureDetector(
                                onTap: () => Navigator.push(
                                    context, _goRoute(const WeatherScreen())),
                                child: Row(
                                  children: [
                                    const Text('⛅', style: TextStyle(fontSize: 15)),
                                    const SizedBox(width: 5),
                                    const Text('32°',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w300,
                                        height: 1.0,
                                      )),
                                    const SizedBox(width: 5),
                                    Text('多雲時晴',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.78),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      )),
                                    const SizedBox(width: 10),
                                    Container(width: 1, height: 11,
                                        color: Colors.white.withValues(alpha: 0.30)),
                                    const SizedBox(width: 10),
                                    _wInfoInline('💧', '75%'),
                                    const SizedBox(width: 8),
                                    _wInfoInline('💨', '12km/h'),
                                    const SizedBox(width: 8),
                                    _wInfoInline('☀️', 'UV 8'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              GestureDetector(
                                onTap: _goSearch,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(30),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.35),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Row(children: [
                                        HugeIcon(icon: HugeIcons.strokeRoundedSearch01,
                                            color: Colors.white.withValues(alpha: 0.85), size: 18),
                                        const SizedBox(width: 10),
                                        Text('搜尋景點、美食、活動…',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.80),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          )),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuickAccessGrid(),
                const WashiTapeDivider(),
                _buildTransportSection(),
                const WashiTapeDivider(color: Color(0x18E8A87C)),
                _buildNewsBanner(),
                const WashiTapeDivider(color: Color(0x18B08BD4)),
                _buildNearbyChickenRice(),
                const WashiTapeDivider(color: Color(0x1885B79D)),
                _buildNearbySpots(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 天氣小資訊 helper（用於 header 內嵌天氣列）──
  Widget _wInfoInline(String icon, String v) => Row(children: [
    Text(icon, style: const TextStyle(fontSize: 10)),
    const SizedBox(width: 2),
    Text(v, style: TextStyle(
      color: Colors.white.withValues(alpha: 0.88),
      fontSize: 10, fontWeight: FontWeight.w600,
    )),
  ]);

  // ── _wInfo（保留給其他地方可能用到）──
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
          child: _BounceQuickButton(
            item: e.value,
          ),
        ));
      }).toList(),
    );
  }

  // ── Quick Access Grid ── 每個按鈕都有真實跳轉 ──
  Widget _buildQuickAccessGrid() {
    final items = [
      _QuickItem(HugeIcons.strokeRoundedLocation06, '地圖探索', const Color(0xFFE6F0E6),
        () => widget.onSwitchTab?.call(2)), // 探索 = 新 index 2
      _QuickItem(HugeIcons.strokeRoundedCalendar03, '行程管理', const Color(0xFFF5EFE6),
        () => widget.onSwitchTab?.call(1)), // 行程 = 新 index 1
      _QuickItem(HugeIcons.strokeRoundedWallet01, '旅遊分帳', const Color(0xFFEDF5ED),
        () => Navigator.push(context, _goRoute(const ExpenseScreen()))),
      _QuickItem(HugeIcons.strokeRoundedUserGroup, '旅遊社群', const Color(0xFFEBEFF2),
        () => widget.onSwitchTab?.call(3)),
      _QuickItem(HugeIcons.strokeRoundedTicket01, '活動行事曆', const Color(0xFFF0EBF5),
        () => widget.onGoToTripCalendar?.call()),
      _QuickItem(HugeIcons.strokeRoundedBus01, '交通動態', const Color(0xFFE8F0F5),
        () => Navigator.push(context, _goRoute(TransportScreen(
            // 🌟 神奇攔截器：把交通動態傳出來的舊版 1 (行程) 自動轉換成新版 2 (地圖)
            onSwitchTab: (idx) => widget.onSwitchTab?.call(idx == 1 ? 2 : idx)
        )))),
      _QuickItem(HugeIcons.strokeRoundedStar, '集章成就', const Color(0xFFF5F0E8),
        () => widget.onSwitchTab?.call(4)),
      _QuickItem(HugeIcons.strokeRoundedCamera01, '打卡相機', const Color(0xFFF0EDF5),
        () => Navigator.push(context, _goRoute(const CameraScreen()))),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _warmSection(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 14),
              child: SectionHeader(title: '快速導覽'),
            ),
            _quickRow(items.sublist(0, 4)),
            const SizedBox(height: 10),
            _quickRow(items.sublist(4, 8)),
          ],
        ),
      ),
    );
  }

  // ── Transport ──
  Widget _buildTransportSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: _warmSection(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 14),
              child: SectionHeader(
                title: '交通動態',
                actionText: '更多',
                onAction: () => Navigator.push(context, _goRoute(const TransportScreen())),
              ),
            ),
            Row(
              children: [
                Expanded(child: _transportCard(Icons.directions_bus_rounded, '市區公車', '紅幹線', '3 分鐘', const Color(0xFFC4856A), 0)),
                const SizedBox(width: 10),
                Expanded(child: _transportCard(Icons.pedal_bike_rounded, 'YouBike', '火車站', '8 輛可借', const Color(0xFF5B8A5F), 1)),
                const SizedBox(width: 10),
                Expanded(child: _transportCard(Icons.train_rounded, '台鐵', '嘉→台北', '14:05', const Color(0xFF88B8C8), 2)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _transportCard(IconData icon, String type, String line, String info, Color color, int tabIdx) {
    return TapFeedback(
      onTap: () => Navigator.push(context, _goRoute(TransportScreen(initialTab: tabIdx))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
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

  // ── News Banner — 自動輪播，一次顯示一則，點擊展開詳細內容 ──
  Widget _buildNewsBanner() {
    final primary = context.appPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: SectionHeader(
            title: '最新消息',
            actionText: _newsError ? '重試' : '全部',
            onAction: _newsError
                ? _fetchNews
                : () => Navigator.push(context, _goRoute(const NewsScreen())),
          ),
        ),

        // ── Loading
        if (_newsLoading)
          SizedBox(height: 100,
            child: Center(child: CircularProgressIndicator(
                color: primary, strokeWidth: 2.5))),

        // ── Error / empty
        if (!_newsLoading && (_newsError || _newsItems.isEmpty))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: _newsError ? _fetchNews : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: _kCardShadow,
                ),
                child: Row(children: [
                  const Text('📭', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    _newsError ? '載入失敗，點此重試' : '目前無最新消息',
                    style: const TextStyle(color: AppColors.textHint, fontSize: 13),
                  )),
                  if (_newsError)
                    Icon(Icons.refresh_rounded, color: primary, size: 20),
                ]),
              ),
            ),
          ),

        // ── Carousel
        if (!_newsLoading && !_newsError && _newsItems.isNotEmpty) ...[
          SizedBox(
            height: 134,
            child: PageView.builder(
              controller: _bannerController,
              onPageChanged: (i) => setState(() => _currentBanner = i),
              itemCount: _newsItems.length,
              itemBuilder: (_, index) {
                final item = _newsItems[index];
                final catColor = item.isEvent
                    ? const Color(0xFF00838F)
                    : const Color(0xFF1565C0);
                final catIconData = item.isEvent ? Icons.event_rounded : Icons.article_outlined;
                final catLabel = item.isEvent ? '活動' : '新聞';
                final subtitle = _cleanHtml(item.summary ?? item.location ?? '');
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TapFeedback(
                    onTap: () => _showNewsDetail(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _kCardShadow,
                      ),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(child: Icon(catIconData, size: 22, color: catColor)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(catLabel,
                                  style: TextStyle(color: catColor, fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                              ),
                              const Spacer(),
                              Text(item.date,
                                style: const TextStyle(fontSize: 10,
                                    color: AppColors.textHint)),
                            ]),
                            const SizedBox(height: 6),
                            Text(item.title,
                              style: const TextStyle(fontWeight: FontWeight.w700,
                                  fontSize: 13, color: AppColors.textPrimary, height: 1.3),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            // 摘要 + 看完整內容合一行，避免 overflow
                            Row(children: [
                              if (subtitle.isNotEmpty)
                                Expanded(
                                  child: Text(subtitle,
                                    style: const TextStyle(fontSize: 11,
                                        color: AppColors.textHint, height: 1.2),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                )
                              else
                                const Spacer(),
                              const SizedBox(width: 6),
                              Text('看完整',
                                style: TextStyle(fontSize: 10,
                                    color: catColor, fontWeight: FontWeight.w600)),
                              Icon(Icons.arrow_forward_ios_rounded, size: 8, color: catColor),
                            ]),
                          ],
                        )),
                        const SizedBox(width: 4),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Page dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_newsItems.length, (i) =>
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _currentBanner ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _currentBanner
                      ? primary
                      : AppColors.textHint.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
        ],
      ],
    );
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
            onAction: () => widget.onSwitchTab?.call(2),
          ),
        ),
        SizedBox(
          height: 210,
          child: _restaurantsLoading
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  itemCount: 4,
                  itemBuilder: (_, __) => _restaurantShimmer(),
                )
              : _restaurants.isEmpty
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.restaurant_rounded, size: 36, color: AppColors.textHint),
                        const SizedBox(height: 8),
                        Text('暫無資料', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                      ],
                    ))
                  : PageView.builder(
                      controller: _restaurantPageCtrl,
                      padEnds: false, // fix left empty space on first card
                      itemCount: _restaurants.length,
                      itemBuilder: (_, i) {
                        return AnimatedBuilder(
                          animation: _restaurantPageCtrl,
                          builder: (_, child) {
                            double offset = 0;
                            if (_restaurantPageCtrl.position.haveDimensions) {
                              offset = (_restaurantPageCtrl.page! - i).clamp(-1.0, 1.0);
                            }
                            final tilt = offset * 0.15;
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0012)
                                ..rotateY(tilt),
                              child: Opacity(
                                opacity: (1 - offset.abs() * 0.3).clamp(0.0, 1.0),
                                child: child,
                              ),
                            );
                          },
                          child: Padding(
                            // First card: left 16, others: symmetric
                            padding: EdgeInsets.only(
                              left: i == 0 ? 16 : 6,
                              right: 6, top: 4, bottom: 4),
                            child: _restaurantCard(_restaurants[i]),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // 翻卡效果：點一下翻轉看細節，再點翻回正面
  Widget _restaurantCard(_RestaurantItem r) {
    return _FlipRestaurantCard(
      r: r,
      onShowDetail: () => _showRestaurantDetail(r),
    );
  }

  Widget _restaurantShimmer() {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMoss,
        borderRadius: BorderRadius.circular(20),
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
                widget.onSwitchTab?.call(2);
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: _warmSection(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: SectionHeader(
                title: '附近景點',
                actionText: '地圖',
                onAction: () => widget.onSwitchTab?.call(2),
              ),
            ),
            // ── Filter chips ──
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
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
                        color: active ? primary : const Color(0xFFF5F1EB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active ? primary : const Color(0xFFE8E0D4),
                        ),
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
            _nearbyLoading
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
          ],
        ),
      ),
    );
  }

  static const _kCatIcon = <String, IconData>{
    'TDX景點': Icons.account_balance_rounded,
    '好店':   Icons.store_rounded,
    '寵物友善': Icons.pets_rounded,
    '飲料店':  Icons.local_cafe_rounded,
  };
  // Soft, harmonious palette — each category has its own identity
  // but all feel like they belong together in a warm travel app
  static const _kCatColor = {
    'TDX景點': Color(0xFF6A9E70),  // sage green — culture / nature
    '好店':    Color(0xFFE8845A),  // terracotta — food / commerce
    '寵物友善': Color(0xFF6BA3C8), // sky blue — friendly / open
    '飲料店':  Color(0xFF9C7FC0),  // lavender — cafe / dessert
  };

  Widget _nearbyRow(_NearbySpotItem s) {
    final primary = context.appPrimary;
    final catColor = _kCatColor[s.category] ?? primary;
    final catIcon  = _kCatIcon[s.category] ?? Icons.place_rounded;
    return TapFeedback(
      onTap: () => _showNearbySpotDetail(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          // Icon bubble
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Icon(catIcon, size: 22, color: catColor)),
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
          // ── Save button ──────────────────────────────────────
          SpotSaveButton(
            spotId:      s.id,
            spotName:    s.name,
            imageUrl:    s.imageUrl,
            size:        15,
            description: s.description,
            address:     s.address,
            category:    s.category,
          ),
          const SizedBox(width: 4),
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
    final catIcon  = _kCatIcon[s.category] ?? Icons.place_rounded;
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
                  child: Center(child: Icon(catIcon, size: 26, color: catColor)),
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
                      widget.onSwitchTab?.call(2);
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
                      widget.onSwitchTab?.call(2);
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

// ═══════════════════════════════════════════════════════════════
// 3D 翻卡元件 — 點正面翻到背面看細節；再點翻回正面
// ═══════════════════════════════════════════════════════════════
class _FlipRestaurantCard extends StatefulWidget {
  final _RestaurantItem r;
  final VoidCallback onShowDetail;
  const _FlipRestaurantCard({required this.r, required this.onShowDetail});

  @override
  State<_FlipRestaurantCard> createState() => _FlipRestaurantCardState();
}

class _FlipRestaurantCardState extends State<_FlipRestaurantCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _showFront = true; // current resting state (which face we're on)

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    if (_ctrl.isAnimating) return;
    // Start animation then commit face change at the end
    _ctrl.forward(from: 0).then((_) {
      if (mounted) {
        setState(() => _showFront = !_showFront);
        _ctrl.reset();
      }
    });
    setState(() {}); // trigger rebuild for animation
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final r = widget.r;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value; // 0 → 1
        // Phase 1 (t: 0→0.5): current face rotates away (squish to edge)
        // Phase 2 (t: 0.5→1): next face rotates in (expand from edge)
        // Both phases use angle range 0→π/2, one going away, one coming in
        // This avoids any > 90° rotation (no upside-down possible)
        final inFirstHalf = t < 0.5;
        final faceAngle = inFirstHalf
            ? t * math.pi          // 0 → π/2  (current face rotates away)
            : (1.0 - t) * math.pi; // π/2 → 0  (next face opens up)
        final showingFront = inFirstHalf ? _showFront : !_showFront;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(faceAngle),
          child: showingFront ? _buildFront(r, primary) : _buildBack(r, primary),
        );
      },
    );
  }

  Widget _buildFront(_RestaurantItem r, Color primary) {
    return GestureDetector(
      onTap: _flip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(fit: StackFit.expand, children: [
          r.imageUrl.isNotEmpty
              ? Image.network(r.imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceMoss,
                    child: Icon(Icons.restaurant_rounded, size: 48, color: AppColors.textHint)))
              : Container(color: AppColors.surfaceMoss,
                  child: Icon(Icons.restaurant_rounded, size: 48, color: AppColors.textHint)),
          Positioned.fill(child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.0),
                         Colors.black.withValues(alpha: 0.68)],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          )),
          Positioned(top: 10, right: 10,
            child: SpotSaveButton(spotId: r.id, spotName: r.name, imageUrl: r.imageUrl, size: 15)),
          Positioned(left: 14, right: 14, bottom: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.name,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Row(children: [
                const Icon(Icons.star_rounded, size: 13, color: AppColors.accentStraw),
                const SizedBox(width: 3),
                Text(r.rating.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                if (r.tags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: Text(r.tags.first,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
            ])),
        ]),
      ),
    );
  }

  Widget _buildBack(_RestaurantItem r, Color primary) {
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return GestureDetector(
      onTap: _flip,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primary.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: mist, shape: BoxShape.circle),
              child: Icon(Icons.flip_rounded, size: 14, color: primary),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.star_rounded, size: 14, color: AppColors.accentStraw),
            const SizedBox(width: 4),
            Text(r.rating.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          if (r.address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.location_on_outlined, size: 13, color: AppColors.textHint),
              const SizedBox(width: 4),
              Expanded(child: Text(r.address,
                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ],
          if (r.shortDesc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.shortDesc,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
              maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onShowDetail,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                backgroundColor: primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('查看詳情', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
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
                              child: Icon(Icons.restaurant_rounded, size: 52, color: AppColors.textHint)),
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

// ══════════════════════════════════════════════════════════════
//  _JoyStrokesPainter — Joy 右上角三個水滴/葉子裝飾（扇形排列）
// ══════════════════════════════════════════════════════════════
class _JoyStrokesPainter extends CustomPainter {
  final Color color;
  const _JoyStrokesPainter({required this.color});

  void _drawLeaf(Canvas canvas, Paint paint, Offset center, double w, double h, double angle) {
    final path = Path();
    // 葉/水滴形：尖端在上（angle=0），圓腹在下
    path.moveTo(0, -h / 2);
    path.cubicTo( w * 0.65, -h * 0.05,  w * 0.65, h * 0.35, 0,  h / 2);
    path.cubicTo(-w * 0.65,  h * 0.35, -w * 0.65, -h * 0.05, 0, -h / 2);
    path.close();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 三個水滴/葉子，由左下往右上扇形排列
    // angle = π/4 讓尖端朝右上方
    _drawLeaf(canvas, paint, const Offset(5.5, 10.5), 4.5, 10.5, math.pi / 4 - 0.12);
    _drawLeaf(canvas, paint, const Offset(13.0, 13.5), 3.8,  9.0, math.pi / 4);
    _drawLeaf(canvas, paint, const Offset(21.0, 17.0), 3.0,  7.5, math.pi / 4 + 0.14);
  }

  @override
  bool shouldRepaint(covariant _JoyStrokesPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
//  _StaticCircle — 無動畫靜態裝飾圓
// ══════════════════════════════════════════════════════════════
class _StaticCircle extends StatelessWidget {
  final double size;
  final double alpha;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const _StaticCircle({
    required this.size,
    required this.alpha,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  _AnimatedCircle — 獨立管理自己的 AnimationController，
//  做柔和縮放脈衝，用於 header 背景裝飾圓。
//  每個圓有不同的 duration / scaleTo / reverse 讓節奏錯開。
// ══════════════════════════════════════════════════════════════
class _AnimatedCircle extends StatefulWidget {
  final double size;
  final double alpha;
  final Duration duration;
  final double scaleTo;
  final bool reverse;
  // 位置：傳其中一對即可
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const _AnimatedCircle({
    required this.size,
    required this.alpha,
    required this.duration,
    required this.scaleTo,
    this.reverse = false,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });

  @override
  State<_AnimatedCircle> createState() => _AnimatedCircleState();
}

class _AnimatedCircleState extends State<_AnimatedCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: widget.scaleTo,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (widget.reverse) {
      _ctrl.repeat(reverse: true);
      // 從中間開始，讓各圓節奏錯開
      _ctrl.forward(from: 0.5);
    } else {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.top,
      bottom: widget.bottom,
      left: widget.left,
      right: widget.right,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: widget.alpha),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  _PulsingDot — 未讀通知紅點，帶柔和脈衝動畫
// ══════════════════════════════════════════════════════════════
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale   = Tween<double>(begin: 0.85, end: 1.20)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(begin: 1.0, end: 0.55)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Quick item model ──
class _QuickItem {
  final dynamic icon; // HugeIcon data
  final String label;
  final Color color;
  final VoidCallback onTap;
  _QuickItem(this.icon, this.label, this.color, this.onTap);
}

// ── Bounce + jelly animation for quick access buttons ──
class _BounceQuickButton extends StatefulWidget {
  final _QuickItem item;
  const _BounceQuickButton({required this.item});
  @override
  State<_BounceQuickButton> createState() => _BounceQuickButtonState();
}

class _BounceQuickButtonState extends State<_BounceQuickButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 500),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl,
        curve: Curves.easeIn,
        reverseCurve: Curves.elasticOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.item.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: StitchedBox(
          color: widget.item.color,
          stitchColor: AppColors.textHint.withValues(alpha: 0.7),
          radius: 16,
          inset: 4,
          dashWidth: 5,
          dashGap: 4,
          stitchStrokeWidth: 1.1,
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            HugeIcon(icon: widget.item.icon, color: AppColors.textPrimary, size: 26),
            const SizedBox(height: 5),
            Text(widget.item.label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }
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