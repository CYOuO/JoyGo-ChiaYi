import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/rail_service.dart' show RailService, TdxService;
import 'search_screen.dart';
import 'map_screen.dart';

String _formatTime(String t) {
  if (t.isEmpty || t == '--:--') return '--:--';
  if (t.length >= 5) return t.substring(0, 5); 
  return t;
}

class _RealNewsItem {
  final String title, date; final String? summary, location, url, imageUrl, endDate; final bool isEvent;
  const _RealNewsItem({required this.title, required this.date, this.summary, this.location, this.url, this.imageUrl, this.endDate, required this.isEvent});
}
String _cleanHtml(String? raw) {
  if (raw == null || raw.trim().isEmpty) return ''; var s = raw;
  s = s.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&hellip;', '…').replaceAll('&mdash;', '—').replaceAll('&ndash;', '–');
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
Map<String, dynamic> _realNewsItemToJson(_RealNewsItem n) => {'title': n.title, 'date': n.date, 'summary': n.summary, 'location': n.location, 'url': n.url, 'imageUrl': n.imageUrl, 'endDate': n.endDate, 'isEvent': n.isEvent};
_RealNewsItem _realNewsItemFromJson(Map<String, dynamic> m) => _RealNewsItem(title: m['title'] as String? ?? '', date: m['date'] as String? ?? '', summary: m['summary'] as String?, location: m['location'] as String?, url: m['url'] as String?, imageUrl: m['imageUrl'] as String?, endDate: m['endDate'] as String?, isEvent: m['isEvent'] as bool? ?? false);

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override State<NewsScreen> createState() => _NewsScreenState();
}
class _NewsScreenState extends State<NewsScreen> with SingleTickerProviderStateMixin {
  static const _eventsUrl = 'https://data.chiayi.gov.tw/opendata/api/getResource?oid=33c3225e-f786-4eaf-8b9c-774cc39c72e0&rid=a809167f-bba6-475d-9dfe-33b4ea7749f6';
  static const _newsUrl = 'https://data.chiayi.gov.tw/opendata/api/getResource?oid=6dcaf207-e99b-4846-bd72-c334ce0d4b59&rid=87d4b27c-07c3-4546-815d-1e733dfd9497';
  static const _kCacheKey = 'news_screen_v1', _kCacheTsKey = 'news_screen_ts_v1', _kCacheTTLMs = 30 * 60 * 1000;

  late final TabController _tabCtrl; List<_RealNewsItem> _all = []; bool _loading = true, _hasError = false;
  List<_RealNewsItem> get _allItems => _all; List<_RealNewsItem> get _eventItems => _all.where((n) => n.isEvent).toList(); List<_RealNewsItem> get _newsItems => _all.where((n) => !n.isEvent).toList();

  @override void initState() { super.initState(); _tabCtrl = TabController(length: 3, vsync: this); _fetch(); }
  @override void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance(); final ts = prefs.getInt(_kCacheTsKey) ?? 0; final cached = prefs.getString(_kCacheKey);
    if (cached != null && cached.isNotEmpty) { try { final list = (jsonDecode(cached) as List).map((m) => _realNewsItemFromJson(m as Map<String, dynamic>)).toList(); if (mounted && list.isNotEmpty) { setState(() { _all = list; _loading = false; _hasError = false; }); if ((DateTime.now().millisecondsSinceEpoch - ts) < _kCacheTTLMs) return; } } catch (_) {} }
    if (mounted && _all.isEmpty) setState(() { _loading = true; _hasError = false; });
    try {
      final results = await Future.wait([_fetchOne(_eventsUrl, isEvent: true), _fetchOne(_newsUrl, isEvent: false)]).timeout(const Duration(seconds: 12));
      final combined = [...results[0], ...results[1]]..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return; setState(() { _all = combined; _loading = false; _hasError = false; });
      try { await prefs.setString(_kCacheKey, jsonEncode(combined.map(_realNewsItemToJson).toList())); await prefs.setInt(_kCacheTsKey, DateTime.now().millisecondsSinceEpoch); } catch (_) {}
    } catch (_) { if (mounted && _all.isEmpty) setState(() { _hasError = true; _loading = false; }); }
  }

  Future<List<_RealNewsItem>> _fetchOne(String url, {required bool isEvent}) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}); if (res.statusCode != 200) return []; final data = jsonDecode(res.body);
      List<dynamic> list = (data is List) ? data : (data['result'] is List ? data['result'] : (data['records'] is List ? data['records'] : []));
      return list.whereType<Map>().map((m) {
        final raw = Map<String, dynamic>.from(m);
        String? pick(List<String> keys) { for (final k in keys) { final v = raw[k]; if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim(); } return null; }
        return _RealNewsItem(title: pick(['title','標題','活動名稱','名稱','Title','Subject']) ?? '無標題', date: isEvent ? pick(['ActiveStart','發布日期','活動開始日期','日期','date','Date','建立時間']) ?? '' : pick(['PostDate','發布日期','日期','date','Date','PublishDate','建立時間']) ?? '', endDate: isEvent ? pick(['ActiveEnd']) : null, summary: pick(['Content','內容','摘要','描述','活動說明','summary','content','description']), location: pick(['PostUnit','發布單位','主辦單位','活動地點','地點','location','venue']), url: pick(['Source','連結','url','URL','link','詳細連結','WebUrl']), imageUrl: pick(['Pic','Thumbnail','圖片','pic','thumbnail']), isEvent: isEvent);
      }).toList();
    } catch (_) { return []; }
  }

  Widget _buildList(List<_RealNewsItem> items, Color primary) {
    if (_loading) return Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5));
    if (_hasError) return Center(child: ElevatedButton(onPressed: _fetch, child: const Text('重試')));
    if (items.isEmpty) return const Center(child: Text('目前無相關消息'));
    return ListView.separated(padding: const EdgeInsets.all(16), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => _RealNewsCard(item: items[i]));
  }

  @override Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(backgroundColor: AppColors.surface, elevation: 0, title: const Text('最新消息', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), bottom: TabBar(controller: _tabCtrl, labelColor: primary, indicatorColor: primary, tabs: const [Tab(text: '全部'), Tab(text: '活動'), Tab(text: '新聞')])), body: TabBarView(controller: _tabCtrl, children: [_buildList(_allItems, primary), _buildList(_eventItems, primary), _buildList(_newsItems, primary)]));
  }
}

class _RealNewsCard extends StatelessWidget {
  final _RealNewsItem item; const _RealNewsCard({required this.item});
  
  void _showDetail(BuildContext context) {
    final c = item.isEvent ? const Color(0xFF00838F) : const Color(0xFF1565C0); 
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final dateRange = item.isEvent && (item.endDate?.isNotEmpty ?? false) ? '${item.date} ～ ${item.endDate}' : item.date;
    final cleanedSummary = _cleanHtml(item.summary);

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => DraggableScrollableSheet(initialChildSize: 0.75, maxChildSize: 0.95, builder: (ctx, scroll) => Container(decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))), child: ListView(controller: scroll, padding: EdgeInsets.zero, children: [
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 0), child: Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))))),
      if (hasImage) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(item.imageUrl!, height: 200, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Row(children: [Text(item.isEvent ? '🏮' : '📰', style: const TextStyle(fontSize: 13)), const SizedBox(width: 4), Text(item.isEvent ? '活動' : '新聞', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700))])), const Spacer(), if (dateRange.isNotEmpty) Text(dateRange, style: const TextStyle(color: AppColors.textHint, fontSize: 12))]),
        const SizedBox(height: 12), Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.4)),
        if (item.location != null && item.location!.isNotEmpty) ...[const SizedBox(height: 8), Row(children: [const Icon(Icons.business_rounded, size: 13, color: AppColors.textHint), const SizedBox(width: 4), Expanded(child: Text(item.location!, style: const TextStyle(color: AppColors.textHint, fontSize: 12)))])],
        const SizedBox(height: 16),
        if (cleanedSummary.isNotEmpty) ...[const Divider(height: 1, color: AppColors.divider), const SizedBox(height: 16), SelectableText(cleanedSummary, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.85))]
        else ...[const Divider(height: 1, color: AppColors.divider), const SizedBox(height: 16), Text(item.isEvent ? '詳細活動資訊請點擊下方連結查看。' : '詳細新聞內容請點擊下方連結查看。', style: const TextStyle(fontSize: 15, color: AppColors.textHint, height: 1.85))],
        if (item.url != null && item.url!.isNotEmpty) ...[const SizedBox(height: 20), Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () async { final uri = Uri.tryParse(item.url!); if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('開啟連結'))), const SizedBox(width: 10), OutlinedButton.icon(onPressed: (){ Clipboard.setData(ClipboardData(text: item.url!)); }, icon: const Icon(Icons.copy, size: 16), label: const Text('複製'))])]
      ]))
    ]))));
  }

  @override Widget build(BuildContext context) {
    final c = item.isEvent ? const Color(0xFF00838F) : const Color(0xFF1565C0);
    return GestureDetector(onTap: () => _showDetail(context), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Text(item.isEvent ? '活動' : '新聞', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700))), const Spacer(), Text(item.date, style: const TextStyle(fontSize: 10, color: AppColors.textHint))]), const SizedBox(height: 8), Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)])));
  }
}

class TransportScreen extends StatefulWidget {
  final int initialTab;
  final void Function(int)? onSwitchTab;
  const TransportScreen({super.key, this.initialTab = 0, this.onSwitchTab});
  @override State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _countdownTimer, _tabDebounceTimer;
  int _secondsRemaining = 30; 

  Future<Map<String, dynamic>>? _youbikeFuture, _busFuture, _traLiveFuture;
  
  List<Map<String, dynamic>>? _traTrains, _thsrTrains, _alishanDocs;
  bool _traLoading = false, _thsrLoading = false, _alishanLoading = false;
  String? _traError, _thsrError; 
  String _traUpdateTime = '', _thsrUpdateTime = '';

  String _busCity = 'Chiayi', _busRoute = ''; 
  final TextEditingController _busRouteCtrl = TextEditingController();
  String _youbikeSearch = '';
  
  static const _traStations = {
    '基隆': '0900', '台北': '1000', '桃園': '1080', '新竹': '1210',
    '竹南': '1250', '苗栗': '3160', '豐原': '3230', '台中': '3300',
    '彰化': '3360', '員林': '3390', '斗六': '3470', '斗南': '3480',
    '大林': '4050', '民雄': '4060', '嘉北': '4070', '嘉義': '4080',
    '水上': '4090', '南靖': '4100', '新營': '4120', '台南': '4220',
    '新左營': '4320', '高雄': '4400', '屏東': '4310'
  };
  String _traOrigin = '嘉義', _traDest = '台北';
  
  static const _thsrStations = {
    '南港': '0990', '台北': '1000', '板橋': '1010', '桃園': '1020', 
    '新竹': '1030', '苗栗': '1035', '台中': '1040', '彰化': '1043', 
    '雲林': '1047', '嘉義': '1050', '台南': '1060', '左營': '1070'
  };
  String _thsrOrigin = '嘉義', _thsrDest = '台北';

  static const _alishanStations = ['嘉義', '北門', '鹿麻產', '竹崎', '木履寮', '樟腦寮', '獨立山', '梨園寮', '交力坪', '水社寮', '奮起湖', '多林', '十字路', '神木', '沼平', '阿里山'];
  String _alishanOrigin = '嘉義', _alishanDest = '奮起湖';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));
    _tabController.addListener(_handleTabSelection);
    _loadDataForTab(_tabController.index);
    _startCountdown();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    _tabDebounceTimer?.cancel();
    _tabDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() { _secondsRemaining = 30; _loadDataForTab(_tabController.index); });
    });
  }

  void _loadDataForTab(int index) {
    if (!mounted) return;
    setState(() {
      switch (index) {
        case 0: if (_busRoute.isNotEmpty) _busFuture = RailService.getBusDynamic(_busCity, _busRoute); break;
        case 1: if (_youbikeFuture == null) _youbikeFuture = RailService.getYoubikeData(); break;
        case 2:
          if (_traLiveFuture == null) _traLiveFuture = RailService.getTraLiveBoard(_traStations[_traOrigin]!);
          if (_traTrains == null && !_traLoading) _fetchTra();
          break;
        case 3: if (_alishanDocs == null && !_alishanLoading) _fetchAlishan(); break;
        case 4: if (_thsrTrains == null && !_thsrLoading) _fetchThsr(); break;
      }
    });
  }

  String get _todayDateStr { final now = DateTime.now().toUtc().add(const Duration(hours: 8)); return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'; }

  // 🌟 修正：加入 isAutoRefresh 參數，實現無閃爍背景更新！
  Future<void> _fetchTra({bool isAutoRefresh = false}) async {
    if (_traOrigin == _traDest) {
      if (mounted && !isAutoRefresh) setState(() { _traTrains = []; _traLoading = false; _traError = '請選擇不同的起迄站'; }); return;
    }
    if (!mounted) return; 
    if (!isAutoRefresh) setState(() { _traLoading = true; _traError = null; _traTrains = []; });
    try {
      final res = await RailService.queryTra(origin: _traStations[_traOrigin]!, dest: _traStations[_traDest]!, trainDate: _todayDateStr);
      if (mounted) setState(() { 
        _traTrains = (res['data'] as List).map((d) => {
          'train_no': d['train_no']?.toString() ?? '', 
          'train_type_name': d['train_type_name']?.toString() ?? '', 
          'departure_time': d['departure_time']?.toString() ?? '', 
          'arrival_time': d['arrival_time']?.toString() ?? '',
          'stops': d['stops'] ?? [] 
        }).toList().cast<Map<String, dynamic>>(); 
        _traUpdateTime = res['updateTime'] ?? '';
        _traLoading = false; 
      });
    } catch (e) { if (mounted && !isAutoRefresh) setState(() { _traLoading = false; _traError = '無法連線或系統限流，請稍候重試'; }); }
  }

  // 🌟 修正：加入 isAutoRefresh
  Future<void> _fetchThsr({bool isAutoRefresh = false}) async {
    if (_thsrOrigin == _thsrDest) {
      if (mounted && !isAutoRefresh) setState(() { _thsrTrains = []; _thsrLoading = false; _thsrError = '請選擇不同的起迄站'; }); return;
    }
    if (!mounted) return; 
    if (!isAutoRefresh) setState(() { _thsrLoading = true; _thsrError = null; _thsrTrains = []; });
    try {
      final res = await RailService.queryThsr(origin: _thsrStations[_thsrOrigin]!, dest: _thsrStations[_thsrDest]!, trainDate: _todayDateStr);
      if (mounted) setState(() { 
        _thsrTrains = (res['data'] as List).map((d) => {
          'TrainNo': d['TrainNo']?.toString() ?? '', 
          'DepartureTime': d['DepartureTime']?.toString() ?? '', 
          'ArrivalTime': d['ArrivalTime']?.toString() ?? '',
          'stops': d['stops'] ?? [] 
        }).toList().cast<Map<String, dynamic>>(); 
        _thsrUpdateTime = res['updateTime'] ?? '';
        _thsrLoading = false; 
      });
    } catch (e) { if (mounted && !isAutoRefresh) setState(() { _thsrLoading = false; _thsrError = '無法連線或系統限流，請稍候重試'; }); }
  }

  // 🌟 修正：加入 isAutoRefresh
  Future<void> _fetchAlishan({bool isAutoRefresh = false}) async {
    if (!mounted) return; 
    if (!isAutoRefresh) setState(() => _alishanLoading = true);
    try { final result = await RailService.fetchAlishanSchedules(); if (mounted) setState(() { _alishanDocs = result; _alishanLoading = false; }); } catch (_) { if (mounted && !isAutoRefresh) setState(() => _alishanLoading = false); }
  }

  // 🌟 核心：倒數計時會觸發所有分頁的更新！
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining <= 1) {
            _secondsRemaining = 30; 
            final idx = _tabController.index;
            if (idx == 0 && _busRoute.isNotEmpty) _busFuture = RailService.getBusDynamic(_busCity, _busRoute);
            else if (idx == 1) _youbikeFuture = RailService.getYoubikeData();
            else if (idx == 2) {
              _traLiveFuture = RailService.getTraLiveBoard(_traStations[_traOrigin]!);
              _fetchTra(isAutoRefresh: true);
            }
            else if (idx == 3) _fetchAlishan(isAutoRefresh: true);
            else if (idx == 4) _fetchThsr(isAutoRefresh: true);
          } else { 
            _secondsRemaining--; 
          }
        });
      }
    });
  }

  @override void dispose() { _tabController.dispose(); _countdownTimer?.cancel(); _tabDebounceTimer?.cancel(); _busRouteCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('交通動態'), actions: [Builder(builder: (bCtx) { final p = Theme.of(bCtx).colorScheme.primary; return Container(margin: const EdgeInsets.only(right: 12), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Color.lerp(p, Colors.white, 0.88)!, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: p, shape: BoxShape.circle)), const SizedBox(width: 5), Text('${_secondsRemaining.toString().padLeft(2,'0')} 秒', style: TextStyle(fontSize: 11, color: p, fontWeight: FontWeight.w600))])); })], bottom: TabBar(controller: _tabController, labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700), unselectedLabelStyle: const TextStyle(fontSize: 11), tabs: const [Tab(icon: Icon(Icons.directions_bus_rounded, size: 18), text: '公車'), Tab(icon: Icon(Icons.pedal_bike_rounded, size: 18), text: 'YouBike'), Tab(icon: Icon(Icons.train_rounded, size: 18), text: '台鐵'), Tab(icon: Icon(Icons.forest_rounded, size: 18), text: '阿里山'), Tab(icon: Icon(Icons.directions_railway_filled_rounded, size: 18), text: '高鐵')])),
      body: TabBarView(controller: _tabController, children: [_buildBusTab(), _buildYouBikeTab(), _buildTrainTab(), _buildAlishanTab(), _buildThsrTab()]),
    );
  }

  Widget _buildODSelector(String origin, String dest, List<String> stations, Function(String) onOrigin, Function(String) onDest, VoidCallback onSwap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('出發站', style: TextStyle(fontSize: 10, color: AppColors.textHint)), DropdownButton<String>(isExpanded: true, value: origin, underline: const SizedBox(), items: stations.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800)))).toList(), onChanged: (v) { if(v!=null) onOrigin(v); })])),
        IconButton(icon: Icon(Icons.swap_horiz_rounded, color: Theme.of(context).colorScheme.primary), onPressed: onSwap),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('抵達站', style: TextStyle(fontSize: 10, color: AppColors.textHint)), DropdownButton<String>(isExpanded: true, value: dest, underline: const SizedBox(), items: stations.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800)))).toList(), onChanged: (v) { if(v!=null) onDest(v); })])),
      ]),
    );
  }

  Widget _buildBusTab() {
    final primary = Theme.of(context).colorScheme.primary;
    final activeChips = _busCity == 'Chiayi' ? ['中山幹線', '忠孝新民幹線', '光林我嘉線'] : ['7329', '7308'];
    return Column(children: [
      Container(color: AppColors.surface, padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(10)), child: Row(children: [ GestureDetector(onTap: () => setState(() { _busCity = 'Chiayi'; _busRouteCtrl.clear(); _busFuture=null; }), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: _busCity=='Chiayi' ? primary : Colors.transparent, borderRadius: BorderRadius.circular(10)), child: Text('嘉義市', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _busCity=='Chiayi' ? Colors.white : AppColors.textSecondary)))), GestureDetector(onTap: () => setState(() { _busCity = 'ChiayiCounty'; _busRouteCtrl.clear(); _busFuture=null; }), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: _busCity=='ChiayiCounty' ? primary : Colors.transparent, borderRadius: BorderRadius.circular(10)), child: Text('嘉義縣', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _busCity=='ChiayiCounty' ? Colors.white : AppColors.textSecondary)))) ])), const SizedBox(width: 12), const Expanded(child: Text('支援查詢全線公車', style: TextStyle(fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w600), textAlign: TextAlign.right))]), const SizedBox(height: 12), TextField(controller: _busRouteCtrl, decoration: InputDecoration(hintText: '🔍 搜尋路線號碼 (支援嘉義全縣市)', prefixIcon: const Icon(Icons.directions_bus_rounded, size: 18), suffixIcon: IconButton(icon: const Icon(Icons.search_rounded, size: 20), onPressed: () { if (_busRouteCtrl.text.isNotEmpty) setState(() { _busRoute = _busRouteCtrl.text.trim(); _busFuture = RailService.getBusDynamic(_busCity, _busRoute); }); }), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)), onSubmitted: (val) { if (val.isNotEmpty) setState(() { _busRoute = val.trim(); _busFuture = RailService.getBusDynamic(_busCity, _busRoute); }); }), const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: activeChips.map((chip) => GestureDetector(onTap: () => setState(() { _busRouteCtrl.text = chip; _busRoute = chip; _busFuture = RailService.getBusDynamic(_busCity, _busRoute); }), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: primary.withValues(alpha: 0.3))), child: Text(chip, style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600))))).toList())])),
      const Divider(height: 1),
      Expanded(child: _busFuture == null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('🚏', style: TextStyle(fontSize: 50)), const SizedBox(height: 10), Text(_busCity == 'Chiayi' ? '請輸入任何市區路線，如「中山幹線」' : '請輸入任何客運號碼，如「7322」', style: const TextStyle(color: AppColors.textHint, fontSize: 15))])) : FutureBuilder<Map<String, dynamic>>(future: _busFuture, builder: (context, snapshot) {
        // 🌟 修正：只有在「沒有舊資料」時才顯示轉圈圈，避免倒數計時刷新時畫面閃爍
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || !snapshot.hasData || (snapshot.data!['data'] as List).isEmpty) return Center(child: Text('目前查無 $_busRoute 的營運資料', style: const TextStyle(color: AppColors.textHint, height: 1.5)));
        final dataMap = snapshot.data!;
        final busStops = dataMap['data'] as List<dynamic>;
        final updateTime = dataMap['updateTime'] as String;
        final dir0 = busStops.where((s) => s['Direction'] == 0).toList()..sort((a,b) => (a['StopSequence'] as int).compareTo(b['StopSequence'] as int));
        final dir1 = busStops.where((s) => s['Direction'] == 1).toList()..sort((a,b) => (a['StopSequence'] as int).compareTo(b['StopSequence'] as int));
        return ListView(padding: const EdgeInsets.all(14), children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('🕒 最後更新: $updateTime', style: const TextStyle(color: AppColors.textHint, fontSize: 11))),
          _BusRouteCard(stops: dir0, primary: primary), if (dir1.isNotEmpty) _BusRouteCard(stops: dir1, primary: primary)
        ]);
      })),
    ]);
  }

  Widget _buildYouBikeTab() {
    return Column(children: [
      Container(color: AppColors.surface, padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: TextField(decoration: const InputDecoration(hintText: '搜尋站點名稱...', prefixIcon: Icon(Icons.search_rounded, size: 18), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)), onChanged: (v) => setState(() => _youbikeSearch = v))),
      Expanded(child: _youbikeFuture == null ? const Center(child: CircularProgressIndicator()) : FutureBuilder<Map<String, dynamic>>(future: _youbikeFuture, builder: (context, snapshot) {
        // 🌟 修正：無感刷新
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || !snapshot.hasData || (snapshot.data!['data'] as List).isEmpty) return const Center(child: Text('目前沒有車位資料或連線異常'));
        final dataMap = snapshot.data!;
        final allStations = dataMap['data'] as List<dynamic>;
        final updateTime = dataMap['updateTime'] as String;
        
        final stations = _youbikeSearch.trim().isEmpty ? allStations : allStations.where((s) {
          String name = (s['station_name'] != null && s['station_name'].toString().isNotEmpty) ? s['station_name'] : s['station_uid'];
          return name.toString().toLowerCase().contains(_youbikeSearch.trim().toLowerCase());
        }).toList();

        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('🕒 最後更新: $updateTime', style: const TextStyle(color: AppColors.textHint, fontSize: 11))])),
          Expanded(child: ListView.builder(padding: const EdgeInsets.all(14), itemCount: stations.length, itemBuilder: (context, index) {
            final s = stations[index]; final gen = s['GeneralBikes'] as int? ?? 0; final elec = s['ElectricBikes'] as int? ?? 0; final canReturn = s['AvailableReturnBikes'] as int? ?? 0; final total = gen + elec; final statusColor = total > 5 ? Theme.of(context).colorScheme.primary : AppColors.warning;
            String displayName = (s['station_name'] != null && s['station_name'].toString().isNotEmpty) ? s['station_name'] : s['station_uid'];
            displayName = displayName.replaceAll('CYI', '嘉義站 ');

            return GestureDetector(onTap: () { if (s['lat'] != null && s['lng'] != null) { Navigator.popUntil(context, (route) => route.isFirst); MapScreen.focusNotifier.value = (lat: s['lat'], lng: s['lng'], catKey: 'YouBike'); widget.onSwitchTab?.call(1); } }, child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('🚲', style: TextStyle(fontSize: 20)))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)), const SizedBox(height: 4), Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text('一般: $gen', style: const TextStyle(fontSize: 9, color: Colors.blue))), const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text('電輔: $elec', style: const TextStyle(fontSize: 9, color: Colors.orange)))])])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('可借 $total 輛', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: statusColor)), Text('可還 $canReturn 格', style: const TextStyle(fontSize: 11, color: AppColors.textHint))])])));
          }))
        ]);
      })),
    ]);
  }

  Widget _buildTrainTab() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      _buildODSelector(_traOrigin, _traDest, _traStations.keys.toList(), 
        (v) { setState(() => _traOrigin = v); _traLiveFuture = RailService.getTraLiveBoard(_traStations[_traOrigin]!); _fetchTra(); }, 
        (v) { setState(() => _traDest = v); _fetchTra(); }, 
        () { setState(() { final t = _traOrigin; _traOrigin = _traDest; _traDest = t; _traLiveFuture = RailService.getTraLiveBoard(_traStations[_traOrigin]!); }); _fetchTra(); }),
      
      if (_traLiveFuture != null) FutureBuilder<Map<String, dynamic>>(future: _traLiveFuture, builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError || (snapshot.data!['data'] as List).isEmpty) return const SizedBox.shrink();
        final displayTrains = (snapshot.data!['data'] as List).take(5).toList();
        final updateTime = snapshot.data!['updateTime'] as String;
        return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.train, color: Colors.amber, size: 18), const SizedBox(width: 8), Text('$_traOrigin 即將進站 (🕒 $updateTime)', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13))]), const Divider(color: Colors.white24, height: 16), ...displayTrains.map((train) { final delay = train['delay_time'] as int; return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(flex: 2, child: Text('${train['train_type_name']} (${train['train_no']})', style: const TextStyle(color: Colors.white, fontSize: 13))), Expanded(flex: 1, child: Text(train['direction'] == 0 ? '順行' : '逆行', style: const TextStyle(color: Colors.white70, fontSize: 12))), Expanded(flex: 1, child: Text(_formatTime(train['schedule_departure_time'].toString()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: (delay == 0 ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)), child: Text(delay == 0 ? '準點' : '晚 $delay 分', style: TextStyle(color: delay == 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)))])); })]));
      }),
      
      if (_traLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
      else if (_traError != null) Center(child: Padding(padding: const EdgeInsets.only(top: 20), child: Text(_traError!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))))
      else if (_traTrains == null || _traTrains!.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: Center(child: Text('此區間今日無直達班次', style: TextStyle(color: AppColors.textHint, fontSize: 15))))
      else ...[
        if (_traUpdateTime.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('🕒 時刻表最後同步: $_traUpdateTime', style: const TextStyle(color: AppColors.textHint, fontSize: 11))),
        ..._traTrains!.map((t) => _ExpandableRailCard(trainNo: t['train_no'], type: t['train_type_name'], dep: t['departure_time'], arr: t['arrival_time'], origin: _traOrigin, dest: _traDest, date: _todayDateStr, isThsr: false, preloadedStops: t['stops'] as List<dynamic>?))
      ],
    ]);
  }

  Widget _buildAlishanTab() {
    final List<Map<String, dynamic>> validTrains = [];
    if (_alishanDocs != null && _alishanOrigin != _alishanDest) {
      try {
        for (final d in _alishanDocs!) {
          final rawStops = d['stopTimes'] ?? d['StopTimes'] ?? d['stops'] ?? d['Stops'];
          if (rawStops == null || rawStops is! List) continue; 
          
          final stopsList = rawStops.map((s) => s as Map<dynamic, dynamic>).toList();
          stopsList.sort((a, b) => ((a['StopSequence'] as num?)?.toInt() ?? 0).compareTo((b['StopSequence'] as num?)?.toInt() ?? 0));
          
          final oIdx = stopsList.indexWhere((s) {
             final name = (s['StationName'] ?? s['stationName'] ?? s['station_name'] ?? s['name'] ?? '').toString();
             return name.contains(_alishanOrigin);
          });
          final dIdx = stopsList.indexWhere((s) {
             final name = (s['StationName'] ?? s['stationName'] ?? s['station_name'] ?? s['name'] ?? '').toString();
             return name.contains(_alishanDest);
          });
          
          if (oIdx != -1 && dIdx != -1 && oIdx < dIdx) {
            validTrains.add({
              'no': (d['TrainNo'] ?? d['trainNo'] ?? d['train_no'] ?? '未知').toString(), 
              'dep': (stopsList[oIdx]['DepartureTime'] ?? stopsList[oIdx]['departureTime'] ?? '--:--').toString(), 
              'arr': (stopsList[dIdx]['ArrivalTime'] ?? stopsList[dIdx]['arrivalTime'] ?? '--:--').toString(), 
              'stops': stopsList
            });
          }
        }
        validTrains.sort((a, b) => (a['dep'] as String).compareTo(b['dep'] as String));
      } catch (e) {
        debugPrint('Alishan parsing error: $e');
      }
    }

    return ListView(padding: const EdgeInsets.all(14), children: [
      _buildODSelector(_alishanOrigin, _alishanDest, _alishanStations, (v){setState(()=>_alishanOrigin=v);}, (v){setState(()=>_alishanDest=v);}, (){setState((){final t=_alishanOrigin; _alishanOrigin=_alishanDest; _alishanDest=t;});}),
      if (_alishanLoading) const Center(child: CircularProgressIndicator()) 
      else if (_alishanOrigin == _alishanDest) const Center(child: Padding(padding: EdgeInsets.only(top: 30), child: Text('請選擇不同的起迄站', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))))
      else if (validTrains.isEmpty) const Center(child: Padding(padding: EdgeInsets.only(top: 30), child: Text('此區間今日無直達班次', style: TextStyle(color: AppColors.textHint)))) 
      else ...validTrains.map((t) => _ExpandableAlishanCard(train: t, origin: _alishanOrigin, dest: _alishanDest)),
    ]);
  }

  Widget _buildThsrTab() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      _buildODSelector(_thsrOrigin, _thsrDest, _thsrStations.keys.toList(), 
        (v) { setState(() => _thsrOrigin = v); _fetchThsr(); }, 
        (v) { setState(() => _thsrDest = v); _fetchThsr(); }, 
        () { setState(() { final t = _thsrOrigin; _thsrOrigin = _thsrDest; _thsrDest = t; }); _fetchThsr(); }),
      if (_thsrLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
      else if (_thsrError != null) Center(child: Padding(padding: const EdgeInsets.only(top: 20), child: Text(_thsrError!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))))
      else if (_thsrTrains == null || _thsrTrains!.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: Center(child: Text('此區間今日無直達班次', style: TextStyle(color: AppColors.textHint))))
      else ...[
        if (_thsrUpdateTime.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('🕒 時刻表最後同步: $_thsrUpdateTime', style: const TextStyle(color: AppColors.textHint, fontSize: 11))),
        ..._thsrTrains!.map((t) => _ExpandableRailCard(trainNo: t['TrainNo'], type: '高鐵', dep: t['DepartureTime'], arr: t['ArrivalTime'], origin: _thsrOrigin, dest: _thsrDest, date: _todayDateStr, isThsr: true, preloadedStops: t['stops'] as List<dynamic>?))
      ],
    ]);
  }
}

class _BusRouteCard extends StatefulWidget {
  final List<dynamic> stops; final Color primary;
  const _BusRouteCard({required this.stops, required this.primary});
  @override State<_BusRouteCard> createState() => _BusRouteCardState();
}
class _BusRouteCardState extends State<_BusRouteCard> {
  bool _expanded = false;
  @override Widget build(BuildContext context) {
    if (widget.stops.isEmpty) return const SizedBox.shrink();
    String origin = widget.stops.first['StopName'] ?? '起點'; String dest = widget.stops.last['StopName'] ?? '終點';
    return Container(
      margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16), onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: widget.primary.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(Icons.directions_bus_rounded, color: widget.primary, size: 20)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('行駛方向', style: TextStyle(fontSize: 10, color: AppColors.textHint)), Row(children: [Expanded(child: Text(origin, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)), const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textHint)), Expanded(child: Text(dest, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis))])])), Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textHint)])),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 16), child: Column(children: widget.stops.map((s) {
            bool isLast = s == widget.stops.last;
            final status = s['StopStatus'] as int; 
            final eta = s['EstimateTime'] as int?; 
            String etaText = '未發車'; 
            Color etaColor = AppColors.textSecondary;
            
            // 🌟 完美解析 TDX 的各種公車狀態碼
            if (status == 0 && eta != null) { 
              final minutes = eta ~/ 60; 
              etaText = minutes <= 1 ? '即將進站' : '$minutes 分鐘'; 
              if (minutes <= 3) etaColor = AppColors.error; 
            } else if (status == 1) {
              etaText = '尚未發車';
            } else if (status == 2) {
              etaText = '交管不停靠'; 
            } else if (status == 3) {
              etaText = '末班車已過';
            } else if (status == 4) {
              etaText = '今日未營運';
            }

            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Column(children: [Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.primary, width: 3), color: Colors.white)), if (!isLast) Container(width: 2, height: 24, color: widget.primary.withValues(alpha: 0.3))]), const SizedBox(width: 14), Expanded(child: Padding(padding: const EdgeInsets.only(top: 0), child: Text(s['StopName'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)))), Text(etaText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: etaColor))]);
          }).toList())),
        ]
      ]),
    );
  }
}

class _ExpandableRailCard extends StatefulWidget {
  final String trainNo, type, dep, arr, origin, dest, date; 
  final bool isThsr;
  final List<dynamic>? preloadedStops;

  const _ExpandableRailCard({required this.trainNo, required this.type, required this.dep, required this.arr, required this.origin, required this.dest, required this.date, required this.isThsr, this.preloadedStops});

  @override State<_ExpandableRailCard> createState() => _ExpandableRailCardState();
}
class _ExpandableRailCardState extends State<_ExpandableRailCard> {
  bool _expanded = false; List<dynamic>? _stops; bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedStops != null && widget.preloadedStops!.isNotEmpty) {
      _stops = widget.preloadedStops;
    }
  }

  void _loadStops() async {
    if (_stops != null && _stops!.isNotEmpty) return;
    setState(() => _loading = true);
    try {
      final res = widget.isThsr ? await RailService.getThsrTrainStops(widget.trainNo, widget.date) : await RailService.getTraTrainStops(widget.trainNo, widget.date);
      if (mounted) setState(() { _stops = res['data'] as List<dynamic>; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  void _toggle() async {
    if (!_expanded) {
      setState(() => _expanded = true);
      if (_stops == null || _stops!.isEmpty) _loadStops();
    } else {
      setState(() => _expanded = false);
    }
  }

  @override Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final typeColor = widget.isThsr ? const Color(0xFF9C27B0) : (widget.type.contains('自強') ? const Color(0xFFBF360C) : widget.type.contains('太魯閣') ? const Color(0xFF0277BD) : widget.type.contains('普悠瑪') ? const Color(0xFF6A1B9A) : widget.type.contains('莒光') ? const Color(0xFF2E7D32) : primary);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider), boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 2))]),
      child: Column(children: [
        Container(height: 6, width: double.infinity, decoration: BoxDecoration(color: typeColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(15)))),
        InkWell(
          onTap: _toggle,
          child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text('${widget.type} ${widget.trainNo}', style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.w800))), const Spacer(), Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textHint, size: 20)]),
            const SizedBox(height: 12),
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_formatTime(widget.dep), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: typeColor, letterSpacing: -0.5)), Text(widget.origin, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600))]),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle)), Expanded(child: Container(height: 2, color: typeColor.withValues(alpha: 0.25))), Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(widget.isThsr ? Icons.directions_railway_filled_rounded : Icons.train_rounded, size: 16, color: typeColor)), Expanded(child: Container(height: 2, color: typeColor.withValues(alpha: 0.25))), Container(width: 6, height: 6, decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle))]))),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_formatTime(widget.arr), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: AppColors.textPrimary, letterSpacing: -0.5)), Text(widget.dest, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600))]),
            ]),
          ])),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          if (_loading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
          else if (_stops != null && _stops!.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 16), child: Column(children: _stops!.map((s) {
              bool isLast = s == _stops!.last;
              bool isTarget = (s['StationName']?.toString() ?? '').contains(widget.origin) || (s['StationName']?.toString() ?? '').contains(widget.dest);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Column(children: [Container(width: isTarget ? 14 : 10, height: isTarget ? 14 : 10, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: typeColor, width: isTarget ? 4 : 2), color: Colors.white)), if (!isLast) Container(width: 2, height: 24, color: typeColor.withValues(alpha: 0.3))]), const SizedBox(width: 14), Expanded(child: Text(s['StationName']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w600, color: isTarget ? AppColors.textPrimary : AppColors.textSecondary))), Text(_formatTime(s['ArrivalTime']?.toString() ?? ''), style: TextStyle(fontSize: 14, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w600, color: isTarget ? AppColors.textPrimary : AppColors.textSecondary))]);
            }).toList()))
          else
            Padding(padding: const EdgeInsets.all(16), child: Column(children: [const Text('無法取得停靠站資料 (可能因遭遇系統限流)', style: TextStyle(color: AppColors.textHint, fontSize: 12)), const SizedBox(height: 8), TextButton.icon(onPressed: _loadStops, icon: const Icon(Icons.refresh, size: 16), label: const Text('重試'))]))
        ]
      ]),
    );
  }
}

class _ExpandableAlishanCard extends StatefulWidget {
  final Map<String, dynamic> train; final String origin, dest;
  const _ExpandableAlishanCard({required this.train, required this.origin, required this.dest});
  @override State<_ExpandableAlishanCard> createState() => _ExpandableAlishanCardState();
}
class _ExpandableAlishanCardState extends State<_ExpandableAlishanCard> {
  bool _expanded = false;
  @override Widget build(BuildContext context) {
    const c = Color(0xFF5C4033);
    final stops = widget.train['stops'] as List<dynamic>? ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(children: [
        Container(height: 6, width: double.infinity, decoration: const BoxDecoration(color: c, borderRadius: BorderRadius.vertical(top: Radius.circular(15)))),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('🚃', style: TextStyle(fontSize: 16)), Text(widget.train['no']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))])), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: const Text('觀光列車', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700))), const Spacer(), Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textHint, size: 20)]), const SizedBox(height: 6), Row(children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_formatTime(widget.train['dep']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary))]), Expanded(child: Row(children: [Expanded(child: Container(height: 1, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 8))), const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textHint), Expanded(child: Container(height: 1, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 8)))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_formatTime(widget.train['arr']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary))])])]))])),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 16), child: Column(children: stops.map((s) {
            bool isLast = s == stops.last;
            bool isTarget = (s['StationName']?.toString() ?? s['stationName']?.toString() ?? '').contains(widget.origin) || (s['StationName']?.toString() ?? s['stationName']?.toString() ?? '').contains(widget.dest);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Column(children: [Container(width: isTarget ? 14 : 10, height: isTarget ? 14 : 10, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: isTarget ? 4 : 2), color: Colors.white)), if (!isLast) Container(width: 2, height: 24, color: c.withValues(alpha: 0.3))]), const SizedBox(width: 14), Expanded(child: Text(s['StationName']?.toString() ?? s['stationName']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w600, color: isTarget ? AppColors.textPrimary : AppColors.textSecondary))), Text(_formatTime((s['ArrivalTime'] ?? s['arrivalTime'] ?? '').toString()), style: TextStyle(fontSize: 14, fontWeight: isTarget ? FontWeight.w800 : FontWeight.w600, color: isTarget ? AppColors.textPrimary : AppColors.textSecondary))]);
          }).toList())),
        ]
      ]),
    );
  }
}
