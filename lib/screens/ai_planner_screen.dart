import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart' show StitchedBox, DoodleHeart, DoodleCloud, DoodleLightning;

// ════════════════════════════════════════════════════════════════
// Gemini API 介面（已預留，待接 API 時替換）
// ════════════════════════════════════════════════════════════════
class GeminiPlanner {
  // TODO: 設定 Gemini API Key
  // static const _apiKey = 'YOUR_GEMINI_API_KEY';
  // static const _endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';

  /// 智排行程：根據候選清單與偏好生成行程安排
  static Future<List<_DayPlan>> generateSchedule({
    required List<String> candidateSpots,
    required int days,
    required String departureTime, // 'morning' | 'afternoon' | 'flexible'
  }) async {
    // TODO: 替換為真實 Gemini API 呼叫
    // final prompt = '''
    //   你是嘉義在地旅遊達人。以下是候選景點清單：${candidateSpots.join(', ')}
    //   請將這些景點安排成 $days 天的行程，每天 ${departureTime == 'morning' ? '早上9點' : '下午2點'}出發。
    //   考慮景點距離、用餐時間、開放時間，以 JSON 格式輸出。
    // ''';
    // final response = await http.post(Uri.parse(_endpoint), ...);

    await Future.delayed(const Duration(milliseconds: 1800));
    return _mockSchedule(candidateSpots, days, departureTime);
  }

  /// 旅遊顧問：根據使用者偏好生成推薦行程
  static Future<_TripProposal> generateProposal({
    required Map<String, dynamic> preferences,
  }) async {
    // TODO: 替換為真實 Gemini API 呼叫
    await Future.delayed(const Duration(milliseconds: 2000));
    return _mockProposal(preferences);
  }

  // ── Mock 模擬資料（接 API 後刪除）────────────────────────────

  static final _dayColors = [
    const Color(0xFFE8845A),
    const Color(0xFF5A8ABF),
    const Color(0xFF5A9F6A),
    const Color(0xFF8A5ABF),
    const Color(0xFFBFA84A),
  ];

  static List<_DayPlan> _mockSchedule(List<String> spots, int days, String dep) {
    final rng = math.Random(42);
    final spotsPerDay = (spots.length / days).ceil();
    final plans = <_DayPlan>[];
    var idx = 0;
    for (var d = 0; d < days; d++) {
      final daySpots = spots.skip(idx).take(spotsPerDay).toList();
      idx += spotsPerDay;
      if (daySpots.isEmpty) break;
      final startHour = dep == 'morning' ? 9 : (dep == 'afternoon' ? 14 : 9 + rng.nextInt(3));
      final items = <_ScheduleItem>[];
      var hour = startHour;
      for (final spot in daySpots) {
        items.add(_ScheduleItem(
          time: '${hour.toString().padLeft(2, '0')}:${rng.nextInt(2) == 0 ? '00' : '30'}',
          name: spot,
          duration: '${60 + rng.nextInt(4) * 30} 分鐘',
          note: _spotNote(spot),
          icon: _spotIcon(spot),
        ));
        hour += 1 + rng.nextInt(2);
        if (hour >= 12 && hour <= 13 && d < days - 1) {
          items.add(_ScheduleItem(time: '12:30', name: '午餐時間', duration: '60 分鐘',
              note: '建議嘗試在地雞肉飯', icon: Icons.restaurant_rounded, isMeal: true));
          hour = 14;
        }
      }
      if (hour < 18) {
        items.add(_ScheduleItem(time: '18:00', name: '晚餐 / 自由活動', duration: '—',
            note: '文化路夜市、林聰明沙鍋', icon: Icons.dinner_dining_rounded, isMeal: true));
      }
      plans.add(_DayPlan(day: d + 1, color: _dayColors[d % _dayColors.length], items: items));
    }
    return plans;
  }

  static _TripProposal _mockProposal(Map<String, dynamic> pref) {
    final days = int.tryParse(pref['days']?.toString() ?? '') ?? 2;
    final style = pref['style'] as String? ?? '輕旅行';
    final List<String> spots;
    if (style == '美食') {
      spots = ['阿里山咖啡莊園','林聰明沙鍋魚頭','奮起湖便當','文化路夜市','郭家粽子'];
    } else if (style == '文青') {
      spots = ['嘉義市立美術館','木藝生態博物館','北門驛','諸羅老城牆遺址','中正公園'];
    } else if (style == '自然') {
      spots = ['阿里山國家風景區','瑞里綠色隧道','蘭潭水庫','奮起湖','太興岩'];
    } else {
      spots = ['嘉義公園','故宮南院','檜意森活村','文化路夜市','阿里山'];
    }
    return _TripProposal(
      title: '$style嘉義 $days 日遊',
      highlight: '精選 ${spots.length} 個嘉義必訪亮點，涵蓋在地美食、歷史文化與自然景色',
      spots: spots,
      days: days,
      budget: pref['budget'] as String? ?? '一般',
      tips: '建議租機車或自駕，景點較分散。早上先安排山區景點，下午回市區。',
    );
  }

  static String _spotNote(String name) {
    if (name.contains('阿里山')) return '建議早上前往，避開人潮';
    if (name.contains('夜市')) return '晚上6點後人氣最旺';
    if (name.contains('美術館')) return '週一公休，注意時間';
    return '建議停留約 1.5 小時';
  }

  static IconData _spotIcon(String name) {
    if (name.contains('餐') || name.contains('美食') || name.contains('飯') || name.contains('小吃'))
      return Icons.restaurant_rounded;
    if (name.contains('山') || name.contains('林') || name.contains('湖'))
      return Icons.landscape_rounded;
    if (name.contains('館') || name.contains('博物') || name.contains('文化'))
      return Icons.museum_rounded;
    return Icons.place_rounded;
  }
}

// ─── Data models ─────────────────────────────────────────────────

class _DayPlan {
  final int day;
  final Color color;
  final List<_ScheduleItem> items;
  const _DayPlan({required this.day, required this.color, required this.items});
}

class _ScheduleItem {
  final String time, name, duration, note;
  final IconData icon;
  final bool isMeal;
  const _ScheduleItem({
    required this.time, required this.name, required this.duration,
    required this.note, required this.icon, this.isMeal = false,
  });
}

class _TripProposal {
  final String title, highlight, budget, tips;
  final List<String> spots;
  final int days;
  const _TripProposal({
    required this.title, required this.highlight, required this.spots,
    required this.days, required this.budget, required this.tips,
  });
}

// ════════════════════════════════════════════════════════════════
// AIPlannerScreen
// ════════════════════════════════════════════════════════════════
class AIPlannerScreen extends StatefulWidget {
  final List<String> candidateSpots;  // 候選清單景點名稱
  const AIPlannerScreen({super.key, required this.candidateSpots});

  @override State<AIPlannerScreen> createState() => _AIPlannerScreenState();
}

class _AIPlannerScreenState extends State<AIPlannerScreen>
    with TickerProviderStateMixin {

  // ── mode: 'schedule' | 'consult' ────────────────────────────
  String _mode = 'schedule';

  // ── Smart Schedule state ─────────────────────────────────────
  int _days = 2;
  String _depTime = 'morning';
  bool _scheduling = false;
  List<_DayPlan>? _schedulePlan;

  // ── Travel Consult state ─────────────────────────────────────
  int _consultStep = 0;        // 0-4 = question steps, 5 = done
  bool _consulting  = false;
  _TripProposal? _proposal;
  final _consultAnswers = <String, dynamic>{};

  // ── Animations ───────────────────────────────────────────────
  late AnimationController _sparkleCtrl;
  late AnimationController _modeCtrl;
  late Animation<double> _modeAnim;

  @override
  void initState() {
    super.initState();
    _sparkleCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))..repeat();
    _modeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
    _modeAnim = CurvedAnimation(parent: _modeCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _sparkleCtrl.dispose();
    _modeCtrl.dispose();
    super.dispose();
  }

  void _switchMode(String m) {
    setState(() {
      _mode = m;
      _schedulePlan = null;
      _consultStep  = 0;
      _proposal     = null;
      _consultAnswers.clear();
    });
    if (m == 'consult') _modeCtrl.forward(); else _modeCtrl.reverse();
  }

  // ── Smart schedule ───────────────────────────────────────────
  Future<void> _runSchedule() async {
    setState(() { _scheduling = true; _schedulePlan = null; });
    final plan = await GeminiPlanner.generateSchedule(
      candidateSpots: widget.candidateSpots,
      days: _days,
      departureTime: _depTime,
    );
    if (mounted) setState(() { _schedulePlan = plan; _scheduling = false; });
  }

  // ── Consult flow ─────────────────────────────────────────────
  final _consultQuestions = <(String, String, List<(IconData, String, String)>)>[
    ('幾天的旅行？', 'days', [
      (Icons.looks_one_rounded,  '1 天', '1'),
      (Icons.looks_two_rounded,  '2 天', '2'),
      (Icons.looks_3_rounded,    '3 天', '3'),
      (Icons.looks_4_rounded,    '4 天以上', '4'),
    ]),
    ('幾個人一起去？', 'group', [
      (Icons.person_rounded,           '獨自一人', '獨旅'),
      (Icons.favorite_rounded,         '兩人世界', '情侶'),
      (Icons.family_restroom_rounded,  '親子出遊', '家庭'),
      (Icons.group_rounded,            '朋友同行', '朋友'),
    ]),
    ('這次旅行的風格？', 'style', [
      (Icons.restaurant_rounded,       '美食探索', '美食'),
      (Icons.museum_rounded,           '文青深度', '文青'),
      (Icons.landscape_rounded,        '山林自然', '自然'),
      (Icons.photo_camera_rounded,     '打卡拍照', '打卡'),
    ]),
    ('預算大概？', 'budget', [
      (Icons.savings_rounded,          '省錢模式', '省錢'),
      (Icons.credit_card_rounded,      '一般消費', '一般'),
      (Icons.star_rounded,             '品質優先', '豪華'),
    ]),
    ('特別想要什麼？', 'special', [
      (Icons.child_care_rounded,       '適合小孩', '親子'),
      (Icons.pets_rounded,             '毛孩同行', '寵物'),
      (Icons.accessibility_rounded,    '無障礙友善', '無障礙'),
      (Icons.directions_bike_rounded,  '體驗騎車', '單車'),
    ]),
  ];

  Future<void> _runConsult() async {
    setState(() { _consulting = true; _proposal = null; });
    final proposal = await GeminiPlanner.generateProposal(preferences: _consultAnswers);
    if (mounted) setState(() { _proposal = proposal; _consulting = false; });
  }

  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final mist    = Color.lerp(primary, Colors.white, 0.88)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader(primary)),
          // ── Mode toggle ────────────────────────────────────
          SliverToBoxAdapter(child: _buildModeToggle(primary)),
          // ── Content ────────────────────────────────────────
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
                  child: child),
              ),
              child: _mode == 'schedule'
                  ? _buildScheduleMode(primary, mist)
                  : _buildConsultMode(primary, mist),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Header — 諸羅精靈識別區（手繪波浪底部 + 塗鴉裝飾）
  // ────────────────────────────────────────────────────────────
  Widget _buildHeader(Color primary) {
    final dark = Color.lerp(primary, Colors.black, 0.25)!;
    return ClipPath(
      clipper: _AIHeaderClipper(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [primary, dark]),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 52),
            child: Stack(children: [
              // 手繪塗鴉裝飾（忽略點擊）
              Positioned.fill(child: IgnorePointer(child: Stack(children: [
                Positioned(top: 12,  right: 18, child: DoodleHeart(color: Colors.white.withValues(alpha: 0.14), size: 14)),
                Positioned(top: 55,  right: 48, child: DoodleLightning(color: Colors.white.withValues(alpha: 0.12), size: 11)),
                Positioned(top: 100, right: 22, child: DoodleCloud(color: Colors.white.withValues(alpha: 0.10), width: 26)),
                Positioned(top: 18,  left: 100, child: DoodleHeart(color: Colors.white.withValues(alpha: 0.09), size: 9)),
                Positioned(top: 70,  left: 44,  child: DoodleCloud(color: Colors.white.withValues(alpha: 0.08), width: 18)),
                Positioned(top: 40,  right: 80, child: CustomPaint(painter: _StarDotPainter(Colors.white.withValues(alpha: 0.20)), size: const Size(6, 6))),
                Positioned(top: 90,  right: 60, child: CustomPaint(painter: _StarDotPainter(Colors.white.withValues(alpha: 0.15)), size: const Size(5, 5))),
                Positioned(top: 30,  left: 60,  child: CustomPaint(painter: _StarDotPainter(Colors.white.withValues(alpha: 0.18)), size: const Size(4, 4))),
              ]))),
              // 主內容
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Back button + settings
                Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 16)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.science_outlined, size: 13, color: Colors.white.withValues(alpha: 0.85)),
                      const SizedBox(width: 5),
                      Text('Gemini 預留中', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 24),
                // Mascot area
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _buildSparkleOrb(primary),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('諸羅精靈', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      const SizedBox(width: 6),
                      DoodleHeart(color: Colors.white.withValues(alpha: 0.7), size: 10),
                    ]),
                    const SizedBox(height: 4),
                    Text('你的嘉義旅行規劃夥伴', style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                      child: Text(
                        widget.candidateSpots.isEmpty
                            ? '目前候選清單是空的，先去加景點吧！'
                            : '已有 ${widget.candidateSpots.length} 個景點待安排',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
                    ),
                  ])),
                ]),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSparkleOrb(Color primary) {
    return AnimatedBuilder(
      animation: _sparkleCtrl,
      builder: (_, __) {
        final t = _sparkleCtrl.value;
        return SizedBox(
          width: 72, height: 72,
          child: Stack(alignment: Alignment.center, children: [
            // Outer ring
            Transform.rotate(
              angle: t * 2 * math.pi,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25 + 0.15 * math.sin(t * math.pi)),
                    width: 1.5)),
              ),
            ),
            // Inner orb
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26)),
            ),
            // Orbiting dot
            Transform.translate(
              offset: Offset(
                32 * math.cos(t * 2 * math.pi),
                32 * math.sin(t * 2 * math.pi)),
              child: Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white)),
            ),
          ]),
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────
  // Mode toggle — 手繪縫線風格
  // ────────────────────────────────────────────────────────────
  Widget _buildModeToggle(Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(children: [
        Expanded(child: _modeCard(
          icon: Icons.route_rounded,
          label: '智排行程',
          subtitle: '候選清單一鍵排程',
          number: '01',
          selected: _mode == 'schedule',
          primary: primary,
          onTap: () => _switchMode('schedule'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _modeCard(
          icon: Icons.forum_rounded,
          label: '旅遊顧問',
          subtitle: '從零開始量身規劃',
          number: '02',
          selected: _mode == 'consult',
          primary: primary,
          onTap: () => _switchMode('consult'),
        )),
      ]),
    );
  }

  Widget _modeCard({
    required IconData icon, required String label, required String subtitle,
    required String number, required bool selected, required Color primary,
    required VoidCallback onTap,
  }) {
    final mist = Color.lerp(primary, Colors.white, 0.90)!;
    final dark = Color.lerp(primary, Colors.black, 0.15)!;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: StitchedBox(
          color: selected ? primary : Colors.white,
          stitchColor: selected ? Colors.white.withValues(alpha: 0.3) : primary.withValues(alpha: 0.25),
          radius: 20, inset: 5, dashWidth: 5, dashGap: 4,
          boxShadow: [BoxShadow(
            color: selected ? primary.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.06),
            blurRadius: selected ? 16 : 6, offset: const Offset(0, 4))],
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Number tag + icon row
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.2) : mist,
                  borderRadius: BorderRadius.circular(8)),
                child: Text(number, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : primary, letterSpacing: 0.5)),
              ),
              const Spacer(),
              Icon(icon, size: 20, color: selected ? Colors.white.withValues(alpha: 0.9) : primary),
            ]),
            const SizedBox(height: 12),
            // Decorative squiggle line
            SizedBox(height: 3, child: CustomPaint(
              painter: _SquigglePainter(color: selected ? Colors.white.withValues(alpha: 0.25) : primary.withValues(alpha: 0.2)),
              size: const Size(double.infinity, 3),
            )),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w900,
              color: selected ? Colors.white : AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(
              fontSize: 10, height: 1.5,
              color: selected ? Colors.white.withValues(alpha: 0.72) : AppColors.textHint)),
          ]),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // MODE 1: Smart Schedule
  // ════════════════════════════════════════════════════════════
  Widget _buildScheduleMode(Color primary, Color mist) {
    final key = const ValueKey('schedule');
    if (widget.candidateSpots.isEmpty) {
      return _emptyState(key, primary, '還沒有候選景點', '先到地圖或收藏頁加入景點\n再回來讓精靈幫你排程', Icons.map_outlined);
    }
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Candidates preview
        StitchedBox(
          color: Colors.white,
          stitchColor: primary.withValues(alpha: 0.22),
          radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.checklist_rounded, size: 15, color: primary),
              const SizedBox(width: 6),
              Text('${widget.candidateSpots.length} 個候選景點',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6,
              children: widget.candidateSpots.asMap().entries.map((e) =>
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: mist,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primary.withValues(alpha: 0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 16, height: 16,
                      decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                      child: Center(child: Text('${e.key + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
                    const SizedBox(width: 5),
                    Text(e.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ]),
                )
              ).toList(),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Day count
        const Text('幾天的行程？', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(children: List.generate(5, (i) {
          final d = i + 1;
          final sel = _days == d;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() { _days = d; _schedulePlan = null; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: sel ? primary : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? primary : AppColors.divider),
                  boxShadow: sel ? [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$d', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: sel ? Colors.white : AppColors.textPrimary)),
                  Text('天', style: TextStyle(fontSize: 9, color: sel ? Colors.white.withValues(alpha: 0.8) : AppColors.textHint)),
                ]),
              ),
            ),
          );
        })),
        const SizedBox(height: 16),

        // Departure time
        const Text('幾點出發？', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(children: [
          _depChip('morning',   Icons.wb_sunny_rounded,    '早上', primary),
          const SizedBox(width: 8),
          _depChip('afternoon', Icons.wb_cloudy_rounded,   '下午', primary),
          const SizedBox(width: 8),
          _depChip('flexible',  Icons.shuffle_rounded,     '彈性', primary),
        ]),
        const SizedBox(height: 20),

        // Go button
        GestureDetector(
          onTap: _scheduling ? null : _runSchedule,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: _scheduling ? null : LinearGradient(colors: [primary, Color.lerp(primary, Colors.black, 0.2)!]),
              color: _scheduling ? AppColors.surfaceMoss : null,
              borderRadius: BorderRadius.circular(18),
              boxShadow: _scheduling ? [] : [BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: _scheduling
              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                  const SizedBox(width: 12),
                  const Text('精靈思考中…', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Text('讓精靈排程', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
          ),
        ),
        const SizedBox(height: 20),

        // Results
        if (_schedulePlan != null) _buildScheduleResult(primary),
      ]),
    );
  }

  Widget _depChip(String val, IconData icon, String label, Color primary) {
    final sel = _depTime == val;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() { _depTime = val; _schedulePlan = null; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? primary.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? primary : AppColors.divider)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: sel ? primary : AppColors.textHint),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: sel ? primary : AppColors.textSecondary)),
        ]),
      ),
    ));
  }

  Widget _buildScheduleResult(Color primary) {
    final plan = _schedulePlan!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.check_circle_rounded, size: 16, color: primary),
        const SizedBox(width: 6),
        Text('精靈為你安排了 ${plan.length} 天行程', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary)),
      ]),
      const SizedBox(height: 12),
      ...plan.map((day) => _dayCard(day)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMoss,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textHint),
          const SizedBox(width: 8),
          const Expanded(child: Text(
            '連結 Gemini API 後，精靈將根據真實交通時間、景點評分、開放時段最佳化排程。',
            style: TextStyle(fontSize: 11, color: AppColors.textHint, height: 1.6))),
        ]),
      ),
    ]);
  }

  Widget _dayCard(_DayPlan day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: day.color.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: day.color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        // Day header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: day.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
          child: Row(children: [
            Text('第 ${day.day} 天', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('${day.items.length} 個景點', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
          ]),
        ),
        // Timeline
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(children: day.items.asMap().entries.map((e) {
            final item = e.value;
            final isLast = e.key == day.items.length - 1;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Timeline dot
              Column(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: item.isMeal ? AppColors.surfaceMoss : day.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: item.isMeal ? AppColors.divider : day.color.withValues(alpha: 0.4))),
                  child: Center(child: Icon(item.icon, size: 14, color: item.isMeal ? AppColors.textHint : day.color)),
                ),
                if (!isLast) Container(width: 2, height: 32, color: day.color.withValues(alpha: 0.2)),
              ]),
              const SizedBox(width: 10),
              // Content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 5),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: day.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(item.time, style: TextStyle(fontSize: 10, color: day.color, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 6),
                      Text(item.duration, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                    ]),
                    const SizedBox(height: 3),
                    Text(item.name, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: item.isMeal ? AppColors.textHint : AppColors.textPrimary)),
                    if (item.note.isNotEmpty)
                      Text(item.note, style: const TextStyle(fontSize: 11, color: AppColors.textHint, height: 1.4)),
                  ]),
                ),
              ),
            ]);
          }).toList()),
        ),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  // MODE 2: Travel Consult
  // ════════════════════════════════════════════════════════════
  Widget _buildConsultMode(Color primary, Color mist) {
    final key = const ValueKey('consult');
    if (_proposal != null) {
      return Padding(key: key, padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildProposalCard(_proposal!, primary));
    }
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Progress indicator
        _buildConsultProgress(primary),
        const SizedBox(height: 20),
        // Questions answered so far
        ...List.generate(math.min(_consultStep + 1, _consultQuestions.length), (i) {
          final q = _consultQuestions[i];
          final isActive = i == _consultStep;
          return _buildQuestionCard(i, q, isActive, primary, mist);
        }),
        if (_consulting) ...[
          const SizedBox(height: 16),
          _buildThinkingCard(primary),
        ],
      ]),
    );
  }

  Widget _buildConsultProgress(Color primary) {
    final total = _consultQuestions.length;
    final done  = _consultStep.clamp(0, total);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('問題 $done / $total', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (done > 0) TextButton.icon(
          onPressed: () => setState(() { _consultStep = 0; _consultAnswers.clear(); _proposal = null; }),
          icon: const Icon(Icons.refresh_rounded, size: 13),
          label: const Text('重新開始', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(foregroundColor: AppColors.textHint, padding: EdgeInsets.zero),
        ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: done / total,
          minHeight: 5,
          backgroundColor: AppColors.surfaceMoss,
          valueColor: AlwaysStoppedAnimation(primary),
        ),
      ),
    ]);
  }

  Widget _buildQuestionCard(
    int idx,
    (String, String, List<(IconData, String, String)>) q,
    bool isActive,
    Color primary, Color mist,
  ) {
    final answered = _consultAnswers.containsKey(q.$2);
    final answerVal = _consultAnswers[q.$2] as String?;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 20 * (1 - t)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? primary.withValues(alpha: 0.4) : AppColors.divider,
            width: isActive ? 1.5 : 1),
          boxShadow: [BoxShadow(
            color: isActive ? primary.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.04),
            blurRadius: isActive ? 12 : 4, offset: const Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Question
            Row(children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: answered ? primary : AppColors.surfaceMoss,
                  shape: BoxShape.circle),
                child: Center(child: answered
                    ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                    : Text('${idx + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                        color: isActive ? AppColors.textSecondary : AppColors.textHint))),
              ),
              const SizedBox(width: 10),
              Text(q.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                  color: isActive ? AppColors.textPrimary : AppColors.textSecondary)),
            ]),
            // Answer chips
            if (isActive || answered) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8,
                children: q.$3.map((opt) {
                  final sel = answerVal == opt.$3;
                  return GestureDetector(
                    onTap: isActive ? () {
                      setState(() {
                        _consultAnswers[q.$2] = opt.$3;
                        if (idx < _consultQuestions.length - 1) {
                          _consultStep = idx + 1;
                        } else {
                          _consultStep = _consultQuestions.length;
                          _runConsult();
                        }
                      });
                    } : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? primary : (isActive ? AppColors.surfaceMoss : Colors.transparent),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? primary : (isActive ? AppColors.divider : Colors.transparent))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(opt.$1, size: 14, color: sel ? Colors.white : (isActive ? AppColors.textSecondary : AppColors.textHint)),
                        const SizedBox(width: 6),
                        Text(opt.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : (isActive ? AppColors.textSecondary : AppColors.textHint))),
                      ]),
                    ),
                  );
                }).toList()),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildThinkingCard(Color primary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.2))),
      child: Row(children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: primary)),
        const SizedBox(width: 12),
        Text('諸羅精靈正在為你規劃…', style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildProposalCard(_TripProposal proposal, Color primary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Result header
      StitchedBox(
        color: primary.withValues(alpha: 0.07),
        stitchColor: primary.withValues(alpha: 0.3),
        radius: 20, inset: 4, dashWidth: 5, dashGap: 4,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: primary),
            const SizedBox(width: 6),
            const Text('精靈為你規劃了', style: TextStyle(fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text(proposal.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: primary, height: 1.3)),
          const SizedBox(height: 6),
          Text(proposal.highlight, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 14),
      // Spot list
      const Text('推薦景點', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      ...proposal.spots.asMap().entries.map((e) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider)),
        child: Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
            child: Center(child: Text('${e.key + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)))),
          const SizedBox(width: 10),
          Text(e.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ]),
      )),
      const SizedBox(height: 12),
      // Tips
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMoss,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.tips_and_updates_rounded, size: 15, color: primary),
          const SizedBox(width: 8),
          Expanded(child: Text(proposal.tips,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.6))),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textHint),
          const SizedBox(width: 8),
          const Expanded(child: Text(
            '連結 Gemini API 後，精靈將根據即時天氣、景點評分、交通路線、用餐熱門時段提供更精準的推薦。',
            style: TextStyle(fontSize: 11, color: AppColors.textHint, height: 1.6))),
        ]),
      ),
      const SizedBox(height: 14),
      // Re-plan button
      OutlinedButton.icon(
        onPressed: () => setState(() { _consultStep = 0; _consultAnswers.clear(); _proposal = null; }),
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('重新規劃'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          foregroundColor: primary, side: BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    ]);
  }

  // ────────────────────────────────────────────────────────────
  Widget _emptyState(Key key, Color primary, String title, String body, IconData icon) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
      child: Column(children: [
        Icon(icon, size: 56, color: primary.withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.6)),
      ]),
    );
  }
}

// ── 波浪裝飾線 ────────────────────────────────────────────────
class _SquigglePainter extends CustomPainter {
  final Color color;
  const _SquigglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(0, size.height / 2);
    final seg = size.width / 6;
    for (var i = 0; i < 6; i++) {
      final x = seg * i;
      path.cubicTo(x + seg * 0.3, 0, x + seg * 0.7, size.height, x + seg, size.height / 2);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SquigglePainter old) => old.color != color;
}

// ── AI Header 手繪波浪裁切器 ──────────────────────────────────
class _AIHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) {
    final base = s.height - 32.0;
    final p = Path()..lineTo(0, base + 6);
    p.cubicTo(
      s.width * 0.20, base - 18,
      s.width * 0.55, base + 26,
      s.width * 0.78, base - 10,
    );
    p.cubicTo(
      s.width * 0.88, base - 20,
      s.width * 0.95, base + 8,
      s.width,        base + 2,
    );
    p.lineTo(s.width, 0);
    p.lineTo(0, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(_AIHeaderClipper old) => false;
}

// ── 手繪星點（+字形）────────────────────────────────────────
class _StarDotPainter extends CustomPainter {
  final Color color;
  const _StarDotPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2, cy = size.height / 2;
    canvas.drawLine(Offset(cx - size.width, cy), Offset(cx + size.width, cy), paint);
    canvas.drawLine(Offset(cx, cy - size.height), Offset(cx, cy + size.height), paint);
    canvas.drawLine(Offset(cx - size.width * 0.7, cy - size.height * 0.7),
        Offset(cx + size.width * 0.7, cy + size.height * 0.7), paint);
    canvas.drawLine(Offset(cx + size.width * 0.7, cy - size.height * 0.7),
        Offset(cx - size.width * 0.7, cy + size.height * 0.7), paint);
  }

  @override
  bool shouldRepaint(_StarDotPainter old) => false;
}
