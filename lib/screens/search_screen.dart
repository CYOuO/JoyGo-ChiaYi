import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/dummy_data.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';
  String _filter = '全部';

  final _filters = ['全部', '景點', '餐廳', '活動', '住宿'];

  List<Spot> get _results {
    if (_query.isEmpty) return [];
    return DummyData.spots.where((s) {
      final matchQ = s.name.contains(_query) || s.description.contains(_query) || s.address.contains(_query);
      final matchF = _filter == '全部' ||
          (_filter == '景點' && s.category == 'attraction') ||
          (_filter == '餐廳' && s.category == 'restaurant') ||
          (_filter == '住宿' && s.category == 'hotel');
      return matchQ && matchF;
    }).toList();
  }

  final List<String> _hotSearches = ['火雞肉飯', '阿里山', '文化路夜市', '北門車站', '嘉義公園', '美術館'];
  final List<String> _recentSearches = ['阿里山日出', '嘉義伴手禮'];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppColors.primary)),
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
                          color: sel ? AppColors.primary : AppColors.surfaceMoss,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppColors.primary : AppColors.divider),
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
            child: _query.isEmpty ? _buildSuggestions() : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
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
                            AppColors.primary, AppColors.accentSky, AppColors.textHint];
            final c = colors[entry.key % colors.length];
            return GestureDetector(
              onTap: () { _ctrl.text = entry.value; setState(() => _query = entry.value); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.withOpacity(0.25)),
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

  Widget _buildResults() {
    final results = _results;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 52)),
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
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceWarm,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(s.imageUrl, width: 56, height: 56, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56, height: 56,
                  color: AppColors.surfaceMoss,
                  child: Center(child: Text(s.category == 'restaurant' ? '🍜' : '🏛️',
                    style: const TextStyle(fontSize: 24))),
                ),
              ),
            ),
            title: RichText(
              text: TextSpan(
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                children: _highlight(s.name, _query),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.star_rounded, size: 12, color: AppColors.accentStraw),
                  Text(' ${s.rating}  ·  ', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  Expanded(child: Text(s.address, style: const TextStyle(fontSize: 11, color: AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 18),
          ),
        );
      },
    );
  }

  List<TextSpan> _highlight(String text, String query) {
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
        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900),
      ));
      start = idx + query.length;
    }
    return spans;
  }
}
