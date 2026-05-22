import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/dummy_data.dart';
import 'search_screen.dart';

// ── Pet data model ────────────────────────────────────────────
class PetSpot {
  final String name, cat, phone, addr, rules, services;
  final double lat, lng;
  const PetSpot({
    required this.name,
    required this.cat,
    required this.phone,
    required this.addr,
    required this.lat,
    required this.lng,
    required this.rules,
    required this.services,
  });
}

// ── CSV loader ────────────────────────────────────────────────
Future<List<PetSpot>> loadPetSpots() async {
  try {
    final raw = await rootBundle.loadString('assets/data/Pet-Friendly.csv');
    final result = <PetSpot>[];
    final lines = raw.split('\n');
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cols = _csvSplit(line);
      if (cols.length < 8) continue;
      final lat = double.tryParse(cols[5].trim()) ?? 0;
      final lng = double.tryParse(cols[4].trim()) ?? 0;
      if (lat == 0 || lng == 0) continue;
      result.add(PetSpot(
        cat:      cols[0].trim(),
        name:     cols[1].trim(),
        phone:    cols[2].trim(),
        addr:     cols[3].trim(),
        lng:      lng,
        lat:      lat,
        rules:    cols[6].trim().replaceAll('\n', '・'),
        services: cols[7].trim().replaceAll('\n', '・'),
      ));
    }
    return result;
  } catch (e) {
    return [];
  }
}

List<String> _csvSplit(String line) {
  final result = <String>[];
  final sb = StringBuffer();
  bool inQ = false;
  for (int i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQ = !inQ;
    } else if (ch == ',' && !inQ) {
      result.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  result.add(sb.toString());
  return result;
}

// ── Navigation helper ─────────────────────────────────────────
// 不使用 canLaunchUrl：
//   Android 需在 AndroidManifest.xml 加 <queries> 才能讓它回傳 true，
//   且對 https:// 幾乎永遠回傳 false。
// 直接 launchUrl + catchError，失敗才 fallback。
Future<void> launchMapNavigation(
    BuildContext context, double lat, double lng, String name) async {
  final encodedName = Uri.encodeComponent(name);

  // ── Android: geo: intent（系統彈出地圖 App 選擇器）──
  // ── iOS:    comgooglemaps:// → 若未安裝再 fallback Apple Maps ──
  bool launched = false;

  if (Platform.isIOS) {
    // 1. 嘗試 Google Maps App
    final gmUri = Uri.parse(
      'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
    );
    launched = await launchUrl(gmUri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);

    if (!launched) {
      // 2. Fallback → Apple Maps
      final appleUri = Uri.parse('maps://?daddr=$lat,$lng&q=$encodedName');
      launched = await launchUrl(appleUri, mode: LaunchMode.externalApplication)
          .catchError((_) => false);
    }
  } else {
    // Android: geo: URI
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedName)');
    launched = await launchUrl(geoUri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
  }

  // ── 最終 fallback：瀏覽器開 Google Maps 網頁 ──
  if (!launched) {
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    launched = await launchUrl(webUri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
  }

  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('無法開啟地圖，請確認已安裝地圖 App'),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ════════════════════════════════════════════════════════════
// MAP SCREEN
// ════════════════════════════════════════════════════════════
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Set<String> _selectedCats = {'attraction', 'restaurant'};
  bool _showPet = false;
  List<PetSpot> _petSpots = [];

  Spot?    _selSpot;
  PetSpot? _selPet;
  bool _showPetList   = false;
  bool _showLayerPanel = false;

  final MapController _mapCtrl = MapController();

  static const _center = LatLng(23.4800, 120.4491);

  static const _coords = <String, LatLng>{
    's1': LatLng(23.5052, 120.8052),
    's2': LatLng(23.4766, 120.4447),
    's3': LatLng(23.4794, 120.4341),
    's4': LatLng(23.4850, 120.4490),
    's5': LatLng(23.4738, 120.4404),
    's6': LatLng(23.4782, 120.4516),
    's7': LatLng(23.4800, 120.4460),
    's8': LatLng(23.4935, 120.5180),
  };

  static const _normalCats = <Map<String, Object>>[
    {'key': 'attraction', 'label': '景點',    'icon': '🏛️', 'color': Color(0xFF5B8A5F)},
    {'key': 'restaurant', 'label': '餐廳',    'icon': '🍜', 'color': Color(0xFFC4856A)},
    {'key': 'hotel',      'label': '住宿',    'icon': '🏨', 'color': Color(0xFF88B8C8)},
    {'key': 'youbike',    'label': 'YouBike', 'icon': '🚲', 'color': Color(0xFF8FBF8F)},
    {'key': 'aed',        'label': 'AED',     'icon': '❤️', 'color': Color(0xFFBF6060)},
  ];

  @override
  void initState() {
    super.initState();
    loadPetSpots().then((list) {
      if (mounted) setState(() => _petSpots = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── OSM map ──
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 14.0,
              minZoom: 10.0,
              maxZoom: 18.0,
              onTap: (_, __) => setState(() {
                _selSpot     = null;
                _selPet      = null;
                _showPetList = false;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.explore_chiayi',
                maxZoom: 19,
              ),
              _normalMarkerLayer(),
              if (_showPet && !_showPetList) _petMarkerLayer(),
            ],
          ),

          // ── Top search + chips ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen())),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.10),
                              blurRadius: 8, offset: const Offset(0, 2),
                            )],
                          ),
                          child: Row(children: [
                            const Icon(Icons.search_rounded,
                              color: AppColors.textHint, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('搜尋嘉義景點、美食...',
                              style: TextStyle(
                                color: AppColors.textHint, fontSize: 14))),
                            Container(width: 1, height: 18,
                              color: AppColors.divider),
                            const SizedBox(width: 8),
                            const Icon(Icons.mic_none_rounded,
                              color: AppColors.textHint, size: 18),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _iconBtn(Icons.layers_rounded,
                      () => setState(() =>
                        _showLayerPanel = !_showLayerPanel)),
                  ]),

                  const SizedBox(height: 10),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _buildCategoryChips()),
                  ),
                ],
              ),
            ),
          ),

          // ── Zoom / locate controls ──
          Positioned(
            right: 16,
            bottom: (_selSpot != null || _selPet != null || _showPetList)
                ? 220 : 100,
            child: Column(children: [
              _iconBtn(Icons.my_location_rounded, _locateTip),
              const SizedBox(height: 8),
              _iconBtn(Icons.add_rounded, () => _mapCtrl.move(
                _mapCtrl.camera.center, _mapCtrl.camera.zoom + 1)),
              const SizedBox(height: 8),
              _iconBtn(Icons.remove_rounded, () => _mapCtrl.move(
                _mapCtrl.camera.center, _mapCtrl.camera.zoom - 1)),
            ]),
          ),

          if (_showLayerPanel) _layerPanel(),
          if (_selSpot != null)  _spotCard(_selSpot!),
          if (_selPet  != null)  _petCard(_selPet!),
          if (_showPetList)      _petListPanel(),
        ],
      ),
    );
  }

  // ── Chip list ────────────────────────────────────────────────
  List<Widget> _buildCategoryChips() {
    final chips = <Widget>[];

    for (final cat in _normalCats) {
      final key   = cat['key']   as String;
      final label = cat['label'] as String;
      final icon  = cat['icon']  as String;
      final color = cat['color'] as Color;
      final sel   = _selectedCats.contains(key);

      chips.add(
        GestureDetector(
          onTap: () => setState(() {
            sel ? _selectedCats.remove(key) : _selectedCats.add(key);
            _selSpot = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? color : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.08), blurRadius: 4,
              )],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: sel ? Colors.white : AppColors.textSecondary,
              )),
            ]),
          ),
        ),
      );
    }

    // 寵物友善 chip，左半切換顯示、右半切換地圖/列表
    chips.add(
      AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _showPet ? const Color(0xFF5B8A5F) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.08), blurRadius: 4,
          )],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // ── 左半：開/關寵物友善圖層 ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _showPet = !_showPet;
              if (!_showPet) {
                _selPet      = null;
                _showPetList = false;
              }
            }),
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                top: 7,
                bottom: 7,
                right: _showPet ? 6 : 12,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('🐾', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Text('寵物友善', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: _showPet ? Colors.white : AppColors.textSecondary,
                )),
              ]),
            ),
          ),
          // ── 右半：列表/地圖切換（只有開啟時顯示）──
          if (_showPet)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _showPetList = !_showPetList;
                _selPet      = null;
              }),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    _showPetList ? Icons.map_rounded : Icons.list_rounded,
                    color: Colors.white, size: 12,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _showPetList ? '地圖' : '列表',
                    style: const TextStyle(
                      fontSize: 10, color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );

    return chips;
  }

  // ── Normal marker layer ──────────────────────────────────────
  Widget _normalMarkerLayer() {
    final spots = DummyData.spots
        .where((s) => _selectedCats.contains(s.category))
        .toList();

    const catColors = <String, Color>{
      'attraction': Color(0xFF5B8A5F),
      'restaurant': Color(0xFFC4856A),
      'hotel':      Color(0xFF88B8C8),
      'youbike':    Color(0xFF8FBF8F),
      'aed':        Color(0xFFBF6060),
    };
    const catIcons = <String, String>{
      'attraction': '🏛️',
      'restaurant': '🍜',
      'hotel':      '🏨',
      'youbike':    '🚲',
      'aed':        '❤️',
    };

    final coordList = _coords.values.toList();
    final markers = <Marker>[
      Marker(
        point: _center,
        width: 32, height: 32,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.accentSky,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(
              color: AppColors.accentSky.withOpacity(0.4),
              blurRadius: 12, spreadRadius: 2,
            )],
          ),
          child: const Center(child: Icon(Icons.person_pin_rounded,
            color: Colors.white, size: 16)),
        ),
      ),
    ];

    for (int i = 0; i < spots.length; i++) {
      final spot  = spots[i];
      final coord = _coords[spot.id] ?? coordList[i % coordList.length];
      final isSel = _selSpot?.id == spot.id;
      final color = catColors[spot.category] ?? AppColors.primary;

      markers.add(Marker(
        point:  coord,
        width:  isSel ? 140 : 46,
        height: 46,
        child: GestureDetector(
          onTap: () => setState(() {
            _selSpot     = isSel ? null : spot;
            _selPet      = null;
            _showPetList = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSel ? AppColors.primaryDark : color,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: isSel ? 12 : 6,
              )],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(catIcons[spot.category] ?? '📍',
                style: const TextStyle(fontSize: 14)),
              if (isSel) ...[
                const SizedBox(width: 4),
                Flexible(child: Text(spot.name,
                  style: const TextStyle(color: Colors.white,
                    fontSize: 11, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ),
        ),
      ));
    }

    return MarkerLayer(markers: markers);
  }

  // ── Pet marker layer ─────────────────────────────────────────
  Widget _petMarkerLayer() {
    const color = Color(0xFF5B8A5F);
    final markers = <Marker>[];

    for (final s in _petSpots) {
      final isSel = _selPet?.name == s.name;
      markers.add(Marker(
        point:  LatLng(s.lat, s.lng),
        width:  isSel ? 130 : 42,
        height: 38,
        child: GestureDetector(
          onTap: () => setState(() {
            _selPet      = isSel ? null : s;
            _selSpot     = null;
            _showPetList = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: isSel ? const Color(0xFF3A6140) : color,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(
                color: color.withOpacity(0.4), blurRadius: 6,
              )],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('🐾', style: TextStyle(fontSize: 12)),
              if (isSel) ...[
                const SizedBox(width: 4),
                Flexible(child: Text(s.name,
                  style: const TextStyle(color: Colors.white,
                    fontSize: 10, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ),
        ),
      ));
    }

    return MarkerLayer(markers: markers);
  }

  // ── Small icon button ────────────────────────────────────────
  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.10), blurRadius: 6,
          )],
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 20),
      ),
    );
  }

  void _locateTip() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('📍 正在定位中... 請確認已開啟位置權限'),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Normal spot bottom card ──────────────────────────────────
  Widget _spotCard(Spot spot) {
    final coord = _coords[spot.id];
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        margin: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20, offset: const Offset(0, -4),
          )],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(spot.imageUrl,
                    width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72, height: 72,
                      color: AppColors.surfaceMoss,
                      child: Center(child: Text(
                        spot.category == 'restaurant' ? '🍜' : '🏛️',
                        style: const TextStyle(fontSize: 28),
                      )),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spot.name,
                        style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 16, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.star_rounded,
                          size: 13, color: AppColors.accentStraw),
                        Text(' ${spot.rating} · ',
                          style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                        const Icon(Icons.access_time_rounded,
                          size: 12, color: AppColors.textHint),
                        Text(' ${spot.openHours}',
                          style: const TextStyle(
                            fontSize: 11, color: AppColors.textHint)),
                      ]),
                      const SizedBox(height: 3),
                      Text('📍 ${spot.address}',
                        style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                    color: AppColors.textHint),
                  onPressed: () => setState(() => _selSpot = null),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: () {
                    final lat = coord?.latitude  ?? 23.48;
                    final lng = coord?.longitude ?? 120.45;
                    launchMapNavigation(context, lat, lng, spot.name);
                  },
                  icon: const Icon(Icons.directions_rounded, size: 15),
                  label: const Text('導航'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _selSpot = null);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('已將「${spot.name}」加入候選清單'),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  icon: const Icon(Icons.add_location_alt_outlined,
                    size: 15, color: AppColors.primary),
                  label: const Text('加入候選',
                    style: TextStyle(color: AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  ),
                )),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primaryMist,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.push(context,
                      MaterialPageRoute(
                        builder: (_) => SpotDetailPage(spot: spot))),
                    icon: const Icon(Icons.open_in_new_rounded,
                      color: AppColors.primary, size: 20),
                    tooltip: '查看詳情',
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pet bottom card ──────────────────────────────────────────
  Widget _petCard(PetSpot s) {
    const color = Color(0xFF5B8A5F);
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        margin: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20, offset: const Offset(0, -4),
          )],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('🐾', style: TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 15, color: AppColors.textPrimary),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        _catChip(s.cat),
                        const SizedBox(width: 6),
                        Expanded(child: Text(s.addr,
                          style: const TextStyle(
                            fontSize: 10, color: AppColors.textHint),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                    color: AppColors.textHint),
                  onPressed: () => setState(() => _selPet = null),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(children: [
                const Icon(Icons.pets_rounded,
                  size: 12, color: AppColors.textHint),
                const SizedBox(width: 4),
                Expanded(child: Text(s.rules.replaceAll('・', ' · '),
                  style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: () =>
                    launchMapNavigation(context, s.lat, s.lng, s.name),
                  icon: const Icon(Icons.directions_rounded, size: 15),
                  label: const Text('導航'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  ),
                )),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMoss,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: () => setState(() {
                      _showPetList = true;
                      _selPet      = null;
                    }),
                    icon: const Icon(Icons.list_rounded,
                      color: AppColors.primary, size: 20),
                    tooltip: '查看列表',
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pet list panel (slide-up, same screen) ───────────────────
  Widget _petListPanel() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(children: [
              const Text('🐾', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('寵物友善店家 (${_petSpots.length})',
                style: const TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 16, color: AppColors.textPrimary)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showPetList = false),
                icon: const Icon(Icons.map_rounded,
                  size: 16, color: AppColors.primary),
                label: const Text('地圖',
                  style: TextStyle(
                    color: AppColors.primary, fontSize: 13)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                  color: AppColors.textHint),
                onPressed: () => setState(() => _showPetList = false),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _petSpots.length,
              itemBuilder: (_, i) {
                final s = _petSpots[i];
                return GestureDetector(
                  onTap: () => setState(() {
                    _selPet      = s;
                    _showPetList = false;
                    _mapCtrl.move(LatLng(s.lat, s.lng), 16.0);
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWarm,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(children: [
                      const Text('🐾', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.textPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Row(children: [
                              _catChip(s.cat),
                              const SizedBox(width: 6),
                              Expanded(child: Text(s.addr,
                                style: const TextStyle(
                                  fontSize: 10, color: AppColors.textHint),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ]),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.directions_rounded,
                          color: AppColors.primary, size: 20),
                        onPressed: () =>
                          launchMapNavigation(context, s.lat, s.lng, s.name),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ── Layer panel ──────────────────────────────────────────────
  Widget _layerPanel() {
    return Positioned(
      top: 130, right: 16,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.12), blurRadius: 12,
          )],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('圖層', style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            for (final cat in _normalCats)
              _layerRow(
                label:    cat['label'] as String,
                icon:     cat['icon']  as String,
                color:    cat['color'] as Color,
                selected: _selectedCats.contains(cat['key'] as String),
                onTap: () {
                  final key = cat['key'] as String;
                  setState(() {
                    _selectedCats.contains(key)
                      ? _selectedCats.remove(key)
                      : _selectedCats.add(key);
                    _selSpot = null;
                  });
                },
              ),
            const Divider(height: 14),
            _layerRow(
              label:    '寵物友善',
              icon:     '🐾',
              color:    const Color(0xFF5B8A5F),
              selected: _showPet,
              onTap:    () => setState(() => _showPet = !_showPet),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layerRow({
    required String label,
    required String icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: selected ? color : AppColors.divider,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(icon),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.textPrimary : AppColors.textHint,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          )),
        ]),
      ),
    );
  }

  // ── Category chip widget (for pet list rows) ─────────────────
  Widget _catChip(String cat) {
    const catColors = <String, Color>{
      '飲食類': Color(0xFFC4856A),
      '住宿業': Color(0xFF88B8C8),
      '生活類': Color(0xFF8FBF8F),
      '觀光類': Color(0xFFB8A8E8),
      '交通類': Color(0xFFD4A847),
    };
    final color = catColors[cat] ?? AppColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(cat,
        style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SPOT DETAIL PAGE
// ════════════════════════════════════════════════════════════
class SpotDetailPage extends StatefulWidget {
  final Spot spot;
  const SpotDetailPage({super.key, required this.spot});
  @override
  State<SpotDetailPage> createState() => _SpotDetailPageState();
}

class _SpotDetailPageState extends State<SpotDetailPage> {
  bool _liked  = false;
  int  _imgIdx = 0;

  List<String> get _images => [
    widget.spot.imageUrl,
    'https://picsum.photos/seed/${widget.spot.id}b/600/400',
    'https://picsum.photos/seed/${widget.spot.id}c/600/400',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.primaryDark,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black38, shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 20),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: () => setState(() => _liked = !_liked),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black38, shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _liked ? Icons.favorite : Icons.favorite_border,
                    color: _liked ? AppColors.error : Colors.white, size: 20,
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                PageView.builder(
                  itemCount: _images.length,
                  onPageChanged: (i) => setState(() => _imgIdx = i),
                  itemBuilder: (_, i) => Image.network(_images[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.surfaceMoss,
                      child: Center(child: Text(
                        widget.spot.category == 'restaurant' ? '🍜' : '🏛️',
                        style: const TextStyle(fontSize: 60),
                      )),
                    ),
                  ),
                ),
                Container(decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                    ],
                  ),
                )),
                Positioned(top: 60, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${_imgIdx + 1}/${_images.length}',
                      style: const TextStyle(color: Colors.white,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
                Positioned(bottom: 12, left: 0, right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_images.length, (i) =>
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width:  i == _imgIdx ? 16 : 5,
                        height: 5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: i == _imgIdx
                            ? Colors.white : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.spot.name,
                    style: const TextStyle(fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.star_rounded,
                      size: 16, color: AppColors.accentStraw),
                    Text(' ${widget.spot.rating}',
                      style: const TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 15, color: AppColors.textPrimary)),
                    const Text('  ·  ',
                      style: TextStyle(color: AppColors.textHint)),
                    const Icon(Icons.access_time_rounded,
                      size: 14, color: AppColors.textHint),
                    Text('  ${widget.spot.openHours}',
                      style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.location_on_rounded,
                      size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(child: Text(widget.spot.address,
                      style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13))),
                  ]),
                  const SizedBox(height: 16),
                  Text(widget.spot.description,
                    style: const TextStyle(fontSize: 14,
                      color: AppColors.textSecondary, height: 1.8)),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () => launchMapNavigation(
                        context, 23.48, 120.45, widget.spot.name),
                      icon: const Icon(Icons.directions_rounded, size: 16),
                      label: const Text('導航'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.add_location_alt_outlined,
                        size: 16),
                      label: const Text('加入行程'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}