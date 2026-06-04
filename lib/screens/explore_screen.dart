import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart' show IllustratedEmptyState, EmptyScene, CategoryChip;
import '../models/spot.dart';
import '../services/spot_service.dart';
import '../services/local_fav_service.dart';
import 'search_screen.dart';
import 'trip_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String _selectedCategory = 'all';
  String _sortBy = 'rating';
  List<Spot> _allSpots = [];
  bool _loading = true;
  String _search = '';

  final _categories = <Map<String, dynamic>>[
    {'key': 'all',        'label': '全部',    'icon': Icons.map_rounded},
    {'key': 'attraction', 'label': '景點',    'icon': Icons.account_balance_rounded},
    {'key': 'restaurant', 'label': '美食',    'icon': Icons.ramen_dining_rounded},
    {'key': 'hotel',      'label': '住宿',    'icon': Icons.hotel_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    setState(() => _loading = true);
    final spots = await SpotService.loadAllSpots();
    if (mounted) setState(() { _allSpots = spots; _loading = false; });
  }

  List<Spot> get _filteredSpots {
    var spots = _allSpots.toList();
    if (_selectedCategory != 'all') {
      spots = spots.where((s) => s.category == _selectedCategory).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      spots = spots.where((s) =>
        s.name.toLowerCase().contains(q) ||
        s.address.toLowerCase().contains(q) ||
        s.description.toLowerCase().contains(q)
      ).toList();
    }
    if (_sortBy == 'rating') {
      spots.sort((a, b) => b.rating.compareTo(a.rating));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('探索嘉義', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.textPrimary),
            onPressed: () => _showFilter(context),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
            onPressed: () async {
              final result = await Navigator.push<String>(context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()));
              if (result != null && mounted) setState(() => _search = result);
            },
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
                    label: cat['label'] as String,
                    icon: cat['icon'] as IconData,
                    isSelected: _selectedCategory == cat['key'],
                    onTap: () => setState(() => _selectedCategory = cat['key'] as String),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1),

          // Search chip if active
          if (_search.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                Icon(Icons.search_rounded, size: 14, color: primary),
                const SizedBox(width: 4),
                Text('搜尋：$_search', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _search = ''),
                  child: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textHint),
                ),
              ]),
            ),

          // Results count + sort
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                if (_loading)
                  const Text('載入中…', style: TextStyle(color: AppColors.textHint, fontSize: 13))
                else
                  Text('共 ${_filteredSpots.length} 個結果',
                      style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showFilter(context),
                  child: Row(
                    children: [
                      Icon(Icons.sort_rounded, size: 16, color: primary),
                      const SizedBox(width: 4),
                      Text(_sortBy == 'rating' ? '評分最高' : '距離最近',
                        style: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Spot list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSpots.isEmpty
                    ? IllustratedEmptyState(
                        scene: EmptyScene.map,
                        title: _search.isNotEmpty ? '找不到「$_search」' : '此分類暫無景點',
                        body: '試試其他分類或搜尋關鍵字',
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadSpots(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _filteredSpots.length,
                          itemBuilder: (context, index) {
                            final spot = _filteredSpots[index];
                            return _SpotListCard(spot: spot);
                          },
                        ),
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
            const Text('篩選與排序',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            const Text('排序方式',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ('評分最高', 'rating'),
              ].map((s) {
                final isSelected = s.$2 == _sortBy;
                return FilterChip(
                  label: Text(s.$1),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _sortBy = s.$2);
                    Navigator.pop(context);
                  },
                  selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  checkmarkColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Theme.of(context).colorScheme.primary : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('套用篩選'),
              ),
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
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _isSaved = LocalFavService.isSaved(widget.spot.id);
    // Listen for changes
    LocalFavService.notifier.addListener(_onFavChanged);
  }

  void _onFavChanged() {
    if (mounted) setState(() => _isSaved = LocalFavService.isSaved(widget.spot.id));
  }

  @override
  void dispose() {
    LocalFavService.notifier.removeListener(_onFavChanged);
    super.dispose();
  }

  Future<void> _toggleSave() async {
    await LocalFavService.toggleWithMeta(
      widget.spot.id,
      spotName: widget.spot.name,
      imageUrl: widget.spot.imageUrl,
      rating: widget.spot.rating,
      category: widget.spot.category,
    );
    if (mounted) setState(() => _isSaved = LocalFavService.isSaved(widget.spot.id));
  }

  Future<void> _openNavigation() async {
    final name = Uri.encodeComponent(widget.spot.name);
    final lat = widget.spot.lat;
    final lng = widget.spot.lng;
    // Try Google Maps first, fall back to address search
    final uri = lat != 0 && lng != 0
        ? Uri.parse('https://maps.google.com/?q=$lat,$lng')
        : Uri.parse('https://maps.google.com/?q=$name');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${widget.spot.name}：${widget.spot.address}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: const Offset(0, 3))],
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
                      child: Icon(
                        widget.spot.category == 'restaurant'
                            ? Icons.ramen_dining_rounded
                            : Icons.account_balance_rounded,
                        size: 48, color: AppColors.textHint,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      const Icon(Icons.star_rounded, size: 13, color: AppColors.accentStraw),
                      Text(' ${widget.spot.rating}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                Positioned(
                  top: 12, right: 12,
                  child: GestureDetector(
                    onTap: _toggleSave,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      child: Icon(
                        _isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: _isSaved ? AppColors.accentStraw : Colors.white, size: 18,
                      ),
                    ),
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
                Row(children: [
                  Expanded(child: Text(widget.spot.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary))),
                  Text(_categoryLabel(widget.spot.category),
                      style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                Text(widget.spot.description,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.location_on_rounded, size: 13, color: primary),
                  const SizedBox(width: 4),
                  Expanded(child: Text(widget.spot.address,
                      style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textHint),
                  const SizedBox(width: 2),
                  Text(widget.spot.openHours,
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const TripScreen())),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: const Text('加入行程', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        foregroundColor: primary,
                        side: BorderSide(color: primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openNavigation,
                      icon: const Icon(Icons.directions_rounded, size: 15),
                      label: const Text('導航', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        backgroundColor: primary, foregroundColor: Colors.white, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String cat) {
    const map = {'attraction': '景點', 'restaurant': '美食', 'hotel': '住宿', 'youbike': 'YouBike'};
    return map[cat] ?? cat;
  }
}
