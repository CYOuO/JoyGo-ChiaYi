import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/dummy_data.dart';

class StampScreen extends StatefulWidget {
  const StampScreen({super.key});

  @override
  State<StampScreen> createState() => _StampScreenState();
}

class _StampScreenState extends State<StampScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _visitedSpots = {'1', '2', '5'};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
          '集章成就',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary),
            onPressed: () => _showHowTo(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '景點印章'),
            Tab(text: '成就徽章'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStampTab(),
          _buildAchievementTab(),
        ],
      ),
    );
  }

  Widget _buildStampTab() {
    final spots = DummyData.spots;
    final visitedCount = _visitedSpots.length;
    final total = spots.length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // Progress header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          '🗺️',
                          style: TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '嘉義探索進度',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$visitedCount / $total 個景點已踩點',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${((visitedCount / total) * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: visitedCount / total,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final spot = spots[index];
                final isVisited = _visitedSpots.contains(spot.id);
                final visitCount = isVisited ? 2 : 0;

                return GestureDetector(
                  onTap: () => _showStampDetail(context, spot, isVisited),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: isVisited
                          ? AppColors.surface
                          : AppColors.surfaceMoss.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isVisited
                            ? _getStampColor(visitCount)
                            : AppColors.surfaceMoss,
                        width: isVisited ? 2 : 1,
                      ),
                      boxShadow: isVisited
                          ? [
                              BoxShadow(
                                color: _getStampColor(visitCount).withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isVisited) ...[
                          // Stamp design
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _getStampColor(visitCount),
                                    width: 3,
                                  ),
                                ),
                              ),
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getStampColor(visitCount)
                                      .withOpacity(0.15),
                                ),
                                child: Center(
                                  child: Text(
                                    _spotEmoji(spot.category),
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: _getStampColor(visitCount),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$visitCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          // Unvisited - grey
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.textHint.withOpacity(0.1),
                              border: Border.all(
                                color: AppColors.textHint.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0,      0,      0,      1, 0,
                                ]),
                                child: Text(
                                  _spotEmoji(spot.category),
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            spot.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isVisited
                                  ? AppColors.textPrimary
                                  : AppColors.textHint,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVisited) ...[
                          const SizedBox(height: 2),
                          Text(
                            '✓ 已踩點',
                            style: TextStyle(
                              fontSize: 10,
                              color: _getStampColor(visitCount),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
              childCount: spots.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.75,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStampColor(int visitCount) {
    if (visitCount >= 5) return AppColors.stampGold;
    if (visitCount >= 3) return AppColors.stampSilver;
    return AppColors.stampBronze;
  }

  String _spotEmoji(String category) {
    switch (category) {
      case 'restaurant':
        return '🍜';
      case 'attraction':
        return '🏛️';
      case 'hotel':
        return '🏨';
      case 'youbike':
        return '🚲';
      default:
        return '📍';
    }
  }

  Widget _buildAchievementTab() {
    final achievements = DummyData.achievements;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Achievement stats
        Row(
          children: [
            _achieveStat('已解鎖', '${achievements.where((a) => a.isUnlocked).length}', AppColors.stampGold),
            const SizedBox(width: 12),
            _achieveStat('進行中', '${achievements.where((a) => !a.isUnlocked).length}', AppColors.primary),
            const SizedBox(width: 12),
            _achieveStat('總成就', '${achievements.length}', AppColors.textHint),
          ],
        ),
        const SizedBox(height: 20),
        // Achievement list
        ...achievements.map((achievement) => _buildAchievementCard(achievement)),
      ],
    );
  }

  Widget _achieveStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementCard(Achievement achievement) {
    Color rarityColor;
    String rarityLabel;

    switch (achievement.rarity) {
      case 'gold':
        rarityColor = AppColors.stampGold;
        rarityLabel = '黃金';
        break;
      case 'silver':
        rarityColor = AppColors.stampSilver;
        rarityLabel = '白銀';
        break;
      case 'special':
        rarityColor = AppColors.error;
        rarityLabel = '特別';
        break;
      default:
        rarityColor = AppColors.stampBronze;
        rarityLabel = '青銅';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: achievement.isUnlocked
              ? rarityColor.withOpacity(0.4)
              : AppColors.surfaceMoss,
          width: achievement.isUnlocked ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: achievement.isUnlocked
                ? rarityColor.withOpacity(0.1)
                : AppColors.cardShadow,
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: achievement.isUnlocked
                  ? rarityColor.withOpacity(0.15)
                  : AppColors.surfaceMoss,
              shape: BoxShape.circle,
              border: Border.all(
                color: achievement.isUnlocked ? rarityColor : AppColors.textHint.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: achievement.isUnlocked
                  ? Text(achievement.icon, style: const TextStyle(fontSize: 26))
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(achievement.icon,
                            style: TextStyle(
                                fontSize: 26,
                                color: Colors.black.withOpacity(0.15))),
                        const Icon(Icons.lock_rounded,
                            color: AppColors.textHint, size: 20),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        achievement.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: achievement.isUnlocked
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: rarityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        rarityLabel,
                        style: TextStyle(
                          color: rarityColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: achievement.progress / achievement.total,
                    backgroundColor: AppColors.surfaceMoss,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      achievement.isUnlocked ? rarityColor : AppColors.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.isUnlocked
                      ? '已完成！'
                      : '${achievement.progress} / ${achievement.total}',
                  style: TextStyle(
                    fontSize: 11,
                    color: achievement.isUnlocked ? rarityColor : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showStampDetail(BuildContext context, Spot spot, bool isVisited) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isVisited) ...[
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.stampBronze, width: 3),
                    color: AppColors.stampBronze.withOpacity(0.1),
                  ),
                  child: Center(
                    child: Text(_spotEmoji(spot.category),
                        style: const TextStyle(fontSize: 36)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '✓ 已踩點成功！',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ] else ...[
                const Text('🔒', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text(
                  '尚未踩點',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                spot.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                spot.address,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (!isVisited)
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _visitedSpots.add(spot.id));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('前往打卡'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              if (isVisited)
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('關閉'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHowTo(BuildContext context) {
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
              '如何集章？',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _howToStep('1️⃣', '前往景點', '實際到訪景點，開啟App定位'),
            _howToStep('2️⃣', '掃描/拍照', '使用打卡相機拍照留念'),
            _howToStep('3️⃣', '驗證成功', '系統確認位置，印章立即點亮！'),
            _howToStep('4️⃣', '累積次數', '同一景點多次造訪，印章顏色越來越深'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _howToStep(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(num, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textHint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
