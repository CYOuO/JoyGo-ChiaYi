import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'search_screen.dart';
import '../models/dummy_data.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _likedTrips = {};
  RangeValues _budgetRange = const RangeValues(0, 3000);  // 預算範圍篩選（元/人）
  static const double _budgetMax = 3000;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          '旅遊社群',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '探索'),
            Tab(text: '追蹤中'),
            Tab(text: '我的貼文'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExploreTab(),
          _buildFollowingTab(),
          _buildMyPostsTab(),
        ],
      ),
    );
  }

  Widget _buildExploreTab() {
    final trips = DummyData.communityTrips;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Featured banner
        _buildFeaturedBanner(),
        const SizedBox(height: 20),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['全部', '一日遊', '二日遊', '美食', '文化', '親子'].map((tag) {
              final isSelected = tag == '全部';
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.surfaceMoss,
                  ),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Budget RangeSlider
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('💰', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                const Text('預算篩選', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentTerra.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _budgetRange.start == 0 && _budgetRange.end >= _budgetMax
                        ? '不限預算'
                        : 'NT\$${_budgetRange.start.round()} - NT\$${_budgetRange.end >= _budgetMax ? '3000+' : _budgetRange.end.round()}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentTerra),
                  ),
                ),
              ]),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.accentTerra,
                  inactiveTrackColor: AppColors.divider,
                  thumbColor: AppColors.accentTerra,
                  overlayColor: AppColors.accentTerra.withOpacity(0.12),
                  trackHeight: 3,
                  rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: RangeSlider(
                  values: _budgetRange,
                  min: 0,
                  max: _budgetMax,
                  divisions: 30,
                  onChanged: (v) => setState(() => _budgetRange = v),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('NT\$0', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                const Text('NT\$1000', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                const Text('NT\$2000', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                const Text('NT\$3000+', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
              ]),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Trip cards (budget filtered)
        ...trips.where((t) =>
          t.budget >= _budgetRange.start &&
          (t.budget <= _budgetRange.end || _budgetRange.end >= _budgetMax)
        ).map((trip) => _buildCommunityCard(trip)),
      ],
    );
  }

  Widget _buildFeaturedBanner() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentStraw,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '本週精選',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '嘉義文青散步路線\n共獲234次按讚 🎉',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '由「城市探索者」分享',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(TripPlan trip) {
    final isLiked = _likedTrips.contains(trip.id);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailPage(
        trip: trip,
        initialLiked: isLiked,
        onLikeChanged: (v) => setState(() => v ? _likedTrips.add(trip.id) : _likedTrips.remove(trip.id)),
      ))),
      child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Creator header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: NetworkImage(trip.creatorAvatar),
                  backgroundColor: AppColors.surfaceMoss,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.creatorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Row(children: [
                        Text(
                          trip.date,
                          style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentTerra.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6)),
                          child: Text('💰 NT\$${trip.budget}/人',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accentTerra)),
                        ),
                      ]),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '套用行程',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cover image
          if (trip.coverImage != null)
            Image.network(
              trip.coverImage!,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: AppColors.surfaceMoss,
                child: const Center(child: Text('🗺️', style: TextStyle(fontSize: 48))),
              ),
            ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                // Spot tags
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: trip.spotIds.take(3).map((id) {
                    final spot = DummyData.spots.firstWhere(
                      (s) => s.id == id,
                      orElse: () => DummyData.spots[0],
                    );
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMoss,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '📍 ${spot.name}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isLiked) {
                            _likedTrips.remove(trip.id);
                          } else {
                            _likedTrips.add(trip.id);
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? AppColors.error : AppColors.textHint,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${trip.likes + (isLiked ? 1 : 0)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Icon(Icons.chat_bubble_outline_rounded,
                        size: 18, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    const Text('23',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(width: 20),
                    const Icon(Icons.share_outlined, size: 18, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    const Text('分享',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已加入收藏'), backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating)),
                      child: const Icon(Icons.bookmark_border_rounded, size: 20, color: AppColors.textHint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ));  // closes GestureDetector child + GestureDetector
  }

  Widget _buildFollowingTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('👥', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text(
            '還沒有追蹤任何人',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '去探索頁面找找志同道合的旅伴吧！',
            style: TextStyle(color: AppColors.textHint),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _tabController.animateTo(0),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('探索社群'),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPostsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('✏️', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text(
            '尚未發布任何行程',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '分享你的嘉義旅行，讓更多人看見！',
            style: TextStyle(color: AppColors.textHint),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('發布行程'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// POST DETAIL PAGE
// ═══════════════════════════════════════════════
class PostDetailPage extends StatefulWidget {
  final TripPlan trip;
  final bool initialLiked;
  final void Function(bool) onLikeChanged;
  const PostDetailPage({super.key, required this.trip, required this.initialLiked, required this.onLikeChanged});
  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late bool _liked;
  final TextEditingController _commentCtrl = TextEditingController();
  final List<_Comment> _comments = [
    _Comment(name:'阿山哥', emoji:'🧑', text:'超棒的行程！我去年也去了一樣的路線，北門車站的日落真的美極了。', time:'2小時前', likes:14),
    _Comment(name:'旅行小咪', emoji:'👩', text:'這個阿里山的section想多了解，請問幾點去最好呢？早上日出嗎？', time:'5小時前', likes:8),
    _Comment(name:'嘉義人', emoji:'😊', text:'本地人推薦！文化路夜市要早去才有位置，週末超多人！', time:'昨天', likes:23),
  ];

  @override
  void initState() {
    super.initState();
    _liked = widget.initialLiked;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          CircleAvatar(radius: 14, backgroundImage: NetworkImage(widget.trip.creatorAvatar),
            backgroundColor: AppColors.surfaceMoss),
          const SizedBox(width: 8),
          Text(widget.trip.creatorName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Cover image
                if (widget.trip.coverImage != null)
                  Image.network(widget.trip.coverImage!, height: 230, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(height: 230, color: AppColors.surfaceMoss,
                      child: const Center(child: Text('🗺️', style: TextStyle(fontSize: 60))))),

                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Title & meta
                    Text(widget.trip.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textHint),
                      Text('  ${widget.trip.date}', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                      const SizedBox(width: 14),
                      const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textHint),
                      Text('  ${widget.trip.spotIds.length} 個景點 · ${widget.trip.days}天',
                        style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                    ]),
                    const SizedBox(height: 14),

                    // Description
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMoss,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(
                        '${widget.trip.title}是一趟結合文化、美食與自然的嘉義深度旅行。第一天從阿里山的壯闊晨霧開始，帶你感受高山的清新空氣；下午回到市區探索北門車站的歷史氛圍，傍晚在文化路夜市品嚐在地小吃。第二天安排嘉義公園漫步以及市立美術館，最後帶著滿滿回憶返程。\n\n💡 小提醒：阿里山建議平日前往人較少，文化路夜市週末很熱鬧要早點去佔位！',
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.8),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Spot list
                    const Text('行程景點', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    ...widget.trip.spotIds.asMap().entries.map((e) {
                      final spot = DummyData.spots.firstWhere((s) => s.id == e.value, orElse: () => DummyData.spots[0]);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceWarm,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(children: [
                          Container(width: 26, height: 26, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: Center(child: Text('${e.key+1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)))),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(spot.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                            Text(spot.address, style: const TextStyle(fontSize: 11, color: AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 16),
                        ]),
                      );
                    }),

                    const SizedBox(height: 16),

                    // Like / comment bar
                    Row(children: [
                      GestureDetector(
                        onTap: () { setState(() => _liked = !_liked); widget.onLikeChanged(_liked); },
                        child: Row(children: [
                          Icon(_liked ? Icons.favorite : Icons.favorite_border,
                            color: _liked ? AppColors.error : AppColors.textHint, size: 22),
                          const SizedBox(width: 5),
                          Text('${widget.trip.likes + (_liked ? 1 : 0)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const SizedBox(width: 20),
                      Row(children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: AppColors.textHint),
                        const SizedBox(width: 5),
                        Text('${_comments.length}', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      ]),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('套用行程'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ]),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 14),

                    // Comments
                    Row(children: [
                      const Text('留言區', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primaryMist, borderRadius: BorderRadius.circular(8)),
                        child: Text('${_comments.length}', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    ..._comments.map((c) => _commentTile(c)),
                    const SizedBox(height: 80),
                  ]),
                ),
              ],
            ),
          ),
          // Comment input bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(children: [
              const CircleAvatar(radius: 16, backgroundColor: AppColors.primaryMist,
                child: Text('😊', style: TextStyle(fontSize: 14))),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: const InputDecoration(hintText: '留下你的想法…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                  minLines: 1, maxLines: 3,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_commentCtrl.text.trim().isEmpty) return;
                  setState(() {
                    _comments.insert(0, _Comment(name:'我', emoji:'😊', text:_commentCtrl.text.trim(), time:'剛剛', likes:0));
                    _commentCtrl.clear();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _commentTile(_Comment c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.surfaceMoss, shape: BoxShape.circle),
          child: Center(child: Text(c.emoji, style: const TextStyle(fontSize: 16)))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Text(c.time, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ]),
            const SizedBox(height: 4),
            Text(c.text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.favorite_border, size: 13, color: AppColors.textHint),
              const SizedBox(width: 3),
              Text('${c.likes}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              const SizedBox(width: 12),
              const Text('回覆', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Comment {
  final String name, emoji, text, time;
  final int likes;
  const _Comment({required this.name, required this.emoji, required this.text, required this.time, required this.likes});
}
