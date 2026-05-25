import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/dummy_data.dart';
import '../widgets/common_widgets.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String _selectedCategory = 'all';
  String _sortBy = 'rating';

  final _categories = [
    {'key': 'all', 'label': '全部', 'icon': '🗺️'},
    {'key': 'attraction', 'label': '景點', 'icon': '🏛️'},
    {'key': 'restaurant', 'label': '美食', 'icon': '🍜'},
    {'key': 'hotel', 'label': '住宿', 'icon': '🏨'},
    {'key': 'youbike', 'label': 'YouBike', 'icon': '🚲'},
  ];

  List<Spot> get _filteredSpots {
    var spots = DummyData.spots.toList();
    if (_selectedCategory != 'all') {
      spots = spots.where((s) => s.category == _selectedCategory).toList();
    }
    if (_sortBy == 'rating') {
      spots.sort((a, b) => b.rating.compareTo(a.rating));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('探索嘉義',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.textPrimary),
            onPressed: () => _showFilter(context),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Category filter
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  return CategoryChip(
                    label: cat['label']!,
                    icon: cat['icon']!,
                    isSelected: _selectedCategory == cat['key'],
                    onTap: () =>
                        setState(() => _selectedCategory = cat['key']!),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1),

          // Results count + sort
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  '共 ${_filteredSpots.length} 個結果',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showFilter(context),
                  child: Row(
                    children: [
                      Icon(Icons.sort_rounded,
                          size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        '評分最高',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Spot list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: _filteredSpots.length,
              itemBuilder: (context, index) {
                final spot = _filteredSpots[index];
                return _SpotListCard(spot: spot);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '篩選與排序',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '排序方式',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['評分最高', '距離最近', '最新加入'].map((s) {
                final isSelected = s == '評分最高';
                return FilterChip(
                  label: Text(s),
                  selected: isSelected,
                  onSelected: (_) {},
                  selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  checkmarkColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color:
                        isSelected ? Theme.of(context).colorScheme.primary : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              '距離範圍',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            Slider(
              value: 5.0,
              min: 1,
              max: 20,
              divisions: 19,
              label: '5 km',
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('套用篩選'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotListCard extends StatefulWidget {
  final Spot spot;

  const _SpotListCard({required this.spot});

  @override
  State<_SpotListCard> createState() => _SpotListCardState();
}

class _SpotListCardState extends State<_SpotListCard> {
  bool _isLiked = false;
  bool _isSaved = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                Image.network(
                  widget.spot.imageUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    color: AppColors.surfaceMoss,
                    child: Center(
                      child: Text(
                        widget.spot.category == 'restaurant' ? '🍜' : '🏛️',
                        style: const TextStyle(fontSize: 48),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: AppColors.accentStraw),
                        Text(
                          ' ${widget.spot.rating}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _actionBtn(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        _isLiked ? AppColors.error : Colors.white,
                        () => setState(() => _isLiked = !_isLiked),
                      ),
                      const SizedBox(width: 6),
                      _actionBtn(
                        _isSaved ? Icons.bookmark : Icons.bookmark_border,
                        _isSaved ? AppColors.accentStraw : Colors.white,
                        () => setState(() => _isSaved = !_isSaved),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Info
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.spot.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _categoryLabel(widget.spot.category),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.spot.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 13, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.spot.address,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.access_time_rounded,
                        size: 13, color: AppColors.textHint),
                    const SizedBox(width: 2),
                    Text(
                      widget.spot.openHours,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('加入行程',
                            style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.directions_rounded, size: 15),
                        label: const Text('導航', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  String _categoryLabel(String cat) {
    const map = {
      'attraction': '🏛️ 景點',
      'restaurant': '🍜 美食',
      'hotel': '🏨 住宿',
      'youbike': '🚲 YouBike',
    };
    return map[cat] ?? cat;
  }
}
