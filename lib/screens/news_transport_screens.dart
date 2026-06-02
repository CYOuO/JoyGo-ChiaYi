import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../widgets/common_widgets.dart' show NewsCardSkeleton;
import '../services/rail_service.dart';
import 'map_screen.dart';

String _formatTime(String t) {
  if (t.isEmpty || t == '--:--') return '--:--';
  if (t.length >= 5) return t.substring(0, 5);
  return t;
}

// ─────────── News helpers (unchanged) ─────────────────────────
(Color, IconData) _newsItemColor(String? location, bool isEvent) {
  final loc = (location ?? '').toLowerCase();
  if (loc.contains('文化') || loc.contains('藝術') || loc.contains('博物')) return (const Color(0xFFB06090), Icons.museum_rounded);
  if (loc.contains('教育') || loc.contains('學') || loc.contains('校')) return (const Color(0xFF5A8FAF), Icons.school_rounded);
  if (loc.contains('體育') || loc.contains('運動')) return (const Color(0xFF5A9F5A), Icons.sports_rounded);
  if (loc.contains('環保') || loc.contains('環境') || loc.contains('農業')) return (const Color(0xFF5E9F7A), Icons.eco_rounded);
  if (loc.contains('衛生') || loc.contains('健康') || loc.contains('醫')) return (const Color(0xFFD45A5A), Icons.local_hospital_rounded);
  if (loc.contains('建設') || loc.contains('工程') || loc.contains('都市')) return (const Color(0xFFB08B40), Icons.construction_rounded);
  if (loc.contains('社會') || loc.contains('福利') || loc.contains('民政')) return (const Color(0xFF7A7ABF), Icons.people_rounded);
  if (loc.contains('財政') || loc.contains('稅務') || loc.contains('經濟')) return (const Color(0xFF7A9F5A), Icons.account_balance_rounded);
  if (loc.contains('警察') || loc.contains('消防') || loc.contains('安全')) return (const Color(0xFF5A7AAF), Icons.local_police_rounded);
  if (loc.contains('觀光') || loc.contains('旅遊')) return (const Color(0xFFBF8040), Icons.tour_rounded);
  if (isEvent) return (const Color(0xFF00838F), Icons.celebration_rounded);
  return (const Color(0xFF1565C0), Icons.article_rounded);
}

class _RealNewsItem {
  final String title, date;
  final String? summary, location, url, imageUrl, endDate;
  final bool isEvent;
  const _RealNewsItem({required this.title, required this.date, this.summary, this.location, this.url, this.imageUrl, this.endDate, required this.isEvent});
}

String _cleanHtml(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  var s = raw;
  s = s.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&hellip;', '…').replaceAll('&mdash;', '—').replaceAll('&ndash;', '–');
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

Map<String, dynamic> _realNewsItemToJson(_RealNewsItem n) => {'title': n.title, 'date': n.date, 'summary': n.summary, 'location': n.location, 'url': n.url, 'imageUrl': n.imageUrl, 'endDate': n.endDate, 'isEvent': n.isEvent};
_RealNewsItem _realNewsItemFromJson(Map<String, dynamic> m) => _RealNewsItem(title: m['title'] as String? ?? '', date: m['date'] as String? ?? '', summary: m['summary'] as String?, location: m['location'] as String?, url: m['url'] as String?, imageUrl: m['imageUrl'] as String?, endDate: m['endDate'] as String?, isEvent: m['isEvent'] as bool? ?? false);

// ─────────── NewsScreen (unchanged) ───────────────────────────
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override State<NewsScreen> createState() => _NewsScreenState();
}
class _NewsScreenState extends State<NewsScreen> with SingleTickerProviderStateMixin {
  static const _eventsUrl = 'https://data.chiayi.gov.tw/opendata/api/getResource?oid=33c3225e-f786-4eaf-8b9c-774cc39c72e0&rid=a809167f-bba6-475d-9dfe-33b4ea7749f6';
  static const _newsUrl = 'https://data.chiayi.gov.tw/opendata/api/getResource?oid=6dcaf207-e99b-4846-bd72-c334ce0d4b59&rid=87d4b27c-07c3-4546-815d-1e733dfd9497';
  static const _kCacheKey = 'news_screen_v1', _kCacheTsKey = 'news_screen_ts_v1', _kCacheTTLMs = 30 * 60 * 1000;

  late final TabController _tabCtrl;
  List<_RealNewsItem> _all = [];
  bool _loading = true, _hasError = false;
  List<_RealNewsItem> get _allItems => _all;
  List<_RealNewsItem> get _eventItems => _all.where((n) => n.isEvent).toList();
  List<_RealNewsItem> get _newsItems => _all.where((n) => !n.isEvent).toList();

  @override void initState() { super.initState(); _tabCtrl = TabController(length: 3, vsync: this); _fetch(); }
  @override void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_kCacheTsKey) ?? 0;
    final cached = prefs.getString(_kCacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final list = (jsonDecode(cached) as List).map((m) => _realNewsItemFromJson(m as Map<String, dynamic>)).toList();
        if (mounted && list.isNotEmpty) { setState(() { _all = list; _loading = false; _hasError = false; }); if ((DateTime.now().millisecondsSinceEpoch - ts) < _kCacheTTLMs) return; }
      } catch (_) {}
    }
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
    if (_loading) return ListView.separated(padding: const EdgeInsets.all(16), itemCount: 5, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, __) => const NewsCardSkeleton());
    if (_hasError) return Center(child: ElevatedButton(onPressed: _fetch, child: const Text('重試')));
    if (items.isEmpty) return const Center(child: Text('目前無相關消息'));
    return ListView.separated(padding: const EdgeInsets.all(16), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => _RealNewsCard(item: items[i]));
  }

  @override Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface, elevation: 0,
        title: Builder(builder: (bCtx) {
          final p = Theme.of(bCtx).colorScheme.primary;
          return Row(mainAxisSize: MainAxisSize.min, children: [DoodleHeart(color: p.withValues(alpha: 0.55), size: 10), const SizedBox(width: 6), const Text('最新消息', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const SizedBox(width: 6), DoodleLightning(color: p.withValues(alpha: 0.55), size: 10)]);
        }),
        bottom: TabBar(controller: _tabCtrl, labelColor: primary, indicatorColor: primary, tabs: const [Tab(text: '全部'), Tab(text: '活動'), Tab(text: '新聞')]),
      ),
      body: TabBarView(controller: _tabCtrl, children: [_buildList(_allItems, primary), _buildList(_eventItems, primary), _buildList(_newsItems, primary)]),
    );
  }
}

class _RealNewsCard extends StatelessWidget {
  final _RealNewsItem item; const _RealNewsCard({required this.item});
  void _showDetail(BuildContext context) {
    final (c, _) = _newsItemColor(item.location, item.isEvent);
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final dateRange = item.isEvent && (item.endDate?.isNotEmpty ?? false) ? '${item.date} ～ ${item.endDate}' : item.date;
    final cleanedSummary = _cleanHtml(item.summary);
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => DraggableScrollableSheet(initialChildSize: 0.75, maxChildSize: 0.95, builder: (ctx, scroll) => Container(decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))), child: ListView(controller: scroll, padding: EdgeInsets.zero, children: [
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 0), child: Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))))),
      if (hasImage) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(item.imageUrl!, height: 200, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(item.isEvent ? Icons.celebration_rounded : Icons.article_rounded, size: 13, color: c), const SizedBox(width: 4), Text(item.isEvent ? '活動' : '新聞', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700))])), const Spacer(), if (dateRange.isNotEmpty) Text(dateRange, style: const TextStyle(color: AppColors.textHint, fontSize: 12))]),
        const SizedBox(height: 12), Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.4)),
        if (item.location != null && item.location!.isNotEmpty) ...[const SizedBox(height: 8), Row(children: [const Icon(Icons.business_rounded, size: 13, color: AppColors.textHint), const SizedBox(width: 4), Expanded(child: Text(item.location!, style: const TextStyle(color: AppColors.textHint, fontSize: 12)))])],
        const SizedBox(height: 16),
        if (cleanedSummary.isNotEmpty) ...[const Divider(height: 1, color: AppColors.divider), const SizedBox(height: 16), SelectableText(cleanedSummary, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.85))]
        else ...[const Divider(height: 1, color: AppColors.divider), const SizedBox(height: 16), Text(item.isEvent ? '詳細活動資訊請點擊下方連結查看。' : '詳細新聞內容請點擊下方連結查看。', style: const TextStyle(fontSize: 15, color: AppColors.textHint, height: 1.85))],
        if (item.url != null && item.url!.isNotEmpty) ...[const SizedBox(height: 20), Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () async { final uri = Uri.tryParse(item.url!); if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('開啟連結'))), const SizedBox(width: 10), OutlinedButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: item.url!)); }, icon: const Icon(Icons.copy, size: 16), label: const Text('複製'))])]
      ]))
    ]))));
  }

  @override Widget build(BuildContext context) {
    final (c, iconData) = _newsItemColor(item.location, item.isEvent);
    return GestureDetector(onTap: () => _showDetail(context), child: StitchedBox(color: Color.lerp(c, Colors.white, 0.93)!, stitchColor: c.withValues(alpha: 0.35), radius: 16, inset: 4, dashWidth: 4, dashGap: 3, padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(iconData, size: 10, color: c), const SizedBox(width: 3), Text(item.isEvent ? '活動' : '新聞', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700))])), const Spacer(), Text(item.date, style: const TextStyle(fontSize: 10, color: AppColors.textHint))]),
      const SizedBox(height: 8),
      Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
      if ((item.location ?? '').isNotEmpty) ...[const SizedBox(height: 4), Text(item.location!, style: TextStyle(fontSize: 10, color: c.withValues(alpha: 0.7)), maxLines: 1, overflow: TextOverflow.ellipsis)],
    ])));
  }
}

// ═══════════════════════════════════════════════════════════════
//  TRANSPORT SCREEN  ─ 日記手繪風，搭配 AppColors 色票
// ═══════════════════════════════════════════════════════════════

// 每個交通種類的配色對（背景 pastel, 強調色）
const _kBusBg      = AppColors.cuteSky;        // #C4E1F0
const _kBusAcc     = AppColors.accentSky;      // #88B8C8
const _kYbBg       = AppColors.cuteMint;       // #C2E8D5
const _kYbAcc      = AppColors.primary;        // #5B8A5F
const _kTraBg      = AppColors.cuteLavender;   // #D8CCEC
const _kTraAcc     = Color(0xFF7B6BAE);        // soft purple
const _kAliBg      = AppColors.cuteLemon;      // #FFE9A8
const _kAliAcc     = AppColors.accentSand;     // #D4B896
const _kThsrBg     = AppColors.cutePeach;      // #FFD3C2
const _kThsrAcc    = AppColors.accentTerra;    // #C4856A

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

  // Bus
  String _busCity = 'Chiayi', _busRoute = '';
  String _busStopFilter = '';  // 站點名稱過濾
  final _busCtrl = TextEditingController();
  final _busStopCtrl = TextEditingController();
  Future<Map<String, dynamic>>? _busFuture;

  // YouBike
  Future<Map<String, dynamic>>? _ybFuture;
  String _ybSearch = '';

  // TRA
  Future<Map<String, dynamic>>? _traLive;
  List<Map<String, dynamic>>? _traTrains;
  bool _traLoading = false;
  String? _traError, _traUpdateTime;

  // Alishan
  List<Map<String, dynamic>>? _aliDocs;
  bool _aliLoading = false;

  // THSR
  List<Map<String, dynamic>>? _thsrTrains;
  bool _thsrLoading = false;
  String? _thsrError, _thsrUpdateTime;

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
  }

  Future<void> _fetchTra({bool auto = false}) async {
    if (_traO == _traD) { if (!auto) setState(() { _traTrains = []; _traLoading = false; _traError = '請選擇不同的起迄站'; }); return; }
    if (!mounted) return;
    if (!auto) setState(() { _traLoading = true; _traError = null; _traTrains = []; });
    try {
      final res = await RailService.queryTra(origin: _traO, dest: _traD, trainDate: _today);
      if (mounted) setState(() { _traTrains = (res['data'] as List).map((d) => Map<String, dynamic>.from(d as Map)).toList(); _traUpdateTime = res['updateTime'] as String?; _traLoading = false; });
    } catch (_) { if (mounted && !auto) setState(() { _traLoading = false; _traError = '無法連線，請稍候重試'; }); }
  }

  Future<void> _fetchThsr({bool auto = false}) async {
    if (_thsrO == _thsrD) { if (!auto) setState(() { _thsrTrains = []; _thsrLoading = false; _thsrError = '請選擇不同的起迄站'; }); return; }
    if (!mounted) return;
    if (!auto) setState(() { _thsrLoading = true; _thsrError = null; _thsrTrains = []; });
    try {
      final res = await RailService.queryThsr(origin: _thsrO, dest: _thsrD, trainDate: _today);
      if (mounted) setState(() { _thsrTrains = (res['data'] as List).map((d) => Map<String, dynamic>.from(d as Map)).toList(); _thsrUpdateTime = res['updateTime'] as String?; _thsrLoading = false; });
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
          _secs = 30;
          final i = _tabCtrl.index;
          if (i == 0 && _busRoute.isNotEmpty) _busFuture = RailService.getBusDynamic(_busCity, _busRoute);
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
    _busCtrl.dispose(); _busStopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.appPrimary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          DoodleLightning(color: primary.withValues(alpha: 0.7), size: 12),
          const SizedBox(width: 6),
          Text('交通動態', style: TextStyle(fontWeight: FontWeight.w800, color: primary)),
          const SizedBox(width: 6),
          DoodleHeart(color: primary.withValues(alpha: 0.5), size: 10),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: primary, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('${_secs.toString().padLeft(2,'0')} 秒', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: primary,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          tabs: const [
            Tab(icon: Icon(Icons.directions_bus_rounded, size: 18), text: '公車'),
            Tab(icon: Icon(Icons.pedal_bike_rounded, size: 18), text: 'YouBike'),
            Tab(icon: Icon(Icons.train_rounded, size: 18), text: '台鐵'),
            Tab(icon: Icon(Icons.forest_rounded, size: 18), text: '阿里山'),
            Tab(icon: Icon(Icons.directions_railway_filled_rounded, size: 18), text: '高鐵'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_builtBus(), _buildYb(), _buildTra(), _buildAli(), _buildThsr()],
      ),
    );
  }

  // ─── BUS ───────────────────────────────────────────────────────
  Widget _builtBus() {
    final chips = _busCity == 'Chiayi' ? ['中山幹線', '忠孝新民幹線', '光林我嘉線'] : ['7329', '7308', '7322'];
    return Column(children: [
      Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _CityToggle(value: _busCity, onChanged: (v) => setState(() { _busCity = v; _busRoute = ''; _busCtrl.clear(); _busStopCtrl.clear(); _busStopFilter = ''; _busFuture = null; })),
            const Spacer(),
            Text('支援全縣市公車', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          ]),
          const SizedBox(height: 10),
          // Route search
          TextField(
            controller: _busCtrl,
            decoration: InputDecoration(
              hintText: '輸入路線名稱（如：中山幹線）',
              prefixIcon: const Icon(Icons.directions_bus_rounded, size: 18),
              suffixIcon: _busCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () => setState(() { _busCtrl.clear(); _busRoute = ''; _busStopCtrl.clear(); _busStopFilter = ''; _busFuture = null; })) : null,
            ),
            onSubmitted: (v) { if (v.trim().isNotEmpty) setState(() { _busRoute = v.trim(); _busStopFilter = ''; _busStopCtrl.clear(); _busFuture = RailService.getBusDynamic(_busCity, _busRoute); }); },
          ),
          // Stop filter (only shows when route loaded)
          if (_busFuture != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _busStopCtrl,
              decoration: InputDecoration(
                hintText: '🔍 站點名稱過濾（如：文化路）',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _busStopFilter.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () => setState(() { _busStopCtrl.clear(); _busStopFilter = ''; })) : null,
              ),
              onChanged: (v) => setState(() => _busStopFilter = v.trim()),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: chips.map((c) => GestureDetector(
            onTap: () => setState(() { _busCtrl.text = c; _busRoute = c; _busStopCtrl.clear(); _busStopFilter = ''; _busFuture = RailService.getBusDynamic(_busCity, _busRoute); }),
            child: StitchedBox(
              color: Color.lerp(_kBusBg, Colors.white, 0.3)!,
              stitchColor: _kBusAcc.withValues(alpha: 0.45),
              radius: 20, inset: 3, dashWidth: 3, dashGap: 2.5,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
          )).toList()),
        ]),
      ),
      Expanded(child: _busFuture == null
          ? _Hint(icon: Icons.directions_bus_rounded, color: _kBusAcc, text: '輸入路線名稱查詢即時公車資訊')
          : FutureBuilder<Map<String, dynamic>>(
              future: _busFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                if (!snap.hasData || snap.hasError)
                  return _Hint(icon: Icons.wifi_off_rounded, color: _kBusAcc, text: '無法取得資料，請稍後重試');
                var all = (snap.data!['data'] as List? ?? []).cast<Map<String, dynamic>>();
                if (all.isEmpty) return _Hint(icon: Icons.search_off_rounded, color: _kBusAcc, text: '查無「$_busRoute」的即時資訊');

                // Dedup by direction + StopUID
                final seen = <String>{};
                all = all.where((s) => seen.add('${s['Direction']}:${s['StopUID'] ?? s['StopName']}')).toList();

                // Stop name filter
                if (_busStopFilter.isNotEmpty) {
                  all = all.where((s) => (s['StopName'] as String? ?? '').contains(_busStopFilter)).toList();
                }

                final dir0 = (all.where((s) => (s['Direction'] as int? ?? 0) == 0).toList()..sort((a, b) => (a['StopSequence'] as int? ?? 0).compareTo(b['StopSequence'] as int? ?? 0)));
                final dir1 = (all.where((s) => (s['Direction'] as int? ?? 0) == 1).toList()..sort((a, b) => (a['StopSequence'] as int? ?? 0).compareTo(b['StopSequence'] as int? ?? 0)));

                if (dir0.isEmpty && dir1.isEmpty)
                  return _Hint(icon: Icons.search_off_rounded, color: _kBusAcc, text: '站點「$_busStopFilter」不在此路線內');

                return ListView(padding: const EdgeInsets.all(14), children: [
                  if ((snap.data!['updateTime'] as String? ?? '').isNotEmpty)
                    _UpdTime(snap.data!['updateTime'] as String),
                  if (dir0.isNotEmpty) ...[_BusCard(stops: dir0, onSwitchTab: widget.onSwitchTab), const SizedBox(height: 12)],
                  if (dir1.isNotEmpty) _BusCard(stops: dir1, onSwitchTab: widget.onSwitchTab),
                ]);
              },
            )),
    ]);
  }

  // ─── YOUBIKE ───────────────────────────────────────────────────
  Widget _buildYb() {
    return Column(children: [
      Container(color: AppColors.surface, padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: TextField(
        decoration: const InputDecoration(hintText: '搜尋站點名稱...', prefixIcon: Icon(Icons.search_rounded, size: 18)),
        onChanged: (v) => setState(() => _ybSearch = v),
      )),
      Expanded(child: _ybFuture == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<Map<String, dynamic>>(
              future: _ybFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) return const Center(child: CircularProgressIndicator());
                final all = (snap.data?['data'] as List? ?? []).cast<Map<String, dynamic>>();
                if (all.isEmpty) return const Center(child: Text('目前沒有車位資料'));
                final stations = _ybSearch.trim().isEmpty ? all : all.where((s) => (s['station_name'] ?? s['station_uid'] ?? '').toString().contains(_ybSearch.trim())).toList();
                return Column(children: [
                  if ((snap.data!['updateTime'] as String? ?? '').isNotEmpty)
                    Padding(padding: const EdgeInsets.fromLTRB(16,8,16,2), child: _UpdTime(snap.data!['updateTime'] as String, end: true)),
                  Expanded(child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    itemCount: stations.length,
                    itemBuilder: (ctx, i) {
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
                            color: Color.lerp(_kYbBg, Colors.white, 0.45)!,
                            stitchColor: _kYbAcc.withValues(alpha: 0.35),
                            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              Container(width: 42, height: 42, decoration: BoxDecoration(color: _kYbAcc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.pedal_bike_rounded, size: 22, color: _kYbAcc)),
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
                                Text('可借 $total 輛', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: good ? _kYbAcc : AppColors.error)),
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
    return ListView(padding: const EdgeInsets.all(14), children: [
      _ODCard(origin: _traO, dest: _traD, stations: _traStations.keys.toList(), bg: _kTraBg, acc: _kTraAcc,
        onO: (v) { setState(() { _traO = v; _traLive = RailService.getTraLiveBoard(_traStations[v]!); }); _fetchTra(); },
        onD: (v) { setState(() => _traD = v); _fetchTra(); },
        onSwap: () { setState(() { final t = _traO; _traO = _traD; _traD = t; _traLive = RailService.getTraLiveBoard(_traStations[_traO]!); }); _fetchTra(); },
      ),
      const SizedBox(height: 12),
      if (_traLive != null) FutureBuilder<Map<String, dynamic>>(
        future: _traLive,
        builder: (ctx, snap) {
          final trains = (snap.data?['data'] as List? ?? []);
          final upd = snap.data?['updateTime'] as String? ?? '';
          return _LiveBoard(station: _traO, trains: trains, updateTime: upd);
        },
      ),
      const SizedBox(height: 12),
      if (_traLoading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else if (_traError != null) Center(child: Text(_traError!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)))
      else if (_traTrains == null || _traTrains!.isEmpty)
        _Hint(icon: Icons.train_rounded, color: _kTraAcc, text: '此區間今日無直達班次')
      else ...[
        if ((_traUpdateTime ?? '').isNotEmpty) _UpdTime(_traUpdateTime!),
        const SizedBox(height: 4),
        ..._traTrains!.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RailCard(no: t['train_no']?.toString() ?? '', type: t['train_type_name']?.toString() ?? '', dep: t['departure_time']?.toString() ?? '', arr: t['arrival_time']?.toString() ?? '', origin: _traO, dest: _traD, date: _today, isThsr: false, stops: t['stops'] is List ? (t['stops'] as List) : []),
        )),
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
          final stops = (raw as List).map((s) => Map<dynamic, dynamic>.from(s as Map)).toList()
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
      _ODCard(origin: _aliO, dest: _aliD, stations: _aliStations, bg: _kAliBg, acc: _kAliAcc,
        onO: (v) => setState(() => _aliO = v), onD: (v) => setState(() => _aliD = v),
        onSwap: () => setState(() { final t = _aliO; _aliO = _aliD; _aliD = t; }),
      ),
      const SizedBox(height: 12),
      if (_aliLoading) const Center(child: CircularProgressIndicator())
      else if (_aliO == _aliD) Center(child: Text('請選擇不同的起迄站', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)))
      else if (valid.isEmpty) _Hint(icon: Icons.forest_rounded, color: _kAliAcc, text: '此區間今日無直達班次')
      else ...valid.map((t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _AliCard(train: t, origin: _aliO, dest: _aliD))),
    ]);
  }

  // ─── THSR ──────────────────────────────────────────────────────
  Widget _buildThsr() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      _ODCard(origin: _thsrO, dest: _thsrD, stations: _thsrStations.keys.toList(), bg: _kThsrBg, acc: _kThsrAcc,
        onO: (v) { setState(() => _thsrO = v); _fetchThsr(); },
        onD: (v) { setState(() => _thsrD = v); _fetchThsr(); },
        onSwap: () { setState(() { final t = _thsrO; _thsrO = _thsrD; _thsrD = t; }); _fetchThsr(); },
      ),
      const SizedBox(height: 12),
      if (_thsrLoading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else if (_thsrError != null) Center(child: Text(_thsrError!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)))
      else if (_thsrTrains == null || _thsrTrains!.isEmpty)
        _Hint(icon: Icons.directions_railway_filled_rounded, color: _kThsrAcc, text: '此區間今日無直達班次')
      else ...[
        if ((_thsrUpdateTime ?? '').isNotEmpty) _UpdTime(_thsrUpdateTime!),
        const SizedBox(height: 4),
        ..._thsrTrains!.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RailCard(no: t['TrainNo']?.toString() ?? '', type: '高鐵', dep: t['DepartureTime']?.toString() ?? '', arr: t['ArrivalTime']?.toString() ?? '', origin: _thsrO, dest: _thsrD, date: _today, isThsr: true, stops: t['stops'] is List ? (t['stops'] as List) : []),
        )),
      ],
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
    if (trains.isEmpty) {
      return StitchedBox(
        color: Color.lerp(_kTraBg, Colors.white, 0.55)!,
        stitchColor: _kTraAcc.withValues(alpha: 0.35),
        radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 15, color: _kTraAcc),
          const SizedBox(width: 8),
          Text('$station 目前暫無即時進站資訊', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      );
    }
    return StitchedBox(
      color: Color.lerp(_kTraBg, Colors.white, 0.4)!,
      stitchColor: _kTraAcc.withValues(alpha: 0.4),
      radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.departure_board_rounded, size: 16, color: _kTraAcc),
          const SizedBox(width: 6),
          Text('$station 即將進站', style: TextStyle(color: _kTraAcc, fontWeight: FontWeight.w800, fontSize: 13)),
          const Spacer(),
          if (updateTime.isNotEmpty) Text(updateTime, style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
        ]),
        Divider(color: _kTraAcc.withValues(alpha: 0.2), height: 14),
        ...trains.map((t) {
          final delay = t['delay_time'] as int? ?? 0;
          return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            Expanded(flex: 3, child: Text('${t['train_type_name'] ?? ''} ${t['train_no'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
            Expanded(flex: 1, child: Text(t['direction'] == 0 ? '順行' : '逆行', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
            Text(_formatTime(t['schedule_departure_time']?.toString() ?? ''), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _kTraAcc)),
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

  String _etaText(Map s) {
    final status = s['StopStatus'] as int? ?? 0;
    final eta = s['EstimateTime'] as int?;
    if (status == 1) return '尚未發車';
    if (status == 2) return '交管停靠';
    if (status == 3) return '末班已過';
    if (status == 4) return '今日停駛';
    if (eta == null) return '資料更新中';
    if (eta == 0) return '進站中';
    final m = eta ~/ 60;
    return m <= 1 ? '即將進站' : '$m 分鐘';
  }

  Color _etaColor(Map s) {
    final status = s['StopStatus'] as int? ?? 0;
    if (status != 0) return AppColors.textHint;
    final eta = s['EstimateTime'] as int? ?? 9999;
    if (eta <= 60) return AppColors.success;
    if (eta <= 300) return AppColors.warning;
    return _kBusAcc;
  }

  bool _showPlate(Map s) {
    if ((s['StopStatus'] as int? ?? 0) != 0) return false;
    final eta = s['EstimateTime'] as int? ?? 9999;
    final plate = s['PlateNumb'] as String? ?? '';
    return eta <= 120 && plate.isNotEmpty && plate != '尚未發車' && plate != '-1';
  }

  @override Widget build(BuildContext context) {
    final stops = widget.stops;
    final dir = (stops.first['Direction'] as int? ?? 0) == 0 ? '去程' : '返程';
    final origin = stops.first['StopName'] as String? ?? '起點';
    final dest = stops.last['StopName'] as String? ?? '終點';

    return StitchedBox(
      color: Color.lerp(_kBusBg, Colors.white, 0.45)!,
      stitchColor: _kBusAcc.withValues(alpha: 0.35),
      radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(padding: const EdgeInsets.fromLTRB(14, 13, 12, 13), child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _kBusAcc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: Text(dir, style: TextStyle(color: _kBusAcc, fontSize: 11, fontWeight: FontWeight.w700))),
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
            Divider(height: 1, color: _kBusAcc.withValues(alpha: 0.15)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Column(children: List.generate(stops.length, (i) {
                final s = stops[i];
                final isLast = i == stops.length - 1;
                final etaText = _etaText(s);
                final etaColor = _etaColor(s);
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
                      Expanded(child: Text(s['StopName'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: imminent ? FontWeight.w800 : FontWeight.w500, color: imminent ? AppColors.textPrimary : AppColors.textSecondary))),
                      const SizedBox(width: 8),
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
          ],
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

// 膠帶顏色循環（模擬圖片中每張卡片不同顏色的膠帶）
const _kTapeColors = [
  Color(0xFFFFC1C1), // 粉紅
  Color(0xFFFFD9A0), // 橙黃
  Color(0xFFC8E6C9), // 薄荷綠
  Color(0xFFCFD8FF), // 薰衣草藍
  Color(0xFFFFECB3), // 奶油黃
  Color(0xFFB2EBF2), // 天空藍
];

class _RailCardState extends State<_RailCard> {
  bool _expanded = false;
  bool _starred = false;
  List<dynamic>? _stops;
  bool _loading = false;

  Color get _acc {
    if (widget.isThsr) return _kThsrAcc;
    final t = widget.type;
    if (t.contains('自強')) return const Color(0xFFBF4040);
    if (t.contains('太魯閣')) return AppColors.accentSky;
    if (t.contains('普悠瑪')) return const Color(0xFF7B5FAE);
    if (t.contains('莒光')) return AppColors.primary;
    return _kTraAcc;
  }
  Color get _bg => widget.isThsr ? _kThsrBg : _kTraBg;

  // 依班次號碼決定膠帶顏色（穩定不隨刷新改變）
  Color get _tapeColor {
    final idx = (int.tryParse(widget.no.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) % _kTapeColors.length;
    return _kTapeColors[idx];
  }

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
    final stops = widget.train['stops'] as List<dynamic>? ?? [];
    return StitchedBox(
      color: Color.lerp(_kAliBg, Colors.white, 0.45)!,
      stitchColor: _kAliAcc.withValues(alpha: 0.4),
      radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: [
          Container(height: 4, decoration: const BoxDecoration(color: _kAliAcc, borderRadius: BorderRadius.vertical(top: Radius.circular(15)))),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: _kAliAcc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('🚃', style: TextStyle(fontSize: 16)),
                Text(widget.train['no']?.toString() ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w800)),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: _kAliAcc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: const Text('觀光列車', style: TextStyle(color: _kAliAcc, fontSize: 10, fontWeight: FontWeight.w700))), const Spacer(), Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.textHint)]),
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
            Divider(height: 1, color: _kAliAcc.withValues(alpha: 0.15)),
            Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 16), child: Column(children: stops.map((s) {
              final name = (s['StationName'] ?? s['stationName'] ?? '').toString();
              final time = _formatTime((s['ArrivalTime'] ?? s['arrivalTime'] ?? '').toString());
              final isTarget = name.contains(widget.origin) || name.contains(widget.dest);
              final isLast = s == stops.last;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 18, child: Column(children: [
                  Container(width: isTarget ? 13 : 9, height: isTarget ? 13 : 9, decoration: BoxDecoration(shape: BoxShape.circle, color: isTarget ? _kAliAcc : Colors.white, border: Border.all(color: isTarget ? _kAliAcc : AppColors.divider, width: isTarget ? 2.5 : 1.5))),
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