import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/dummy_data.dart';
import '../widgets/common_widgets.dart';
import 'search_screen.dart';
import 'notifications_screen.dart';
import 'events_screen.dart';
import 'news_transport_screens.dart';
import 'camera_screen.dart';
import 'weather_screen.dart';
import 'news_transport_screens.dart' show TransportScreen, NewsScreen;

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  final void Function(int)? onSwitchTab;  // ← 傳入切換底部 tab 的 callback

  const HomeScreen({super.key, this.onOpenDrawer, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _bannerController = PageController();
  int _currentBanner = 0;
  int _unreadCount = 3;

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  void _goSearch() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
  void _goNotifications() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
  ).then((_) => setState(() => _unreadCount = 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar ──
          SliverAppBar(
            expandedHeight: 155,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF4A7A50),
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
              onPressed: widget.onOpenDrawer,
            ),
            actions: [
              // Notification bell with badge
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: _goNotifications,
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        child: Center(
                          child: Text('$_unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.search_rounded, color: Colors.white),
                onPressed: _goSearch,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6EA870), Color(0xFF4A7A50), Color(0xFF3A6140)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(right: -40, top: -30,
                      child: Container(width: 160, height: 160,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.07)))),
                    Positioned(right: 20, top: 20,
                      child: Container(width: 80, height: 80,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05)))),
                    Positioned(left: -20, bottom: -20,
                      child: Container(width: 110, height: 110,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06)))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 70, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('探索諸羅',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                              color: Colors.white, letterSpacing: 2)),
                          const SizedBox(height: 4),
                          Text('嘉義・在地旅遊全攻略',
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85), letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWeatherCard(),
                _buildQuickAccessGrid(),
                _buildTransportSection(),
                _buildNewsBanner(),
                _buildNearbySpots(),
                _buildHotFood(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Weather ──
  Widget _buildWeatherCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeatherScreen())),
      child: Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7AB8CC), Color(0xFF5B8A5F)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF7AB8CC).withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('嘉義市', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                const Text('⛅ 多雲時晴', style: TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 12),
                Row(children: [
                  _wInfo('💧', '75%'),
                  const SizedBox(width: 14),
                  _wInfo('💨', '12km/h'),
                  const SizedBox(width: 14),
                  _wInfo('☀️', 'UV 8'),
                ]),
              ],
            ),
          ),
          Column(children: [
            const Text('32°', style: TextStyle(color: Colors.white, fontSize: 50, fontWeight: FontWeight.w200)),
            Text('體感 35°', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
          ]),
        ],
      ),
    )); // closes GestureDetector child
  }

  Widget _wInfo(String icon, String v) => Row(children: [
    Text(icon, style: const TextStyle(fontSize: 11)),
    const SizedBox(width: 2),
    Text(v, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.w600)),
  ]);

  Widget _quickRow(List<_QuickItem> rowItems) {
    return Row(
      children: rowItems.asMap().entries.map((e) {
        final isLast = e.key == rowItems.length - 1;
        return Expanded(child: Container(
          margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: e.value.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: e.value.color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(e.value.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 5),
                Text(e.value.label, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ]),
            ),
          ),
        ));
      }).toList(),
    );
  }

  // ── Quick Access Grid ── 每個按鈕都有真實跳轉 ──
  Widget _buildQuickAccessGrid() {
    final items = [
      _QuickItem('🗺️', '地圖探索', const Color(0xFFE6F0E6), () => widget.onSwitchTab?.call(1)),
      _QuickItem('🗓️', '行程管理', const Color(0xFFF5EFE6), () => widget.onSwitchTab?.call(2)),
      _QuickItem('💸', '旅遊分帳', const Color(0xFFEDF5ED), () => widget.onSwitchTab?.call(3)),
      _QuickItem('👥', '旅遊社群', const Color(0xFFEBEFF2), () => widget.onSwitchTab?.call(4)),
      _QuickItem('📅', '活動行事曆', const Color(0xFFF0EBF5),
        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventsScreen()))),
      _QuickItem('🚌', '交通動態', const Color(0xFFE8F0F5),
        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransportScreen()))),
      _QuickItem('🎖️', '集章成就', const Color(0xFFF5F0E8), () => widget.onSwitchTab?.call(5)),
      _QuickItem('📸', '打卡相機', const Color(0xFFF0EDF5),
        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: SectionHeader(title: '快速導覽'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _quickRow(items.sublist(0, 4)),
              const SizedBox(height: 10),
              _quickRow(items.sublist(4, 8)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Transport ──
  Widget _buildTransportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: SectionHeader(
            title: '交通動態',
            actionText: '更多',
            onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransportScreen())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: _transportCard('🚌', '市區公車', '紅幹線', '3 分鐘', const Color(0xFFC4856A), 0)),
              const SizedBox(width: 10),
              Expanded(child: _transportCard('🚲', 'YouBike', '火車站', '8 輛可借', const Color(0xFF5B8A5F), 1)),
              const SizedBox(width: 10),
              Expanded(child: _transportCard('🚂', '台鐵', '嘉→台北', '14:05', const Color(0xFF88B8C8), 2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _transportCard(String icon, String type, String line, String info, Color color, int tabIdx) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransportScreen(initialTab: tabIdx))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(type, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          Text(line, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(info, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('點此查看 ›', style: TextStyle(fontSize: 9, color: color.withOpacity(0.7), fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── News Banner ──
  Widget _buildNewsBanner() {
    final news = DummyData.news;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: SectionHeader(
            title: '最新消息',
            actionText: '全部',
            onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewsScreen())),
          ),
        ),
        SizedBox(
          height: 130,
          child: PageView.builder(
            controller: _bannerController,
            onPageChanged: (i) => setState(() => _currentBanner = i),
            itemCount: news.length,
            itemBuilder: (_, index) {
              final item = news[index];
              final catEmoji = {'活動':'🏮','交通':'🚌','美食':'🍜','旅遊':'🏔️','公告':'📢'}[item.category] ?? '📋';
              final catColor = {'活動':const Color(0xFFE8A87C),'交通':const Color(0xFF88B8C8),
                '美食':const Color(0xFFD4A847),'旅遊':const Color(0xFF8FBF8F),'公告':const Color(0xFFB8A8E8)}[item.category] ?? AppColors.textHint;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => _showNewsDetail(item),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWarm,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: const Offset(0,2))],
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 54, height: 54,
                        decoration: BoxDecoration(color: catColor.withOpacity(0.13), borderRadius: BorderRadius.circular(14)),
                        child: Center(child: Text(catEmoji, style: const TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: catColor.withOpacity(0.13), borderRadius: BorderRadius.circular(6)),
                            child: Text(item.category, style: TextStyle(color: catColor, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          Text(item.date, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                        ]),
                        const SizedBox(height: 7),
                        Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 5),
                        Text(item.summary, style: const TextStyle(fontSize: 11, color: AppColors.textHint, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(news.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _currentBanner ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i == _currentBanner ? AppColors.primary : AppColors.textHint.withOpacity(0.3),
            ),
          )),
        ),
      ],
    );
  }

  void _showNewsDetail(NewsItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(item.category, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 10),
              Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(item.date, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
              const SizedBox(height: 14),
              Text('${item.summary}\n\n這是示範文章內容，實際串接後將顯示完整新聞。嘉義市觀光局持續更新最新旅遊資訊，歡迎持續關注探索諸羅App。',
                style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.8)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Nearby spots ──
  Widget _buildNearbySpots() {
    final attractions = DummyData.spots.where((s) => s.category == 'attraction').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: SectionHeader(
            title: '附近景點',
            actionText: '查看地圖',
            onAction: () => widget.onSwitchTab?.call(1),
          ),
        ),
        SizedBox(
          height: 215,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: attractions.length,
            itemBuilder: (_, i) {
              final s = attractions[i];
              return SpotCard(
                name: s.name, category: s.category, rating: s.rating,
                imageUrl: s.imageUrl, address: s.address, isLiked: s.isLiked,
                onTap: () => _showSpotDetail(s),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Hot food ──
  Widget _buildHotFood() {
    final restaurants = DummyData.spots.where((s) => s.category == 'restaurant').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: SectionHeader(title: '人氣美食', actionText: '更多', onAction: _goSearch),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: restaurants.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceWarm,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(s.imageUrl, width: 54, height: 54, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(width: 54, height: 54,
                      color: AppColors.surfaceMoss,
                      child: const Center(child: Text('🍜', style: TextStyle(fontSize: 22))))),
                ),
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                subtitle: Row(children: [
                  const Icon(Icons.star_rounded, size: 12, color: AppColors.accentStraw),
                  Text(' ${s.rating}  ·  ${s.openHours}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                onTap: () => _showSpotDetail(s),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  void _showSpotDetail(Spot spot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpotDetailSheet(spot: spot),
    );
  }
}

// ── Quick item model ──
class _QuickItem {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  _QuickItem(this.icon, this.label, this.color, this.onTap);
}

// ── Spot detail sheet ──
class _SpotDetailSheet extends StatefulWidget {
  final Spot spot;
  const _SpotDetailSheet({required this.spot});
  @override
  State<_SpotDetailSheet> createState() => _SpotDetailSheetState();
}

class _SpotDetailSheetState extends State<_SpotDetailSheet> {
  bool _liked = false;
  bool _saved = false;
  int _imgIndex = 0;

  // Simulated multiple images per spot
  List<String> get _images => [
    widget.spot.imageUrl,
    widget.spot.imageUrl.replaceAll(RegExp(r'/\d+/\d+$'), '/400/300') + '?v=2',
    widget.spot.imageUrl.replaceAll(RegExp(r'seed/\w+/'), 'seed/${widget.spot.id}b/'),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Image carousel ──
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      child: Stack(
                        children: [
                          SizedBox(
                            height: 240,
                            child: PageView.builder(
                              itemCount: _images.length,
                              onPageChanged: (i) => setState(() => _imgIndex = i),
                              itemBuilder: (_, i) => Image.network(
                                _images[i], fit: BoxFit.cover, width: double.infinity, height: 240,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 240, color: AppColors.surfaceMoss,
                                  child: Center(child: Text(
                                    widget.spot.category == 'restaurant' ? '🍜' : '🏛️',
                                    style: const TextStyle(fontSize: 60))),
                                ),
                              ),
                            ),
                          ),
                          // Dot indicators
                          Positioned(bottom: 10, left: 0, right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(_images.length, (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _imgIndex ? 16 : 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  color: i == _imgIndex ? Colors.white : Colors.white54,
                                ),
                              )),
                            ),
                          ),
                          // Image count badge
                          Positioned(top: 12, right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                              child: Text('${_imgIndex + 1}/${_images.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text(widget.spot.name,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                            IconButton(
                              onPressed: () => setState(() => _liked = !_liked),
                              icon: Icon(_liked ? Icons.favorite : Icons.favorite_border,
                                color: _liked ? AppColors.error : AppColors.textHint)),
                            IconButton(
                              onPressed: () => setState(() => _saved = !_saved),
                              icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border,
                                color: _saved ? AppColors.primary : AppColors.textHint)),
                          ]),
                          Row(children: [
                            const Icon(Icons.star_rounded, size: 15, color: AppColors.accentStraw),
                            Text(' ${widget.spot.rating}  ·  ', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textHint),
                            Text('  ${widget.spot.openHours}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            const Icon(Icons.location_on_rounded, size: 13, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Expanded(child: Text(widget.spot.address,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
                          ]),
                          const SizedBox(height: 14),
                          Text(widget.spot.description,
                            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.7)),
                          const SizedBox(height: 20),
                          Row(children: [
                            Expanded(child: ElevatedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('加入行程'),
                            )),
                            const SizedBox(width: 10),
                            _iconBtn(Icons.map_outlined, () {}),
                            const SizedBox(width: 8),
                            _iconBtn(Icons.share_outlined, () {}),
                          ]),
                        ],
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

  Widget _iconBtn(IconData icon, VoidCallback onTap) => Container(
    decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
    child: IconButton(icon: Icon(icon, color: AppColors.textSecondary, size: 20), onPressed: onTap),
  );
}
