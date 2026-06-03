import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../widgets/common_widgets.dart' show NewsCardSkeleton;
import '../utils/html_utils.dart';
import '../utils/dept_style.dart';

class _RealNewsItem {
  final String title, date;
  final String? summary, location, url, imageUrl, endDate;
  final bool isEvent;
  const _RealNewsItem({required this.title, required this.date, this.summary, this.location, this.url, this.imageUrl, this.endDate, required this.isEvent});
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
    final (c, _) = deptColorIcon(item.location, item.isEvent);
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final dateRange = item.isEvent && (item.endDate?.isNotEmpty ?? false) ? '${item.date} ～ ${item.endDate}' : item.date;
    final cleanedSummary = cleanHtml(item.summary);
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
    final (c, iconData) = deptColorIcon(item.location, item.isEvent);
    return GestureDetector(onTap: () => _showDetail(context), child: StitchedBox(color: Color.lerp(c, Colors.white, 0.93)!, stitchColor: c.withValues(alpha: 0.35), radius: 16, inset: 4, dashWidth: 4, dashGap: 3, padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(iconData, size: 10, color: c), const SizedBox(width: 3), Text(item.isEvent ? '活動' : '新聞', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700))])), const Spacer(), Text(item.date, style: const TextStyle(fontSize: 10, color: AppColors.textHint))]),
      const SizedBox(height: 8),
      Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
      if ((item.location ?? '').isNotEmpty) ...[const SizedBox(height: 4), Text(item.location!, style: TextStyle(fontSize: 10, color: c.withValues(alpha: 0.7)), maxLines: 1, overflow: TextOverflow.ellipsis)],
    ])));
  }
}
