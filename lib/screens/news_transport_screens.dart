import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'search_screen.dart';

// ═══════════════════════════════════════════════════
//  Shared news item (government open data)
// ═══════════════════════════════════════════════════
class _RealNewsItem {
  final String title;
  final String date;
  final String? summary;
  final String? location;   // PostUnit (發布/主辦單位)
  final String? url;        // Source link
  final String? imageUrl;   // Pic / Thumbnail
  final String? endDate;    // ActiveEnd (events only)
  final bool isEvent; // true = 活動, false = 新聞
  const _RealNewsItem({
    required this.title, required this.date,
    this.summary, this.location, this.url, this.imageUrl, this.endDate,
    required this.isEvent,
  });
}

// ── HTML / entity cleaner ──────────────────────
String _cleanHtml(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  var s = raw;
  // Decode common HTML entities
  s = s.replaceAll('&nbsp;',  ' ');
  s = s.replaceAll('&amp;',   '&');
  s = s.replaceAll('&lt;',    '<');
  s = s.replaceAll('&gt;',    '>');
  s = s.replaceAll('&quot;',  '"');
  s = s.replaceAll('&#39;',   "'");
  s = s.replaceAll('&hellip;','…');
  s = s.replaceAll('&mdash;', '—');
  s = s.replaceAll('&ndash;', '–');
  // Strip HTML tags
  s = s.replaceAll(RegExp(r'<br\s*/?>',    caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</?p[^>]*>',   caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'),      '');
  // Collapse runs of spaces/tabs (keep newlines)
  s = s.replaceAll(RegExp(r'[ \t]{2,}'),   ' ');
  // Collapse 3+ consecutive newlines into two (paragraph break)
  s = s.replaceAll(RegExp(r'\n{3,}'),      '\n\n');
  return s.trim();
}

// ── News cache JSON helpers ────────────────────────────────
Map<String, dynamic> _realNewsItemToJson(_RealNewsItem n) => {
  'title': n.title, 'date': n.date, 'summary': n.summary,
  'location': n.location, 'url': n.url, 'imageUrl': n.imageUrl,
  'endDate': n.endDate, 'isEvent': n.isEvent,
};
_RealNewsItem _realNewsItemFromJson(Map<String, dynamic> m) => _RealNewsItem(
  title:    m['title']    as String? ?? '',
  date:     m['date']     as String? ?? '',
  summary:  m['summary']  as String?,
  location: m['location'] as String?,
  url:      m['url']      as String?,
  imageUrl: m['imageUrl'] as String?,
  endDate:  m['endDate']  as String?,
  isEvent:  m['isEvent']  as bool?   ?? false,
);

// ════════════════════════════════════════════════
// NEWS SCREEN — real government API data
// ════════════════════════════════════════════════
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen>
    with SingleTickerProviderStateMixin {
  static const _eventsUrl =
      'https://data.chiayi.gov.tw/opendata/api/getResource'
      '?oid=33c3225e-f786-4eaf-8b9c-774cc39c72e0'
      '&rid=a809167f-bba6-475d-9dfe-33b4ea7749f6';
  static const _newsUrl =
      'https://data.chiayi.gov.tw/opendata/api/getResource'
      '?oid=6dcaf207-e99b-4846-bd72-c334ce0d4b59'
      '&rid=87d4b27c-07c3-4546-815d-1e733dfd9497';

  // ── Cache ─────────────────────────────────────────────────
  static const _kCacheKey   = 'news_screen_v1';
  static const _kCacheTsKey = 'news_screen_ts_v1';
  static const _kCacheTTLMs = 30 * 60 * 1000; // 30 minutes

  late final TabController _tabCtrl;
  List<_RealNewsItem> _all  = [];
  bool _loading  = true;
  bool _hasError = false;

  List<_RealNewsItem> get _allItems   => _all;
  List<_RealNewsItem> get _eventItems => _all.where((n) => n.isEvent).toList();
  List<_RealNewsItem> get _newsItems  => _all.where((n) => !n.isEvent).toList();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted) return;

    final prefs  = await SharedPreferences.getInstance();
    final ts     = prefs.getInt(_kCacheTsKey) ?? 0;
    final cached = prefs.getString(_kCacheKey);
    final age    = DateTime.now().millisecondsSinceEpoch - ts;

    // ── Show cached data instantly (no spinner) ───────────────────────────
    if (cached != null && cached.isNotEmpty) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((m) => _realNewsItemFromJson(m as Map<String, dynamic>))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() { _all = list; _loading = false; _hasError = false; });
          if (age < _kCacheTTLMs) return; // cache still fresh — skip network
          // cache stale: fall through and refresh silently
        }
      } catch (_) { /* corrupt cache — fall through */ }
    }

    // ── Network fetch ─────────────────────────────────────────────────────
    if (mounted && _all.isEmpty) setState(() { _loading = true; _hasError = false; });

    try {
      final results = await Future.wait([
        _fetchOne(_eventsUrl, isEvent: true),
        _fetchOne(_newsUrl,   isEvent: false),
      ]).timeout(const Duration(seconds: 12));
      final combined = [...results[0], ...results[1]]
        ..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() { _all = combined; _loading = false; _hasError = false; });
      // ── Persist to cache ───────────────────────────────────────────────
      try {
        await prefs.setString(_kCacheKey,
            jsonEncode(combined.map(_realNewsItemToJson).toList()));
        await prefs.setInt(_kCacheTsKey, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    } catch (_) {
      if (mounted && _all.isEmpty) setState(() { _hasError = true; _loading = false; });
      // If we have cached data already, fail silently (don't overwrite good data)
    }
  }

  Future<List<_RealNewsItem>> _fetchOne(
      String url, {required bool isEvent}) async {
    try {
      final res = await http.get(Uri.parse(url),
          headers: {'Accept': 'application/json'});
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map) {
        final r = data['result'];
        if (r is List) list = r;
        else if (r is Map && r['records'] is List) list = r['records'] as List;
        else if (data['records'] is List) list = data['records'] as List;
        else list = [];
      } else list = [];
      return list.whereType<Map>().map((m) {
        final raw = Map<String, dynamic>.from(m);
        String? pick(List<String> keys) {
          for (final k in keys) {
            final v = raw[k];
            if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
          }
          return null;
        }
        // Events:  Source, title, Content, PostUnit, ActiveStart, ActiveEnd, File, Pic, Thumbnail
        // News:    Source, title, Content, PostDate, PostUnit, File, Pic, Thumbnail
        return _RealNewsItem(
          title:    pick(['title','標題','活動名稱','名稱','Title','Subject']) ?? '無標題',
          date:     isEvent
              ? pick(['ActiveStart','發布日期','活動開始日期','日期','date','Date','建立時間']) ?? ''
              : pick(['PostDate','發布日期','日期','date','Date','PublishDate','建立時間']) ?? '',
          endDate:  isEvent ? pick(['ActiveEnd']) : null,
          summary:  pick(['Content','內容','摘要','描述','活動說明','summary','content','description']),
          location: pick(['PostUnit','發布單位','主辦單位','活動地點','地點','location','venue']),
          url:      pick(['Source','連結','url','URL','link','詳細連結','WebUrl']),
          imageUrl: pick(['Pic','Thumbnail','圖片','pic','thumbnail']),
          isEvent:  isEvent,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Widget _buildList(List<_RealNewsItem> items, Color primary) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5));
    }
    if (_hasError) return _ErrorView(onRetry: _fetch, primary: primary);
    if (items.isEmpty) {
      return const Center(
        child: Text('目前無相關消息', style: TextStyle(color: AppColors.textHint, fontSize: 14)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _RealNewsCard(item: items[i], primary: primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('最新消息',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          if (_hasError)
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _fetch),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '活動'),
            Tab(text: '新聞'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildList(_allItems,   primary),
          _buildList(_eventItems, primary),
          _buildList(_newsItems,  primary),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final Color primary;
  const _ErrorView({required this.onRetry, required this.primary});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('📡', style: TextStyle(fontSize: 40)),
      const SizedBox(height: 12),
      const Text('載入失敗', style: TextStyle(
          color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('請確認網路連線後重試',
          style: TextStyle(color: AppColors.textHint, fontSize: 13)),
      const SizedBox(height: 18),
      ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('重試'),
        style: ElevatedButton.styleFrom(backgroundColor: primary),
      ),
    ]),
  );
}

class _RealNewsCard extends StatelessWidget {
  final _RealNewsItem item;
  final Color primary;
  const _RealNewsCard({required this.item, required this.primary});

  Color get _catColor =>
      item.isEvent ? const Color(0xFF00838F) : const Color(0xFF1565C0);
  String get _catEmoji => item.isEvent ? '🏮' : '📰';
  String get _catLabel => item.isEvent ? '活動' : '新聞';

  @override
  Widget build(BuildContext context) {
    final c         = _catColor;
    final hasImage  = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final dateRange = item.isEvent && (item.endDate?.isNotEmpty ?? false)
        ? '${item.date} ～ ${item.endDate}'
        : item.date;
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail (if available)
            if (hasImage)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: Image.network(
                  item.imageUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hasImage)
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: Text(_catEmoji,
                              style: const TextStyle(fontSize: 24))),
                    ),
                  if (!hasImage) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                                color: c.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(_catLabel,
                                style: TextStyle(
                                    color: c,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          if (dateRange.isNotEmpty)
                            Text(
                                dateRange.length > 10
                                    ? dateRange.substring(0, 10)
                                    : dateRange,
                                style: const TextStyle(
                                    fontSize: 10, color: AppColors.textHint)),
                        ]),
                        const SizedBox(height: 6),
                        Text(item.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                                height: 1.4),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (item.location != null &&
                            item.location!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.business_rounded,
                                size: 11, color: AppColors.textHint),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(item.location!,
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.textHint),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Split cleaned text into paragraph widgets with proper spacing.
  List<Widget> _buildParagraphs(String text) {
    if (text.isEmpty) return [];
    final paras = text.split('\n\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final widgets = <Widget>[];
    for (int i = 0; i < paras.length; i++) {
      widgets.add(Text(
        paras[i],
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textSecondary,
          height: 1.9,
          letterSpacing: 0.2,
        ),
      ));
      if (i < paras.length - 1) widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  void _showDetail(BuildContext context) {
    final c         = _catColor;
    final hasImage  = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final dateRange = item.isEvent && (item.endDate?.isNotEmpty ?? false)
        ? '${item.date} ～ ${item.endDate}'
        : item.date;
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
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
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
                        borderRadius: BorderRadius.circular(2))),
                ),
              ),
              // Thumbnail image
              if (hasImage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      item.imageUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badge + date
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(children: [
                            Text(_catEmoji,
                                style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 4),
                            Text(_catLabel,
                                style: TextStyle(
                                    color: c,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ])),
                      const Spacer(),
                      if (dateRange.isNotEmpty)
                        Text(dateRange,
                            style: const TextStyle(
                                color: AppColors.textHint, fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    // Title
                    Text(item.title,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.4)),
                    // PostUnit (發布單位)
                    if (item.location != null && item.location!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.business_rounded,
                            size: 13, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(item.location!,
                                style: const TextStyle(
                                    color: AppColors.textHint, fontSize: 12))),
                      ]),
                    ],
                    const SizedBox(height: 16),
                    // Content
                    if (item.summary != null && item.summary!.isNotEmpty) ...[
                      const Divider(height: 1, color: AppColors.divider),
                      const SizedBox(height: 16),
                      ..._buildParagraphs(_cleanHtml(item.summary)),
                    ] else ...[
                      const Divider(height: 1, color: AppColors.divider),
                      const SizedBox(height: 16),
                      Text(
                          item.isEvent
                              ? '詳細活動資訊請點擊下方連結查看。'
                              : '詳細新聞內容請點擊下方連結查看。',
                          style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textHint,
                              height: 1.85)),
                    ],
                    // Source link
                    if (item.url != null && item.url!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.tryParse(item.url!);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('閱讀完整內容'),
                      ),
                    ],
                  ],
                ),
              ),
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
  String _busDest = '全部終點';
  String _busSearch = '';

  // YouBike state
  String _youbikeSearch = '';

  // Train station
  String _trainStation = '嘉義';
  String _trainSearch = '';

  // Alishan state
  String _alishanRoute = '嘉義 → 阿里山';

  // THSR state
  String _thsrDirection     = '北上';
  bool   _thsrShowTimetable = false;  // toggle today ↔ full timetable

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));
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
          Builder(builder: (bCtx) {
            final p = Theme.of(bCtx).colorScheme.primary;
            final mist = Color.lerp(p, Colors.white, 0.88)!;
            return Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: mist,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 7, height: 7,
                    decoration: BoxDecoration(color: p, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(_countdownText,
                    style: TextStyle(fontSize: 11, color: p, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ],
        bottom: TabBar(
          controller: _tabController,
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
        controller: _tabController,
        children: [
          _buildBusTab(),
          _buildYouBikeTab(),
          _buildTrainTab(),
          _buildAlishanTab(),
          _buildThsrTab(),
        ],
      ),
    );
  }

  // ── BUS TAB ──
  Widget _buildBusTab() {
    final allStops = ['嘉義火車站', '文化路', '嘉義公園', '嘉義高中', '中山路', '東市場', '竹崎', '奮起湖', '阿里山', '太保市', '故宮南院'];
    final allDests = ['全部終點', '文化路', '嘉義公園', '東市場', '阿里山', '故宮南院'];

    final busData = [
      _BusRoute(route:'紅幹線', from:'嘉義火車站', to:'東市場', etaMin:3,
        stops:['嘉義火車站','中正路口','文化路','東市場'], color:const Color(0xFFC4856A), current:'中正路口', progress:0.35),
      _BusRoute(route:'藍幹線', from:'嘉義火車站', to:'嘉義公園', etaMin:8,
        stops:['嘉義火車站','林森路','嘉義公園'], color:const Color(0xFF88B8C8), current:'林森路', progress:0.55),
      _BusRoute(route:'101', from:'嘉義火車站', to:'阿里山', etaMin:45,
        stops:['嘉義火車站','竹崎','奮起湖','阿里山'], color:Theme.of(context).colorScheme.primary, current:'竹崎', progress:0.25),
      _BusRoute(route:'7218', from:'嘉義火車站', to:'故宮南院', etaMin:22,
        stops:['嘉義火車站','太保市','故宮南院'], color:const Color(0xFF8F7DB8), current:'太保市', progress:0.50),
    ];

    // Filter: route must pass through both origin AND destination
    final q = _busSearch.trim();
    final filtered = busData.where((b) {
      final matchFrom = b.stops.any((s) => s.contains(_busFrom));
      final matchDest = _busDest == '全部終點' || b.stops.any((s) => s.contains(_busDest));
      final matchSearch = q.isEmpty || b.route.contains(q) || b.from.contains(q) || b.to.contains(q)
          || b.stops.any((s) => s.contains(q)) || b.current.contains(q);
      // Check that origin comes before destination in the route
      final fromIdx = b.stops.indexWhere((s) => s.contains(_busFrom));
      final destIdx = _busDest == '全部終點' ? 999 : b.stops.indexWhere((s) => s.contains(_busDest));
      final orderOk = _busDest == '全部終點' || (fromIdx >= 0 && destIdx >= 0 && fromIdx <= destIdx);
      return matchFrom && matchDest && matchSearch && orderOk;
    }).toList();

    return Column(
      children: [
        // From / To + swap
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            Expanded(
              child: _dropdownBox('🚏 出發站', _busFrom, allStops,
                (v) => setState(() => _busFrom = v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GestureDetector(
                onTap: () {
                  if (_busDest != '全部終點') {
                    final tmp = _busFrom;
                    setState(() { _busFrom = _busDest; _busDest = tmp; });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.88)!, shape: BoxShape.circle),
                  child: Icon(Icons.swap_horiz_rounded, color: Theme.of(context).colorScheme.primary, size: 18),
                ),
              ),
            ),
            Expanded(
              child: _dropdownBox('🏁 目的地', _busDest, allDests,
                (v) => setState(() => _busDest = v)),
            ),
          ]),
        ),
        // Search bar
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
    final primary = Theme.of(context).colorScheme.primary;
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
                trailing: s == value ? Icon(Icons.check_rounded, color: primary) : null,
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
    final etaColor = eta <= 5 ? AppColors.error : eta <= 15 ? AppColors.warning : Theme.of(context).colorScheme.primary;

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
                Text('後到站', style: TextStyle(fontSize: 10, color: etaColor.withValues(alpha: 0.7))),
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
    final allStations = [
      {'name':'嘉義火車站', 'available':8, 'empty':4, 'dist':'0.1km', 'update':'1分鐘前'},
      {'name':'文化路夜市口', 'available':3, 'empty':9, 'dist':'0.3km', 'update':'2分鐘前'},
      {'name':'嘉義公園', 'available':12, 'empty':2, 'dist':'0.5km', 'update':'剛剛'},
      {'name':'嘉義高中', 'available':0, 'empty':14, 'dist':'0.7km', 'update':'3分鐘前'},
      {'name':'嘉義市立美術館', 'available':6, 'empty':6, 'dist':'0.9km', 'update':'1分鐘前'},
      {'name':'故宮南院', 'available':15, 'empty':3, 'dist':'4.2km', 'update':'剛剛'},
      {'name':'嘉義大學', 'available':5, 'empty':7, 'dist':'1.1km', 'update':'2分鐘前'},
      {'name':'北門車站', 'available':2, 'empty':10, 'dist':'1.5km', 'update':'1分鐘前'},
    ];

    final q = _youbikeSearch.trim().toLowerCase();
    final stations = q.isEmpty
        ? allStations
        : allStations.where((s) => (s['name'] as String).toLowerCase().contains(q)).toList();

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜尋站點名稱...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _youbikeSearch.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () => setState(() => _youbikeSearch = ''))
                : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onChanged: (v) => setState(() => _youbikeSearch = v),
          ),
        ),
      Expanded(child: stations.isEmpty
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('🔍', style: TextStyle(fontSize: 40)),
            SizedBox(height: 12),
            Text('找不到符合的站點', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          ]))
        : ListView(
          padding: const EdgeInsets.all(14),
          children: [
        _infoTip('YouBike 站點資訊即時更新，顯示距離為直線距離'),
        const SizedBox(height: 10),
        ...stations.map((s) {
          final available = s['available'] as int;
          final empty = s['empty'] as int;
          final total = available + empty;
          final ratio = total > 0 ? available / total : 0.0;
          final statusColor = available > 5 ? Theme.of(context).colorScheme.primary
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
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
        ),
      ),
    ],
    );
  }

  // ── TRAIN TAB ──
  Widget _buildTrainTab() {
    // All TRA stations in Chiayi County/City (+ neighboring stations for context)
    const chiayiStations = [
      '大林', '民雄', '嘉義', '水上', '南靖',
    ];
    final allStations = ['嘉義','大林','民雄','水上','南靖','新營','台南','高雄','台中','台北'];

    final allBound = [
      _Train(no:'自強 108', type:'自強', from:'嘉義', to:'台北', dep:'14:05', arr:'16:52', delay:0, stops:['嘉義','台中','板橋','台北']),
      _Train(no:'太魯閣 224', type:'太魯閣', from:'嘉義', to:'花蓮', dep:'15:30', arr:'18:55', delay:5, stops:['嘉義','台中','台北','花蓮']),
      _Train(no:'莒光 222', type:'莒光', from:'嘉義', to:'台北', dep:'16:15', arr:'20:10', delay:0, stops:['嘉義','民雄','大林','斗六','彰化','台中','台北']),
      _Train(no:'自強 109', type:'自強', from:'嘉義', to:'高雄', dep:'14:02', arr:'15:08', delay:0, stops:['嘉義','水上','南靖','新營','台南','高雄']),
      _Train(no:'自強 113', type:'自強', from:'嘉義', to:'潮州', dep:'15:45', arr:'17:20', delay:3, stops:['嘉義','台南','高雄','鳳山','潮州']),
      _Train(no:'莒光 105', type:'莒光', from:'嘉義', to:'台南', dep:'11:30', arr:'12:20', delay:0, stops:['嘉義','水上','南靖','後壁','台南']),
      _Train(no:'區間 2311', type:'區間', from:'民雄', to:'台南', dep:'13:20', arr:'15:05', delay:0, stops:['民雄','嘉義','水上','南靖','新營','台南']),
      _Train(no:'區間 2215', type:'區間', from:'大林', to:'嘉義', dep:'12:45', arr:'13:10', delay:0, stops:['大林','民雄','嘉義']),
    ];

    // Filter by selected station (trains that stop at this station)
    final trainFiltered = allBound.where((t) {
      final stationMatch = t.stops.contains(_trainStation);
      final searchMatch = _trainSearch.isEmpty ||
          t.no.contains(_trainSearch) || t.stops.any((s) => s.contains(_trainSearch));
      return stationMatch && searchMatch;
    }).toList();

    final northbound = trainFiltered.where((t) {
      final fromIdx = t.stops.indexOf(_trainStation);
      final northDests = ['台中','板橋','台北','花蓮'];
      return northDests.any((d) {
        final dIdx = t.stops.indexOf(d);
        return dIdx > fromIdx && dIdx >= 0;
      });
    }).toList();

    final southbound = trainFiltered.where((t) {
      final fromIdx = t.stops.indexOf(_trainStation);
      final southDests = ['台南','高雄','鳳山','潮州'];
      return southDests.any((d) {
        final dIdx = t.stops.indexOf(d);
        return dIdx > fromIdx && dIdx >= 0;
      });
    }).toList();

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.train_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                const Text('起點站：', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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
              // Chiayi station chips
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: chiayiStations.map((s) {
                final sel = s == _trainStation;
                return GestureDetector(
                  onTap: () => setState(() => _trainStation = s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel ? Theme.of(context).colorScheme.primary : AppColors.surfaceMoss,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? Theme.of(context).colorScheme.primary : AppColors.divider),
                    ),
                    child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.textSecondary)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 4),
              const Text('快速選擇嘉義縣市車站', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
            ],
          ),
        ),
        _infoTip('資料每分鐘更新，誤點資訊以臺鐵官網為準'),
        const SizedBox(height: 14),

        if (northbound.isNotEmpty) ...[
          _trainSectionHeader('⬆️ 北上', '往台中・台北方向'),
          const SizedBox(height: 8),
          ...northbound.map((t) => _trainCard(t, _trainStation)),
          const SizedBox(height: 16),
        ],

        if (southbound.isNotEmpty) ...[
          _trainSectionHeader('⬇️ 南下', '往台南・高雄方向'),
          const SizedBox(height: 8),
          ...southbound.map((t) => _trainCard(t, _trainStation)),
          const SizedBox(height: 16),
        ],

        if (northbound.isEmpty && southbound.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: Center(child: Column(children: [
              Text('🚂', style: TextStyle(fontSize: 40)),
              SizedBox(height: 12),
              Text('找不到從此站出發的班次', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
            ])),
          ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _trainSectionHeader(String title, String sub) {
    final primary = Theme.of(context).colorScheme.primary;
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: mist,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: primary)),
      ),
      const SizedBox(width: 8),
      Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
    ]);
  }

  Widget _trainCard(_Train t, [String? fromStation]) {
    final depStation = fromStation ?? t.from;
    final primary = Theme.of(context).colorScheme.primary;
    final typeColor = t.type == '自強'   ? const Color(0xFFBF360C)
        : t.type == '太魯閣' ? const Color(0xFF0277BD)
        : t.type == '普悠瑪' ? const Color(0xFF6A1B9A)
        : t.type == '莒光'   ? const Color(0xFF2E7D32)
        : t.type == '區間'   ? primary
        : AppColors.textSecondary;

    // Duration string
    String _dur() {
      try {
        final dep = t.dep.split(':');
        final arr = t.arr.split(':');
        final depM = int.parse(dep[0]) * 60 + int.parse(dep[1]);
        var arrM  = int.parse(arr[0]) * 60 + int.parse(arr[1]);
        if (arrM < depM) arrM += 1440;
        final diff = arrM - depM;
        final h = diff ~/ 60;
        final m = diff % 60;
        return h > 0 ? '${h}時${m}分' : '${m}分';
      } catch (_) { return ''; }
    }

    final depIdx = t.stops.indexOf(depStation);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(
          color: AppColors.cardShadow, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Colored left accent bar ──
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: typeColor,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            // ── Card content ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Row 1: type chip + number + delay ──
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(t.type,
                          style: const TextStyle(color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Text(t.no, style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14,
                          color: AppColors.textPrimary)),
                      const Spacer(),
                      if (t.delay > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 11, color: AppColors.error),
                            const SizedBox(width: 3),
                            Text('誤點 ${t.delay} 分',
                              style: const TextStyle(color: AppColors.error,
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                          ]),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF2E7D32).withValues(alpha: 0.25)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_rounded,
                                size: 11, color: Color(0xFF2E7D32)),
                            SizedBox(width: 3),
                            Text('準點', style: TextStyle(color: Color(0xFF2E7D32),
                                fontSize: 10, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    // ── Row 2: time + route line ──
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      // Departure
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.dep, style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 24,
                          color: typeColor, letterSpacing: -0.5)),
                        Text(depStation, style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                      ]),
                      // Middle route line
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(children: [
                            Row(children: [
                              Container(width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: typeColor, shape: BoxShape.circle)),
                              Expanded(child: Container(height: 2,
                                  color: typeColor.withValues(alpha: 0.25))),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('🚂',
                                    style: TextStyle(fontSize: 14)),
                              ),
                              Expanded(child: Container(height: 2,
                                  color: typeColor.withValues(alpha: 0.25))),
                              Container(width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: typeColor, shape: BoxShape.circle)),
                            ]),
                            const SizedBox(height: 4),
                            Text(_dur(),
                              style: const TextStyle(fontSize: 10,
                                  color: AppColors.textHint,
                                  fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                      // Arrival
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(t.arr, style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 24,
                          color: t.delay > 0 ? AppColors.error : AppColors.textPrimary,
                          letterSpacing: -0.5)),
                        Text(t.to, style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    // ── Row 3: stop dots ──
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: t.stops.asMap().entries.map((e) {
                          final isKey = e.value == depStation || e.value == t.to;
                          final isPassed = depIdx >= 0 && e.key < depIdx;
                          return Row(mainAxisSize: MainAxisSize.min, children: [
                            if (e.key > 0)
                              Container(
                                width: 16, height: 1.5,
                                color: isPassed
                                    ? AppColors.divider
                                    : typeColor.withValues(alpha: 0.3)),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: isKey ? 8 : 5,
                                  height: isKey ? 8 : 5,
                                  decoration: BoxDecoration(
                                    color: isKey ? typeColor : AppColors.textHint,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(e.value,
                                  style: TextStyle(
                                    fontSize: isKey ? 10 : 9,
                                    fontWeight: isKey
                                        ? FontWeight.w700 : FontWeight.w400,
                                    color: isKey
                                        ? typeColor : AppColors.textHint,
                                  )),
                              ],
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ALISHAN RAILWAY TAB ──
  Widget _buildAlishanTab() {
    const routes = ['嘉義 → 阿里山', '嘉義 → 奮起湖', '阿里山 → 嘉義', '奮起湖 → 嘉義', '阿里山 ↔ 祝山（日出）'];
    final schedules = <String, List<_AlishanTrain>>{
      '嘉義 → 阿里山': [
        const _AlishanTrain(no:'A01', type:'觀光列車', dep:'09:00', arr:'12:28', price:849, remark:'需事先訂票'),
        const _AlishanTrain(no:'A03', type:'觀光列車', dep:'13:00', arr:'16:28', price:849, remark:'假日加開'),
      ],
      '嘉義 → 奮起湖': [
        const _AlishanTrain(no:'B01', type:'普通車', dep:'08:00', arr:'10:50', price:440, remark:''),
        const _AlishanTrain(no:'B03', type:'普通車', dep:'10:20', arr:'13:10', price:440, remark:''),
        const _AlishanTrain(no:'B05', type:'普通車', dep:'14:00', arr:'16:50', price:440, remark:''),
        const _AlishanTrain(no:'B07', type:'普通車', dep:'16:30', arr:'19:20', price:440, remark:'末班車'),
      ],
      '阿里山 → 嘉義': [
        const _AlishanTrain(no:'A02', type:'觀光列車', dep:'14:00', arr:'17:25', price:849, remark:'需事先訂票'),
        const _AlishanTrain(no:'A04', type:'觀光列車', dep:'16:00', arr:'19:25', price:849, remark:'假日加開'),
      ],
      '奮起湖 → 嘉義': [
        const _AlishanTrain(no:'B02', type:'普通車', dep:'11:30', arr:'14:20', price:440, remark:''),
        const _AlishanTrain(no:'B04', type:'普通車', dep:'15:00', arr:'17:50', price:440, remark:''),
        const _AlishanTrain(no:'B06', type:'普通車', dep:'17:20', arr:'20:10', price:440, remark:'末班車'),
      ],
      '阿里山 ↔ 祝山（日出）': [
        const _AlishanTrain(no:'S01', type:'祝山線', dep:'依日出時間', arr:'祝山', price:150, remark:'早晨日出班次'),
        const _AlishanTrain(no:'S02', type:'祝山線', dep:'日出後30分', arr:'阿里山', price:150, remark:'回程'),
        const _AlishanTrain(no:'S03', type:'沼平線', dep:'各整點', arr:'沼平', price:100, remark:'每整點發車'),
      ],
    };
    final list = schedules[_alishanRoute] ?? [];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Route chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: routes.map((r) {
              final sel = r == _alishanRoute;
              const forestGreen = Color(0xFF2E7D32);
              return GestureDetector(
                onTap: () => setState(() => _alishanRoute = r),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? forestGreen : AppColors.surfaceWarm,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? forestGreen : AppColors.divider),
                  ),
                  child: Text(r, style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppColors.textSecondary,
                  )),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        _infoTip('阿里山林業鐵路班次資訊，實際班次以林鐵官方公告為準，建議提前訂票'),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Center(
            child: Padding(padding: EdgeInsets.only(top: 30),
              child: Text('目前無班次資料', style: TextStyle(color: AppColors.textHint, fontSize: 14)))),
        ...list.map((t) => _alishanCard(t)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse('https://www.railway.gov.tw/Alishan-Frontend/');
            if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Text('🌲', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('前往林鐵及文資局官方訂票',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF2E7D32))),
                const Text('請提前購票，熱門班次易客滿',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              ])),
              const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF2E7D32)),
            ]),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _alishanCard(_AlishanTrain t) {
    const typeColor = {
      '觀光列車': Color(0xFF5C4033),
      '祝山線': Color(0xFFE65100),
      '沼平線': Color(0xFF1565C0),
    };
    final c = typeColor[t.type] ?? const Color(0xFF2E7D32);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🚃', style: TextStyle(fontSize: 18)),
            Text(t.no, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(t.type, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
            if (t.remark.isNotEmpty) ...[
              const SizedBox(width: 6),
              Expanded(child: Text(t.remark,
                style: const TextStyle(fontSize: 10, color: AppColors.warning),
                overflow: TextOverflow.ellipsis)),
            ],
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.dep, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary)),
              const Text('出發', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
            ]),
            Expanded(child: Row(children: [
              Expanded(child: Container(height: 1, color: AppColors.divider,
                margin: const EdgeInsets.symmetric(horizontal: 8))),
              const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textHint),
              Expanded(child: Container(height: 1, color: AppColors.divider,
                margin: const EdgeInsets.symmetric(horizontal: 8))),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(t.arr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary)),
              const Text('抵達', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
            ]),
          ]),
        ])),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('NT\$${t.price}',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: primary)),
          const Text('票價', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
        ]),
      ]),
    );
  }

  // ── THSR TAB (today view + full timetable toggle) ──
  Widget _buildThsrTab() =>
      _thsrShowTimetable ? _buildThsrTimetableView() : _buildThsrTodayView();

  Widget _buildThsrTodayView() {
    final primary = Theme.of(context).colorScheme.primary;
    const thsrPurple = Color(0xFF9C27B0);

    final northbound = [
      _ThsrTrain(no:'0102', dep:'06:36', arr:'08:00', dest:'南港', price:1290, seats:'有空位',
        stops:['嘉義','台中','板橋','台北','南港']),
      _ThsrTrain(no:'0106', dep:'07:36', arr:'09:01', dest:'南港', price:1290, seats:'有空位',
        stops:['嘉義','台中','桃園','台北','南港']),
      _ThsrTrain(no:'0110', dep:'08:36', arr:'10:00', dest:'台北', price:1190, seats:'少量',
        stops:['嘉義','台中','桃園','台北']),
      _ThsrTrain(no:'0114', dep:'09:36', arr:'11:01', dest:'南港', price:1290, seats:'有空位',
        stops:['嘉義','台中','台北','南港']),
      _ThsrTrain(no:'0118', dep:'10:36', arr:'12:00', dest:'台北', price:1190, seats:'有空位',
        stops:['嘉義','桃園','台北']),
      _ThsrTrain(no:'0122', dep:'12:00', arr:'13:22', dest:'南港', price:1290, seats:'客滿',
        stops:['嘉義','台中','苗栗','新竹','桃園','台北','南港']),
      _ThsrTrain(no:'0126', dep:'13:36', arr:'15:01', dest:'台北', price:1190, seats:'有空位',
        stops:['嘉義','台中','台北']),
      _ThsrTrain(no:'0130', dep:'15:36', arr:'17:01', dest:'南港', price:1290, seats:'少量',
        stops:['嘉義','台中','桃園','台北','南港']),
      _ThsrTrain(no:'0134', dep:'17:36', arr:'19:01', dest:'南港', price:1290, seats:'有空位',
        stops:['嘉義','台中','台北','南港']),
      _ThsrTrain(no:'0138', dep:'19:36', arr:'21:00', dest:'台北', price:1190, seats:'有空位',
        stops:['嘉義','台中','桃園','台北']),
    ];
    final southbound = [
      _ThsrTrain(no:'0101', dep:'09:24', arr:'10:04', dest:'左營', price:1190, seats:'有空位',
        stops:['南港','台北','桃園','台中','嘉義','台南','左營']),
      _ThsrTrain(no:'0105', dep:'11:24', arr:'12:04', dest:'左營', price:1190, seats:'少量',
        stops:['台北','桃園','台中','嘉義','台南','左營']),
      _ThsrTrain(no:'0109', dep:'13:00', arr:'13:40', dest:'左營', price:1190, seats:'有空位',
        stops:['南港','台北','台中','嘉義','台南','左營']),
      _ThsrTrain(no:'0113', dep:'15:00', arr:'15:40', dest:'左營', price:1190, seats:'有空位',
        stops:['台北','桃園','台中','嘉義','台南','左營']),
      _ThsrTrain(no:'0117', dep:'17:00', arr:'17:40', dest:'左營', price:1190, seats:'客滿',
        stops:['台北','台中','嘉義','台南','左營']),
      _ThsrTrain(no:'0121', dep:'18:24', arr:'19:04', dest:'左營', price:1190, seats:'少量',
        stops:['南港','台北','桃園','台中','嘉義','台南','左營']),
      _ThsrTrain(no:'0125', dep:'20:00', arr:'20:40', dest:'左營', price:1190, seats:'有空位',
        stops:['台北','台中','嘉義','台南','左營']),
    ];

    final list = _thsrDirection == '北上' ? northbound : southbound;
    final today = DateTime.now();
    final dateStr = '${today.year}/${today.month.toString().padLeft(2,'0')}/${today.day.toString().padLeft(2,'0')}';

    return Column(children: [
      Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('嘉義高鐵站  $dateStr',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
            const Text('每30分鐘更新', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          ])),
          _thsrDirToggle(primary),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _infoTip(_thsrDirection == '北上' ? '往台中・台北・南港方向（停嘉義班次）' : '往台南・左營（高雄）方向（停嘉義班次）'),
          const SizedBox(height: 12),
          ...list.map((t) => _thsrCard(t, primary, thsrPurple)),
          const SizedBox(height: 12),
          // Toggle to full timetable
          GestureDetector(
            onTap: () => setState(() => _thsrShowTimetable = true),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: thsrPurple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: thsrPurple.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                const Text('📋', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('查看完整時刻表',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF9C27B0))),
                  Text('所有停靠嘉義站班次一覽',
                    style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                ])),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF9C27B0)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('https://www.thsrc.com.tw/');
              if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceMoss,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Row(children: [
                Text('🚅', style: TextStyle(fontSize: 18)),
                SizedBox(width: 10),
                Expanded(child: Text('台灣高速鐵路官方訂票',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary))),
                Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.textHint),
              ]),
            ),
          ),
          const SizedBox(height: 20),
        ],
      )),
    ]);
  }

  Widget _thsrDirToggle(Color primary) => Container(
    decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _thsrDirBtn('北上', primary),
      _thsrDirBtn('南下', primary),
    ]),
  );

  Widget _thsrDirBtn(String label, Color primary) {
    final sel = _thsrDirection == label;
    return GestureDetector(
      onTap: () => setState(() => _thsrDirection = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: sel ? Colors.white : AppColors.textSecondary,
        )),
      ),
    );
  }

  Widget _thsrCard(_ThsrTrain t, Color primary, Color thsrPurple) {
    final seatColor = t.seats == '客滿' ? AppColors.error
        : t.seats == '少量' ? AppColors.warning
        : primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: t.seats == '客滿' ? AppColors.error.withValues(alpha: 0.35) : AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: thsrPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
            child: Text('高鐵 ${t.no}次',
              style: TextStyle(color: thsrPurple, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: seatColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
            child: Text(t.seats,
              style: TextStyle(color: seatColor, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.dep, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.textPrimary)),
            const Text('嘉義出發', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
          ]),
          Expanded(child: Column(children: [
            Row(children: [
              Expanded(child: Container(height: 1.5, color: AppColors.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.directions_railway_filled_rounded, size: 16, color: thsrPurple)),
              Expanded(child: Container(height: 1.5, color: AppColors.divider)),
            ]),
            const SizedBox(height: 3),
            Text('NT\$${t.price}', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(t.arr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.textPrimary)),
            Text(t.dest, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          ]),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: t.stops.asMap().entries.map((e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e.key > 0) Container(
                  width: 16, height: 1.5, color: AppColors.divider,
                  margin: const EdgeInsets.symmetric(horizontal: 2)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: e.value == '嘉義' || e.value == t.dest
                        ? thsrPurple.withValues(alpha: 0.12) : AppColors.surfaceMoss,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: e.value == '嘉義' || e.value == t.dest
                        ? thsrPurple.withValues(alpha: 0.3) : AppColors.divider),
                  ),
                  child: Text(e.value, style: TextStyle(
                    fontSize: 9,
                    color: e.value == '嘉義' || e.value == t.dest
                        ? thsrPurple : AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
                ),
              ],
            )).toList(),
          ),
        ),
      ]),
    );
  }

  // ── THSR FULL TIMETABLE VIEW ──
  Widget _buildThsrTimetableView() {
    const thsrPurple = Color(0xFF9C27B0);
    final primary = Theme.of(context).colorScheme.primary;

    // All trains stopping at 嘉義 — [no, dep, arr, dest, type]
    const northList = [
      ['0102', '06:36', '08:00', '南港', '直達'],
      ['0106', '07:36', '09:01', '南港', '普通'],
      ['0108', '08:00', '09:35', '台北', '普通'],
      ['0110', '08:36', '10:00', '台北', '普通'],
      ['0112', '09:00', '10:36', '台北', '普通'],
      ['0114', '09:36', '11:01', '南港', '普通'],
      ['0116', '10:00', '11:35', '台北', '普通'],
      ['0118', '10:36', '12:00', '台北', '普通'],
      ['0120', '11:00', '12:35', '南港', '普通'],
      ['0122', '12:00', '13:22', '南港', '普通'],
      ['0124', '12:36', '14:01', '台北', '普通'],
      ['0126', '13:36', '15:01', '台北', '普通'],
      ['0128', '14:36', '16:01', '南港', '普通'],
      ['0130', '15:36', '17:01', '南港', '普通'],
      ['0132', '16:36', '18:00', '台北', '普通'],
      ['0134', '17:36', '19:01', '南港', '普通'],
      ['0136', '18:36', '20:00', '台北', '普通'],
      ['0138', '19:36', '21:00', '南港', '普通'],
      ['0140', '20:36', '22:00', '台北', '普通'],
      ['0642', '21:36', '23:00', '台北', '直達'],
    ];
    const southList = [
      ['0101', '08:24', '09:04', '左營', '直達'],
      ['0103', '09:00', '09:40', '左營', '普通'],
      ['0105', '10:24', '11:04', '左營', '普通'],
      ['0107', '11:00', '11:40', '左營', '普通'],
      ['0109', '12:00', '12:40', '左營', '普通'],
      ['0111', '12:24', '13:04', '左營', '普通'],
      ['0113', '13:24', '14:04', '左營', '普通'],
      ['0115', '14:00', '14:40', '左營', '普通'],
      ['0117', '15:00', '15:40', '左營', '普通'],
      ['0119', '15:24', '16:04', '左營', '普通'],
      ['0121', '16:24', '17:04', '左營', '普通'],
      ['0123', '17:00', '17:40', '左營', '普通'],
      ['0125', '18:00', '18:40', '左營', '普通'],
      ['0127', '18:24', '19:04', '左營', '普通'],
      ['0129', '19:24', '20:04', '左營', '普通'],
      ['0131', '20:00', '20:40', '左營', '普通'],
      ['0133', '21:00', '21:40', '左營', '直達'],
    ];

    final list = _thsrDirection == '北上' ? northList : southList;

    return Column(children: [
      // Header with back button
      Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
            onPressed: () => setState(() => _thsrShowTimetable = false),
            tooltip: '返回今日班次',
          ),
          const Expanded(child: Text('嘉義高鐵站 完整時刻表',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary))),
          _thsrDirToggle(primary),
        ]),
      ),
      const Divider(height: 1),
      // Column header
      Container(
        color: AppColors.surfaceMoss,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(children: [
          SizedBox(width: 56, child: Text('車次', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint))),
          SizedBox(width: 8),
          SizedBox(width: 56, child: Text('出發', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint))),
          SizedBox(width: 8),
          SizedBox(width: 56, child: Text('抵達', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint))),
          SizedBox(width: 8),
          Expanded(child: Text('終點', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint))),
          SizedBox(width: 50, child: Text('類型', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint), textAlign: TextAlign.right)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
          itemBuilder: (_, i) {
            final t = list[i];
            final isDirect = t[4] == '直達';
            return Container(
              color: isDirect ? thsrPurple.withValues(alpha: 0.04) : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                SizedBox(width: 56,
                  child: Text(t[0], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                const SizedBox(width: 8),
                SizedBox(width: 56,
                  child: Text(t[1], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primary))),
                const SizedBox(width: 8),
                SizedBox(width: 56,
                  child: Text(t[2], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t[3], style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                SizedBox(width: 50,
                  child: Align(alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDirect ? thsrPurple.withValues(alpha: 0.12) : AppColors.surfaceMoss,
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(t[4], style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: isDirect ? thsrPurple : AppColors.textHint)),
                    ),
                  )),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _infoTip(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentSky.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentSky.withValues(alpha: 0.3)),
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

class _AlishanTrain {
  final String no, type, dep, arr, remark;
  final int price;
  const _AlishanTrain({required this.no, required this.type, required this.dep,
    required this.arr, required this.price, required this.remark});
}

class _ThsrTrain {
  final String no, dep, arr, dest, seats;
  final List<String> stops;
  final int price;
  const _ThsrTrain({required this.no, required this.dep, required this.arr,
    required this.dest, required this.stops, required this.price, required this.seats});
}
