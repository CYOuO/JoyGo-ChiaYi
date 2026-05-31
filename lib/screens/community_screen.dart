import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart' show StitchedBox, HandDrawnUnderline, DoodleCircle;
import '../models/dummy_data.dart';
import '../services/community_service.dart';
import '../widgets/common_widgets.dart' show WashiTapeDivider;

// 全域時間格式化工具
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
  if (diff.inDays < 1) return '${diff.inHours} 小時前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${dt.month}/${dt.day}';
}

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  // ── 主 tab：0=我的貼文  1=追蹤的貼文  2=探索全部
  int _tabIndex = 2;
  late final PageController _pageController;

  // ── 防止 onPageChanged 在程式觸發的動畫中更新 _tabIndex ──────────
  // ROOT CAUSE of tab hiccup: PageView fires onPageChanged for each
  // intermediate page during animateToPage, causing pill to jump to
  // the middle tab briefly. This flag blocks those spurious callbacks.
  bool _programmaticScroll = false;

  // ── 探索子分類：0=行程分享  1=討論區
  int _contentTab = 0;
  // ── 排序：true=最新  false=熱門
  bool _sortLatest = true;

  final Set<String> _likedTrips = {};
  // 追蹤：key=authorId, value=authorName（本地快取供 UI 使用）
  final Map<String, String> _followedUsers = {};
  Set<String> get _followedIds => _followedUsers.keys.toSet();
  RangeValues _budgetRange = const RangeValues(0, 3000);
  static const double _budgetMax = 3000;
  bool get _budgetActive => _budgetRange.start > 0 || _budgetRange.end < _budgetMax;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  // 標籤篩選（null = 全部）
  String? _selectedTag;
  static const _kTags = ['嘉義市', '親子', '美食', '文化'];

  int get _pageIndex => 2 - _tabIndex;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _pageIndex);
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    // Load following list from Firebase
    CommunityService.followingIdsStream().listen((ids) async {
      if (!mounted) return;
      // We need the names too – fetch from following subcollection
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('following').get();
      if (mounted) {
        setState(() {
          _followedUsers.clear();
          for (final d in snap.docs) {
            _followedUsers[d.id] = d.data()['name']?.toString() ?? '';
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜尋景點名稱，篩選行程…',
                  hintStyle: const TextStyle(fontSize: 14),
                  border: InputBorder.none,
                  filled: false,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          })
                      : null,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Builder(builder: (ctx) {
                final p = Theme.of(ctx).colorScheme.primary;
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 22, child: Stack(children: [
                    Positioned(left: 0, top: 3, child: Container(width: 8, height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: p))),
                    Positioned(left: 6, top: 12, child: Container(width: 5, height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        color: p.withValues(alpha: 0.35)))),
                  ])),
                  const SizedBox(width: 2),
                  const Text('旅遊社群', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ]);
              }),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() { _isSearching = false; _searchQuery = ''; });
                })
            : null,
        actions: _isSearching ? [] : [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
            onPressed: () => setState(() => _isSearching = true),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Segmented Control (pill 膠囊式) ──────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _SegmentedControl(
              labels: const ['我的貼文', '追蹤的貼文', '探索全部'],
              selectedIndex: _tabIndex,
              primary: primary,
              onChanged: (i) {
                if (_tabIndex == i) return;
                setState(() { _tabIndex = i; _programmaticScroll = true; });
                _pageController
                    .animateToPage(2 - i,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut)
                    .then((_) { if (mounted) _programmaticScroll = false; });
              },
            ),
          ),

          // ── PageView：反轉子頁順序讓「左滑」感覺正確 ────────────
          // page 0 = segmented 2 = 探索全部
          // page 1 = segmented 1 = 追蹤的貼文
          // page 2 = segmented 0 = 我的貼文
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (pageIdx) {
                // Ignore intermediate pages during programmatic animation
                if (!_programmaticScroll) {
                  setState(() => _tabIndex = 2 - pageIdx);
                }
              },
              children: [
                _buildExploreTab(),
                _buildFollowingTab(),
                _buildMyPostsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExploreTab() {
    final primary = Theme.of(context).colorScheme.primary;
    final trips = DummyData.communityTrips;

    // 依排序排列
    final sorted = [...trips];
    if (!_sortLatest) sorted.sort((a, b) => b.likes.compareTo(a.likes));

    // 依搜尋 + 預算 + 標籤過濾
    final q = _searchQuery.trim().toLowerCase();
    final filtered = sorted.where((t) {
      // 預算篩選
      final budgetOk = t.budget >= _budgetRange.start &&
          (t.budget <= _budgetRange.end || _budgetRange.end >= _budgetMax);
      if (!budgetOk) return false;
      // 標籤篩選（簡單關鍵字比對行程標題或景點名稱）
      if (_selectedTag != null) {
        final tag = _selectedTag!.toLowerCase();
        final tagMatch = t.title.toLowerCase().contains(tag) ||
            t.spotIds.any((id) {
              final spot = DummyData.spots.firstWhere(
                  (s) => s.id == id, orElse: () => DummyData.spots[0]);
              return spot.name.toLowerCase().contains(tag) ||
                  spot.address.toLowerCase().contains(tag);
            });
        if (!tagMatch) return false;
      }
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.spotIds.any((id) {
            final spot = DummyData.spots.firstWhere(
                (s) => s.id == id, orElse: () => DummyData.spots[0]);
            return spot.name.toLowerCase().contains(q);
          });
    }).toList();

    return Column(
      children: [
        // ── Filter bar ────────────────────────────────────────
        Container(
          color: AppColors.surface,
          child: Column(children: [
            // Row 1：分類 chips（全寬可滾動，不塞排序按鈕）
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                _tagChip('全部', null, primary),
                ..._kTags.map((t) => _tagChip(t, t, primary)),
              ]),
            ),
            // Row 2：預算滑桿（直接顯示）+ 排序按鈕
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(children: [
                Icon(Icons.attach_money_rounded, size: 14,
                    color: _budgetActive ? primary : AppColors.textHint),
                Expanded(child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: primary,
                    inactiveTrackColor: AppColors.divider,
                    thumbColor: primary,
                    overlayColor: primary.withValues(alpha: 0.1),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: RangeSlider(
                    values: _budgetRange,
                    min: 0, max: _budgetMax, divisions: 30,
                    onChanged: (v) => setState(() => _budgetRange = v),
                  ),
                )),
                Text(
                  _budgetActive
                      ? 'NT\$${_budgetRange.start.round()}–${_budgetRange.end >= _budgetMax ? "不限" : "${_budgetRange.end.round()}"}'
                      : '不限',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: _budgetActive ? primary : AppColors.textHint)),
                const SizedBox(width: 10),
                _SortToggleButton(
                  isLatest: _sortLatest,
                  onToggle: () => setState(() => _sortLatest = !_sortLatest),
                  primary: primary,
                ),
              ]),
            ),
            // Row 3：內容分類 tab（全寬均分，下劃線式）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(children: [
                Expanded(child: _contentTabItem('行程分享', 0, primary)),
                Expanded(child: _contentTabItem('討論區', 1, primary)),
              ]),
            ),
            const Divider(height: 1),
          ]),
        ),

        // ── Content ───────────────────────────────────────────
        Expanded(
          child: _contentTab == 0
              ? _buildTripList(filtered, primary, q)
              : _buildDiscussionList(primary),
        ),
      ],
    );
  }

  // ── Firebase 真實貼文卡片 ────────────────────────────────────
  Widget _firebasePostCard(CommunityPost post, Color primary) {
    return StatefulBuilder(builder: (ctx, setLocal) {
      bool liked = false; // 初始：非同步 fetch 後更新
      return FutureBuilder<bool>(
        future: CommunityService.isLiked(post.id),
        builder: (_, snap) {
          liked = snap.data ?? false;
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => FirebasePostDetailPage(post: post))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Image
                if (post.imageURLs.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.network(post.imageURLs.first,
                      height: 160, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Author row
                    Row(children: [
                      CircleAvatar(radius: 16,
                        backgroundImage: post.authorPhoto.isNotEmpty
                            ? NetworkImage(post.authorPhoto) : null,
                        backgroundColor: primary.withValues(alpha: 0.1),
                        child: post.authorPhoto.isEmpty
                            ? Icon(Icons.person_rounded, size: 16, color: primary)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: GestureDetector(
                        onTap: () => _showAuthorProfile(context, post, primary),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(post.authorName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(_timeAgo(post.createdAt),
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                        ]),
                      )),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(post.type == 'trip' ? Icons.luggage_rounded : Icons.chat_rounded,
                            size: 10, color: primary),
                          const SizedBox(width: 3),
                          Text(post.type == 'trip' ? '行程' : '討論',
                            style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(post.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    if (post.content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(post.content,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      GestureDetector(
                        onTap: () async {
                          final now = await CommunityService.toggleLike(post.id);
                          setLocal(() => liked = now);
                        },
                        child: Row(children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                            child: Icon(
                              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              key: ValueKey(liked),
                              size: 18,
                              color: liked ? AppColors.error : AppColors.textHint,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('${post.likeCount + (liked ? 0 : 0)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ]),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.chat_bubble_outline_rounded, size: 16, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text('${post.commentCount}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          await CommunityService.toggleSave(post.id);
                        },
                        child: const Icon(Icons.bookmark_border_rounded, size: 18, color: AppColors.textHint),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => Share.share('探索諸羅 · ${post.title}\n\n${post.content}'),
                        child: const Icon(Icons.share_outlined, size: 18, color: AppColors.textHint),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
    });
  }

  // ── 建立貼文 bottom sheet ─────────────────────────────────────
  void _showCreatePostSheet(BuildContext context, Color primary, {String defaultType = 'trip'}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先登入才能發布貼文'), behavior: SnackBarBehavior.floating));
      return;
    }
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CreatePostPage(primary: primary, defaultType: defaultType)));
  }

  void _showBudgetSheet(BuildContext context, Color primary) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              Text('預算篩選', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setLocal(() {});
                  setState(() => _budgetRange = const RangeValues(0, _budgetMax));
                  Navigator.pop(ctx);
                },
                child: const Text('重設'),
              ),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('NT\$${_budgetRange.start.round()}', style: TextStyle(fontSize: 14, color: primary, fontWeight: FontWeight.w700)),
              Text(_budgetRange.end >= _budgetMax ? '不限金額' : 'NT\$${_budgetRange.end.round()}',
                style: TextStyle(fontSize: 14, color: primary, fontWeight: FontWeight.w700)),
            ]),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: primary,
                inactiveTrackColor: AppColors.divider,
                thumbColor: primary,
                overlayColor: primary.withValues(alpha: 0.12),
                trackHeight: 4,
                rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: RangeSlider(
                values: _budgetRange,
                min: 0, max: _budgetMax, divisions: 30,
                onChanged: (v) {
                  setLocal(() {});
                  setState(() => _budgetRange = v);
                },
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('NT\$0', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              Text('NT\$1000', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              Text('NT\$2000', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              Text('不限', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('套用篩選'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, Color primary) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? primary : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? primary : AppColors.divider),
      ),
      child: Text(label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary)),
    );
  }

  Widget _tagChip(String label, String? tag, Color primary) {
    final selected = _selectedTag == tag;
    return GestureDetector(
      onTap: () => setState(() => _selectedTag = tag),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? primary : AppColors.divider),
        ),
        child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  Widget _contentTabItem(String label, int index, Color primary) {
    final selected = _contentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _contentTab = index),
      child: Column(children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
            color: selected ? primary : AppColors.textHint),
          child: Text(label, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 3.0,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ]),
    );
  }

  // ── 行程分享：StreamBuilder from Firebase，搭配 dummy fallback ──
  Widget _buildTripList(List<TripPlan> dummyTrips, Color primary, String q) {
    return StreamBuilder<List<CommunityPost>>(
      stream: CommunityService.postsStream(
          type: 'trip', byLikes: !_sortLatest),
      builder: (ctx, snap) {
        final fbPosts = snap.data ?? [];
        return Stack(children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              _buildFeaturedBanner(),
              const WashiTapeDivider(color: Color(0x18D4A574)),
              // Firebase 真實貼文
              if (fbPosts.isNotEmpty) ...[
                ...fbPosts.map((p) => _firebasePostCard(p, primary)),
                const Divider(height: 32),
              ],
              // Dummy fallback（若 Firestore 空白時仍有內容展示）
              ...dummyTrips.map((trip) => _buildCommunityCard(trip)),
            ],
          ),
          // FAB — 發布新貼文
          Positioned(
            right: 16, bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'create_post',
              onPressed: () => _showCreatePostSheet(context, primary),
              icon: const Icon(Icons.add_rounded),
              label: const Text('發文'),
              backgroundColor: primary,
              foregroundColor: Colors.white,
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildDiscussionList(Color primary) {
    return StreamBuilder<List<CommunityPost>>(
      stream: CommunityService.postsStream(type: 'discussion', byLikes: !_sortLatest),
      builder: (ctx, snap) {
        final fbPosts = snap.data ?? [];
        // Show spinner on first load, not on updates (avoids flashing empty state)
        final isFirstLoad = snap.connectionState == ConnectionState.waiting && snap.data == null;
        return Stack(children: [
          isFirstLoad
              ? const Center(child: CircularProgressIndicator())
              : fbPosts.isEmpty
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 52, color: AppColors.textHint),
                        const SizedBox(height: 12),
                        const Text('還沒有討論', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        const Text('點下方按鈕發起第一個討論！', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                      ],
                    ))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      children: fbPosts.map((p) => _firebasePostCard(p, primary)).toList(),
                    ),
          // FAB
          Positioned(
            right: 16, bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'create_discussion',
              onPressed: () => _showCreatePostSheet(context, primary, defaultType: 'discussion'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('發文'),
              backgroundColor: primary,
              foregroundColor: Colors.white,
            ),
          ),
        ]);
      },
    );
  }

  Widget _discussionCard((String, String, String, String, int, String) post, Color primary) {
    return GestureDetector(
      onTap: () => _showDiscussionDetail(context, post, primary),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Center(child: Text(post.$4, style: const TextStyle(fontSize: 16)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.$3, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(post.$6, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('💬 討論', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(post.$1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(post.$2, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.favorite_border_rounded, size: 15, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text('${post.$5}', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(width: 14),
            Icon(Icons.chat_bubble_outline_rounded, size: 15, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text('${post.$5 ~/ 3}', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textHint.withValues(alpha: 0.5)),
          ]),
        ]),
      ),
    );
  }

  void _showDiscussionDetail(BuildContext context,
      (String, String, String, String, int, String) post, Color primary) {
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Center(child: Container(width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
              // Author
              Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Center(child: Text(post.$4, style: const TextStyle(fontSize: 18)))),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(post.$3, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(post.$6, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                ]),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(8)),
                  child: Text('💬 討論', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 14),
              _BrushedTitle(text: post.$1, primary: primary),
              const SizedBox(height: 12),
              Text(post.$2, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.8)),
              const SizedBox(height: 6),
              Text('歡迎分享你的看法與建議，讓更多旅人參考！', style: TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.7)),
              const Divider(height: 28),
              Row(children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 15, color: primary),
                const SizedBox(width: 6),
                Text('留言區', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary)),
              ]),
              const SizedBox(height: 12),
              _discussionReply('旅行達人', '🌟', '謝謝分享！這個問題我也很好奇，期待更多人的回覆。', '1小時前', 5, primary),
              _discussionReply('嘉義在地人', '🏡', '我是本地人，可以幫你解答，嘉義最值得去的就是文化路和北門車站周邊！', '3小時前', 12, primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _discussionReply(String name, String emoji, String text, String time, int initialLikes, Color primary) {
    return StatefulBuilder(builder: (ctx, setLocal) {
      bool liked = false;
      int likes = initialLikes;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 15)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 8),
              Text(time, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ]),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 5),
            Row(children: [
              GestureDetector(
                onTap: () => setLocal(() {
                  liked = !liked;
                  likes += liked ? 1 : -1;
                }),
                child: Row(children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(
                      liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      key: ValueKey(liked),
                      size: 13,
                      color: liked ? AppColors.error : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text('$likes', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                ]),
              ),
              const SizedBox(width: 12),
              Text('回覆', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
            ]),
          ])),
        ]),
      );
    });
  }

  void _showUserProfile(BuildContext context, TripPlan trip) {
    final publishedTrips = DummyData.communityTrips
        .where((t) => t.creatorName == trip.creatorName).length;
    // Use creatorName as key for dummy data users (real users would use authorId)
    final dummyUserId = 'dummy_${trip.creatorName.hashCode}';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final followed = _followedUsers.containsKey(dummyUserId);
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              DoodleCircle(
                size: 82,
                color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.4),
                child: CircleAvatar(radius: 36, backgroundImage: NetworkImage(trip.creatorAvatar),
                  backgroundColor: AppColors.surfaceMoss)),
              const SizedBox(height: 12),
              Text(trip.creatorName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _profileStat('追蹤者', '${128 + (followed ? 1 : 0)}'),
                Container(width: 1, height: 28, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 20)),
                _profileStat('追蹤中', '34'),
                Container(width: 1, height: 28, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 20)),
                _profileStat('已發布行程', '$publishedTrips'),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final nowFollowed = await CommunityService.toggleFollow(
                        dummyUserId, trip.creatorName);
                    setState(() {
                      if (nowFollowed) {
                        _followedUsers[dummyUserId] = trip.creatorName;
                      } else {
                        _followedUsers.remove(dummyUserId);
                      }
                    });
                    setLocal(() {});
                  },
                  icon: Icon(followed ? Icons.person_remove_outlined : Icons.person_add_outlined, size: 18),
                  label: Text(followed ? '取消追蹤' : '追蹤'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: followed ? AppColors.textHint : Theme.of(ctx).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _showAuthorProfile(BuildContext context, CommunityPost post, Color primary) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        final followed = _followedUsers.containsKey(post.authorId);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            CircleAvatar(radius: 38,
              backgroundImage: post.authorPhoto.isNotEmpty ? NetworkImage(post.authorPhoto) : null,
              backgroundColor: primary.withValues(alpha: 0.1),
              child: post.authorPhoto.isEmpty ? Icon(Icons.person_rounded, size: 36, color: primary) : null),
            const SizedBox(height: 12),
            Text(post.authorName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () async {
                final now = await CommunityService.toggleFollow(post.authorId, post.authorName);
                setState(() {
                  if (now) {
                    _followedUsers[post.authorId] = post.authorName;
                  } else {
                    _followedUsers.remove(post.authorId);
                  }
                });
                setLocal(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(now ? '已追蹤 ${post.authorName}' : '已取消追蹤'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: now ? primary : AppColors.textSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
                }
              },
              icon: Icon(followed ? Icons.person_remove_outlined : Icons.person_add_outlined, size: 18),
              label: Text(followed ? '取消追蹤' : '追蹤'),
              style: ElevatedButton.styleFrom(
                backgroundColor: followed ? AppColors.textHint : primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            )),
          ]),
        );
      }),
    );
  }

  Widget _profileStat(String label, String value) => Column(children: [
    Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
  ]);

  Widget _buildFeaturedBanner() {
    final primary = Theme.of(context).colorScheme.primary;
    final primaryDark = Color.lerp(primary, Colors.black, 0.25) ?? primary;
    return StitchedBox(
      color: primary,
      stitchColor: Colors.white.withValues(alpha: 0.35),
      radius: 20,
      inset: 6,
      dashWidth: 6,
      dashGap: 4,
      stitchStrokeWidth: 1.5,
      padding: EdgeInsets.zero,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, primaryDark],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20, top: -20,
              child: Container(width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08)))),
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
                      borderRadius: BorderRadius.circular(4)),
                    child: const Text('本週精選',
                      style: TextStyle(color: AppColors.primaryDark, fontSize: 10, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 8),
                  const Text('嘉義文青散步路線\n本週最多人按讚',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.4)),
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
      clipBehavior: Clip.antiAlias,
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
                GestureDetector(
                  onTap: () => _showUserProfile(context, trip),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: NetworkImage(trip.creatorAvatar),
                    backgroundColor: AppColors.surfaceMoss,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showUserProfile(context, trip),
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
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '套用行程',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cover image — polaroid style (white border + tiny tilt)
          if (trip.coverImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Transform.rotate(
                angle: (trip.id.hashCode % 5 - 2) * 0.012, // -0.024 ~ 0.024 rad
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10, offset: const Offset(2, 3))]),
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.network(
                      trip.coverImage!,
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 170, color: AppColors.surfaceMoss,
                        child: Center(child: Icon(Icons.photo_outlined, size: 40, color: AppColors.textHint))),
                    ),
                  ),
                ),
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
                        spot.name,
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
                        SnackBar(content: const Text('已加入收藏'), backgroundColor: Theme.of(context).colorScheme.primary,
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
    final primary = Theme.of(context).colorScheme.primary;
    if (_followedIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_outlined, size: 60, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text('還沒有追蹤任何人',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('去探索頁面找找志同道合的旅伴吧！',
              style: TextStyle(color: AppColors.textHint)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() { _tabIndex = 2; _programmaticScroll = true; });
                _pageController.animateToPage(0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut)
                    .then((_) { if (mounted) _programmaticScroll = false; });
              },
              child: const Text('探索社群'),
            ),
          ],
        ),
      );
    }
    return StreamBuilder<List<CommunityPost>>(
      stream: CommunityService.followingPostsStream(_followedIds),
      builder: (ctx, snap) {
        final posts = snap.data ?? [];
        final isLoading = snap.connectionState == ConnectionState.waiting && posts.isEmpty;
        if (isLoading) return const Center(child: CircularProgressIndicator());
        if (posts.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.inbox_rounded, size: 52, color: AppColors.textHint),
            const SizedBox(height: 12),
            const Text('追蹤的人還沒有發文',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('等等看他們分享新旅程！',
              style: TextStyle(color: AppColors.textHint)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: posts.length,
          itemBuilder: (_, i) => _firebasePostCard(posts[i], primary),
        );
      },
    );
  }

  Widget _buildMyPostsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.edit_outlined, size: 60, color: AppColors.textHint),
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
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════
// 排序切換按鈕 — 有按壓縮放動畫，不用顏色區分
// ════════════════════════════════════════════════════
class _SortToggleButton extends StatefulWidget {
  final bool isLatest;
  final VoidCallback onToggle;
  final Color primary;
  const _SortToggleButton({required this.isLatest, required this.onToggle, required this.primary});

  @override
  State<_SortToggleButton> createState() => _SortToggleButtonState();
}

class _SortToggleButtonState extends State<_SortToggleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scale = Tween(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onToggle(); },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                widget.isLatest ? Icons.access_time_rounded : Icons.local_fire_department_rounded,
                key: ValueKey(widget.isLatest),
                size: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                widget.isLatest ? '最新' : '熱門',
                key: ValueKey(widget.isLatest),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// BRUSHED TITLE — 仿筆刷底色標題（與首頁 SectionHeader 同風格）
// ═══════════════════════════════════════════════
class _BrushPaint extends CustomPainter {
  final Color color;
  const _BrushPaint({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    final top    = size.height * 0.58;
    final bottom = size.height * 0.96;
    path.moveTo(-2, top + 1);
    path.cubicTo(size.width * 0.25, top - 4, size.width * 0.60, top + 5, size.width + 3, top);
    path.lineTo(size.width + 3, bottom);
    path.cubicTo(size.width * 0.55, bottom + 3, size.width * 0.20, bottom - 2, -2, bottom + 1);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BrushPaint old) => old.color != color;
}

class _BrushedTitle extends StatelessWidget {
  final String text;
  final Color primary;
  const _BrushedTitle({required this.text, required this.primary});

  @override
  Widget build(BuildContext context) {
    // Row + Spacer 讓 CustomPaint 縮到文字寬度（與 SectionHeader 同做法）
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: CustomPaint(
            painter: _BrushPaint(color: primary.withValues(alpha: 0.15)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Text(text,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary, height: 1.35)),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// SEGMENTED CONTROL v2 — AnimationController 驅動
// 文字顏色根據 pill 的即時位置連續插值，
// 過渡中間 tab 時文字保持白色，完全消除「卡一下」感
// ═══════════════════════════════════════════════
class _SegmentedControl extends StatefulWidget {
  final List<String> labels;
  final int selectedIndex;
  final Color primary;
  final void Function(int) onChanged;

  const _SegmentedControl({
    required this.labels,
    required this.selectedIndex,
    required this.primary,
    required this.onChanged,
  });

  @override
  State<_SegmentedControl> createState() => _SegmentedControlState();
}

class _SegmentedControlState extends State<_SegmentedControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _pillAnim; // fractional position (0.0 = first tab)

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240))
      ..value = 1.0;
    _pillAnim = AlwaysStoppedAnimation(widget.selectedIndex.toDouble());
  }

  @override
  void didUpdateWidget(_SegmentedControl old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      final from = _pillAnim.value; // snapshot current visual position
      _pillAnim = Tween<double>(
        begin: from,
        end: widget.selectedIndex.toDouble(),
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final pillW = (constraints.maxWidth - 8) / widget.labels.length;
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final pos = _pillAnim.value; // continuous position value
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEEF2),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              // Pill — positions driven by animated value
              Positioned(
                left: pos * pillW,
                top: 0, bottom: 0, width: pillW,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.primary,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [BoxShadow(
                      color: widget.primary.withValues(alpha: 0.28),
                      blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                ),
              ),
              // Labels — text colour lerped from pill proximity
              // When pill passes over middle tab, text turns white → no hiccup
              Row(children: List.generate(widget.labels.length, (i) {
                final overlap = (1.0 - (pos - i).abs()).clamp(0.0, 1.0);
                final textColor = Color.lerp(
                    AppColors.textSecondary, Colors.white, overlap)!;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onChanged(i),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        widget.labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: overlap > 0.5
                              ? FontWeight.w700 : FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                );
              })),
            ]),
          );
        },
      );
    });
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
  final FocusNode _commentFocus = FocusNode();
  String? _replyTarget; // name of comment being replied to
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
    _commentFocus.dispose();
    super.dispose();
  }

  void _startReply(String toName) {
    setState(() {
      _replyTarget = toName;
      _commentCtrl.text = '@$toName ';
    });
    _commentFocus.requestFocus();
    // Move cursor to end
    _commentCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _commentCtrl.text.length));
  }

  void _clearReply() {
    final target = _replyTarget;
    setState(() => _replyTarget = null);
    if (target != null && _commentCtrl.text.startsWith('@$target')) {
      _commentCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final mist = Color.lerp(primary, Colors.white, 0.88)!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
            ),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16, color: AppColors.textPrimary),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              _appBarAction(Icons.share_outlined, () {}),
              const SizedBox(width: 8),
              _appBarAction(Icons.bookmark_border_rounded, () {}),
            ]),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // ── Cover image
                Stack(children: [
                  widget.trip.coverImage != null
                    ? Image.network(widget.trip.coverImage!, height: 260,
                        width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderCover())
                    : _placeholderCover(),
                  // Gradient overlay at bottom
                  Positioned(bottom: 0, left: 0, right: 0,
                    child: Container(height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent,
                            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85)],
                        ),
                      ),
                    )),
                ]),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // ── Author row
                    Row(children: [
                      CircleAvatar(radius: 16,
                        backgroundImage: NetworkImage(widget.trip.creatorAvatar),
                        backgroundColor: AppColors.surfaceMoss),
                      const SizedBox(width: 8),
                      Text(widget.trip.creatorName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      Text('· ${widget.trip.date}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                    ]),
                    const SizedBox(height: 12),

                    // ── Title with brush stroke
                    _BrushedTitle(text: widget.trip.title, primary: primary),
                    const SizedBox(height: 10),

                    // ── Meta chips
                    Row(children: [
                      _metaChip(Icons.access_time_rounded, '${widget.trip.days}天行程', mist, primary),
                      const SizedBox(width: 8),
                      _metaChip(Icons.place_outlined, '${widget.trip.spotIds.length} 個景點', mist, primary),
                    ]),
                    const SizedBox(height: 18),

                    // ── Like / apply row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Row(children: [
                        GestureDetector(
                          onTap: () { setState(() => _liked = !_liked); widget.onLikeChanged(_liked); },
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                            child: Row(key: ValueKey(_liked), children: [
                              Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: _liked ? AppColors.error : AppColors.textHint, size: 20),
                              const SizedBox(width: 5),
                              Text('${widget.trip.likes + (_liked ? 1 : 0)}',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                    color: _liked ? AppColors.error : AppColors.textSecondary)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 18),
                        const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppColors.textHint),
                        const SizedBox(width: 5),
                        Text('${_comments.length}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.add_rounded, size: 15),
                          label: const Text('套用行程'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 18),

                    // ── Description card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.description_outlined, size: 16, color: primary),
                          const SizedBox(width: 6),
                          HandDrawnUnderline(
                            color: primary.withValues(alpha: 0.25),
                            child: Text('行程介紹',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary))),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          '${widget.trip.title}是一趟結合文化、美食與自然的嘉義深度旅行。第一天從阿里山的壯闊晨霧開始，帶你感受高山的清新空氣；下午回到市區探索北門車站的歷史氛圍，傍晚在文化路夜市品嚐在地小吃。第二天安排嘉義公園漫步以及市立美術館，最後帶著滿滿回憶返程。\n\n💡 小提醒：阿里山建議平日前往，文化路夜市週末很熱鬧要早點去佔位！',
                          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.8)),
                      ]),
                    ),
                    const SizedBox(height: 18),

                    // ── Spot list card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.place_rounded, size: 16, color: primary),
                          const SizedBox(width: 6),
                          HandDrawnUnderline(
                            color: primary.withValues(alpha: 0.25),
                            child: Text('行程景點',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary))),
                        ]),
                        const SizedBox(height: 12),
                        ...widget.trip.spotIds.asMap().entries.map((e) {
                          final spot = DummyData.spots.firstWhere(
                              (s) => s.id == e.value, orElse: () => DummyData.spots[0]);
                          final isLast = e.key == widget.trip.spotIds.length - 1;
                          return Column(children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                              Column(children: [
                                Container(width: 28, height: 28,
                                  decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                                  child: Center(child: Text('${e.key + 1}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12,
                                        fontWeight: FontWeight.w800)))),
                                if (!isLast) Container(width: 2, height: 24,
                                  color: primary.withValues(alpha: 0.2)),
                              ]),
                              const SizedBox(width: 12),
                              Expanded(child: Padding(
                                padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(spot.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700,
                                        fontSize: 14, color: AppColors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(spot.address,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                ]),
                              )),
                            ]),
                          ]);
                        }),
                      ]),
                    ),
                    const SizedBox(height: 18),

                    // ── Comments card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 16, color: primary),
                          const SizedBox(width: 6),
                          Text('留言區',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(8)),
                            child: Text('${_comments.length}',
                              style: TextStyle(color: primary, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        ..._comments.map((c) => _commentTile(c)),
                      ]),
                    ),
                    const SizedBox(height: 100),
                  ]),
                ),
              ],
            ),
          ),

          // ── Comment input bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10, offset: const Offset(0, -3))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Reply banner
              if (_replyTarget != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: mist,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(Icons.reply_rounded, size: 14, color: primary),
                    const SizedBox(width: 6),
                    Text('回覆 @$_replyTarget', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _clearReply,
                      child: Icon(Icons.close_rounded, size: 14, color: primary)),
                  ]),
                ),
              Row(children: [
                // User avatar
                Builder(builder: (ctx) {
                  final user = FirebaseAuth.instance.currentUser;
                  return CircleAvatar(
                    radius: 16,
                    backgroundColor: mist,
                    backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                    child: user?.photoURL == null
                        ? Text(user?.displayName?.isNotEmpty == true ? user!.displayName![0] : '😊',
                            style: const TextStyle(fontSize: 14))
                        : null,
                  );
                }),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    focusNode: _commentFocus,
                    decoration: InputDecoration(
                      hintText: _replyTarget != null ? '回覆 @$_replyTarget…' : '留下你的想法…',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: primary.withValues(alpha: 0.5), width: 1.5)),
                    ),
                    minLines: 1, maxLines: 3,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final text = _commentCtrl.text.trim();
                    if (text.isEmpty) return;
                    final user = FirebaseAuth.instance.currentUser;
                    final name = user?.displayName ?? '我';
                    setState(() {
                      _comments.insert(0, _Comment(
                        name: name, emoji: '😊',
                        text: text, time: '剛剛', likes: 0,
                      ));
                      _commentCtrl.clear();
                      _replyTarget = null;
                    });
                    _commentFocus.unfocus();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _appBarAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _placeholderCover() => Container(
    height: 260,
    color: AppColors.surfaceMoss,
    child: const Center(child: Text('🗺️', style: TextStyle(fontSize: 60))),
  );

  Widget _metaChip(IconData icon, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  Widget _commentTile(_Comment c) {
    final primary = Theme.of(context).colorScheme.primary;
    return StatefulBuilder(builder: (ctx, setLocal) {
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
                // ── 按讚（可互動）──
                GestureDetector(
                  onTap: () => setLocal(() {
                    c.liked = !c.liked;
                    c.likes += c.liked ? 1 : -1;
                  }),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                        child: child),
                      child: Icon(
                        c.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        key: ValueKey(c.liked),
                        size: 13,
                        color: c.liked ? AppColors.error : AppColors.textHint,
                      ),
                    ),
                    const SizedBox(width: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        '${c.likes}',
                        key: ValueKey(c.likes),
                        style: TextStyle(
                          fontSize: 11,
                          color: c.liked ? AppColors.error : AppColors.textHint,
                          fontWeight: c.liked ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                // ── 回覆（可互動）──
                GestureDetector(
                  onTap: () => _startReply(c.name),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.reply_rounded, size: 12, color: primary.withValues(alpha: 0.7)),
                    const SizedBox(width: 2),
                    Text('回覆', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      );
    });
  }
}

class _Comment {
  final String name, emoji, text, time;
  int likes;
  bool liked;
  _Comment({required this.name, required this.emoji, required this.text,
            required this.time, required this.likes, this.liked = false});
}

// ════════════════════════════════════════════════════════════
// FIREBASE POST DETAIL PAGE — 真實留言、按讚、分享
// ════════════════════════════════════════════════════════════
class FirebasePostDetailPage extends StatefulWidget {
  final CommunityPost post;
  const FirebasePostDetailPage({super.key, required this.post});
  @override
  State<FirebasePostDetailPage> createState() => _FirebasePostDetailPageState();
}

class _FirebasePostDetailPageState extends State<FirebasePostDetailPage> {
  final _commentCtrl  = TextEditingController();
  final _scrollCtrl   = ScrollController();
  final _commentFocus = FocusNode();
  bool _liked = false;
  bool _saved = false;
  bool _sending = false;
  double _lastKeyboardH = 0;
  String? _replyTarget; // name of comment being replied to
  File? _commentImage;  // image/gif to attach

  @override
  void initState() {
    super.initState();
    _loadUserState();
  }

  void _startFbReply(String toName) {
    setState(() {
      _replyTarget = toName;
      _commentCtrl.text = '@$toName ';
    });
    _commentFocus.requestFocus();
    _commentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentCtrl.text.length));
  }

  void _clearFbReply() {
    final target = _replyTarget;
    setState(() => _replyTarget = null);
    if (target != null && _commentCtrl.text.startsWith('@$target')) {
      _commentCtrl.clear();
    }
  }

  Future<void> _pickCommentImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null && mounted) setState(() => _commentImage = File(img.path));
  }

  // Called in build() when keyboard height changes
  void _onKeyboardChanged(double keyboardH) {
    if (keyboardH > 0 && _lastKeyboardH == 0) {
      // Keyboard just appeared — scroll to bottom after layout settles
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      });
    }
    _lastKeyboardH = keyboardH;
  }

  Future<void> _loadUserState() async {
    final liked = await CommunityService.isLiked(widget.post.id);
    final savedSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
        .collection('saved_posts').doc(widget.post.id).get();
    if (mounted) setState(() { _liked = liked; _saved = savedSnap.exists; });
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final mist    = Color.lerp(primary, Colors.white, 0.88)!;
    final post    = widget.post;

    // Track keyboard for auto-scroll (no focus listener needed)
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    _onKeyboardChanged(keyboardH);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(width: 34, height: 34,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)]),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 15, color: AppColors.textPrimary)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(_saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                key: ValueKey(_saved),
                color: _saved ? primary : AppColors.textHint, size: 22)),
            onPressed: () async {
              final now = await CommunityService.toggleSave(post.id);
              if (mounted) setState(() => _saved = now);
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary, size: 22),
            onPressed: () => Share.share('探索諸羅 · ${post.title}\n\n${post.content}'),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(children: [
        Expanded(child: ListView(
          controller: _scrollCtrl,
          // Top padding accounts for transparent AppBar so content isn't hidden
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + kToolbarHeight),
          children: [
          // Cover images
          if (post.imageURLs.isNotEmpty)
            SizedBox(
              height: 240,
              child: PageView.builder(
                itemCount: post.imageURLs.length,
                itemBuilder: (_, i) => Image.network(post.imageURLs[i],
                  fit: BoxFit.cover, width: double.infinity,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceMoss,
                    child: Center(child: Icon(Icons.map_outlined, size: 60, color: AppColors.textHint)))),
              ),
            )
          else
            Container(height: 120, color: primary.withValues(alpha: 0.08),
              child: Center(child: Icon(post.type == 'trip'
                  ? Icons.luggage_rounded : Icons.chat_rounded,
                  size: 60, color: primary.withValues(alpha: 0.3)))),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Author
              Row(children: [
                CircleAvatar(radius: 16,
                  backgroundImage: post.authorPhoto.isNotEmpty ? NetworkImage(post.authorPhoto) : null,
                  backgroundColor: mist,
                  child: post.authorPhoto.isEmpty ? Icon(Icons.person_rounded, size: 16, color: primary) : null),
                const SizedBox(width: 8),
                Text(post.authorName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text('· ${_timeAgo(post.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ]),
              const SizedBox(height: 12),
              // Title with brush
              _BrushedTitle(text: post.title, primary: primary),
              const SizedBox(height: 10),
              // Content
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
                ),
                child: Text(post.content,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.8)),
              ),
              if (post.spotNames.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('景點', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: post.spotNames.map((s) =>
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.place_outlined, size: 11, color: primary),
                    const SizedBox(width: 3),
                    Text(s, style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                  ]),
                  )).toList()),
              ],
              const SizedBox(height: 14),
              // Like / share bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
                ),
                child: Row(children: [
                  GestureDetector(
                    onTap: () async {
                      final now = await CommunityService.toggleLike(post.id);
                      if (mounted) setState(() => _liked = now);
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Row(key: ValueKey(_liked), children: [
                        Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: _liked ? AppColors.error : AppColors.textHint, size: 20),
                        const SizedBox(width: 4),
                        Text('${post.likeCount}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Text('${post.commentCount}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Share.share('探索諸羅 · ${post.title}\n\n${post.content}'),
                    child: const Icon(Icons.share_outlined, size: 18, color: AppColors.textHint)),
                ]),
              ),
              const SizedBox(height: 18),
              // Comments stream
              Text('留言區', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: primary)),
              const SizedBox(height: 10),
              StreamBuilder<List<CommunityComment>>(
                stream: CommunityService.commentsStream(post.id),
                builder: (_, snap) {
                  final comments = snap.data ?? [];
                  if (comments.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('還沒有留言，來搶頭香！',
                        style: TextStyle(color: AppColors.textHint, fontSize: 13))),
                    );
                  }
                  return Column(children: comments.map((c) => _fbCommentTile(c, post.id, primary)).toList());
                },
              ),
              const SizedBox(height: 80),
            ]),
          ),
        ])),
        // Comment input
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, -3))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Reply target banner
            if (_replyTarget != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: mist, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(Icons.reply_rounded, size: 14, color: primary),
                  const SizedBox(width: 6),
                  Text('回覆 @$_replyTarget', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(onTap: _clearFbReply,
                    child: Icon(Icons.close_rounded, size: 14, color: primary)),
                ]),
              ),
            // Image preview
            if (_commentImage != null) ...[
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.file(_commentImage!, height: 80, width: 80, fit: BoxFit.cover)),
                Positioned(top: 2, right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _commentImage = null),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, size: 12, color: Colors.white)),
                  )),
              ]),
              const SizedBox(height: 6),
            ],
            Row(children: [
              // Photo button
              GestureDetector(
                onTap: _pickCommentImage,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.image_outlined, size: 18, color: primary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  focusNode: _commentFocus,
                  decoration: InputDecoration(
                    hintText: _replyTarget != null ? '回覆 @$_replyTarget…' : '分享你的想法…',
                    filled: true, fillColor: const Color(0xFFF5F5F5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: primary.withValues(alpha: 0.4), width: 1.5)),
                  ),
                  minLines: 1, maxLines: 4,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : () async {
                  final text = _commentCtrl.text.trim();
                  if (text.isEmpty && _commentImage == null) return;
                  setState(() => _sending = true);
                  try {
                    await CommunityService.addComment(
                      post.id,
                      text,
                      image: _commentImage,
                    );
                    _commentCtrl.clear();
                    setState(() { _replyTarget = null; _commentImage = null; });
                    _commentFocus.unfocus();
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('留言失敗：$e'), behavior: SnackBarBehavior.floating));
                  } finally {
                    if (mounted) setState(() => _sending = false);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                  child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _fbCommentTile(CommunityComment c, String postId, Color primary) {
    return StatefulBuilder(builder: (ctx, setLocal) {
      bool liked = false;
      return FutureBuilder<Set<String>>(
        future: CommunityService.getLikedCommentIds([c.id]),
        builder: (_, snap) {
          liked = snap.data?.contains(c.id) ?? false;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 16,
                backgroundImage: c.authorPhoto.isNotEmpty ? NetworkImage(c.authorPhoto) : null,
                backgroundColor: primary.withValues(alpha: 0.08),
                child: c.authorPhoto.isEmpty ? Icon(Icons.person_rounded, size: 16, color: primary) : null),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(c.authorName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 8),
                  Text(_timeAgo(c.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                ]),
                const SizedBox(height: 4),
                Text(c.text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                if (c.imageUrl != null && c.imageUrl!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showFullImage(context, c.imageUrl!),
                    child: Hero(
                      tag: 'comment_img_${c.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          c.imageUrl!,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  // ── 按讚 (interactive) ─────────────────────
                  GestureDetector(
                    onTap: () async {
                      final now = await CommunityService.toggleCommentLike(postId, c.id);
                      setLocal(() => liked = now);
                    },
                    child: Row(children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack), child: child),
                        child: Icon(
                          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          key: ValueKey(liked), size: 13,
                          color: liked ? AppColors.error : AppColors.textHint),
                      ),
                      const SizedBox(width: 3),
                      Text('${c.likeCount}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  // ── 回覆 (now triggers reply!) ─────────────
                  GestureDetector(
                    onTap: () => _startFbReply(c.authorName),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.reply_rounded, size: 12, color: primary.withValues(alpha: 0.7)),
                      const SizedBox(width: 2),
                      Text('回覆', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ])),
            ]),
          );
        },
      );
    });
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
    if (diff.inDays < 1) return '${diff.inHours} 小時前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.push(context, PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(
            child: InteractiveViewer(
              child: Image.network(url,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64)),
            ),
          ),
        ),
      ),
    ));
  }
}

// ════════════════════════════════════════════════════════════
// CREATE POST PAGE — 建立真實貼文到 Firebase
// ════════════════════════════════════════════════════════════
class CreatePostPage extends StatefulWidget {
  final Color primary;
  final String defaultType;
  const CreatePostPage({super.key, required this.primary, this.defaultType = 'trip'});
  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _titleCtrl   = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _spotCtrl    = TextEditingController();
  late String _type;
  List<File> _images = [];
  List<String> _spots = [];
  bool _posting = false;
  // 選擇的既有行程
  Map<String, dynamic>? _selectedTrip;

  @override
  void initState() {
    super.initState();
    _type = widget.defaultType;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _spotCtrl.dispose();
    super.dispose();
  }

  // 從 Firestore 讀取使用者行程並選擇
  Future<void> _pickTrip(BuildContext context, Color primary) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('trips').where('uid', isEqualTo: uid).get();
    if (!mounted) return;
    if (snap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('你還沒有建立任何行程'), behavior: SnackBarBehavior.floating));
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          const Text('選擇行程', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...snap.docs.map((doc) {
            final d = doc.data();
            final spots = (d['spots'] as List?)?.map((s) => s.toString()).toList() ?? [];
            return ListTile(
              leading: Icon(Icons.luggage_rounded, color: primary),
              title: Text(d['title']?.toString() ?? '未命名行程',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${spots.length} 個景點'),
              onTap: () => Navigator.pop(context, {...d, '__id': doc.id, 'spots': spots}),
            );
          }),
        ]),
      ),
    );
    if (chosen != null) {
      setState(() {
        _selectedTrip = chosen;
        // 自動填入景點
        _spots = List<String>.from(chosen['spots'] ?? []);
        // 自動填入標題（如果空白）
        if (_titleCtrl.text.isEmpty && chosen['title'] != null) {
          _titleCtrl.text = chosen['title'].toString();
        }
      });
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 75, limit: 5);
    if (picked.isNotEmpty) {
      setState(() => _images = picked.map((x) => File(x.path)).toList());
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填寫標題和內容'), behavior: SnackBarBehavior.floating));
      return;
    }
    if (_type == 'trip' && _selectedTrip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('行程分享請先選擇一個行程'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _posting = true);
    try {
      await CommunityService.createPost(
        title:     _titleCtrl.text.trim(),
        content:   _contentCtrl.text.trim(),
        type:      _type,
        images:    _images,
        spotNames: _spots,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 貼文發布成功！'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('發布失敗：$e'), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('發布貼文', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: _posting ? null : _submit,
            child: _posting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('發布', style: TextStyle(fontWeight: FontWeight.w800, color: primary, fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 貼文類型
          Row(children: [
            _typeChip('🧳 行程分享', 'trip', primary),
            const SizedBox(width: 10),
            _typeChip('💬 討論區', 'discussion', primary),
          ]),
          const SizedBox(height: 12),
          // 選擇行程（僅行程分享類型）
          if (_type == 'trip') ...[
            GestureDetector(
              onTap: () => _pickTrip(context, primary),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTrip != null
                      ? primary.withValues(alpha: 0.06)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _selectedTrip != null ? primary : AppColors.divider),
                ),
                child: Row(children: [
                  Icon(Icons.luggage_rounded, size: 18,
                      color: _selectedTrip != null ? primary : AppColors.textHint),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    _selectedTrip != null
                        ? '${_selectedTrip!['title'] ?? '已選行程'}'
                        : '選擇你的行程（必填）',
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: _selectedTrip != null ? primary : AppColors.textHint),
                  )),
                  Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textHint),
                ]),
              ),
            ),
            // 顯示行程景點
            if (_selectedTrip != null && (_selectedTrip!['spots'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('行程景點', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ...(_selectedTrip!['spots'] as List).asMap().entries.map((e) =>
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Container(width: 20, height: 20,
                          decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                          child: Center(child: Text('${e.key + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)))),
                        const SizedBox(width: 8),
                        Text(e.value.toString(),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                      ]),
                    )),
                ]),
              ),
            ],
            const SizedBox(height: 12),
          ],
          // 標題
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '標題',
              hintStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textHint),
              border: InputBorder.none, filled: false),
          ),
          const Divider(),
          // 內容
          TextField(
            controller: _contentCtrl,
            maxLines: null, minLines: 5,
            decoration: InputDecoration(
              hintText: '分享你的嘉義旅行故事…',
              hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
              border: InputBorder.none, filled: false),
          ),
          const Divider(),
          // 景點 tag
          if (_spots.isNotEmpty) ...[
            Wrap(spacing: 8, children: _spots.map((s) => Chip(
              label: Text('📍 $s'),
              onDeleted: () => setState(() => _spots.remove(s)),
              backgroundColor: primary.withValues(alpha: 0.08),
              labelStyle: TextStyle(color: primary, fontWeight: FontWeight.w600),
            )).toList()),
            const SizedBox(height: 8),
          ],
          Row(children: [
            Expanded(child: TextField(
              controller: _spotCtrl,
              decoration: const InputDecoration(
                hintText: '加入景點（如：阿里山、北門車站）',
                border: InputBorder.none, filled: false),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  setState(() { _spots.add(v.trim()); _spotCtrl.clear(); });
                }
              },
            )),
            Icon(Icons.place_outlined, color: primary),
          ]),
          const Divider(),
          // 圖片
          if (_images.isNotEmpty) ...[
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(_images[i], width: 100, height: 100, fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: Text(_images.isEmpty ? '加入照片' : '更換照片（${_images.length}/5）'),
            style: OutlinedButton.styleFrom(foregroundColor: primary, side: BorderSide(color: primary)),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, String value, Color primary) {
    final sel = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? primary : Colors.transparent,
          border: Border.all(color: sel ? primary : AppColors.divider),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: sel ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

