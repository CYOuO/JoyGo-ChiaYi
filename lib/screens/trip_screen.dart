import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/dummy_data.dart';
import '../widgets/common_widgets.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TRIP SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class TripScreen extends StatefulWidget {
  const TripScreen({super.key});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showAIPanel = false;

  final List<_MockTrip> _myTrips = [
    _MockTrip(title:'嘉義週末輕旅行', date:'2025-06-07 ～ 06-08',
      spots:['阿里山國家風景區','北門車站','文化路夜市'], days:2, isCompleted:false,
      cover:'https://picsum.photos/seed/mytrip1/600/200'),
    _MockTrip(title:'親子阿里山一日遊', date:'2025-05-18',
      spots:['阿里山國家風景區','嘉義公園','林聰明沙鍋魚頭'], days:1, isCompleted:true,
      cover:'https://picsum.photos/seed/mytrip2/600/200'),
  ];

  // 候選清單（每個 item 帶 Spot 資料）
  final List<_CandidateSpot> _candidates = [
    _CandidateSpot(spot: DummyData.spots[6]), // 嘉義市立美術館
    _CandidateSpot(spot: DummyData.spots[5]), // 御品元
    _CandidateSpot(spot: DummyData.spots[2]), // 北門車站
    _CandidateSpot(spot: DummyData.spots[1]), // 文化路夜市
  ];

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

  void _addToCandidate(Spot s) {
    if (_candidates.any((c) => c.spot.id == s.id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${s.name} 已在候選清單中'),
        backgroundColor: AppColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _candidates.add(_CandidateSpot(spot: s)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已將「${s.name}」加入候選清單 ✓'),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: '查看清單',
        textColor: Colors.white,
        onPressed: () => _tabController.animateTo(1),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('行程管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
            onPressed: () => setState(() => _showAIPanel = !_showAIPanel),
            tooltip: 'AI 行程助手',
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            onPressed: () => _showCreateTrip(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '我的行程'),
            Tab(text: '候選清單'),
            Tab(text: '收藏景點'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildMyTripsTab(),
              _buildCandidatesTab(),
              _buildSavedSpotsTab(),
            ],
          ),
          if (_showAIPanel) _buildAIPanel(context),
        ],
      ),
    );
  }

  // ── My Trips ──
  Widget _buildMyTripsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          _statCard('規劃中', '${_myTrips.where((t) => !t.isCompleted).length}', '🗓️', const Color(0xFFF5EFE6)),
          const SizedBox(width: 10),
          _statCard('已完成', '${_myTrips.where((t) => t.isCompleted).length}', '✅', const Color(0xFFEDF5ED)),
          const SizedBox(width: 10),
          _statCard('總景點', '${_myTrips.fold(0, (s, t) => s + t.spots.length)}', '📍', const Color(0xFFEBEFF2)),
        ]),
        const SizedBox(height: 16),
        ..._myTrips.map((t) => _buildTripCard(t)),
      ],
    );
  }

  Widget _statCard(String label, String val, String icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 3),
        Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ]),
    ));
  }

  Widget _buildTripCard(_MockTrip trip) {
    return GestureDetector(
      onTap: () => _showTripDetail(context, trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(children: [
                Image.network(trip.cover, height: 130, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 130, color: AppColors.primaryMist,
                    child: const Center(child: Text('🗺️', style: TextStyle(fontSize: 40))))),
                Container(height: 130,
                  decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.5)]))),
                Positioned(top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: trip.isCompleted ? AppColors.primary : AppColors.accentStraw,
                      borderRadius: BorderRadius.circular(20)),
                    child: Text(trip.isCompleted ? '已完成' : '規劃中',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: trip.isCompleted ? Colors.white : AppColors.primaryDark)),
                  ),
                ),
                Positioned(bottom: 10, left: 14,
                  child: Text(trip.title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(trip.date, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const Spacer(),
                    Text('${trip.days}天 · ${trip.spots.length}個景點',
                      style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 4,
                    children: trip.spots.map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider)),
                      child: Text(s, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                    )).toList()),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => _showTripDetail(context, trip),
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: const Text('編輯'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () => _showShareOptions(context),
                      icon: const Icon(Icons.share_rounded, size: 15),
                      label: const Text('分享'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    )),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Candidates Tab ── 拖移排序 + 加入入口 ──
  Widget _buildCandidatesTab() {
    return Column(
      children: [
        // 說明 banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryMist,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Text('💡', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              '長按拖移 ☰ 可調整順序，或點「加入景點」從地圖選取，\n再點「AI 幫我排程」自動最佳化！',
              style: TextStyle(fontSize: 12, color: AppColors.primary, height: 1.5),
            )),
          ]),
        ),
        // 加入景點按鈕
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () => _showAddCandidateSheet(context),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('＋ 加入景點到候選清單'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 拖移列表
        Expanded(
          child: _candidates.isEmpty
              ? _emptyCandidates()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _candidates.length,
                  onReorder: (oldI, newI) {
                    setState(() {
                      if (newI > oldI) newI--;
                      final item = _candidates.removeAt(oldI);
                      _candidates.insert(newI, item);
                    });
                    HapticFeedback.lightImpact();
                  },
                  itemBuilder: (_, i) {
                    final c = _candidates[i];
                    return _candidateItem(c, i);
                  },
                ),
        ),
        // Bottom actions
        if (_candidates.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => setState(() => _showAIPanel = true),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('AI 最佳排程'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: () => _convertToTrip(context),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('轉為行程'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )),
            ]),
          ),
      ],
    );
  }

  Widget _candidateItem(_CandidateSpot c, int index) {
    final spot = c.spot;
    final catIcon = spot.category == 'restaurant' ? '🍜'
        : spot.category == 'youbike' ? '🚲' : '🏛️';

    return Container(
      key: ValueKey(spot.id),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Order number
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text('${index + 1}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
            ),
            const SizedBox(width: 8),
            Text(catIcon, style: const TextStyle(fontSize: 22)),
          ],
        ),
        title: Text(spot.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
        subtitle: Row(children: [
          const Icon(Icons.access_time_rounded, size: 11, color: AppColors.textHint),
          Text('  ${spot.openHours}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(width: 8),
          const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
          Text('  ${spot.rating}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
              onPressed: () => setState(() => _candidates.removeAt(index)),
              tooltip: '移除',
            ),
            const Icon(Icons.drag_handle_rounded, color: AppColors.textHint, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _emptyCandidates() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📋', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          const Text('候選清單是空的', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('點上方按鈕加入想去的景點', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showAddCandidateSheet(context),
            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
            label: const Text('加入景點'),
          ),
        ],
      ),
    );
  }

  // ── Add candidate sheet（從景點清單選） ──
  void _showAddCandidateSheet(BuildContext context) {
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
          child: Column(
            children: [
              Container(margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('選擇景點加入候選清單', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: DummyData.spots.length,
                  itemBuilder: (_, i) {
                    final s = DummyData.spots[i];
                    final already = _candidates.any((c) => c.spot.id == s.id);
                    final icon = s.category == 'restaurant' ? '🍜'
                        : s.category == 'youbike' ? '🚲' : '🏛️';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: already ? AppColors.primaryMist : AppColors.surfaceWarm,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: already ? AppColors.primary.withOpacity(0.3) : AppColors.divider),
                      ),
                      child: ListTile(
                        leading: Text(icon, style: const TextStyle(fontSize: 24)),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Row(children: [
                          const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
                          Text('  ${s.rating}  ·  ${s.address}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                        trailing: already
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                                child: const Text('加入', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                        onTap: already ? null : () {
                          _addToCandidate(s);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Saved spots ──
  Widget _buildSavedSpotsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 0.8, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: DummyData.spots.length,
      itemBuilder: (_, i) {
        final s = DummyData.spots[i];
        return GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceWarm,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 6)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Image.network(s.imageUrl, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceMoss,
                        child: Center(child: Text(s.category == 'restaurant' ? '🍜' : '🏛️',
                          style: const TextStyle(fontSize: 36))))),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(children: [
                      GestureDetector(
                        onTap: () => _addToCandidate(s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.primaryMist, borderRadius: BorderRadius.circular(6)),
                          child: const Text('＋加入候選', style: TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.star_rounded, size: 11, color: AppColors.accentStraw),
                      Text(' ${s.rating}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── AI Panel ──
  Widget _buildAIPanel(BuildContext context) {
    final prefs = ['🏛️ 文化歷史','🍜 美食探索','👨‍👩‍👧 親子友善','⛰️ 自然生態','📸 打卡拍照','🌙 夜間活動'];
    final selected = {0, 1};
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.66,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
        ),
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 12, bottom: 14),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primaryMist, borderRadius: BorderRadius.circular(12)),
                child: const Text('✨', style: TextStyle(fontSize: 20))),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI 行程助手', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
                Text('由 Gemini AI 驅動', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              ]),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
                onPressed: () => setState(() => _showAIPanel = false)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Candidate preview
                if (_candidates.isNotEmpty) ...[
                  const Text('候選景點（共 ${0} 個）', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider)),
                    child: Column(
                      children: _candidates.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Container(width: 20, height: 20,
                            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: Center(child: Text('${e.key+1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
                          const SizedBox(width: 8),
                          Text(e.value.spot.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        ]),
                      )).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('旅遊偏好', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8,
                  children: prefs.asMap().entries.map((e) {
                    final isSel = selected.contains(e.key);
                    return GestureDetector(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.primary : AppColors.surfaceMoss,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSel ? AppColors.primary : AppColors.divider)),
                        child: Text(e.value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : AppColors.textSecondary)),
                      ),
                    );
                  }).toList()),
                const SizedBox(height: 16),
                const Text('旅遊天數', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                _AIDaysSlider(),
                const SizedBox(height: 4),
                const SizedBox(height: 16),
                // Free-text requirements ABOVE AI preview
                const Text('詳細需求（選填）', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                const TextField(
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '例如：希望行程輕鬆不趕，想吃道地小吃，有小孩同行，避免山路...',
                    hintStyle: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // AI result preview
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMist,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Text('🤖', style: TextStyle(fontSize: 15)),
                      SizedBox(width: 6),
                      Text('AI 建議預覽', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13)),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      _candidates.isEmpty
                          ? '請先加入景點到候選清單，AI 會依照開放時間與距離幫您安排最佳順序。'
                          : '📍 Day 1\n${_candidates.asMap().entries.map((e) => '${_timeSlot(e.key)} ${e.value.spot.name}').join('\n')}\n\n💡 已根據開放時間與距離最佳化順序，步行距離約 3.2km！',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.7)),
                  ]),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('生成 AI 行程建議'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _timeSlot(int i) {
    final slots = ['09:00','10:30','12:00','13:30','15:00','17:00','19:00'];
    return slots[i % slots.length];
  }

  void _convertToTrip(BuildContext ctx) {
    if (_candidates.isEmpty) return;
    setState(() {
      _myTrips.insert(0, _MockTrip(
        title: '新行程（候選清單）',
        date: '2025-06-15',
        spots: _candidates.map((c) => c.spot.name).toList(),
        days: 1,
        isCompleted: false,
        cover: 'https://picsum.photos/seed/newtrip/600/200',
      ));
      _candidates.clear();
    });
    _tabController.animateTo(0);
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: const Text('已成功建立行程 🎉'),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showCreateTrip(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('建立新行程', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            const TextField(decoration: InputDecoration(labelText: '行程名稱', hintText: '例如：嘉義三日遊')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: TextField(
                decoration: const InputDecoration(labelText: '開始日期', suffixIcon: Icon(Icons.calendar_today_rounded, size: 16)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                decoration: const InputDecoration(labelText: '結束日期', suffixIcon: Icon(Icons.calendar_today_rounded, size: 16)))),
            ]),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              child: const Text('建立行程')),
          ]),
        ),
      ),
    );
  }

  void _showTripDetail(BuildContext context, _MockTrip trip) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _TripDetailPage(trip: trip)));
  }

  void _showShareOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('分享行程', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _shareOpt('📱', 'QR Code\n分享', AppColors.primary),
            _shareOpt('👥', '發布到\n社群', AppColors.accentTerra),
            _shareOpt('🔗', '複製\n連結', AppColors.primaryLight),
            _shareOpt('✏️', '邀請\n共編', AppColors.accentSand),
          ]),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _shareOpt(String icon, String label, Color color) => GestureDetector(
    child: Column(children: [
      Container(width: 58, height: 58,
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 26)))),
      const SizedBox(height: 7),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4)),
    ]),
  );
}

// ── Models ──
class _MockTrip {
  final String title, date, cover;
  final List<String> spots;
  final int days;
  final bool isCompleted;
  _MockTrip({required this.title, required this.date, required this.spots,
             required this.days, required this.isCompleted, required this.cover});
}

class _CandidateSpot {
  final Spot spot;
  _CandidateSpot({required this.spot});
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TRIP DETAIL PAGE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _TripDetailPage extends StatefulWidget {
  final _MockTrip trip;
  const _TripDetailPage({required this.trip});
  @override
  State<_TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<_TripDetailPage> {
  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context)),
            actions: [
              IconButton(icon: const Icon(Icons.image_outlined, color: Colors.white), onPressed: () => _showChangeCover(context), tooltip: '更換封面'),
              IconButton(icon: const Icon(Icons.share_rounded, color: Colors.white), onPressed: () {}),
              IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () {}),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                Image.network(trip.cover, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF6EA870), Color(0xFF4A7A50)])))),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Trip title (moved here from image)
                Text(trip.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                // Info strip
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _info('📅', trip.date, '日期'),
                    _div(),
                    _info('🗓️', '${trip.days}天', '天數'),
                    _div(),
                    _info('📍', '${trip.spots.length}', '景點'),
                    _div(),
                    _info('💰', '~800元', '預估'),
                  ]),
                ),
                const SizedBox(height: 20),
                SectionHeader(title: '行程安排'),
                const SizedBox(height: 14),
                _buildTimeline(),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider))),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: const Text('打卡記錄'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.qr_code_rounded, size: 16),
            label: const Text('QR 共同編輯'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
        ]),
      ),
    );
  }

  Widget _info(String icon, String val, String label) => Column(children: [
    Text(icon, style: const TextStyle(fontSize: 17)),
    const SizedBox(height: 2),
    Text(val, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.textPrimary)),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
  ]);

  Widget _div() => Container(width: 1, height: 30, color: AppColors.divider);

  Widget _buildTimeline() {
    final steps = widget.trip.spots.asMap().entries.map((e) =>
      <String,String>{'time': _timeSlot(e.key), 'name': e.value, 'icon': '📍', 'cost': '', 'note': ''}
    ).toList();

    return Column(
      children: steps.asMap().entries.map((entry) {
        final i = entry.key;
        final s = entry.value;
        final isLast = i == steps.length - 1;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(width: 30, height: 30,
              decoration: BoxDecoration(color: AppColors.primaryMist, shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2)),
              child: Center(child: Text(s['icon']!, style: const TextStyle(fontSize: 13)))),
            if (!isLast) Container(width: 2, height: 72, color: AppColors.primary.withOpacity(0.25)),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _showEditStop(context, i, s),
              child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    GestureDetector(
                      onTap: () => _showTimePicker(context, i, s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primaryMist, borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.access_time_rounded, size: 11, color: AppColors.primary),
                          const SizedBox(width: 3),
                          Text(s['time']!, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s['name']!,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary))),
                    const Icon(Icons.edit_outlined, color: AppColors.textHint, size: 14),
                  ]),
                  if ((s['cost'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                      const Icon(Icons.payments_outlined, size: 11, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text('預估 NT\$${s['cost']}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                  ],
                  if ((s['note'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.note_outlined, size: 11, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Expanded(child: Text(s['note']!, style: const TextStyle(fontSize: 11, color: AppColors.textHint), maxLines: 2)),
                    ]),
                  ],
                ]),
              ),
            )),
          ),
        ]);
      }).toList(),
    );
  }

  String _timeSlot(int i) {
    const slots = ['09:00','11:00','12:30','14:00','16:00','18:00','20:00'];
    return slots[i % slots.length];
  }
}

// ── AI Days Slider Widget ──
class _AIDaysSlider extends StatefulWidget {
  const _AIDaysSlider();
  @override
  State<_AIDaysSlider> createState() => _AIDaysSliderState();
}

class _AIDaysSliderState extends State<_AIDaysSlider> {
  double _days = 2;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        const Text('1天', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
        Expanded(
          child: Slider(
            value: _days,
            min: 1,
            max: 14,
            divisions: 13,
            label: '${_days.round()} 天',
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => _days = v),
          ),
        ),
        const Text('14天', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
      ]),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryMist,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text('已選擇：${_days.round()} 天',
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 14)),
        ]),
      ),
    ]);
  }
}

// ── Trip Detail Edit Stop ──
extension _TripDetailEdit on _TripDetailPageState {
  void _showEditStop(BuildContext ctx, int idx, Map<String, String> s) {
    final costCtrl = TextEditingController(text: s['cost'] ?? '');
    final noteCtrl = TextEditingController(text: s['note'] ?? '');
    showModalBottomSheet(
      context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('編輯：${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            TextField(controller: costCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '預估花費（元）',
                prefixIcon: Icon(Icons.payments_outlined, size: 18),
                hintText: '例如：500')),
            const SizedBox(height: 12),
            TextField(controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '備註 / 注意事項',
                prefixIcon: Icon(Icons.note_outlined, size: 18),
                hintText: '例如：建議早點到、需要預約...')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                s['cost'] = costCtrl.text;
                s['note'] = noteCtrl.text;
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              child: const Text('儲存'),
            ),
          ]),
        ),
      ),
    );
  }

  void _showTimePicker(BuildContext ctx, int idx, Map<String, String> s) async {
    final picked = await showTimePicker(
      context: ctx,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: '設定到達時間',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        s['time'] = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}';
      });
    }
  }
}

// ── Change Cover Image ──
void _showChangeCover(BuildContext ctx) {
  final covers = [
    'https://picsum.photos/seed/cover1/600/200',
    'https://picsum.photos/seed/cover2/600/200',
    'https://picsum.photos/seed/cover3/600/200',
    'https://picsum.photos/seed/alishan/600/200',
    'https://picsum.photos/seed/chiayi/600/200',
    'https://picsum.photos/seed/food/600/200',
  ];
  showModalBottomSheet(
    context: ctx, backgroundColor: Colors.transparent,
    builder: (_) => Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('選擇封面圖片', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: covers.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: 160, margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(covers[i], fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceMoss)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: const Text('從相簿選取'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
        ),
      ]),
    ),
  );
}
