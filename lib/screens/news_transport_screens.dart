import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/dummy_data.dart';
import 'search_screen.dart';

// ════════════════════════════════════════════════
// NEWS SCREEN — emoji-based, no images
// ════════════════════════════════════════════════
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  String _filter = '全部';
  final _filters = ['全部', '活動', '交通', '美食', '旅遊', '公告'];

  static const _catEmoji = {
    '活動': '🏮',
    '交通': '🚌',
    '美食': '🍜',
    '旅遊': '🏔️',
    '公告': '📢',
    '其他': '📋',
  };

  static const _catColor = {
    '活動': Color(0xFFE8A87C),
    '交通': Color(0xFF88B8C8),
    '美食': Color(0xFFD4A847),
    '旅遊': Color(0xFF8FBF8F),
    '公告': Color(0xFFB8A8E8),
    '其他': Color(0xFFA0AFA0),
  };

  List<NewsItem> get _filtered {
    if (_filter == '全部') return DummyData.news;
    return DummyData.news.where((n) => n.category == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('最新消息'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final sel = f == _filter;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : AppColors.surfaceMoss,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? AppColors.primary : AppColors.divider),
                      ),
                      child: Text(f, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppColors.textSecondary)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _NewsCard(
                item: _filtered[i],
                emoji: _catEmoji[_filtered[i].category] ?? '📋',
                color: _catColor[_filtered[i].category] ?? AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;
  final String emoji;
  final Color color;
  const _NewsCard({required this.item, required this.emoji, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emoji square
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(item.category,
                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    const Spacer(),
                    Text(item.date, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                  ]),
                  const SizedBox(height: 6),
                  Text(item.title, style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text(item.summary, style: const TextStyle(
                    fontSize: 12, color: AppColors.textHint, height: 1.4),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
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
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Container(width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
              Row(children: [
                Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(6)),
                    child: Text(item.category, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 4),
                  Text(item.date, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                ])),
              ]),
              const SizedBox(height: 14),
              Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              Text('${item.summary}\n\n這是完整的新聞內容。實際上線後將顯示 Content 欄位的完整資料，由 PostUnit 發布，活動期間為 ActiveStart 至 ActiveEnd。如有附件請參考 File 欄位連結。\n\n嘉義市觀光局持續為您提供最新旅遊資訊，歡迎持續關注探索諸羅 App 的最新消息。',
                style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.85)),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════
// TRANSPORT SCREEN
// ════════════════════════════════════════════════
class TransportScreen extends StatefulWidget {
  final int initialTab;
  const TransportScreen({super.key, this.initialTab = 0});
  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _countdownTimer;
  int _secondsRemaining = 30; // 30 sec countdown

  // Bus state
  String _busFrom = '嘉義火車站';
  String _busTo = '全部路線';
  String _busSearch = '';

  // Train station
  String _trainStation = '嘉義';
  String _trainSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {
        if (_secondsRemaining <= 1) {
          _secondsRemaining = 30; // reset after each 30s
        } else {
          _secondsRemaining--;
        }
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String get _countdownText {
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} 後更新';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('交通動態'),
        actions: [
          // Live update countdown
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryMist,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 7, height: 7,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(_countdownText,
                  style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.directions_bus_rounded, size: 18), text: '公車'),
            Tab(icon: Icon(Icons.pedal_bike_rounded, size: 18), text: 'YouBike'),
            Tab(icon: Icon(Icons.train_rounded, size: 18), text: '台鐵'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBusTab(),
          _buildYouBikeTab(),
          _buildTrainTab(),
        ],
      ),
    );
  }

  // ── BUS TAB ──
  Widget _buildBusTab() {
    final allStops = ['嘉義火車站', '文化路', '嘉義公園', '嘉義高中', '中山路', '東市場'];
    final allRoutes = ['全部路線', '紅幹線', '藍幹線', '101', '7218'];

    final busData = [
      _BusRoute(route:'紅幹線', from:'嘉義火車站', to:'文化路', etaMin:3,
        stops:['嘉義火車站','中正路口','文化路','東市場'], color:const Color(0xFFC4856A), current:'中正路口', progress:0.35),
      _BusRoute(route:'藍幹線', from:'嘉義火車站', to:'嘉義公園', etaMin:8,
        stops:['嘉義火車站','林森路','嘉義公園'], color:const Color(0xFF88B8C8), current:'林森路', progress:0.55),
      _BusRoute(route:'101', from:'嘉義市區', to:'阿里山', etaMin:45,
        stops:['嘉義火車站','竹崎','奮起湖','阿里山'], color:AppColors.primary, current:'竹崎', progress:0.25),
      _BusRoute(route:'7218', from:'嘉義火車站', to:'故宮南院', etaMin:22,
        stops:['嘉義火車站','太保市','故宮南院'], color:const Color(0xFF8F7DB8), current:'太保市', progress:0.50),
    ];

    // Filter
    final q = _busSearch.trim();
    final filtered = busData.where((b) {
      final matchFrom = _busFrom == '嘉義火車站' || b.from.contains(_busFrom) || b.stops.contains(_busFrom);
      final matchRoute = _busTo == '全部路線' || b.route == _busTo;
      final matchSearch = q.isEmpty || b.route.contains(q) || b.from.contains(q) || b.to.contains(q)
          || b.stops.any((s) => s.contains(q)) || b.current.contains(q);
      return matchFrom && matchRoute && matchSearch;
    }).toList();

    return Column(
      children: [
        // Search bar
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜尋路線或站牌名稱...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _busSearch.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () => setState(() => _busSearch = ''))
                : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onChanged: (v) => setState(() => _busSearch = v),
          ),
        ),
        // Route selector
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            children: [
              // From / To row
              Row(children: [
                Expanded(
                  child: _dropdownBox('🚏 出發站', _busFrom, allStops,
                    (v) => setState(() => _busFrom = v)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppColors.primaryMist, shape: BoxShape.circle),
                    child: const Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 18),
                  ),
                ),
                Expanded(
                  child: _dropdownBox('🛣️ 路線', _busTo, allRoutes,
                    (v) => setState(() => _busTo = v)),
                ),
              ]),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _infoTip('即時公車資訊每30秒更新，實際到站時間以現場為準'),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text('🚌\n\n找不到符合的路線',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: AppColors.textHint, height: 2)),
                  ),
                )
              else
                ...filtered.map((b) => _busCard(b)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dropdownBox(String label, String value, List<String> items, void Function(String) onChanged) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary))),
              const Divider(),
              ...items.map((s) => ListTile(
                title: Text(s),
                trailing: s == value ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () { onChanged(s); Navigator.pop(context); },
              )),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceMoss,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          const SizedBox(height: 2),
          Row(children: [
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis)),
            const Icon(Icons.expand_more_rounded, size: 16, color: AppColors.textHint),
          ]),
        ]),
      ),
    );
  }

  Widget _busCard(_BusRoute b) {
    final eta = b.etaMin;
    final etaColor = eta <= 5 ? AppColors.error : eta <= 15 ? AppColors.warning : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              // Route badge
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: b.color, borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('🚌', style: TextStyle(fontSize: 16)),
                  Text(b.route, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${b.from} → ${b.to}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, size: 11, color: AppColors.textHint),
                    Text(' 目前位置：${b.current}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ]),
                ]),
              ),
              // ETA
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$eta 分鐘',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: etaColor)),
                Text('後到站', style: TextStyle(fontSize: 10, color: etaColor.withOpacity(0.7))),
              ]),
            ]),
          ),
          // Progress bar with stops
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: b.progress,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(b.color),
                  ),
                ),
                const SizedBox(height: 6),
                // Stops
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: b.stops.asMap().entries.map((e) {
                    final ratio = e.key / (b.stops.length - 1);
                    final passed = ratio <= b.progress;
                    return Text(e.value,
                      style: TextStyle(fontSize: 9,
                        color: passed ? b.color : AppColors.textHint,
                        fontWeight: passed ? FontWeight.w700 : FontWeight.w400));
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── YOUBIKE TAB ──
  Widget _buildYouBikeTab() {
    final stations = [
      {'name':'嘉義火車站', 'available':8, 'empty':4, 'dist':'0.1km', 'update':'1分鐘前'},
      {'name':'文化路夜市口', 'available':3, 'empty':9, 'dist':'0.3km', 'update':'2分鐘前'},
      {'name':'嘉義公園', 'available':12, 'empty':2, 'dist':'0.5km', 'update':'剛剛'},
      {'name':'嘉義高中', 'available':0, 'empty':14, 'dist':'0.7km', 'update':'3分鐘前'},
      {'name':'嘉義市立美術館', 'available':6, 'empty':6, 'dist':'0.9km', 'update':'1分鐘前'},
      {'name':'故宮南院', 'available':15, 'empty':3, 'dist':'4.2km', 'update':'剛剛'},
    ];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _infoTip('YouBike 站點資訊即時更新，顯示距離為直線距離'),
        const SizedBox(height: 10),
        ...stations.map((s) {
          final available = s['available'] as int;
          final empty = s['empty'] as int;
          final total = available + empty;
          final ratio = total > 0 ? available / total : 0.0;
          final statusColor = available > 5 ? AppColors.primary
              : available > 0 ? AppColors.warning : AppColors.error;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceWarm,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('🚲', style: TextStyle(fontSize: 20)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                    Row(children: [
                      const Icon(Icons.near_me_rounded, size: 11, color: AppColors.textHint),
                      Text(' ${s['dist']} · 更新：${s['update']}',
                        style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                    ]),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('可借 $available 輛',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: statusColor)),
                    Text('空位 $empty 格',
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ]),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('可借', style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
                        Text('$available/$total 輛', style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio, minHeight: 8,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── TRAIN TAB ──
  Widget _buildTrainTab() {
    final allStations = ['嘉義','水上','南靖','後壁','新營','台南','高雄','台中','台北'];

    // Northbound trains (嘉義 → 北)
    final northbound = [
      _Train(no:'自強 108', type:'自強', from:'嘉義', to:'台北', dep:'14:05', arr:'16:52', delay:0, stops:['嘉義','台中','板橋','台北']),
      _Train(no:'太魯閣 224', type:'太魯閣', from:'嘉義', to:'花蓮', dep:'15:30', arr:'18:55', delay:5, stops:['嘉義','台中','台北','花蓮']),
      _Train(no:'莒光 222', type:'莒光', from:'嘉義', to:'台北', dep:'16:15', arr:'20:10', delay:0, stops:['嘉義','斗六','彰化','台中','台北']),
    ];
    // Southbound trains (嘉義 → 南)
    final southbound = [
      _Train(no:'自強 109', type:'自強', from:'嘉義', to:'高雄', dep:'14:02', arr:'15:08', delay:0, stops:['嘉義','台南','高雄']),
      _Train(no:'自強 113', type:'自強', from:'嘉義', to:'潮州', dep:'15:45', arr:'17:20', delay:3, stops:['嘉義','台南','高雄','鳳山','潮州']),
      _Train(no:'莒光 105', type:'莒光', from:'嘉義', to:'台南', dep:'11:30', arr:'12:20', delay:0, stops:['嘉義','水上','後壁','台南']),
    ];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Train search bar
        TextField(
          decoration: InputDecoration(
            hintText: '搜尋車號或站名...',
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            suffixIcon: _trainSearch.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () => setState(() => _trainSearch = ''))
              : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onChanged: (v) => setState(() => _trainSearch = v),
        ),
        const SizedBox(height: 10),
        // Station selector
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceWarm,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(children: [
            const Icon(Icons.train_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            const Text('查詢站點：', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            Expanded(
              child: DropdownButton<String>(
                value: _trainStation,
                isExpanded: true,
                underline: const SizedBox(),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                items: allStations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => v != null ? setState(() => _trainStation = v) : null,
              ),
            ),
          ]),
        ),
        _infoTip('資料每分鐘更新，誤點資訊以臺鐵官網為準'),
        const SizedBox(height: 14),

        // Northbound section
        _trainSectionHeader('⬆️ 北上', '往台中・台北方向'),
        const SizedBox(height: 8),
        ...northbound.where((t) => _trainSearch.isEmpty || t.no.contains(_trainSearch) || t.stops.any((s) => s.contains(_trainSearch))).map((t) => _trainCard(t)),
        const SizedBox(height: 16),

        // Southbound section
        _trainSectionHeader('⬇️ 南下', '往台南・高雄方向'),
        const SizedBox(height: 8),
        ...southbound.where((t) => _trainSearch.isEmpty || t.no.contains(_trainSearch) || t.stops.any((s) => s.contains(_trainSearch))).map((t) => _trainCard(t)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _trainSectionHeader(String title, String sub) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryMist,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primary)),
      ),
      const SizedBox(width: 8),
      Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
    ]);
  }

  Widget _trainCard(_Train t) {
    final typeColor = t.type == '自強' ? AppColors.accentTerra
        : t.type == '太魯閣' ? AppColors.accentSky
        : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: typeColor.withOpacity(0.13), borderRadius: BorderRadius.circular(6)),
              child: Text(t.type, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(t.no, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(width: 8),
            if (t.delay > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('誤點 ${t.delay}分', style: const TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text('準點', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            // Departure
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.dep, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.textPrimary)),
              Text(t.from, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ]),
            Expanded(
              child: Column(children: [
                Row(children: [
                  Expanded(child: Container(height: 1.5, color: AppColors.divider)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: const Icon(Icons.train_rounded, size: 16, color: AppColors.textHint)),
                  Expanded(child: Container(height: 1.5, color: AppColors.divider)),
                ]),
                const SizedBox(height: 3),
                Text('${t.stops.length - 1}站', style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
              ]),
            ),
            // Arrival
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(t.arr, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22,
                color: t.delay > 0 ? AppColors.error : AppColors.textPrimary)),
              Text(t.to, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ]),
          ]),
          const SizedBox(height: 8),
          // Stops row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: t.stops.asMap().entries.map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (e.key > 0) Row(children: [
                    const SizedBox(width: 4),
                    Container(width: 20, height: 1, color: AppColors.divider),
                    const SizedBox(width: 4),
                  ]),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: e.value == t.from || e.value == t.to
                          ? AppColors.primaryMist : AppColors.surfaceMoss,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: e.value == t.from || e.value == t.to
                          ? AppColors.primary.withOpacity(0.3) : AppColors.divider),
                    ),
                    child: Text(e.value, style: TextStyle(
                      fontSize: 10,
                      color: e.value == t.from || e.value == t.to ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
                  ),
                ],
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTip(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentSky.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentSky.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.accentSky, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
      ]),
    );
  }
}

// ── Models ──
class _BusRoute {
  final String route, from, to, current;
  final int etaMin;
  final List<String> stops;
  final Color color;
  final double progress;
  const _BusRoute({required this.route, required this.from, required this.to,
    required this.etaMin, required this.stops, required this.color,
    required this.current, required this.progress});
}

class _Train {
  final String no, type, from, to, dep, arr;
  final int delay;
  final List<String> stops;
  const _Train({required this.no, required this.type, required this.from,
    required this.to, required this.dep, required this.arr,
    required this.delay, required this.stops});
}
