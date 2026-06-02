import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

// ════════════════════════════════════════════════
// MODEL
// ════════════════════════════════════════════════
class PetSpot {
  final String name, cat, phone, addr, rules, services;
  final double lat, lng;
  const PetSpot({
    required this.name, required this.cat, required this.phone,
    required this.addr, required this.lat, required this.lng,
    required this.rules, required this.services,
  });
}

// ════════════════════════════════════════════════
// CSV PARSER — reads assets/data/pet_friendly.csv
// ════════════════════════════════════════════════
Future<List<PetSpot>> loadPetSpots() async {
  final raw = await rootBundle.loadString('assets/data/pet_friendly.csv');
  final lines = raw.split('\n');
  final spots = <PetSpot>[];
  for (int i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    // Simple CSV split (fields don't contain commas within quotes in this file)
    final cols = _splitCsvLine(line);
    if (cols.length < 8) continue;
    final lat = double.tryParse(cols[5]) ?? 0;
    final lng = double.tryParse(cols[4]) ?? 0;
    if (lat == 0 || lng == 0) continue;
    spots.add(PetSpot(
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
  return spots;
}

List<String> _splitCsvLine(String line) {
  final result = <String>[];
  final sb = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ',' && !inQuotes) {
      result.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  result.add(sb.toString());
  return result;
}

// Legacy static fallback (first row only, for safety)
const List<PetSpot> _petSpots = [
  // ── 飲食類 ──
  PetSpot(name:'韓雞Bar-嘉義形象店(正統韓式炸雞）',cat:'飲食類',phone:'(05)2168599',addr:'嘉義市西區民生北路186號',lat:23.47847,lng:120.44644,rules:'可落地',services:'提供寵物飲水・提供酒精或乾洗手・提供協助清潔便溺物・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'朱家麻花捲老字號-12號（正宗老店）',cat:'飲食類',phone:'(05)2910973',addr:'嘉義市友忠路788巷12號',lat:23.48751,lng:120.4432,rules:'可落地・(不可亂大小便喔)',services:'提供酒精或乾洗手'),
  PetSpot(name:'Manners Club',cat:'飲食類',phone:'(05)2360377',addr:'嘉義市新民路377號',lat:23.458228,lng:120.4356598,rules:'可落地・於提籠/推車內才可入內',services:'寵物專用餐具・寵物飲水・協助照顧・提供酒精或乾洗手・協助清潔便溺物・提供狗便袋・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'兩 顆蛋 Egg Egg Dessert',cat:'飲食類',phone:'(05)2227708',addr:'嘉義市蘭井街108號',lat:23.4779,lng:120.45386,rules:'可落地',services:'寵物飲水・寵物牽繩掛勾・提供酒精或乾洗手'),
  PetSpot(name:'來來自然烘培',cat:'飲食類',phone:'(05)2788699',addr:'嘉義市民國路93號',lat:23.47756,lng:120.460489,rules:'於提籠/推車內才可入內',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'柴哥冰廊 x Miss Toast 熱壓吐司',cat:'飲食類',phone:'0982324064',addr:'嘉義市民國路61號',lat:23.47642,lng:120.46066,rules:'可落地・一定要代禮貌帶',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'莊記火雞肉飯',cat:'飲食類',phone:'(05)2765331',addr:'嘉義市新生路660-5號',lat:23.494475,lng:120.456594,rules:'可落地',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'睦鄰咖啡morning cafe',cat:'飲食類',phone:'(05)2750106',addr:'嘉義市中山路89號',lat:23.481942,lng:120.458242,rules:'可落地',services:'寵物飲水・寵物奔跑空間・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'喵咪文創咖啡館',cat:'飲食類',phone:'(05)2781236',addr:'嘉義市中山路43號',lat:23.48218,lng:120.46006,rules:'於提籠/推車內才能進入',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'貳樓餐廳 Second Floor Cafe 嘉義店',cat:'飲食類',phone:'(05)2166222',addr:'嘉義市文化路299號1樓',lat:23.485205,lng:120.448044,rules:'可落地',services:'寵物飲水・寵物餐・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'米克斯寵物友善餐廳',cat:'飲食類',phone:'(05)2366588',addr:'嘉義市青年街164號',lat:23.470569,lng:120.434479,rules:'可落地・寵物需固定在座位上(自備牽繩)',services:'禮貌帶/生理褲(販售)・寵物專用餐具・寵物用品販售・防汙墊・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'Nonamelab',cat:'飲食類',phone:'(05)2280999',addr:'嘉義市西門街127號',lat:23.47746,lng:120.443119,rules:'可落地・於提籠/推車內才可入內・一定要代禮貌帶',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'綠食光 1929',cat:'飲食類',phone:'(05)2259191',addr:'嘉義市中山路258號',lat:23.48035,lng:120.450329,rules:'可落地',services:'可落地(繫牽繩)・於提籠/推車內才可入內(特殊寵物)'),
  PetSpot(name:'廢溫室Greenhouse café',cat:'飲食類',phone:'0926052331',addr:'嘉義市忠孝路346巷18號',lat:23.489139,lng:120.454967,rules:'可落地・需用牽繩',services:'寵物飲水・寵物戶外奔跑空間・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'東發養蜂場',cat:'飲食類',phone:'(05)2719608',addr:'嘉義市義教街839號',lat:23.49867,lng:120.45207,rules:'可落地',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'六年甲班(新生店)',cat:'飲食類',phone:'(05)2778877',addr:'嘉義市新生路663-2號',lat:23.494138,lng:120.45649,rules:'可落地・一定要帶著禮貌帶',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'沐鮨日本料理',cat:'飲食類',phone:'(05)2716610',addr:'嘉義市公園街139號',lat:23.47997,lng:120.4659,rules:'於提籠/推車才可入內',services:'寵物飲水・提供酒精或乾洗手'),
  PetSpot(name:'舊時光新鮮事',cat:'飲食類',phone:'(05)2169909',addr:'嘉義市仁愛路494號',lat:23.476489,lng:120.44222,rules:'寵物可落地・於提籠/推車才可入內',services:'提供寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  // ── 住宿業 ──
  PetSpot(name:'冠閣大飯店',cat:'住宿業',phone:'(05)2318111',addr:'嘉義市忠順一街27號',lat:23.483725,lng:120.434441,rules:'可落地',services:'寵物專用餐具・寵物飲水・寵物餐・寵物美容・提供酒精或乾洗手・協助清潔便溺物・提供狗便袋・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'德爾芙快捷酒店',cat:'住宿業',phone:'(05)2161899',addr:'嘉義市仁愛路361號5-11樓',lat:23.4755,lng:120.442089,rules:'於提籠/推車內才可入內',services:'寵物專用餐具・寵物飲水・防汙墊・提供酒精或乾洗手・提供狗便袋'),
  PetSpot(name:'小小逐月坊',cat:'住宿業',phone:'(05)2168528',addr:'嘉義市國華街181巷14號',lat:23.477217,lng:120.4459271,rules:'可落地・一定要用禮貌帶',services:'禮貌帶/生理褲(租借)・寵物專用餐具・寵物床墊/防汙墊・寵物奔跑空間・提供寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'安蘭居旅店',cat:'住宿業',phone:'(05)2290102',addr:'嘉義市蘭井街465號14樓',lat:23.47664,lng:120.44173,rules:'於提籠/推車才可入內',services:'寵物飲水・寵物運輸籠(小型)・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'安娜與國王有限公司',cat:'住宿業',phone:'(05)2789591',addr:'嘉義市和平路150號',lat:23.480073,lng:120.456894,rules:'於提籠/推車才可入內',services:'寵物飲水・可攜帶寵物入住'),
  PetSpot(name:'新悦花園酒店',cat:'住宿業',phone:'(05)278666',addr:'嘉義市保順路69號',lat:23.50494,lng:120.449971,rules:'可落地・需使用牽繩',services:'寵物專用餐具・寵物旅館・提供貓砂・協助清潔便溺物'),
  // ── 生活類 ──
  PetSpot(name:'東森寵物雲 嘉義西區店',cat:'生活類',phone:'(05)2330006',addr:'嘉義市北港路313號',lat:23.48101,lng:120.42816,rules:'可落地',services:'寵物用品販售・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'東森寵物雲 嘉義北區店',cat:'生活類',phone:'(05)2251000',addr:'嘉義市林森西路186號',lat:23.4842,lng:120.44817,rules:'可落地',services:'寵物用品販售・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'東森寵物雲 嘉義友愛店',cat:'生活類',phone:'(05)2810999',addr:'嘉義市友愛路187號',lat:23.4814,lng:120.4338,rules:'可落地',services:'寵物用品販售・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'東森寵物雲 嘉義後庒店',cat:'生活類',phone:'(05)2306999',addr:'嘉義市吳鳳南路360號',lat:23.4549885,lng:120.4566934,rules:'可落地',services:'寵物用品販售・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'幸福培菓寵物 嘉義店',cat:'生活類',phone:'(05)2841688',addr:'嘉義市新民路723號',lat:23.46929,lng:120.43975,rules:'可落地',services:'禮貌帶/生理褲(販售)・寵物用品販售・寵物美容・提供酒精或乾洗手・協助清潔便溺物・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'皇品城眼鏡',cat:'生活類',phone:'(05)2161234',addr:'嘉義市民族路794號',lat:23.4753,lng:120.44072,rules:'可落地・一定要代禮貌帶',services:'寵物飲水・寵物牽繩掛勾・防汙墊・提供酒精或乾洗手・提供狗便袋・設有寵物友善公約並張貼於明顯處'),
  // ── 交通類 ──
  PetSpot(name:'台灣大車隊',cat:'交通類',phone:'(05)2842797',addr:'嘉義市重慶二街100號',lat:23.45963,lng:120.43264,rules:'於提籠才可入內',services:'親子接送服務・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  // ── 觀光類 ──
  PetSpot(name:'愛木村地方文化館',cat:'觀光類',phone:'(05)2322441',addr:'嘉義市文化路909-3號',lat:23.502027,lng:120.43854,rules:'可落地・於提籠/推車內才可入內',services:'寵物奔跑空間・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'月桃故事館',cat:'觀光類',phone:'(05)2766399',addr:'嘉義市保忠一街359號',lat:23.51244,lng:120.448414,rules:'可落地',services:'寵物飲水・寵物奔跑空間・提供酒精或乾洗手・提供協助清潔便溺物'),
  PetSpot(name:'長圓食品-大福嘉義美食觀光工廠',cat:'觀光類',phone:'(05)2387138',addr:'嘉義市北港路1296號',lat:23.49104,lng:120.40181,rules:'可落地',services:'寵物飲水・寵物牽繩掛勾・提供酒精或乾洗手・協助清潔便溺物・提供狗便袋・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'台灣圖書室',cat:'觀光類',phone:'(05)2228831',addr:'嘉義市中山路255號',lat:23.480499,lng:120.45124,rules:'可落地',services:'寵物專用餐具・寵物飲水・寵物奔跑空間・提供酒精或乾洗手・提供協助清潔便溺物'),
  PetSpot(name:'耐斯廣場時尚百貨',cat:'觀光類',phone:'(05)2767888',addr:'嘉義市忠孝路600號',lat:23.496523,lng:120.452527,rules:'於提籠/推車內才可入內・(餐廳及用餐區除外)',services:'寵物用品販售・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'湘霖園企業社',cat:'觀光類',phone:'(05)2758052',addr:'嘉義市博東路156號',lat:23.490952,lng:120.459432,rules:'可落地',services:'寵物飲水・寵物奔跑空間・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'咱的所在 紅瓦厝窯烤',cat:'觀光類',phone:'(05)2360998',addr:'嘉義市重慶二街146號',lat:23.459129,lng:120.43179,rules:'可落地',services:'寵物飲水・寵物奔跑空間・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'嘉義市東區頂庄社區發展協會',cat:'觀光類',phone:'(05)2765298',addr:'嘉義市義教街538號',lat:23.49869,lng:120.4578,rules:'於提籠/推車內才可入內',services:'寵物飲水・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
  PetSpot(name:'嘉義市大溪社區發展協會',cat:'觀光類',phone:'0935825623',addr:'嘉義市大溪路595號',lat:23.480623,lng:120.402902,rules:'於提籠/推車內才可入內・一定要帶著禮貌帶',services:'寵物奔跑空間・提供酒精或乾洗手・設有寵物友善公約並張貼於明顯處'),
];

// ════════════════════════════════════════════════
// SCREEN
// ════════════════════════════════════════════════
class PetFriendlyScreen extends StatefulWidget {
  const PetFriendlyScreen({super.key});
  @override
  State<PetFriendlyScreen> createState() => _PetFriendlyScreenState();
}

class _PetFriendlyScreenState extends State<PetFriendlyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();
  PetSpot? _selectedSpot;
  String _catFilter = '全部';
  String _search = '';
  List<PetSpot> _spots = [];
  bool _loading = true;

  static const _catConfig = <String, Map<String, dynamic>>{
    '全部':  {'icon': Icons.pets_rounded,           'color': Color(0xFF5B8A5F)},
    '飲食類': {'icon': Icons.restaurant_rounded,     'color': Color(0xFFC4856A)},
    '住宿業': {'icon': Icons.hotel_rounded,           'color': Color(0xFF88B8C8)},
    '生活類': {'icon': Icons.shopping_bag_rounded,   'color': Color(0xFF8FBF8F)},
    '觀光類': {'icon': Icons.attractions_rounded,    'color': Color(0xFFB8A8E8)},
    '交通類': {'icon': Icons.local_taxi_rounded,     'color': Color(0xFFD4A847)},
  };

  List<PetSpot> get _filtered {
    return _spots.where((s) {
      final matchCat = _catFilter == '全部' || s.cat == _catFilter;
      final matchQ = _search.isEmpty ||
          s.name.contains(_search) || s.addr.contains(_search) ||
          s.services.contains(_search) || s.rules.contains(_search);
      return matchCat && matchQ;
    }).toList();
  }

  Color _catColor(String cat) =>
      (_catConfig[cat]?['color'] as Color?) ?? Theme.of(context).colorScheme.primary;
  IconData _catIcon(String cat) =>
      (_catConfig[cat]?['icon'] as IconData?) ?? Icons.pets_rounded;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final spots = await loadPetSpots();
      if (mounted) setState(() { _spots = spots; _loading = false; });
    } catch (e) {
      // Fallback to static data
      if (mounted) setState(() { _spots = List<PetSpot>.from(_petSpots); _loading = false; });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          const Icon(Icons.pets_rounded, size: 20, color: AppColors.textHint),
          const SizedBox(width: 8),
          const Text('寵物友善店家'),
        ]),
      ),
      body: _loading
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.pets_rounded, size: 48, color: AppColors.textHint),
              const SizedBox(height: 16),
              CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
              SizedBox(height: 12),
              Text('載入寵物友善店家...', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ]))
          : Column(
        children: [
          // ── Search ──
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜尋店名・地址・服務...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                isDense: true,
                suffixIcon: _search.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () => setState(() => _search = ''))
                    : null,
              ),
              onChanged: (v) => setState(() { _search = v; _selectedSpot = null; }),
            ),
          ),
          // ── Category filter ──
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _catConfig.keys.map((cat) {
                  final sel = _catFilter == cat;
                  final color = _catColor(cat);
                  return GestureDetector(
                    onTap: () => setState(() { _catFilter = cat; _selectedSpot = null; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? color : AppColors.surfaceMoss,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? color : AppColors.divider),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_catIcon(cat), size: 13, color: _catColor(cat)),
                        const SizedBox(width: 4),
                        Text(cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : AppColors.textSecondary)),
                        if (cat != '全部') ...[
                          const SizedBox(width: 4),
                          Text('(${_petSpots.where((s) => s.cat == cat).length})',
                            style: TextStyle(fontSize: 10, color: sel ? Colors.white70 : AppColors.textHint)),
                        ],
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // ── Tabs ──
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.map_outlined, size: 16), text: '地圖'),
                Tab(icon: Icon(Icons.list_rounded, size: 16), text: '列表'),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Content ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildMapTab(), _buildListTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ── MAP TAB ──
  Widget _buildMapTab() {
    final spots = _filtered;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(23.4800, 120.4491),
            initialZoom: 13.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.explore_chiayi',
            ),
            MarkerLayer(
              markers: spots.map((s) {
                final isSelected = _selectedSpot?.name == s.name;
                final color = _catColor(s.cat);
                return Marker(
                  point: LatLng(s.lat, s.lng),
                  width: isSelected ? 130 : 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => setState(() =>
                      _selectedSpot = _selectedSpot?.name == s.name ? null : s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryDark : color,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: color.withOpacity(0.4),
                          blurRadius: isSelected ? 12 : 6)],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_catIcon(s.cat), size: 14, color: _catColor(s.cat)),
                        if (isSelected) ...[
                          const SizedBox(width: 4),
                          Flexible(child: Text(s.name,
                            style: const TextStyle(color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w700),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        // Count badge
        Positioned(top: 12, left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6)],
            ),
            child: Text('顯示 ${spots.length} 家',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ),
        // Bottom card
        if (_selectedSpot != null) _buildSpotCard(_selectedSpot!),
      ],
    );
  }

  Widget _buildSpotCard(PetSpot s) {
    final color = _catColor(s.cat);
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              Container(width: 46, height: 46,
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Center(child: Icon(_catIcon(s.cat), size: 22, color: _catColor(s.cat)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  _catChip(s.cat, color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.addr, style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ])),
              IconButton(icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
                onPressed: () => setState(() => _selectedSpot = null)),
            ]),
          ),
          // Rules & services
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _infoRow(Icons.pets_rounded, '入內規定', s.rules),
              if (s.services.isNotEmpty) _infoRow(Icons.star_rounded, '寵物服務', s.services),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () => _launchMaps(s),
                icon: const Icon(Icons.directions_rounded, size: 15),
                label: const Text('Google 導航'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(12)),
                child: IconButton(
                  onPressed: () => _launchPhone(s.phone),
                  icon: Icon(Icons.phone_outlined, color: Theme.of(context).colorScheme.primary, size: 20)),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(12)),
                child: IconButton(
                  onPressed: () => _showDetail(s),
                  icon: Icon(Icons.open_in_new_rounded, color: Theme.of(context).colorScheme.primary, size: 20)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── LIST TAB ──
  Widget _buildListTab() {
    final spots = _filtered;
    if (spots.isEmpty) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.pets_rounded, size: 52, color: AppColors.textHint),
        SizedBox(height: 12),
        Text('找不到符合的店家', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      itemCount: spots.length,
      itemBuilder: (_, i) => _listCard(spots[i]),
    );
  }

  Widget _listCard(PetSpot s) {
    final color = _catColor(s.cat);
    return GestureDetector(
      onTap: () => _showDetail(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(children: [
          Container(width: 48, height: 48,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Icon(_catIcon(s.cat), size: 22, color: _catColor(s.cat)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              _catChip(s.cat, color),
              const SizedBox(width: 6),
              Expanded(child: Text(s.addr, style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            Text(s.rules, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 18),
          ]),
        ]),
      ),
    );
  }

  // ── DETAIL SHEET ──
  void _showDetail(PetSpot s) {
    final color = _catColor(s.cat);
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65, maxChildSize: 0.92,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(22),
            children: [
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
              Row(children: [
                Container(width: 56, height: 56,
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Icon(_catIcon(s.cat), size: 26, color: _catColor(s.cat)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _catChip(s.cat, color),
                  const SizedBox(height: 4),
                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
                ])),
              ]),
              const SizedBox(height: 16),
              _detailRow(Icons.location_on_rounded, s.addr),
              const SizedBox(height: 8),
              _detailRow(Icons.phone_rounded, s.phone),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              _sectionLabel('入內規定'),
              const SizedBox(height: 8),
              ...s.rules.split('・').where((r) => r.isNotEmpty).map((r) =>
                Padding(padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(margin: const EdgeInsets.only(top: 6), width: 6, height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r.trim(), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5))),
                  ])),
              ),
              if (s.services.isNotEmpty) ...[
                const SizedBox(height: 14),
                _sectionLabel('寵物服務'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6,
                  children: s.services.split('・').where((v) => v.isNotEmpty).map((v) =>
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.25))),
                      child: Text(v.trim(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                    )
                  ).toList(),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => _launchMaps(s),
                  icon: const Icon(Icons.directions_rounded, size: 15),
                  label: const Text('Google 導航'),
                  style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 12)),
                )),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
                  child: IconButton(
                    onPressed: () { Navigator.pop(ctx); _launchPhone(s.phone); },
                    icon: Icon(Icons.phone_outlined, color: Theme.of(context).colorScheme.primary)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──
  Widget _catChip(String cat, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(cat, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _infoRow(IconData icon, String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Text('$label：', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      Expanded(child: Text(val.replaceAll('・', ' · '),
        style: const TextStyle(fontSize: 11, color: AppColors.textHint), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _detailRow(IconData icon, String val) => Row(children: [
    Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 8),
    Expanded(child: Text(val, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
  ]);

  Widget _sectionLabel(String label) => Text(label,
    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary));

  void _launchMaps(PetSpot s) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(s.name)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _launchPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
