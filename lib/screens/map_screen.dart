import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
// ignore_for_file: unused_element
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';
import '../widgets/common_widgets.dart' show SpotRatingSection, TranslatedText;
import '../services/translation_service.dart';
import '../widgets/spot_save_button.dart';

// ═══════════════════════════════════════════════════════════
//  常數
// ═══════════════════════════════════════════════════════════

const _kCacheTTL    = Duration(hours: 6);
const _kCacheKey    = 'map_places_v8';   // bumped → clears old stale cache
const _kCacheTsKey  = 'map_places_ts_v8';

// ═══════════════════════════════════════════════════════════
//  資料模型
// ═══════════════════════════════════════════════════════════

enum _Cat {
  parking, gas, ev, taxi, toilet, aed,
  goodShop, petShop, drinkShop, restaurant,
  wheelchair, breastfeeding, wifi, police, tdxSpot,
  hotel, youbike, busStop, facility, chiayiFood,
}

class _CatCfg {
  final _Cat cat;
  final String label;
  final IconData icon;
  final Color color;
  final List<String> collections;
  const _CatCfg(this.cat, this.label, this.icon, this.color, this.collections);
}

// Macaron palette — soft, unique color per category
const _kCats = <_CatCfg>[
  _CatCfg(_Cat.parking,      '停車場',   Icons.local_parking_rounded,     Color(0xFF7BA7CC), ['parking_lots','county_parking_lots']),
  _CatCfg(_Cat.gas,          '加油站',   Icons.local_gas_station_rounded,  Color(0xFFE8A87C), ['gas_stations','county_gas_stations']),
  _CatCfg(_Cat.ev,           '充電站',   Icons.ev_station_rounded,         Color(0xFF85B79D), ['ev_charging_stations']),
  _CatCfg(_Cat.taxi,         '計程車',   Icons.local_taxi_rounded,         Color(0xFFE8CB6B), ['taxi_stands']),
  _CatCfg(_Cat.toilet,       '公廁',     Icons.wc_rounded,                 Color(0xFF6CB5B0), ['public_toilets']),
  _CatCfg(_Cat.aed,          'AED',      Icons.favorite_rounded,           Color(0xFFE88B8B), ['aed_locations']),
  _CatCfg(_Cat.goodShop,     '好店',     Icons.store_rounded,              Color(0xFFB08BD4), ['good_shops']),
  _CatCfg(_Cat.petShop,      '寵物友善', Icons.pets_rounded,               Color(0xFFD4869B), ['pet_friendly_shops']),
  _CatCfg(_Cat.drinkShop,    '飲料店',   Icons.local_cafe_rounded,         Color(0xFF8BB8D4), ['excellent_drink_shops']),
  _CatCfg(_Cat.restaurant,   '餐廳',     Icons.restaurant_rounded,         Color(0xFFCC9B7A), ['excellent_restaurants']),
  _CatCfg(_Cat.wheelchair,   '輪椅站',   Icons.accessible_rounded,         Color(0xFF7ABFB3), ['wheelchair_stations']),
  _CatCfg(_Cat.breastfeeding,'哺乳室',   Icons.child_care_rounded,         Color(0xFFC9A0D4), ['breastfeeding_rooms']),
  _CatCfg(_Cat.wifi,         'iTaiwan',  Icons.wifi_rounded,               Color(0xFF8A9CC5), ['itaiwan_hotspots']),
  _CatCfg(_Cat.police,       '警察局',   Icons.local_police_rounded,       Color(0xFF6E8FAF), ['police_stations']),
  _CatCfg(_Cat.tdxSpot,     'TDX景點',  Icons.account_balance_rounded,    Color(0xFF73B5A3), ['tdx_spots']),
  _CatCfg(_Cat.hotel,       '旅館民宿', Icons.hotel_rounded,               Color(0xFFA78BC5), ['tdx_hotels']),
  _CatCfg(_Cat.youbike,     'YouBike', Icons.pedal_bike_rounded,           Color(0xFF8FBF8F), ['tdx_youbike_stations']),
  _CatCfg(_Cat.busStop,     '公車站',  Icons.directions_bus_rounded,       Color(0xFF87AFC7), ['tdx_bus_routes']),
  _CatCfg(_Cat.facility,    '旅遊設施', Icons.info_rounded,                Color(0xFFA3C4A3), ['facilities']),
  _CatCfg(_Cat.chiayiFood,  '雞肉飯',  Icons.rice_bowl_rounded,           Color(0xFFD4A574), ['restaurants']),
];

const _kSkip = <String>{
  'location','經度坐標','緯度坐標','經度','緯度','座標位置',
  '地點LAT','地點LNG','Longitude','Latitude','POINT_X','POINT_Y',
  'AEDID','食品業者登錄字號',
  '周一至周五起','周一至周五迄','周六起','周六迄','周日起','周日迄',
  '開放使用時間備註','項次','序號',
  // 不顯示更新時間類欄位
  '更新時間','修改時間','updateTime','UpdateTime','update_time',
  'updatedAt','updated_at','lastModified','LastModified',
};

const _kLabels = <String, String>{
  '停車場名稱':'停車場','加油站站名':'站名','加油站名站名':'站名',
  '加油站地址':'地址','營業地址':'地址','設置地點':'地址',
  '場所地址':'地址','Address':'地址',
  '店家名稱':'店名','業者名稱':'業者','公共場所名稱':'場所',
  '場所名稱':'場所','Name':'名稱','地點':'地點','名稱':'名稱',
  '型式':'停車型式','收費方式':'收費','收費狀況':'收費',
  '月租費用':'月租','小型車':'小型車位','身障':'身障車位',
  '婦幼':'婦幼車位','機車':'機車位','大型車':'大型車位',
  '電動車格位數':'EV車位','停放型式':'停放型式',
  '營業時間':'營業時間','聯絡電話':'電話','電話':'電話',
  '承商':'管理單位','鄉鎮市':'地區','設置數量':'數量',
  '位置':'位置說明','路段':'路段','設置範圍':'設置區',
  '公廁類型':'廁所類型','尿布檯組':'尿布台(組)','主管機關':'主管機關',
  '入內規定':'入內規定','寵物服務':'寵物服務','類別':'類別','分類':'分類',
  '組別':'店家分類','產品名稱':'招牌商品','產品特色':'特色介紹',
  '開放時間':'開放時間','注意事項':'注意事項',
  '場所類型':'場所類型','場所分類':'場所分類',
  'AED地點描述':'AED位置','AED放置地點':'放置地點',
  '開放時間緊急連絡電話':'緊急聯絡','場所描述':'描述',
  'Agency':'管理單位','Administration':'設施類型','Area':'地區',
  '英文單位名稱':'英文名稱','中文單位名稱':'單位名稱',
  '級別':'評級','營業主體':'業者','備註':'備註','編號':'編號',
};

// 旅遊設施（facilities）類別 → Icon
IconData _facilityIcon(Map<String, dynamic> raw) {
  final type = raw['類別']?.toString() ?? '';
  if (type.contains('旅遊服務中心')) return Icons.account_balance_rounded;
  if (type.contains('借問站')) return Icons.help_outline_rounded;
  return Icons.place_rounded;
}

// TDX 景點類別 → Icon（依嘉義資料實際分類對照）
IconData _tdxIcon(Map<String, dynamic> raw) {
  final v = raw['classes'];
  final List<String> cls = v is List
      ? v.whereType<String>().toList()
      : v is String && v.trim().isNotEmpty
          ? [v.trim()]
          : [];
  for (final c in cls) {
    switch (c.trim()) {
      case '休閒農業類': return Icons.grass_rounded;
      case '古蹟類':    return Icons.fort_rounded;
      case '廟宇類':    return Icons.temple_buddhist_rounded;
      case '文化類':    return Icons.museum_rounded;
      case '林場類':    return Icons.park_rounded;
      case '森林遊樂區類': return Icons.forest_rounded;
      case '生態類':    return Icons.eco_rounded;
      case '自然風景類': return Icons.landscape_rounded;
      case '藝術類':    return Icons.palette_rounded;
      case '觀光工廠類': return Icons.factory_rounded;
      case '遊憩類':    return Icons.local_activity_rounded;
      case '都會公園類': return Icons.park_rounded;
      case '體育健身類': return Icons.sports_rounded;
    }
  }
  return Icons.place_rounded;
}

// TDX 景點類別 → 篩選面板同色系，柔化 30% 適合地圖圖標
Color _tdxColor(Map<String, dynamic> raw) {
  final v = raw['classes'];
  final List<String> cls = v is List
      ? v.whereType<String>().toList()
      : v is String && v.trim().isNotEmpty
          ? [v.trim()]
          : [];
  for (final c in cls) {
    switch (c.trim()) {
      case '休閒農業類':   return const Color(0xFF8BB878);
      case '古蹟類':       return const Color(0xFFB09468);
      case '廟宇類':       return const Color(0xFFD4A840);
      case '文化類':       return const Color(0xFF9B8CF0);
      case '林場類':       return const Color(0xFF5AAF5A);
      case '森林遊樂區類': return const Color(0xFF60B460);
      case '生態類':       return const Color(0xFF6BC06B);
      case '自然風景類':   return const Color(0xFF40B0A0);
      case '藝術類':       return const Color(0xFFEE6088);
      case '觀光工廠類':   return const Color(0xFF9B7B6B);
      case '遊憩類':       return const Color(0xFFFFB444);
      case '都會公園類':   return const Color(0xFF70CC70);
      case '體育健身類':   return const Color(0xFF55B8F0);
    }
  }
  return const Color(0xFFB0B0B0);
}

// 旅遊設施 → Color
Color _facilityColor(Map<String, dynamic> raw) {
  final type = raw['類別']?.toString() ?? '';
  if (type.contains('旅遊服務中心')) return const Color(0xFF00897B);
  if (type.contains('借問站')) return const Color(0xFFFF9800);
  return const Color(0xFFA3C4A3);
}

// Keep emoji helpers as aliases for legacy fallback (unused but safe to keep)
String _facilityEmoji(Map<String, dynamic> raw) => '';
String _tdxEmoji(Map<String, dynamic> raw) => '';

class _Place {
  final String id;
  final LatLng pos;
  final String name;
  final String address;
  final _Cat cat;
  final Map<String, dynamic> raw;
  const _Place({
    required this.id, required this.pos,
    required this.name, required this.address,
    required this.cat, required this.raw,
  });
}

// ═══════════════════════════════════════════════════════════
//  主畫面
// ═══════════════════════════════════════════════════════════

class MapScreen extends StatefulWidget {
  /// Set this notifier from any screen to jump the map to a specific position
  /// and optionally enable a category layer.
  ///
  /// Fields:
  ///   lat / lng   — target coordinates
  ///   catKey      — optional string key; the map will enable the matching
  ///                 category layer (see [_catKeyMap]).
  ///
  /// Known catKey values (use MapScreen.catKey* constants):
  ///   'chiayiFood', 'tdxSpot', 'goodShop', 'petShop', 'drinkShop'
  static final focusNotifier =
      ValueNotifier<({double lat, double lng, String? catKey})?>(null);

  // ── public catKey constants (referenced from other screens) ─
  static const catKeyChiayiFood = 'chiayiFood';
  static const catKeyTdxSpot    = 'tdxSpot';
  static const catKeyGoodShop   = 'goodShop';
  static const catKeyPetShop    = 'petShop';
  static const catKeyDrinkShop  = 'drinkShop';
  static const catKeyYouBike    = 'YouBike';

  // ── internal mapping: catKey → _Cat ─────────────────────────
  static const _catKeyMap = <String, _Cat>{
    'chiayiFood': _Cat.chiayiFood,
    'tdxSpot':    _Cat.tdxSpot,
    'goodShop':   _Cat.goodShop,
    'petShop':    _Cat.petShop,
    'drinkShop':  _Cat.drinkShop,
    'YouBike':    _Cat.youbike,
  };

  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapCtrl    = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  List<_Place> _all        = [];
  bool         _loading    = true;
  Position?    _myPos;
  bool         _isListView = false;
  String       _searchQuery = '';
  String?      _selectedId; // currently selected marker ID

  // TDX 景點為唯一預設勾選；其餘類別預設關閉
  final Set<_Cat> _visible = {_Cat.tdxSpot};

  // 細節篩選
  bool _diaperOnly     = false;
  bool _accessibleOnly = false;
  bool _freeParking    = false;
  bool _evParking      = false;
  bool _disabledParking = false;

  // TDX 景點子類別篩選（空 = 全部顯示）
  final Set<String> _tdxCatFilter = {};

  // ── 各類別子篩選（空 = 全部顯示）────────────────────────
  final Set<String> _toiletTypeFilter       = {};
  final Set<String> _breastfeedingCatFilter = {};
  final Set<String> _petCatFilter           = {};
  final Set<String> _restaurantLevelFilter  = {};
  final Set<String> _drinkCatFilter         = {};
  final Set<String> _goodShopGroupFilter    = {};
  final Set<String> _parkingTypeFilter      = {};
  final Set<String> _hotelClassFilter       = {};

  static const _kToiletTypes = <String>[
    '男廁所', '女廁所', '無障礙廁所', '親子廁所', '性別友善廁所'
  ];
  static const _kBreastfeedingCats = <String>['公共場所', '自願設置'];
  static const _kPetCats = <String>[
    '飲食類', '住宿類', '生活類', '觀光類', '交通類'
  ];
  static const _kRestaurantLevels = <String>['金質(優)', '優', '良'];
  static const _kDrinkCats        = <String>['飲料', '冰品', '咖啡廳'];
  static const _kGoodShopGroups   = <String>[
    '好禮食品組', '好禮非食品組', '好禮永續組', '好店', '好甜品'
  ];
  static const _kParkingTypes  = <String>['立體', '平面'];
  static const _kHotelClasses  = <String>[
    '一般旅館', '民宿', '一般觀光旅館', '國際觀光旅館'
  ];

  static const _kTdxCatList = <({String label, IconData icon, Color color})>[
    (label: '休閒農業類', icon: Icons.agriculture_rounded,         color: Color(0xFF6B9B52)),
    (label: '古蹟類',    icon: Icons.account_balance_rounded,      color: Color(0xFF8B6B3D)),
    (label: '廟宇類',    icon: Icons.temple_buddhist_rounded,      color: Color(0xFFB8860B)),
    (label: '文化類',    icon: Icons.theater_comedy_rounded,       color: Color(0xFF7B68EE)),
    (label: '林場類',    icon: Icons.forest_rounded,               color: Color(0xFF2E7D32)),
    (label: '森林遊樂區類', icon: Icons.park_rounded,              color: Color(0xFF388E3C)),
    (label: '生態類',    icon: Icons.eco_rounded,                  color: Color(0xFF43A047)),
    (label: '自然風景類', icon: Icons.landscape_rounded,           color: Color(0xFF00897B)),
    (label: '藝術類',    icon: Icons.palette_rounded,              color: Color(0xFFE91E63)),
    (label: '觀光工廠類', icon: Icons.factory_rounded,             color: Color(0xFF795548)),
    (label: '遊憩類',    icon: Icons.local_activity_rounded,       color: Color(0xFFFF9800)),
    (label: '都會公園類', icon: Icons.nature_people_rounded,       color: Color(0xFF4CAF50)),
    (label: '體育健身類', icon: Icons.fitness_center_rounded,      color: Color(0xFF2196F3)),
    (label: '其他',      icon: Icons.explore_rounded,             color: Color(0xFF9E9E9E)),
  ];

  static const _chiayiCenter = LatLng(23.480, 120.449);

  // ── 初始化 ───────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    MapScreen.focusNotifier.addListener(_onFocusTarget);
    _init();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    setState(() => _searchQuery = q);
    _searchDebounce?.cancel();
    if (q.isNotEmpty) {
      _searchDebounce = Timer(
        const Duration(milliseconds: 600), _jumpToNearest);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    MapScreen.focusNotifier.removeListener(_onFocusTarget);
    super.dispose();
  }

  Future<void> _init() async {
    // Run in parallel; _loadData may clear _loading early if cache exists
    await Future.wait([_loadData(), _getPos()]);
    // Ensure loading flag is cleared regardless
    if (mounted && _loading) setState(() => _loading = false);
  }

  Future<void> _getPos() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;
      final p = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _myPos = p);
    } catch (_) {}
  }

  // ── 本地緩存 ─────────────────────────────────────────────

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final ts     = prefs.getInt(_kCacheTsKey) ?? 0;
    final cached = prefs.getString(_kCacheKey);
    final age    = DateTime.now().millisecondsSinceEpoch - ts;

    // ── Show cached data IMMEDIATELY even when stale ──────────────────
    if (cached != null) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((e) => _placeFromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _all     = list;
            _loading = false;
          });
        }
        // Always fetch bus stops lazily (they're never cached)
        unawaited(_fetchBusStopsLazy());
        if (age < _kCacheTTL.inMilliseconds) {
          debugPrint('[MapScreen] 緩存有效 (${list.length} 筆)，跳過更新');
          return;
        }
        debugPrint('[MapScreen] 緩存過期，背景刷新…');
      } catch (e) {
        debugPrint('[MapScreen] 緩存解析失敗: $e');
      }
    }

    await _fetchAll();
    await _saveToCache(prefs);
    unawaited(_fetchBusStopsLazy()); // bus stops fetched last, not cached
  }

  Future<void> _saveToCache(SharedPreferences prefs) async {
    try {
      // Exclude bus stops from cache (they're large and fetched fresh each session)
      final toSave = _all.where((p) => p.cat != _Cat.busStop).toList();
      final json = jsonEncode(toSave.map(_placeToJson).toList());
      await prefs.setString(_kCacheKey, json);
      await prefs.setInt(
          _kCacheTsKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('[MapScreen] 緩存儲存 ${toSave.length} 個地點（不含公車站）');
    } catch (e) {
      debugPrint('[MapScreen] 緩存儲存失敗: $e');
    }
  }

  static Map<String, dynamic> _placeToJson(_Place p) => {
    'id':      p.id,
    'lat':     p.pos.latitude,
    'lng':     p.pos.longitude,
    'name':    p.name,
    'address': p.address,
    'cat':     p.cat.index,
    'raw':     _serializeRaw(p.raw),
  };

  static Map<String, dynamic> _serializeRaw(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v == null || v is String || v is int || v is double || v is bool) {
        out[e.key] = v;
      } else if (v is List) {
        // 保留純值 List（如 classes、pictureUrl 陣列）
        final items = v.where((item) =>
            item == null || item is String || item is int ||
            item is double || item is bool).toList();
        if (items.isNotEmpty) out[e.key] = items;
      }
      // 跳過 GeoPoint、Timestamp 等 Firestore 複雜型別
    }
    return out;
  }

  static _Place _placeFromJson(Map<String, dynamic> j) => _Place(
    id:      j['id'] as String,
    pos:     LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
    name:    j['name'] as String,
    address: j['address'] as String,
    cat:     _Cat.values[j['cat'] as int],
    raw:     Map<String, dynamic>.from(j['raw'] as Map),
  );

  // ── Firestore 讀取 ───────────────────────────────────────

  /// Fetch each category independently (excluding bus stops which are large).
  /// Bus stops are fetched lazily via [_fetchBusStopsLazy] after main data loads.
  Future<void> _fetchAll() async {
    // Exclude busStop from main parallel fetch — it's slow and large.
    final cats = _kCats.where((c) => c.cat != _Cat.busStop).toList();
    await Future.wait(cats.map((cfg) async {
      try {
        final places = await _fetchCat(cfg)
            .timeout(const Duration(seconds: 20));
        if (!mounted || places.isEmpty) return;
        setState(() {
          _all = [
            ..._all.where((p) => p.cat != cfg.cat),
            ...places,
          ];
          if (_loading) _loading = false;
        });
        debugPrint('[MapScreen] ${cfg.label} → ${places.length}個');
      } on TimeoutException {
        debugPrint('[MapScreen] ${cfg.label} ⏰ 超時');
      } catch (e) {
        debugPrint('[MapScreen] ${cfg.label} [錯誤] $e');
      }
    }));
    // Ensure loading dismissed even if all categories returned empty
    if (mounted && _loading) setState(() => _loading = false);
    debugPrint('[MapScreen] 主要分類完成，共 ${_all.length} 個地點');
  }

  /// Fetch bus stops in the background (not cached, runs after main load).
  Future<void> _fetchBusStopsLazy() async {
    final busStopCfg = _kCats.firstWhere((c) => c.cat == _Cat.busStop);
    try {
      final stops = await _fetchBusStops(busStopCfg)
          .timeout(const Duration(seconds: 30));
      if (mounted && stops.isNotEmpty) {
        // 同名站點只保留第一個（避免不同路線在同一物理站點重複標記）
        final seen    = <String>{};
        final deduped = stops.where((p) => seen.add(p.name)).toList();
        setState(() {
          _all = [..._all.where((p) => p.cat != _Cat.busStop), ...deduped];
        });
        debugPrint('[MapScreen] 公車站 → ${stops.length}站（去重後 ${deduped.length}站）');
      }
    } catch (e) {
      debugPrint('[MapScreen] 公車站 [錯誤] $e');
    }
  }

  Future<List<_Place>> _fetchCat(_CatCfg cfg) async {
    // Bus stops: each route document has a 'stops' array → expand
    if (cfg.cat == _Cat.busStop) return _fetchBusStops(cfg);

    final out = <_Place>[];
    for (final col in cfg.collections) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(col).limit(500).get();

        int parsed = 0, fallback = 0, noLoc = 0;
        bool dumpedKeys = false;
        for (final doc in snap.docs) {
          final d   = doc.data();
          final pos = _extractLatLng(d);
          if (pos == null) {
            noLoc++;
            if (!dumpedKeys) {
              dumpedKeys = true;
              debugPrint('[MapScreen] $col 第一筆無座標，欄位:');
              d.forEach((k, v) =>
                  debugPrint('  "$k"=$v (${v.runtimeType})'));
            }
            continue;
          }
          final hasGeo =
              d.containsKey('location') && d['location'] is GeoPoint;
          if (hasGeo) parsed++; else fallback++;
          out.add(_Place(
            id:      '${col}_${doc.id}',
            pos:     pos,
            name:    _extractName(cfg.cat, d),
            address: _extractAddr(d),
            cat:     cfg.cat,
            raw:     d,
          ));
        }
        debugPrint('[MapScreen] $col → ${snap.docs.length}筆 '
            'GeoPoint:$parsed 備援:$fallback 無座標:$noLoc');
      } catch (e) {
        debugPrint('[MapScreen] $col → [錯誤] $e');
      }
    }
    return out;
  }

  /// Bus routes: each document has a 'stops' array.
  /// Each element may have location stored as "GeoPoint(lat, lng)" string.
  Future<List<_Place>> _fetchBusStops(_CatCfg cfg) async {
    final out = <_Place>[];
    for (final col in cfg.collections) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(col).limit(200).get();
        int stopCount = 0;
        for (final doc in snap.docs) {
          final d    = doc.data();
          final stops = d['stops'];
          if (stops is! List) continue;
          final routeName = d['routeName']?.toString() ??
                            d['RouteName']?.toString() ??
                            d['路線名稱']?.toString() ?? '';
          for (var i = 0; i < stops.length; i++) {
            final s = stops[i];
            if (s is! Map) continue;
            final sm = Map<String, dynamic>.from(s);
            final stopName = sm['stopName']?.toString() ??
                             sm['StopName']?.toString() ??
                             sm['站名']?.toString() ??
                             sm['name']?.toString() ?? '公車站';
            final raw = {'stopName': stopName, '路線': routeName, ...sm};

            // Support both single 'location' and multi-side 'locations' array
            final locs = sm['locations'];
            if (locs is List && locs.isNotEmpty) {
              // Two-sided stop: place a marker for each position
              for (var j = 0; j < locs.length; j++) {
                LatLng? pos;
                final l = locs[j];
                if (l is GeoPoint) {
                  if (l.latitude > 21 && l.latitude < 26 &&
                      l.longitude > 119 && l.longitude < 123) {
                    pos = LatLng(l.latitude, l.longitude);
                  }
                } else if (l is String) {
                  pos = _parseGeoPointString(l);
                }
                if (pos == null) continue;
                out.add(_Place(
                  id:      '${col}_${doc.id}_${i}_$j',
                  pos:     pos,
                  name:    stopName,
                  address: routeName.isNotEmpty ? '路線: $routeName' : '',
                  cat:     _Cat.busStop,
                  raw:     raw,
                ));
                stopCount++;
              }
            } else {
              // Legacy single location
              final pos = _extractLatLngFromStop(sm);
              if (pos == null) continue;
              out.add(_Place(
                id:      '${col}_${doc.id}_$i',
                pos:     pos,
                name:    stopName,
                address: routeName.isNotEmpty ? '路線: $routeName' : '',
                cat:     _Cat.busStop,
                raw:     raw,
              ));
              stopCount++;
            }
          }
        }
        debugPrint('[MapScreen] $col → ${snap.docs.length}條路線 $stopCount站');
      } catch (e) {
        debugPrint('[MapScreen] $col → [錯誤] $e');
      }
    }
    return out;
  }

  /// Parse GeoPoint from a stop's map:
  /// - GeoPoint object in 'location'
  /// - String "GeoPoint(lat, lng)" in 'location'
  static LatLng? _extractLatLngFromStop(Map<String, dynamic> d) {
    final loc = d['location'];
    if (loc is GeoPoint) {
      if (loc.latitude > 21 && loc.latitude < 26 &&
          loc.longitude > 119 && loc.longitude < 123) {
        return LatLng(loc.latitude, loc.longitude);
      }
    }
    if (loc is String) {
      final parsed = _parseGeoPointString(loc);
      if (parsed != null) return parsed;
    }
    // Fallback to separate lat/lng fields
    return _extractLatLng(d);
  }

  /// Parse "GeoPoint(23.480, 120.449)" → LatLng
  static LatLng? _parseGeoPointString(String s) {
    final m = RegExp(r'GeoPoint\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)')
        .firstMatch(s);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null) return null;
    if (lat > 21 && lat < 26 && lng > 119 && lng < 123) {
      return LatLng(lat, lng);
    }
    return null;
  }

  // ── 欄位提取 ─────────────────────────────────────────────

  static String _extractName(_Cat cat, Map<String, dynamic> d) {
    for (final e in d.entries) {
      if (_cleanKey(e.key) == '中文單位名稱' && e.value != null) {
        return e.value.toString().trim();
      }
    }
    const keys = [
      // TDX collections — 'name' field (tdx_spots, tdx_hotels, tdx_youbike_stations)
      'name', 'Name',
      // YouBike stations
      'StationName',
      // Hotel-specific legacy
      'hotelName', 'HotelName', '旅館名稱', '飯店名稱', '民宿名稱',
      // Bus stop
      'stopName', 'StopName', '站名',
      // Generic Chinese government data
      '停車場名稱','加油站站名','加油站名站名','店家名稱','業者名稱',
      '名稱','公共場所名稱','場所名稱','地點',
    ];
    for (final k in keys) {
      final v = d[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '未知名稱';
  }

  static String _extractAddr(Map<String, dynamic> d) {
    // 'address' first (tdx_spots, tdx_hotels), then Chinese government fields
    const keys = [
      'address', 'Address',
      '地址','加油站地址','營業地址','設置地點','場所地址',
      '路段','鄉鎮市','設置地點',
    ];
    for (final k in keys) {
      final v = d[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    // city fallback
    final city = d['city']?.toString().trim() ?? '';
    return city;
  }

  static LatLng? _extractLatLng(Map<String, dynamic> d) {
    // 1. GeoPoint（排除 0,0 佔位符）
    if (d.containsKey('location')) {
      final geo = d['location'];
      if (geo is GeoPoint &&
          geo.latitude > 21 && geo.latitude < 26 &&
          geo.longitude > 119 && geo.longitude < 123) {
        return LatLng(geo.latitude, geo.longitude);
      }
    }
    // 2. 合併 DMS（座標位置）
    final combined = d['座標位置']?.toString().trim() ?? '';
    if (combined.isNotEmpty) {
      final pos = _parseCombinedDMS(combined);
      if (pos != null) return pos;
    }
    // 3. 分離欄位
    const latKeys = ['緯度','緯度坐標','地點LAT','Latitude','POINT_Y','lat'];
    const lngKeys = ['經度','經度坐標','地點LNG','Longitude','POINT_X','lng'];
    double? lat, lng;
    for (final k in latKeys) {
      final n = _toDouble(d[k]);
      if (n != null && n > 21 && n < 26) { lat = n; break; }
    }
    for (final k in lngKeys) {
      final n = _toDouble(d[k]);
      if (n != null && n > 119 && n < 123) { lng = n; break; }
    }
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  static LatLng? _parseCombinedDMS(String s) {
    final m = RegExp(
      r'(\d+)[^\d]+(\d+)[^\d]+([\d.]+)[^\d]+N\s+(\d+)[^\d]+(\d+)[^\d]+([\d.]+)',
    ).firstMatch(s);
    if (m == null) return null;
    double dms(int d, int mi, int sec) =>
        double.parse(m.group(d)!) +
        double.parse(m.group(mi)!) / 60 +
        double.parse(m.group(sec)!)  / 3600;
    final lat = dms(1, 2, 3);
    final lng = dms(4, 5, 6);
    if (lat > 21 && lat < 26 && lng > 119 && lng < 123) {
      return LatLng(lat, lng);
    }
    return null;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int)    return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v.trim());
      if (parsed != null) return parsed;
      final m = RegExp(r'(\d+)[^\d]+(\d+)[^\d]+([\d.]+)').firstMatch(v);
      if (m != null) {
        final d = double.tryParse(m.group(1)!);
        final min = double.tryParse(m.group(2)!);
        final sec = double.tryParse(m.group(3)!);
        if (d != null && min != null && sec != null) {
          return d + min / 60 + sec / 3600;
        }
      }
    }
    return null;
  }

  static String _cleanKey(String key) =>
      key.replaceAll('﻿', '').replaceAll('"', '').trim();

  // ── 距離工具 ─────────────────────────────────────────────

  double _distanceTo(_Place p) {
    if (_myPos == null) return double.maxFinite;
    return Geolocator.distanceBetween(
      _myPos!.latitude, _myPos!.longitude,
      p.pos.latitude,   p.pos.longitude,
    );
  }

  static String _formatDist(double meters) {
    if (meters == double.maxFinite) return '';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  // 搜尋後自動移動地圖到最近符合地點
  void _jumpToNearest() {
    if (_isListView || !mounted) return;
    final places = _filtered;
    if (places.isEmpty) return;
    // places 已按距離排序，直接移到第一筆
    _mapCtrl.move(places.first.pos, 15.5);
  }

  // 從其他頁面（如首頁附近景點）跳到地圖、開啟圖層、選中 marker 並開 detail
  void _onFocusTarget() {
    final t = MapScreen.focusNotifier.value;
    if (t == null || !mounted) return;

    // 1. 切換到地圖模式
    if (_isListView) setState(() => _isListView = false);

    // 2. 啟用對應圖層
    if (t.catKey != null) {
      final cat = MapScreen._catKeyMap[t.catKey!];
      if (cat != null && !_visible.contains(cat)) {
        setState(() => _visible.add(cat));
      }
    }

    // 3. 找 _all 裡距離目標最近的地點（允許 ~55m 以內的浮點誤差）
    _Place? target;
    double  bestDist = double.infinity;
    final   targetCat = t.catKey != null ? MapScreen._catKeyMap[t.catKey!] : null;
    for (final p in _all) {
      if (targetCat != null && p.cat != targetCat) continue;
      final dLat = p.pos.latitude  - t.lat;
      final dLng = p.pos.longitude - t.lng;
      final dist = dLat * dLat + dLng * dLng;
      if (dist < bestDist) { bestDist = dist; target = p; }
    }
    // 0.0005° ≈ 55m；超過的視為「無精確對應」
    const kThreshold = 0.0005 * 0.0005;
    if (bestDist > kThreshold) target = null;

    // 4. 移動地圖並選中 marker（在下一 frame 確保地圖已渲染）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapCtrl.move(LatLng(t.lat, t.lng), 15.5);

      if (target != null) {
        // 先放大選中 marker（視覺上很明顯）
        setState(() => _selectedId = target!.id);
        // 延遲後開 detail sheet（給動畫一點時間跑）
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted) _showDetail(target!);
        });
      }
    });

    // 5. 重設 notifier 讓同樣座標下次還能觸發
    Future.microtask(() => MapScreen.focusNotifier.value = null);
  }

  // ── 篩選（含距離排序）────────────────────────────────────

  List<_Place> get _filtered {
    final q = _searchQuery.toLowerCase();
    final result = _all.where((p) {
      if (!_visible.contains(p.cat)) return false;
      if (q.isNotEmpty) {
        if (!p.name.toLowerCase().contains(q) &&
            !p.address.toLowerCase().contains(q)) return false;
      }
      if (p.cat == _Cat.toilet) {
        if (_diaperOnly) {
          final n = int.tryParse(p.raw['尿布檯組']?.toString() ?? '0') ?? 0;
          if (n == 0) return false;
        }
        if (_accessibleOnly) {
          final t = (p.raw['公廁類型']?.toString() ?? '').toLowerCase();
          if (!t.contains('通用') && !t.contains('無障礙') && !t.contains('親子')) {
            return false;
          }
        }
      }
      if (p.cat == _Cat.parking) {
        if (_freeParking) {
          final fee = (p.raw['收費方式']?.toString() ??
                       p.raw['收費狀況']?.toString() ?? '');
          if (!fee.contains('免費') && fee != '0') return false;
        }
        if (_evParking) {
          final ev = int.tryParse(
              p.raw['電動車格位數']?.toString() ?? '0') ?? 0;
          if (ev == 0) return false;
        }
        if (_disabledParking) {
          final db = int.tryParse(p.raw['身障']?.toString() ?? '0') ?? 0;
          if (db == 0) return false;
        }
      }
      // TDX 子類別篩選
      if (p.cat == _Cat.tdxSpot && _tdxCatFilter.isNotEmpty) {
        final v = p.raw['classes'];
        final List<String> cls = v is List
            ? v.whereType<String>().toList()
            : v is String && v.trim().isNotEmpty ? [v.trim()] : [];
        if (!cls.any((c) => _tdxCatFilter.contains(c))) return false;
      }
      // 公廁類型篩選
      if (p.cat == _Cat.toilet && _toiletTypeFilter.isNotEmpty) {
        final t = (p.raw['公廁類型']?.toString() ?? '');
        if (!_toiletTypeFilter.any((f) => t.contains(f))) return false;
      }
      // 停車場型式篩選
      if (p.cat == _Cat.parking && _parkingTypeFilter.isNotEmpty) {
        final t = (p.raw['型式']?.toString() ??
                   p.raw['停放型式']?.toString() ?? '');
        if (!_parkingTypeFilter.any((f) => t.contains(f))) return false;
      }
      // 哺集乳室類別篩選
      if (p.cat == _Cat.breastfeeding && _breastfeedingCatFilter.isNotEmpty) {
        final t = (p.raw['場所類別']?.toString() ??
                   p.raw['場所分類']?.toString() ??
                   p.raw['類別']?.toString() ?? '');
        if (!_breastfeedingCatFilter.any((f) => t.contains(f))) return false;
      }
      // 寵物友善類別篩選
      if (p.cat == _Cat.petShop && _petCatFilter.isNotEmpty) {
        final t = (p.raw['類別']?.toString() ??
                   p.raw['分類']?.toString() ?? '');
        if (!_petCatFilter.any((f) => t.contains(f))) return false;
      }
      // 餐飲評核級別篩選
      if (p.cat == _Cat.restaurant && _restaurantLevelFilter.isNotEmpty) {
        final t = (p.raw['級別']?.toString() ?? '');
        if (!_restaurantLevelFilter.any((f) => t.contains(f))) return false;
      }
      // 飲冰品分類篩選
      if (p.cat == _Cat.drinkShop && _drinkCatFilter.isNotEmpty) {
        final t = (p.raw['分類']?.toString() ??
                   p.raw['類別']?.toString() ?? '');
        if (!_drinkCatFilter.any((f) => t.contains(f))) return false;
      }
      // 嘉市好店組別篩選
      if (p.cat == _Cat.goodShop && _goodShopGroupFilter.isNotEmpty) {
        final t = (p.raw['組別']?.toString() ?? '');
        if (!_goodShopGroupFilter.any((f) => t.contains(f))) return false;
      }
      // 旅館等級篩選
      if (p.cat == _Cat.hotel && _hotelClassFilter.isNotEmpty) {
        final t = (p.raw['hotelClass']?.toString() ??
                   p.raw['旅館等級']?.toString() ??
                   p.raw['等級']?.toString() ??
                   p.raw['分類']?.toString() ?? '');
        if (!_hotelClassFilter.any((f) => t.contains(f))) return false;
      }
      return true;
    }).toList();

    // 列表模式或有搜尋文字時，按距離由近到遠排序
    if (_myPos != null && (_isListView || q.isNotEmpty)) {
      result.sort((a, b) => _distanceTo(a).compareTo(_distanceTo(b)));
    }
    return result;
  }

  bool get _hasActiveSubFilters =>
      _diaperOnly || _accessibleOnly ||
      _freeParking || _evParking || _disabledParking ||
      _tdxCatFilter.isNotEmpty ||
      _toiletTypeFilter.isNotEmpty ||
      _breastfeedingCatFilter.isNotEmpty ||
      _petCatFilter.isNotEmpty ||
      _restaurantLevelFilter.isNotEmpty ||
      _drinkCatFilter.isNotEmpty ||
      _goodShopGroupFilter.isNotEmpty ||
      _parkingTypeFilter.isNotEmpty ||
      _hotelClassFilter.isNotEmpty;

  /// 某圖層是否有啟用篩選
  bool _hasFilterForCat(_Cat cat) {
    switch (cat) {
      case _Cat.toilet:       return _toiletTypeFilter.isNotEmpty || _diaperOnly || _accessibleOnly;
      case _Cat.parking:      return _parkingTypeFilter.isNotEmpty || _freeParking || _evParking || _disabledParking;
      case _Cat.breastfeeding:return _breastfeedingCatFilter.isNotEmpty;
      case _Cat.petShop:      return _petCatFilter.isNotEmpty;
      case _Cat.restaurant:   return _restaurantLevelFilter.isNotEmpty;
      case _Cat.drinkShop:    return _drinkCatFilter.isNotEmpty;
      case _Cat.goodShop:     return _goodShopGroupFilter.isNotEmpty;
      case _Cat.hotel:        return _hotelClassFilter.isNotEmpty;
      case _Cat.tdxSpot:      return _tdxCatFilter.isNotEmpty;
      default:                return false;
    }
  }

  /// 計算 marker 的顏色：TDX/facility 依分類著色，其他用預設
  Color _markerColor(_Place p, Color baseColor) {
    Color c;
    if (p.cat == _Cat.tdxSpot) {
      c = _tdxColor(p.raw);
    } else if (p.cat == _Cat.facility) {
      c = _facilityColor(p.raw);
    } else {
      c = baseColor;
    }
    if (_hasFilterForCat(p.cat)) return Color.lerp(c, Colors.black, 0.22)!;
    return c;
  }

  // ── 定位 ─────────────────────────────────────────────────

  Future<void> _goToMe() async {
    if (_myPos == null) await _getPos();
    if (!mounted) return;
    if (_myPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<AppSettingsProvider>().l10n.mapNoLocation),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    _mapCtrl.move(LatLng(_myPos!.latitude, _myPos!.longitude), 15.5);
  }

  // ═══════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final places = _filtered;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(top),
              Expanded(
                child: Stack(children: [
                  _isListView
                      ? _buildListView(places)
                      : _buildMap(places),
                  Positioned(
                    top: 6, left: 0, right: 0,
                    child: _buildQuickChips(),
                  ),
                ]),
              ),
            ],
          ),
          if (_loading) const _MapLoadingOverlay(),
        ],
      ),
      floatingActionButton: Builder(builder: (ctx) {
        final primary = ctx.appPrimary;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'filter',
                onPressed: _showFilters,
                backgroundColor:
                    _hasActiveSubFilters ? primary : Colors.white,
                elevation: 3,
                tooltip: '細節篩選',
                child: Icon(Icons.filter_list_rounded,
                    color: _hasActiveSubFilters ? Colors.white : primary),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.small(
                heroTag: 'locate',
                onPressed: _isListView ? null : _goToMe,
                backgroundColor: Colors.white,
                elevation: 3,
                tooltip: '我的位置',
                child: Icon(Icons.my_location_rounded,
                    color: _isListView ? Colors.grey.shade300 : primary),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.small(
                heroTag: 'layers',
                onPressed: _showLegend,
                backgroundColor: Colors.white,
                elevation: 3,
                tooltip: '圖層控制',
                child: Icon(Icons.layers_rounded, color: primary),
              ),
              if (!_isListView) ...[
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'zoomIn',
                  onPressed: () => _mapCtrl.move(
                      _mapCtrl.camera.center,
                      (_mapCtrl.camera.zoom + 1).clamp(3.0, 18.0)),
                  backgroundColor: Colors.white,
                  elevation: 3,
                  tooltip: '放大',
                  child: Icon(Icons.add_rounded, color: primary),
                ),
                const SizedBox(height: 6),
                FloatingActionButton.small(
                  heroTag: 'zoomOut',
                  onPressed: () => _mapCtrl.move(
                      _mapCtrl.camera.center,
                      (_mapCtrl.camera.zoom - 1).clamp(3.0, 18.0)),
                  backgroundColor: Colors.white,
                  elevation: 3,
                  tooltip: '縮小',
                  child: Icon(Icons.remove_rounded, color: primary),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  // ── 頂部欄 ───────────────────────────────────────────────

  // 快速篩選 chip（常用分類水平列）
  static const _quickChipCats = [_Cat.tdxSpot, _Cat.chiayiFood, _Cat.drinkShop, _Cat.goodShop, _Cat.petShop, _Cat.hotel];

  Widget _buildQuickChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _quickChipCats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = _quickChipCats[i];
          final cfg = _kCats.firstWhere((c) => c.cat == cat);
          final on = _visible.contains(cat);
          return GestureDetector(
            onTap: () => setState(() => on ? _visible.remove(cat) : _visible.add(cat)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: on ? cfg.color : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? cfg.color : Colors.white.withValues(alpha: 0.9)),
                boxShadow: on ? [BoxShadow(color: cfg.color.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))] : null,
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(cfg.icon, size: 14, color: on ? Colors.white : cfg.color),
                const SizedBox(width: 5),
                Text(cfg.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : cfg.color)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(double top) {
    final primary = context.appPrimary;
    return Container(
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(21),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 14),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: primary.withValues(alpha: 0.12),
                  hintText: '搜尋名稱或地址（跳至最近地點）',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: primary, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () => _searchCtrl.clear(),
                          child: Icon(Icons.cancel_rounded,
                              size: 18, color: Colors.grey.shade400),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _viewToggleBtn(
                icon: Icons.map_rounded,
                active: !_isListView,
                onTap: () => setState(() => _isListView = false),
                tooltip: '地圖',
              ),
              _viewToggleBtn(
                icon: Icons.list_rounded,
                active: _isListView,
                onTap: () => setState(() => _isListView = true),
                tooltip: '列表',
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _viewToggleBtn({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    final primary = context.appPrimary;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40, height: 42,
          decoration: BoxDecoration(
            color: active ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 20,
              color: active ? Colors.white : Colors.grey.shade500),
        ),
      ),
    );
  }

  // ── 地圖 ─────────────────────────────────────────────────

  Widget _buildMap(List<_Place> places) {
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _myPos != null
            ? LatLng(_myPos!.latitude, _myPos!.longitude)
            : _chiayiCenter,
        initialZoom: 13.5,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.chiayicity.explore_chiayi',
          maxZoom: 19,
        ),
        if (_myPos != null)
          MarkerLayer(markers: [
            Marker(
              point: LatLng(_myPos!.latitude, _myPos!.longitude),
              width: 20, height: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4)
                  ],
                ),
              ),
            ),
          ]),
        MarkerLayer(
          markers: places.map((p) {
            final cfg  = _kCats.firstWhere((c) => c.cat == p.cat);
            final icon = p.cat == _Cat.tdxSpot
                ? _tdxIcon(p.raw)
                : p.cat == _Cat.facility
                    ? _facilityIcon(p.raw)
                    : cfg.icon;
            final sel = _selectedId == p.id;
            return Marker(
              point: p.pos,
              width:  sel ? 46 : 36,
              height: sel ? 56 : 44,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => _onMarkerTap(p),
                child: _MarkerPin(color: _markerColor(p, cfg.color), icon: icon, isSelected: sel),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 列表模式 ─────────────────────────────────────────────

  Widget _buildListView(List<_Place> places) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (places.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty
                ? '找不到「$_searchQuery」'
                : '目前沒有符合條件的地點',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: places.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey.shade100),
      itemBuilder: (_, i) {
        final p    = places[i];
        final cfg  = _kCats.firstWhere((c) => c.cat == p.cat);
        final dist = _formatDist(_distanceTo(p));
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: _markerColor(p, cfg.color),
            child: Icon(
              p.cat == _Cat.tdxSpot
                  ? _tdxIcon(p.raw)
                  : p.cat == _Cat.facility
                      ? _facilityIcon(p.raw)
                      : cfg.icon,
              color: Colors.white,
              size: 18,
            ),
          ),
          title: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Row(children: [
            if (p.address.isNotEmpty)
              Expanded(
                child: Text(p.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
              )
            else
              Expanded(
                child: Text(cfg.label,
                    style: TextStyle(fontSize: 12, color: cfg.color)),
              ),
            if (dist.isNotEmpty)
              Text(' · $dist',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600)),
          ]),
          trailing: IconButton(
            icon: Icon(Icons.directions_rounded,
                color: Theme.of(context).colorScheme.primary, size: 22),
            tooltip: '導航',
            onPressed: () => _PlaceSheet._nav(p.pos),
          ),
          onTap: () => _showDetail(p),
        );
      },
    );
  }

  // ── 細節篩選 ─────────────────────────────────────────────

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final showToilet       = _visible.contains(_Cat.toilet);
          final showParking      = _visible.contains(_Cat.parking);
          final showTdx          = _visible.contains(_Cat.tdxSpot);
          final showBreastfeeding= _visible.contains(_Cat.breastfeeding);
          final showPet          = _visible.contains(_Cat.petShop);
          final showRestaurant   = _visible.contains(_Cat.restaurant);
          final showDrink        = _visible.contains(_Cat.drinkShop);
          final showGoodShop     = _visible.contains(_Cat.goodShop);
          final showHotel        = _visible.contains(_Cat.hotel);
          final hasAny = showToilet || showParking || showTdx ||
              showBreastfeeding || showPet || showRestaurant ||
              showDrink || showGoodShop || showHotel;

          return DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.90,
            expand: false,
            builder: (_, scroll) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle + 標題列
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36, height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.read<AppSettingsProvider>().l10n.mapDetailFilter,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            if (_hasActiveSubFilters)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _diaperOnly      = false;
                                    _accessibleOnly  = false;
                                    _freeParking     = false;
                                    _evParking       = false;
                                    _disabledParking = false;
                                    _tdxCatFilter.clear();
                                    _toiletTypeFilter.clear();
                                    _breastfeedingCatFilter.clear();
                                    _petCatFilter.clear();
                                    _restaurantLevelFilter.clear();
                                    _drinkCatFilter.clear();
                                    _goodShopGroupFilter.clear();
                                    _parkingTypeFilter.clear();
                                    _hotelClassFilter.clear();
                                  });
                                  setDlg(() {});
                                },
                                child: Text(context.read<AppSettingsProvider>().l10n.clearAll),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // 可捲動內容
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        if (!hasAny) ...[
                          const SizedBox(height: 8),
                          Text(
                            context.read<AppSettingsProvider>().l10n.mapNoLayerHint,
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                                height: 1.6),
                          ),
                        ],

                        // ── TDX 景點類別 ──────────────────────────
                        if (showTdx) ...[
                          _filterHeader(Icons.account_balance_rounded, 'TDX 景點類別'),
                          Text(
                            context.read<AppSettingsProvider>().l10n.mapFilterHintAll,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _kTdxCatList.map((item) {
                              final on = _tdxCatFilter.contains(item.label);
                              return FilterChip(
                                avatar: Icon(item.icon,
                                    size: 14,
                                    color: on ? item.color : item.color.withValues(alpha: 0.65)),
                                label: Text(item.label,
                                    style: TextStyle(fontSize: 12,
                                        color: on ? item.color : AppColors.textSecondary,
                                        fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                                selected: on,
                                selectedColor: item.color.withValues(alpha: 0.12),
                                checkmarkColor: item.color,
                                backgroundColor: Colors.white,
                                side: BorderSide(color: on ? item.color : Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                onSelected: (v) {
                                  setState(() => v
                                      ? _tdxCatFilter.add(item.label)
                                      : _tdxCatFilter.remove(item.label));
                                  setDlg(() {});
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 廁所 ──────────────────────────────────
                        if (showToilet) ...[
                          _filterHeader(Icons.wc_rounded, '公廁'),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            _filterChip(setDlg, '有尿布台',
                                _diaperOnly,
                                (v) => setState(() => _diaperOnly = v)),
                            _filterChip(setDlg, '無障礙/通用',
                                _accessibleOnly,
                                (v) => setState(() => _accessibleOnly = v)),
                          ]),
                          const SizedBox(height: 10),
                          Text(context.read<AppSettingsProvider>().l10n.mapToiletType, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kToiletTypes.map((t) => _setFilterChip(
                              setDlg, t, _toiletTypeFilter,
                            )).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 停車場 ────────────────────────────────
                        if (showParking) ...[
                          _filterHeader(Icons.local_parking_rounded, '停車場'),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            _filterChip(setDlg, '免費停車',
                                _freeParking,
                                (v) => setState(() => _freeParking = v)),
                            _filterChip(setDlg, '有EV車位',
                                _evParking,
                                (v) => setState(() => _evParking = v)),
                            _filterChip(setDlg, '有身障車位',
                                _disabledParking,
                                (v) => setState(() => _disabledParking = v)),
                          ]),
                          const SizedBox(height: 10),
                          Text(context.read<AppSettingsProvider>().l10n.mapParkingType, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kParkingTypes.map((t) => _setFilterChip(
                              setDlg, t, _parkingTypeFilter,
                            )).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 哺集乳室 ──────────────────────────────
                        if (showBreastfeeding) ...[
                          _filterHeader(Icons.child_care_rounded, '哺集乳室類別'),
                          Text('未選則顯示全部', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kBreastfeedingCats.map((t) => _setFilterChip(
                              setDlg, t, _breastfeedingCatFilter,
                            )).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 寵物友善 ──────────────────────────────
                        if (showPet) ...[
                          _filterHeader(Icons.pets_rounded, '寵物友善類別'),
                          Text('未選則顯示全部', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kPetCats.map((t) => _setFilterChip(
                              setDlg, t, _petCatFilter,
                            )).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 餐廳評核級別 ──────────────────────────
                        if (showRestaurant) ...[
                          _filterHeader(Icons.restaurant_rounded, '餐飲評核級別'),
                          Text('未選則顯示全部', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kRestaurantLevels.map((t) => _setFilterChip(
                              setDlg, t, _restaurantLevelFilter,
                              color: const Color(0xFFBF360C),
                            )).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 飲冰品 ────────────────────────────────
                        if (showDrink) ...[
                          _filterHeader(Icons.local_cafe_rounded, '飲冰品分類'),
                          Text('未選則顯示全部', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kDrinkCats.map((t) => _setFilterChip(
                              setDlg, t, _drinkCatFilter,
                              color: const Color(0xFF0277BD),
                            )).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 嘉市好店 ──────────────────────────────
                        if (showGoodShop) ...[
                          _filterHeader(Icons.store_rounded, '嘉市好店組別'),
                          Text('未選則顯示全部', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kGoodShopGroups.map((t) => _setFilterChip(
                              setDlg, t, _goodShopGroupFilter,
                              color: const Color(0xFF6A1B9A),
                            )).toList(),
                          ),
                        ],

                        // ── 旅館民宿等級 ───────────────────────────
                        if (showHotel) ...[
                          if (showGoodShop) const SizedBox(height: 20),
                          _filterHeader(Icons.hotel_rounded, '旅館等級'),
                          Text('未選則顯示全部', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: _kHotelClasses.map((t) => _setFilterChip(
                              setDlg, t, _hotelClassFilter,
                              color: const Color(0xFF7B1FA2),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filterHeader(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ]),
      );

  Widget _filterChip(StateSetter setDlg, String label, bool selected,
      ValueChanged<bool> onChange) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      selectedColor: Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.88)!,
      checkmarkColor: Theme.of(context).colorScheme.primary,
      backgroundColor: Colors.white,
      side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (v) {
        onChange(v);
        setDlg(() {});
      },
    );
  }

  /// Set-based multi-select chip (for new sub-category filters).
  Widget _setFilterChip(
    StateSetter setDlg,
    String label,
    Set<String> filterSet, {
    Color? color,
  }) {
    final sel   = filterSet.contains(label);
    final c     = color ?? Theme.of(context).colorScheme.primary;
    final cMist = Color.lerp(c, Colors.white, 0.85)!;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: sel,
      selectedColor: cMist,
      checkmarkColor: c,
      backgroundColor: Colors.white,
      side: BorderSide(color: sel ? c : Colors.grey.shade300),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (v) {
        setState(() => v ? filterSet.add(label) : filterSet.remove(label));
        setDlg(() {});
      },
    );
  }

  // ── 圖層控制 ─────────────────────────────────────────────

  void _showLegend() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(context.read<AppSettingsProvider>().l10n.mapLayerControl),
          contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                TextButton(
                    onPressed: () {
                      setState(() => _visible.addAll(_Cat.values));
                      setDlg(() {});
                    },
                    child: Text(context.read<AppSettingsProvider>().l10n.mapShowAll)),
                TextButton(
                    onPressed: () {
                      setState(() => _visible.clear());
                      setDlg(() {});
                    },
                    child: Text(context.read<AppSettingsProvider>().l10n.mapHideAll)),
              ]),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _kCats.map((c) {
                    final on = _visible.contains(c.cat);
                    return SwitchListTile(
                      dense: true,
                      secondary: Icon(c.icon, color: c.color, size: 22),
                      title: Text(c.label,
                          style: const TextStyle(fontSize: 14)),
                      value: on,
                      activeThumbColor: Theme.of(ctx).colorScheme.primary,
                      onChanged: (v) {
                        setState(() => v
                            ? _visible.add(c.cat)
                            : _visible.remove(c.cat));
                        setDlg(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.read<AppSettingsProvider>().l10n.done)),
          ],
        ),
      ),
    );
  }

  // ── 詳細資料 ─────────────────────────────────────────────

  /// Tap a map marker: select it (enlarges + glows), zoom to it, then show sheet.
  void _onMarkerTap(_Place p) {
    // 1. Mark as selected → triggers AnimatedContainer in _MarkerPin
    setState(() => _selectedId = p.id);
    // 2. Zoom in (snap to ≥ 15.5) and centre the map on the pin
    final currentZoom = _mapCtrl.camera.zoom;
    _mapCtrl.move(p.pos, currentZoom < 15.0 ? 15.5 : currentZoom);
    // 3. Show detail sheet after a tiny delay so the zoom & animation are visible
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _showDetail(p);
    });
  }

  void _showDetail(_Place p) {
    final fromList = _isListView;
    void jumpToMap() {
      Navigator.pop(context);
      setState(() { _isListView = false; _selectedId = null; });
      Future.microtask(() => _mapCtrl.move(p.pos, 15.5));
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          (p.cat == _Cat.tdxSpot || p.cat == _Cat.hotel)
          ? _TdxPlaceSheet(place: p, onShowOnMap: fromList ? jumpToMap : null)
          : _PlaceSheet(place: p, onShowOnMap: fromList ? jumpToMap : null),
    ).whenComplete(() {
      // Deselect marker when sheet is dismissed
      if (mounted) setState(() => _selectedId = null);
    });
  }
}

// ═══════════════════════════════════════════════════════════
//  可愛載入動畫
// ═══════════════════════════════════════════════════════════

class _MapLoadingOverlay extends StatefulWidget {
  const _MapLoadingOverlay();
  @override
  State<_MapLoadingOverlay> createState() => _MapLoadingOverlayState();
}

class _MapLoadingOverlayState extends State<_MapLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bounce;
  late final Animation<double> _shadow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0, end: -18).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _shadow = Tween<double>(begin: 0.8, end: 1.3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, _bounce.value),
                  child: Icon(Icons.location_on_rounded,
                      size: 54, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 6),
                Transform.scale(
                  scaleX: _shadow.value,
                  child: Container(
                    width: 28, height: 7,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '探索嘉義中…',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '載入 ${_kCats.length} 種地點資料',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Marker 針頭
// ═══════════════════════════════════════════════════════════

class _MarkerPin extends StatelessWidget {
  final Color    color;
  final IconData icon;
  final bool     isSelected;
  const _MarkerPin({
    required this.color,
    required this.icon,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final fill      = isSelected ? color : Color.lerp(color, Colors.white, 0.80)!;
    final iconColor = isSelected ? Colors.white : color;
    final size      = isSelected ? 40.0 : 32.0;
    final iconSize  = isSelected ? 20.0 : 14.0;

    // OverflowBox 讓 easeOutBack 超出 Marker 邊界時不拋 RenderFlex overflow
    return OverflowBox(
      alignment: Alignment.topCenter,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Bubble ──────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 230),
          curve: Curves.easeOutBack,
          width: size, height: size,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: isSelected ? 2.5 : 2.0),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isSelected ? 0.60 : 0.35),
                blurRadius: isSelected ? 14 : 5,
                spreadRadius: isSelected ? 2 : 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
        // ── Tail ────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 230),
          curve: Curves.easeOutBack,
          width: isSelected ? 12 : 10,
          height: isSelected ? 8 : 6,
          child: CustomPaint(
            painter: _PinTailPainter(color: color),
          ),
        ),
      ],
    ),   // Column
    );   // OverflowBox
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant _PinTailPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════
//  詳細資料 BottomSheet
// ═══════════════════════════════════════════════════════════

class _PlaceSheet extends StatelessWidget {
  final _Place place;
  final VoidCallback? onShowOnMap;
  const _PlaceSheet({required this.place, this.onShowOnMap});

  _CatCfg get _cfg => _kCats.firstWhere((c) => c.cat == place.cat);

  List<String> _placeImages() {
    final raw = place.raw;
    // 1. 'images' array (restaurant / good_shop Firestore format)
    final imgs = raw['images'];
    if (imgs is List) {
      final list = imgs.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    // 2. 'pictureUrl' (TDX format — can be List or single String)
    final v = raw['pictureUrl'];
    if (v is List) {
      final list = v.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    // 3. Single image fallback
    final single = (raw['imageUrl'] ?? raw['Thumbnail'] ?? '').toString().trim();
    return single.isNotEmpty ? [single] : [];
  }

  @override
  Widget build(BuildContext context) {
    final imgs = _placeImages();
    return DraggableScrollableSheet(
      initialChildSize: imgs.isNotEmpty ? 0.72 : 0.44,
      minChildSize: 0.26,
      maxChildSize: 0.90,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: _cfg.color, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(_cfg.icon, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (place.address.isNotEmpty)
                        Text(place.address,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // ── 動作按鈕（統一 40×40 尺寸）──────────────────
                SizedBox(
                  width: 40, height: 40,
                  child: Center(child: SpotSaveButton(
                    spotId: place.id,
                    spotName: place.name,
                    imageUrl: (() {
                      final imgs = place.raw['images'];
                      if (imgs is List && imgs.isNotEmpty) return imgs.first.toString();
                      return (place.raw['imageUrl'] ?? place.raw['Thumbnail'] ?? '').toString();
                    })(),
                    rating: ((place.raw['rating'] ?? place.raw['Rating'] ?? 0.0) as num).toDouble(),
                    description: (place.raw['description'] ?? place.raw['Description'] ??
                                  place.raw['shortDesc'] ?? place.raw['Content'] ?? '').toString(),
                    address: place.address,
                    category: place.cat.name,
                    size: 18,
                  )),
                ),
                if (onShowOnMap != null)
                  IconButton(
                    icon: Icon(Icons.map_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 22),
                    tooltip: '在地圖上查看',
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    padding: EdgeInsets.zero,
                    onPressed: onShowOnMap,
                  ),
                IconButton(
                  icon: Icon(Icons.directions_rounded,
                      color: Theme.of(context).colorScheme.primary, size: 24),
                  tooltip: '開啟導航',
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                  padding: EdgeInsets.zero,
                  onPressed: () => _nav(place.pos),
                ),
              ],
            ),
          ),
          const Divider(height: 14),
          if (place.cat == _Cat.toilet) _buildToiletBadges(),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                if (imgs.isNotEmpty) _ImageCarousel(urls: imgs),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ..._buildFields(context),
                    SpotRatingSection(placeId: place.id),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildToiletBadges() {
    final n = int.tryParse(place.raw['尿布檯組']?.toString() ?? '0') ?? 0;
    final type = place.raw['公廁類型']?.toString() ?? '';
    final accessible = type.contains('通用') ||
        type.contains('無障礙') || type.contains('親子');
    if (n == 0 && !accessible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(spacing: 8, runSpacing: 6, children: [
        if (n > 0) _badge('尿布台 ×$n', const Color(0xFFFFE0B2)),
        if (accessible)
          _badge('通用／無障礙廁所', const Color(0xFFB3E5FC)),
      ]),
    );
  }

  Widget _badge(String text, Color bg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600)),
      );

  List<Widget> _buildFields(BuildContext context) {
    if (place.cat == _Cat.facility) return _buildFacilityFields(context);

    const shownName = {
      '停車場名稱','加油站站名','加油站名站名','店家名稱','業者名稱',
      '名稱','公共場所名稱','場所名稱','地點','Name','name',
    };
    const shownAddr = {
      '地址','加油站地址','營業地址','設置地點','場所地址',
      'Address','address','路段','鄉鎮市',
    };
    const skipZero = {'機車','大型車','身障機車','大客車'};
    final rows = <Widget>[];
    for (final entry in place.raw.entries) {
      final rawKey   = entry.key;
      final cleanKey = _MapScreenState._cleanKey(rawKey);
      if (_kSkip.contains(rawKey) || _kSkip.contains(cleanKey)) continue;
      if (shownName.contains(cleanKey) || shownName.contains(rawKey)) continue;
      if (shownAddr.contains(cleanKey) || shownAddr.contains(rawKey)) continue;
      if (rawKey.contains('﻿') &&
          !cleanKey.contains('單位名稱') &&
          !cleanKey.contains('英文')) continue;
      if (place.cat == _Cat.toilet && cleanKey == '尿布檯組') continue;
      // Skip nested Maps — they render as ugly {key: val, ...} strings
      final rawVal = entry.value;
      if (rawVal is Map || rawVal is List) continue;
      final val = rawVal?.toString().trim() ?? '';
      if (val.isEmpty) continue;
      if (val == '0' && skipZero.contains(cleanKey)) continue;
      final label = _kLabels[cleanKey] ?? _kLabels[rawKey] ?? cleanKey;
      rows.add(_InfoRow(label: label, value: val));
    }
    if (rows.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(context.read<AppSettingsProvider>().l10n.mapNoExtraInfo,
            style: const TextStyle(color: AppColors.textHint)),
      ));
    }
    return rows;
  }

  /// Clean structured detail for 旅遊服務中心 / 借問站
  List<Widget> _buildFacilityFields(BuildContext context) {
    final raw = place.raw;

    // Helper: pull a value from multiple possible field names
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = raw[k];
        if (v != null && v is! Map && v is! List) {
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
      return null;
    }

    final type    = pick(['類別', 'type', 'category']);
    final addr    = pick(['地址', 'address', 'Address']) ?? place.address;
    final phone   = pick(['電話', 'phone', 'tel', 'Tel', 'Phone']);
    final note    = pick(['備註', 'note', 'remark', '注意事項']);

    final rows = <Widget>[];
    if (type != null && type.isNotEmpty)
      rows.add(_InfoRow(label: '類別', value: type));
    if (addr.isNotEmpty)
      rows.add(_InfoRow(label: '地址', value: addr));
    if (phone != null)
      rows.add(_InfoRow(label: '電話', value: phone));
    if (note != null)
      rows.add(_InfoRow(label: '備註', value: note));
    if (rows.isEmpty)
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(context.read<AppSettingsProvider>().l10n.mapNoExtraInfo,
            style: const TextStyle(color: AppColors.textHint)),
      ));
    return rows;
  }

  static Future<void> _nav(LatLng pos) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${pos.latitude},${pos.longitude}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

// ═══════════════════════════════════════════════════════════
//  InfoRow
// ═══════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  TDX 景點詳細頁
// ═══════════════════════════════════════════════════════════

class _TdxPlaceSheet extends StatefulWidget {
  final _Place place;
  final VoidCallback? onShowOnMap;
  const _TdxPlaceSheet({required this.place, this.onShowOnMap});
  @override
  State<_TdxPlaceSheet> createState() => _TdxPlaceSheetState();
}

class _TdxPlaceSheetState extends State<_TdxPlaceSheet> {
  bool _descExpanded = false;

  Map<String, dynamic> get _r => widget.place.raw;

  String _str(String key) => _r[key]?.toString().trim() ?? '';

  static List<String> _images(Map<String, dynamic> r) {
    final v = r['pictureUrl'];
    if (v == null) return [];
    if (v is List) {
      return v.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return [];
  }

  static List<String> _classes(Map<String, dynamic> r) {
    final v = r['classes'];
    if (v == null) return [];
    if (v is List) return v.whereType<String>().toList();
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return [];
  }

  static const _teal = Color(0xFF00897B);

  @override
  Widget build(BuildContext context) {
    final imgs    = _images(_r);
    final cats    = _classes(_r);
    final desc    = _str('description');
    final detail  = _str('descriptionDetail');
    final phone   = _str('phone');
    final open    = _str('openTime');
    final website = _str('websiteUrl');
    final remarks = _str('remarks');

    return DraggableScrollableSheet(
      initialChildSize: imgs.isNotEmpty ? 0.72 : 0.52,
      minChildSize: 0.30,
      maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 2),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                // ── 圖片輪播 ─────────────────────────
                if (imgs.isNotEmpty) _ImageCarousel(urls: imgs),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 類別 tags
                      if (cats.isNotEmpty) ...[
                        Wrap(
                          spacing: 6, runSpacing: 4,
                          children: cats.map((c) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(c, style: const TextStyle(
                                fontSize: 11,
                                color: _teal,
                                fontWeight: FontWeight.w600)),
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // 標題 + 操作按鈕
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(widget.place.name,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          // ── 動作按鈕（統一 40×40）───────────────
                          SizedBox(
                            width: 40, height: 40,
                            child: Center(child: SpotSaveButton(
                              spotId: widget.place.id,
                              spotName: widget.place.name,
                              imageUrl: (() {
                                final imgs = widget.place.raw['images'];
                                if (imgs is List && imgs.isNotEmpty) return imgs.first.toString();
                                final v = widget.place.raw['pictureUrl'];
                                if (v is List && v.isNotEmpty) return v.first.toString();
                                if (v is String && v.isNotEmpty) return v;
                                return (widget.place.raw['imageUrl'] ?? widget.place.raw['Thumbnail'] ?? '').toString();
                              })(),
                              rating: ((widget.place.raw['rating'] ?? widget.place.raw['Rating'] ?? 0.0) as num).toDouble(),
                              description: (widget.place.raw['description'] ?? widget.place.raw['Description'] ??
                                            widget.place.raw['shortDesc'] ?? widget.place.raw['Content'] ?? '').toString(),
                              address: widget.place.address,
                              category: widget.place.cat.name,
                              size: 18,
                            )),
                          ),
                          if (widget.onShowOnMap != null)
                            IconButton(
                              icon: Icon(Icons.map_rounded,
                                  color: Theme.of(context).colorScheme.primary, size: 22),
                              tooltip: '在地圖上查看',
                              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                              padding: EdgeInsets.zero,
                              onPressed: widget.onShowOnMap,
                            ),
                          IconButton(
                            icon: Icon(Icons.directions_rounded,
                                color: Theme.of(context).colorScheme.primary, size: 24),
                            tooltip: '開啟導航',
                            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                            padding: EdgeInsets.zero,
                            onPressed: () =>
                                _PlaceSheet._nav(widget.place.pos),
                          ),
                        ],
                      ),

                      // 地址
                      if (widget.place.address.isNotEmpty)
                        _tdxRow(Icons.location_on_outlined,
                            widget.place.address),

                      const Divider(height: 20),

                      // ── 景點說明 (合併 desc + detail，避免重複) ────
                      // Use detail if available (usually more complete);
                      // only append desc if detail doesn't contain it.
                      if (desc.isNotEmpty || detail.isNotEmpty) ...[
                        Builder(builder: (ctx) {
                          final primary = Theme.of(ctx).colorScheme.primary;
                          // Determine the canonical text to show
                          final mainText = () {
                            if (detail.isEmpty) return desc;
                            if (desc.isEmpty) return detail;
                            // If detail already contains the first 40 chars of desc,
                            // it's a superset — just show detail.
                            final prefix = desc.length > 40 ? desc.substring(0, 40) : desc;
                            return detail.contains(prefix) ? detail : '$desc\n\n$detail';
                          }();
                          final needsExpand = mainText.length > 200;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TranslatedText(
                                text: (!_descExpanded && needsExpand)
                                    ? mainText.substring(0, 200)
                                    : mainText,
                                style: const TextStyle(
                                    fontSize: 13, height: 1.7,
                                    color: AppColors.textPrimary),
                                domain: TranslationDomain.spot,
                              ),
                              if (needsExpand) ...[
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => setState(() => _descExpanded = !_descExpanded),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(
                                      _descExpanded
                                          ? context.read<AppSettingsProvider>().l10n.close
                                          : context.read<AppSettingsProvider>().l10n.more,
                                      style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(_descExpanded ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                        size: 16, color: primary),
                                  ]),
                                ),
                              ],
                              const SizedBox(height: 14),
                            ],
                          );
                        }),
                      ],

                      // ── 聯絡資訊 ───────────────────
                      if (phone.isNotEmpty || open.isNotEmpty ||
                          website.isNotEmpty || remarks.isNotEmpty) ...[
                        const Divider(height: 20),
                        if (phone.isNotEmpty)
                          _tdxRow(Icons.phone_outlined, phone),
                        if (open.isNotEmpty)
                          _tdxRow(Icons.access_time_outlined, open),
                        if (website.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              final uri = Uri.tryParse(website);
                              if (uri != null) launchUrl(uri);
                            },
                            child: _tdxRow(Icons.language_outlined, website,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                        if (remarks.isNotEmpty)
                          _tdxRow(Icons.info_outline, remarks),
                      ],
                    ],
                  ),
                ),
                // ── 評分與備註 ──────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  child: SpotRatingSection(placeId: widget.place.id),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tdxRow(IconData icon, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16,
              color: color ?? Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: color ?? AppColors.textPrimary,
                    height: 1.5)),
          ),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════
//  圖片輪播
// ═══════════════════════════════════════════════════════════

class _ImageCarousel extends StatefulWidget {
  final List<String> urls;
  const _ImageCarousel({required this.urls});
  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _current = 0;
  late final PageController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          onPageChanged: (i) => setState(() => _current = i),
          itemCount: widget.urls.length,
          itemBuilder: (_, i) => CachedNetworkImage(
            imageUrl: widget.urls[i],
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, __) => Container(
              color: Colors.grey.shade100,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey.shade100,
              child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.image_not_supported_outlined,
                    color: Colors.grey.shade300, size: 40),
                const SizedBox(height: 8),
                Text(context.read<AppSettingsProvider>().l10n.mapImageError,
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 12)),
              ]),
            ),
          ),
        ),

        // 頁面指示點（多張圖才顯示）
        if (widget.urls.length > 1)
          Positioned(
            bottom: 10, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.urls.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width:  _current == i ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _current == i
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 2)
                  ],
                ),
              )),
            ),
          ),

        // 張數標籤
        if (widget.urls.length > 1)
          Positioned(
            top: 10, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_current + 1} / ${widget.urls.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ]),
    );
  }
}


