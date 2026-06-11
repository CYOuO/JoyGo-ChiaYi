import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/spot.dart';
import '../services/spot_service.dart';
import 'map_screen.dart';

class SearchScreen extends StatefulWidget {
  /// 呼叫此 callback 切換到地圖 Tab
  final VoidCallback? onSwitchToMap;
  const SearchScreen({super.key, this.onSwitchToMap});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';
  String _filter = '全部';
  Timer? _debounce;

  final _filters = ['全部', '景點', '餐廳', '活動', '住宿'];

  // ── 類別篩選映射 ───────────────────────────────────────────────
  bool _matchFilter(Spot s) {
    if (_filter == '全部') return true;
    final cat = s.category.toLowerCase();
    switch (_filter) {
      case '景點':
        return ['attraction', 'scenic', 'scenicspot', 'tdxspot', 'park', 'temple', 'museum', 'cultural', 'historical']
            .any((k) => cat.contains(k));
      case '餐廳':
        return ['restaurant', 'food', 'chiayifood', 'drinkshop', 'nightmarket', 'cafe', 'drink', 'meal']
            .any((k) => cat.contains(k));
      case '住宿':
        return ['hotel', 'hostel', 'motel', 'resort', 'inn', 'b&b', 'accommodation']
            .any((k) => cat.contains(k));
      case '活動':
        return ['event', 'activity', 'festival', 'exhibition', 'show']
            .any((k) => cat.contains(k));
      default:
        return true;
    }
  }

  List<Spot> get _results {
    if (_query.isEmpty) return [];
    final all = SpotService.cached;
    return all.where((s) {
      final q = _query.toLowerCase();
      final matchQ = s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.address.toLowerCase().contains(q);
      return matchQ && _matchFilter(s);
    }).toList();
  }

  final List<String> _hotSearches = ['火雞肉飯', '阿里山', '文化路夜市', '北門車站', '嘉義公園', '美術館'];
  final List<String> _recentSearches = ['阿里山日出', '嘉義伴手禮'];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    // 🌟 重新啟用延遲！讓使用者停頓 300 毫秒後才進行過濾
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _query = v.trim());
      }
    });
  }

  // ── 分類圖示 ────────────────────────────────────────────────────
  IconData _categoryIcon(String cat) {
    final c = cat.toLowerCase();
    if (c.contains('restaurant') || c.contains('food') || c.contains('cafe')) {
      return Icons.restaurant_rounded;
    }
    if (c.contains('hotel') || c.contains('hostel')) return Icons.hotel_rounded;
    if (c.contains('park')) return Icons.park_rounded;
    if (c.contains('temple') || c.contains('museum')) return Icons.museum_rounded;
    return Icons.place_rounded;
  }

  String _categoryLabel(String cat) {
    final c = cat.toLowerCase();
    if (c.contains('restaurant') || c.contains('food') || c.contains('chiayifood')) return '餐廳';
    if (c.contains('hotel') || c.contains('hostel')) return '住宿';
    if (c.contains('park')) return '公園';
    if (c.contains('scenic') || c.contains('attraction')) return '景點';
    if (c.contains('temple')) return '廟宇';
    if (c.contains('museum') || c.contains('cultural')) return '文化';
    if (c.contains('drink')) return '飲品';
    return '景點';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜尋景點、美食、活動...',
            filled: true,
            fillColor: AppColors.surfaceMoss,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textHint),
                    onPressed: () { _ctrl.clear(); setState(() => _query = ''); },
                  )
                : null,
          ),
          onChanged: _onQueryChanged,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: primary)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          if (_query.isNotEmpty)
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((f) {
                    final sel = _filter == f;
                    return GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? primary : AppColors.surfaceMoss,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? primary : AppColors.divider),
                        ),
                        child: Text(f,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          Expanded(
            child: _query.isEmpty ? _buildSuggestions(primary) : _buildResults(primary),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(Color primary) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Row(
            children: [
              const Text('最近搜尋',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textSecondary)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _recentSearches.clear()),
                child: const Text('清除', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _recentSearches.map((s) => GestureDetector(
              onTap: () { _ctrl.text = s; setState(() => _query = s); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMoss,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_rounded, size: 14, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(s, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 24),
        ],
        const Text('熱門搜尋',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _hotSearches.asMap().entries.map((entry) {
            final colors = [AppColors.error, AppColors.accentTerra, AppColors.accentSand,
                            primary, AppColors.accentSky, AppColors.textHint];
            final c = colors[entry.key % colors.length];
            return GestureDetector(
              onTap: () { _ctrl.text = entry.value; setState(() => _query = entry.value); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${entry.key + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                    const SizedBox(width: 4),
                    Text(entry.value, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildResults(Color primary) {
    final results = _results;
    final mist = Color.lerp(primary, Colors.white, 0.92)!;

    if (results.isEmpty) {
      // 如果 SpotService.cached 是空的，提示正在載入
      if (SpotService.cached.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5, color: primary)),
              const SizedBox(height: 16),
              Text('載入景點資料中…', style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 52, color: primary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('找不到「$_query」的結果',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('試試其他關鍵字', style: TextStyle(color: AppColors.textHint)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final s = results[i];
        return GestureDetector(
          onTap: () => _showSpotDetail(context, s),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: mist,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(color: primary.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: s.imageUrl.isNotEmpty
                    ? Image.network(
                        s.imageUrl,
                        width: 56, height: 56, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder(s, primary),
                      )
                    : _imagePlaceholder(s, primary),
              ),
              title: RichText(
                text: TextSpan(
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                  children: _highlight(s.name, _query, primary),
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.star_rounded, size: 12, color: AppColors.accentStraw),
                    Text(' ${s.rating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const Text('  ·  ', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_categoryLabel(s.category),
                          style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(s.address,
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: primary.withValues(alpha: 0.5), size: 18),
            ),
          ),
        );
      },
    );
  }

  Widget _imagePlaceholder(Spot s, Color primary) {
    return Container(
      width: 56, height: 56,
      color: primary.withValues(alpha: 0.10),
      child: Center(child: Icon(_categoryIcon(s.category), size: 24, color: primary.withValues(alpha: 0.5))),
    );
  }

  // ── 景點詳細資訊 Bottom Sheet ──────────────────────────────────
  void _showSpotDetail(BuildContext ctx, Spot spot) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpotDetailSheet(
        spot: spot,
        onGoToMap: () {
          // 設定地圖 focusNotifier
          MapScreen.focusNotifier.value = (
            lat: spot.lat,
            lng: spot.lng,
            catKey: null,
          );
          // 關閉 bottom sheet + 關閉搜尋頁
          Navigator.pop(ctx); // sheet
          Navigator.pop(ctx); // search
          // 切換到地圖 tab
          widget.onSwitchToMap?.call();
        },
      ),
    );
  }

  List<TextSpan> _highlight(String text, String query, Color primary) {
    if (query.isEmpty) return [TextSpan(text: text)];
    final spans = <TextSpan>[];
    int start = 0;
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    while (true) {
      final idx = lower.indexOf(lowerQ, start);
      if (idx == -1) { spans.add(TextSpan(text: text.substring(start))); break; }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(color: primary, fontWeight: FontWeight.w900),
      ));
      start = idx + query.length;
    }
    return spans;
  }
}

// ════════════════════════════════════════════════════════════════
// 景點資訊卡 Bottom Sheet
// ════════════════════════════════════════════════════════════════
class _SpotDetailSheet extends StatelessWidget {
  final Spot spot;
  final VoidCallback? onGoToMap;
  const _SpotDetailSheet({required this.spot, this.onGoToMap});

  String _categoryLabel(String cat) {
    final c = cat.toLowerCase();
    if (c.contains('restaurant') || c.contains('food') || c.contains('chiayifood')) return '餐廳';
    if (c.contains('hotel') || c.contains('hostel')) return '住宿';
    if (c.contains('park')) return '公園';
    if (c.contains('scenic') || c.contains('attraction')) return '景點';
    if (c.contains('temple')) return '廟宇';
    if (c.contains('museum') || c.contains('cultural')) return '文化';
    if (c.contains('drink')) return '飲品';
    return '景點';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            // ── 圖片 + 拖動把手 ─────────────────────────────────
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  // 封面圖
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: spot.imageUrl.isNotEmpty
                        ? Image.network(
                            spot.imageUrl,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildImgFallback(primary),
                          )
                        : _buildImgFallback(primary),
                  ),
                  // 漸層遮罩
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
                            stops: const [0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 拖動把手
                  Positioned(
                    top: 10, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  // 評分 badge（底部）
                  Positioned(
                    bottom: 12, left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded, size: 13, color: AppColors.accentStraw),
                        const SizedBox(width: 3),
                        Text(spot.rating.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                  // 類別 badge（底部）
                  Positioned(
                    bottom: 12, right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_categoryLabel(spot.category),
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),

            // ── 內容 ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                // 名稱
                Text(spot.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                const SizedBox(height: 12),

                // 地址
                if (spot.address.isNotEmpty) ...[
                  _infoRow(Icons.location_on_rounded, spot.address, primary),
                  const SizedBox(height: 8),
                ],

                // 開放時間
                if (spot.openHours.isNotEmpty) ...[
                  _infoRow(Icons.schedule_rounded, spot.openHours, primary),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 4),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 12),

                // 介紹
                if (spot.description.isNotEmpty) ...[
                  Text('景點介紹',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary)),
                  const SizedBox(height: 8),
                  Text(spot.description,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.7)),
                  const SizedBox(height: 20),
                ],

                // 按鈕區
                Row(children: [
                  // 在地圖查看
                  Expanded(
                    child: GestureDetector(
                      onTap: onGoToMap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [primary, Color.lerp(primary, Colors.black, 0.18)!],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.map_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          const Text('在地圖查看', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImgFallback(Color primary) {
    return Container(
      width: double.infinity, height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary.withValues(alpha: 0.15), primary.withValues(alpha: 0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.landscape_rounded, size: 64, color: primary.withValues(alpha: 0.3))),
    );
  }

  Widget _infoRow(IconData icon, String text, Color primary) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: primary.withValues(alpha: 0.7)),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5))),
    ]);
  }
}
