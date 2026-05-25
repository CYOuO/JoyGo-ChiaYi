import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart' show SpotRatingSection;

// ═══════════════════════════════════════════════════════════
//  常數
// ═══════════════════════════════════════════════════════════

const _kCacheTTL    = Duration(hours: 6);
const _kCacheKey    = 'map_places_v7';   // bumped → clears old stale cache
const _kCacheTsKey  = 'map_places_ts_v7';

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
  final String emoji;
  final Color color;
  final List<String> collections;
  const _CatCfg(this.cat, this.label, this.emoji, this.color, this.collections);
}

const _kCats = <_CatCfg>[
  _CatCfg(_Cat.parking,      '停車場',   '🅿️', Color(0xFF1565C0), ['parking_lots','county_parking_lots']),
  _CatCfg(_Cat.gas,          '加油站',   '⛽',  Color(0xFFE65100), ['gas_stations','county_gas_stations']),
  _CatCfg(_Cat.ev,           '充電站',   '⚡',  Color(0xFF2E7D32), ['ev_charging_stations']),
  _CatCfg(_Cat.taxi,         '計程車',   '🚕',  Color(0xFFF9A825), ['taxi_stands']),
  _CatCfg(_Cat.toilet,       '公廁',     '🚻',  Color(0xFF00838F), ['public_toilets']),
  _CatCfg(_Cat.aed,          'AED',      '❤️',  Color(0xFFC62828), ['aed_locations']),
  _CatCfg(_Cat.goodShop,     '好店',     '🏪',  Color(0xFF6A1B9A), ['good_shops']),
  _CatCfg(_Cat.petShop,      '寵物友善', '🐾',  Color(0xFFAD1457), ['pet_friendly_shops']),
  _CatCfg(_Cat.drinkShop,    '飲料店',   '🧋',  Color(0xFF0277BD), ['excellent_drink_shops']),
  _CatCfg(_Cat.restaurant,   '餐廳',     '🍽️', Color(0xFFBF360C), ['excellent_restaurants']),
  _CatCfg(_Cat.wheelchair,   '輪椅站',   '♿',  Color(0xFF00695C), ['wheelchair_stations']),
  _CatCfg(_Cat.breastfeeding,'哺乳室',   '🤱',  Color(0xFF6A1B9A), ['breastfeeding_rooms']),
  _CatCfg(_Cat.wifi,         'iTaiwan',  '📶',  Color(0xFF283593), ['itaiwan_hotspots']),
  _CatCfg(_Cat.police,       '警察局',   '👮',  Color(0xFF0D47A1), ['police_stations']),
  _CatCfg(_Cat.tdxSpot,     'TDX景點',  '🏛️', Color(0xFF00897B), ['tdx_spots']),
  _CatCfg(_Cat.hotel,       '旅館民宿', '🏨', Color(0xFF7B1FA2), ['tdx_hotels']),
  _CatCfg(_Cat.youbike,     'YouBike', '🚲', Color(0xFF00897B), ['tdx_youbike_stations']),
  _CatCfg(_Cat.busStop,     '公車站',  '🚌', Color(0xFF1565C0), ['tdx_bus_routes']),
  _CatCfg(_Cat.facility,   '旅遊設施', '🗺️', Color(0xFF00695C), ['facilities']),
  _CatCfg(_Cat.chiayiFood, '雞肉飯',  '🍗', Color(0xFFBF360C), ['restaurants']),
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

// 旅遊設施（facilities）類別 → Emoji
String _facilityEmoji(Map<String, dynamic> raw) {
  final type = raw['類別']?.toString() ?? '';
  if (type.contains('旅遊服務中心')) return '🏛️';
  if (type.contains('借問站')) return '❓';
  return '📍';
}

// TDX 景點類別 → Emoji（依嘉義資料實際分類對照）
String _tdxEmoji(Map<String, dynamic> raw) {
  final v = raw['classes'];
  final List<String> cls = v is List
      ? v.whereType<String>().toList()
      : v is String && v.trim().isNotEmpty
          ? [v.trim()]
          : [];
  for (final c in cls) {
    switch (c.trim()) {
      case '休閒農業類': return '🌾';
      case '古蹟類':    return '🏯';
      case '廟宇類':    return '⛩️';
      case '文化類':    return '🎭';
      case '林場類':    return '🌲';
      case '森林遊樂區類': return '🌲';
      case '生態類':    return '🦋';
      case '自然風景類': return '🌄';
      case '藝術類':    return '🎨';
      case '觀光工廠類': return '🏭';
      case '遊憩類':    return '🎡';
      case '都會公園類': return '🌳';
      case '體育健身類': return '🏃';
    }
  }
  return '📍'; // 其他 / 未知
}

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

  // ── internal mapping: catKey → _Cat ─────────────────────────
  static const _catKeyMap = <String, _Cat>{
    'chiayiFood': _Cat.chiayiFood,
    'tdxSpot':    _Cat.tdxSpot,
    'goodShop':   _Cat.goodShop,
    'petShop':    _Cat.petShop,
    'drinkShop':  _Cat.drinkShop,
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

  static const _kTdxCatList = <({String label, String emoji})>[
    (label: '休閒農業類', emoji: '🌾'),
    (label: '古蹟類',    emoji: '🏯'),
    (label: '廟宇類',    emoji: '⛩️'),
    (label: '文化類',    emoji: '🎭'),
    (label: '林場類',    emoji: '🌲'),
    (label: '森林遊樂區類', emoji: '🌲'),
    (label: '生態類',    emoji: '🦋'),
    (label: '自然風景類', emoji: '🌄'),
    (label: '藝術類',    emoji: '🎨'),
    (label: '觀光工廠類', emoji: '🏭'),
    (label: '遊憩類',    emoji: '🎡'),
    (label: '都會公園類', emoji: '🌳'),
    (label: '體育健身類', emoji: '🏃'),
    (label: '其他',      emoji: '📍'),
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
        debugPrint('[MapScreen] ${cfg.label} ❌ $e');
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
      debugPrint('[MapScreen] 公車站 ❌ $e');
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
        debugPrint('[MapScreen] $col → ❌ $e');
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
        debugPrint('[MapScreen] $col → ❌ $e');
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

  // 從其他頁面（如首頁附近景點）跳到地圖並置中放大
  void _onFocusTarget() {
    final t = MapScreen.focusNotifier.value;
    if (t == null || !mounted) return;
    // Switch to map view if in list mode
    if (_isListView) setState(() => _isListView = false);
    // Enable matching category layer if specified and not already visible
    if (t.catKey != null) {
      final cat = MapScreen._catKeyMap[t.catKey!];
      if (cat != null && !_visible.contains(cat)) {
        setState(() => _visible.add(cat));
      }
    }
    // Move after the next frame so the map widget is fully rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapCtrl.move(LatLng(t.lat, t.lng), 15.5);
    });
    // Reset so the same coordinates can trigger again next time
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

  // ── 定位 ─────────────────────────────────────────────────

  Future<void> _goToMe() async {
    if (_myPos == null) await _getPos();
    if (!mounted) return;
    if (_myPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('無法取得位置，請確認已開啟定位權限'),
          duration: Duration(seconds: 3),
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
                child: _isListView
                    ? _buildListView(places)
                    : _buildMap(places),
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

  Widget _buildTopBar(double top) {
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
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(21),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 14),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜尋名稱或地址（跳至最近地點）',
                  hintStyle: TextStyle(
                      color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: Icon(Icons.search,
                      color: Colors.grey.shade400, size: 20),
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
              color: Colors.grey.shade100,
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
            final cfg   = _kCats.firstWhere((c) => c.cat == p.cat);
            final emoji = p.cat == _Cat.tdxSpot
                ? _tdxEmoji(p.raw)
                : p.cat == _Cat.facility
                    ? _facilityEmoji(p.raw)
                    : cfg.emoji;
            final sel = _selectedId == p.id;
            return Marker(
              point: p.pos,
              // Selected marker needs more room for the larger bubble
              width:  sel ? 46 : 36,
              height: sel ? 56 : 44,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => _onMarkerTap(p),
                child: _MarkerPin(color: cfg.color, emoji: emoji, isSelected: sel),
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
            backgroundColor: cfg.color,
            child: Text(
              p.cat == _Cat.tdxSpot
                  ? _tdxEmoji(p.raw)
                  : p.cat == _Cat.facility
                      ? _facilityEmoji(p.raw)
                      : cfg.emoji,
              style: const TextStyle(fontSize: 16),
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
                            const Text('細節篩選',
                                style: TextStyle(
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
                                child: const Text('清除全部'),
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
                            '請先在圖層控制中開啟景點類別。',
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                                height: 1.6),
                          ),
                        ],

                        // ── TDX 景點類別 ──────────────────────────
                        if (showTdx) ...[
                          _filterHeader('🏛️', 'TDX 景點類別'),
                          Text(
                            '未選則顯示全部',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _kTdxCatList.map((item) {
                              final on =
                                  _tdxCatFilter.contains(item.label);
                              return FilterChip(
                                avatar: Text(item.emoji,
                                    style:
                                        const TextStyle(fontSize: 13)),
                                label: Text(item.label,
                                    style:
                                        const TextStyle(fontSize: 12)),
                                selected: on,
                                selectedColor: const Color(0xFF00897B)
                                    .withValues(alpha: 0.15),
                                checkmarkColor: const Color(0xFF00897B),
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                    color: on
                                        ? const Color(0xFF00897B)
                                        : Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4),
                                onSelected: (v) {
                                  setState(() => v
                                      ? _tdxCatFilter.add(item.label)
                                      : _tdxCatFilter
                                          .remove(item.label));
                                  setDlg(() {});
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── 廁所 ──────────────────────────────────
                        if (showToilet) ...[
                          _filterHeader('🚻', '公廁'),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            _filterChip(setDlg, '🍼 有尿布台',
                                _diaperOnly,
                                (v) => setState(() => _diaperOnly = v)),
                            _filterChip(setDlg, '♿ 無障礙/通用',
                                _accessibleOnly,
                                (v) => setState(() => _accessibleOnly = v)),
                          ]),
                          const SizedBox(height: 10),
                          Text('公廁類型', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
                          _filterHeader('🅿️', '停車場'),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            _filterChip(setDlg, '🆓 免費停車',
                                _freeParking,
                                (v) => setState(() => _freeParking = v)),
                            _filterChip(setDlg, '⚡ 有EV車位',
                                _evParking,
                                (v) => setState(() => _evParking = v)),
                            _filterChip(setDlg, '♿ 有身障車位',
                                _disabledParking,
                                (v) => setState(() => _disabledParking = v)),
                          ]),
                          const SizedBox(height: 10),
                          Text('停車場型式', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
                          _filterHeader('🤱', '哺集乳室類別'),
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
                          _filterHeader('🐾', '寵物友善類別'),
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
                          _filterHeader('🍽️', '餐飲評核級別'),
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
                          _filterHeader('🧋', '飲冰品分類'),
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
                          _filterHeader('🏪', '嘉市好店組別'),
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
                          _filterHeader('🏨', '旅館等級'),
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

  Widget _filterHeader(String emoji, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
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
          title: const Text('圖層控制'),
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
                    child: const Text('全部顯示')),
                TextButton(
                    onPressed: () {
                      setState(() => _visible.clear());
                      setDlg(() {});
                    },
                    child: const Text('全部隱藏')),
              ]),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _kCats.map((c) {
                    final on = _visible.contains(c.cat);
                    return SwitchListTile(
                      dense: true,
                      secondary: Text(c.emoji,
                          style: const TextStyle(fontSize: 20)),
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
                child: const Text('完成')),
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
                  child: const Text('📍',
                      style: TextStyle(fontSize: 54)),
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
  final Color  color;
  final String emoji;
  final bool   isSelected;
  const _MarkerPin({
    required this.color,
    required this.emoji,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // Normal: light pastel fill.  Selected: solid brand colour.
    final fill      = isSelected ? color : Color.lerp(color, Colors.white, 0.80)!;
    final iconColor = isSelected ? Colors.white : null; // white emoji when selected
    final size      = isSelected ? 40.0 : 32.0;
    final fontSize  = isSelected ? 20.0 : 14.0;

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
          child: Text(
            emoji,
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              // Tint emoji white when bubble is solid colour so it stays legible
              color: iconColor,
            ),
            textAlign: TextAlign.center,
          ),
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.44,
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
                  child: Text(_cfg.emoji,
                      style: const TextStyle(fontSize: 22)),
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
                if (onShowOnMap != null)
                  IconButton(
                    icon: Icon(Icons.map_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 24),
                    tooltip: '在地圖上查看',
                    onPressed: onShowOnMap,
                  ),
                IconButton(
                  icon: Icon(Icons.directions_rounded,
                      color: Theme.of(context).colorScheme.primary, size: 26),
                  tooltip: '開啟導航',
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                ..._buildFields(),
                SpotRatingSection(placeId: place.id),
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
        if (n > 0) _badge('🍼 尿布台 ×$n', const Color(0xFFFFE0B2)),
        if (accessible)
          _badge('♿ 通用／無障礙廁所', const Color(0xFFB3E5FC)),
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

  List<Widget> _buildFields() {
    // For facilities (旅遊服務中心 / 借問站), show a clean custom layout
    if (place.cat == _Cat.facility) return _buildFacilityFields();

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
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('（無額外資訊）',
            style: TextStyle(color: AppColors.textHint)),
      ));
    }
    return rows;
  }

  /// Clean structured detail for 旅遊服務中心 / 借問站
  List<Widget> _buildFacilityFields() {
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
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('（無額外資訊）',
            style: TextStyle(color: AppColors.textHint)),
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

                      // 標題 + 導航按鈕
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(widget.place.name,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (widget.onShowOnMap != null)
                            IconButton(
                              icon: Icon(Icons.map_rounded,
                                  color: Theme.of(context).colorScheme.primary, size: 24),
                              tooltip: '在地圖上查看',
                              onPressed: widget.onShowOnMap,
                            ),
                          IconButton(
                            icon: Icon(Icons.directions_rounded,
                                color: Theme.of(context).colorScheme.primary, size: 26),
                            tooltip: '開啟導航',
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

                      // ── 簡介 ───────────────────────
                      if (desc.isNotEmpty) ...[
                        const Text('簡介',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        Text(
                          (!_descExpanded && desc.length > 160)
                              ? '${desc.substring(0, 160)}…'
                              : desc,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.65,
                              color: AppColors.textPrimary),
                        ),
                        if (desc.length > 160)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _descExpanded = !_descExpanded),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _descExpanded ? '收起 ▲' : '展開全文 ▼',
                                style: TextStyle(
                                    fontSize: 12, color: Theme.of(context).colorScheme.primary),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                      ],

                      // ── 詳細介紹（可折疊）──────────
                      if (detail.isNotEmpty)
                        Theme(
                          data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            iconColor: Theme.of(context).colorScheme.primary,
                            collapsedIconColor: AppColors.textSecondary,
                            title: const Text('詳細介紹',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary)),
                            children: [
                              Text(detail,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.65,
                                      color: AppColors.textPrimary)),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),

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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                Text('圖片無法載入',
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
