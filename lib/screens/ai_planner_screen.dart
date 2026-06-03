import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart'
    show StitchedBox, DoodleHeart, DoodleCloud, DoodleLightning;

// ════════════════════════════════════════════════════════════════
// Data Models
// ════════════════════════════════════════════════════════════════

enum TransportMode { walk, bike, bus, train, hsr, car, taxi }

extension TransportModeExt on TransportMode {
  String get label {
    switch (this) {
      case TransportMode.walk:  return '步行';
      case TransportMode.bike:  return '腳踏車';
      case TransportMode.bus:   return '公車';
      case TransportMode.train: return '火車(TRA)';
      case TransportMode.hsr:   return '高鐵(HSR)';
      case TransportMode.car:   return '自駕';
      case TransportMode.taxi:  return '計程車';
    }
  }
  IconData get icon {
    switch (this) {
      case TransportMode.walk:  return Icons.directions_walk_rounded;
      case TransportMode.bike:  return Icons.directions_bike_rounded;
      case TransportMode.bus:   return Icons.directions_bus_rounded;
      case TransportMode.train: return Icons.train_rounded;
      case TransportMode.hsr:   return Icons.speed_rounded;
      case TransportMode.car:   return Icons.directions_car_rounded;
      case TransportMode.taxi:  return Icons.local_taxi_rounded;
    }
  }
  static TransportMode? fromString(String? s) {
    if (s == null) return null;
    for (final m in TransportMode.values) {
      if (m.name == s) return m;
    }
    return null;
  }
}

class _ScheduleItem {
  final String time, name, duration, note;
  final IconData icon;
  final bool isMeal;
  final TransportMode? transport;
  final String? transportNote;
  final String? stationName;
  final double? stationLat;
  final double? stationLng;

  const _ScheduleItem({
    required this.time, required this.name,
    required this.duration, required this.note,
    required this.icon, this.isMeal = false,
    this.transport, this.transportNote,
    this.stationName, this.stationLat, this.stationLng,
  });
}

class _DayPlan {
  final int day;
  final Color color;
  final List<_ScheduleItem> items;
  const _DayPlan({required this.day, required this.color, required this.items});
}

class AiGeneratedTrip {
  final String title, highlight, tips, budget;
  final List<String> spots;
  final int days;
  final List<_DayPlan> schedule;
  const AiGeneratedTrip({
    required this.title, required this.highlight, required this.tips,
    required this.spots, required this.days,
    required this.budget, required this.schedule,
  });
}

class _ChatMessage {
  final bool isUser;
  final String text;
  final AiGeneratedTrip? generatedTrip;
  const _ChatMessage({required this.isUser, required this.text, this.generatedTrip});
}

// ════════════════════════════════════════════════════════════════
// AIPlannerScreen
// ════════════════════════════════════════════════════════════════
class AIPlannerScreen extends StatefulWidget {
  final List<String> candidateSpots;
  final Map<String, List<String>>? importedTrips;
  final void Function(AiGeneratedTrip trip)? onSaveTrip;

  const AIPlannerScreen({
    super.key,
    required this.candidateSpots,
    this.importedTrips,
    this.onSaveTrip,
  });

  @override
  State<AIPlannerScreen> createState() => _AIPlannerScreenState();
}

class _AIPlannerScreenState extends State<AIPlannerScreen>
    with TickerProviderStateMixin {

  // ── Mode ─────────────────────────────────────────────────────
  String _mode = 'schedule';

  // ── Transport modes ──────────────────────────────────────────
  final Set<TransportMode> _transportModes = {TransportMode.bus};

  // ── Smart Schedule state ─────────────────────────────────────
  int _days = 2;
  String _depTime = 'morning';
  bool _scheduling = false;
  List<_DayPlan>? _schedulePlan;
  String? _selectedImportTrip;

  // ── Chat state ───────────────────────────────────────────────
  final List<_ChatMessage> _chatMessages = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  bool _chatThinking = false;
  AiGeneratedTrip? _chatProposal;
  bool _chatProposalSaved = false;

  // ── Animations ───────────────────────────────────────────────
  late AnimationController _sparkleCtrl;

  // ── Real Gemini ──────────────────────────────────────────────
  static const _kApiKey = AppConfig.geminiApiKey;
  late final GenerativeModel _model;
  final List<Content> _history = [];

  static const _kDayColors = [
    Color(0xFFE8845A), Color(0xFF5A8ABF), Color(0xFF5A9F6A),
    Color(0xFF8A5ABF), Color(0xFFBFA84A),
  ];

  static const _kSystemPrompt = '''
你是嘉義在地旅遊達人「諸羅精靈」，協助規劃嘉義行程。

【回覆規則】
1. 必須回傳純 JSON，不含 Markdown 標記。
2. 格式固定如下：
{
  "replyText": "繁體中文口語回覆，語氣熱情親切",
  "plan": [
    {
      "day": 1,
      "items": [
        {
          "time": "09:00",
          "name": "景點/餐廳/活動名稱",
          "duration": "90 分鐘",
          "note": "建議說明",
          "isMeal": false,
          "isTransport": false,
          "transport": null,
          "transportNote": null,
          "stationName": null,
          "lat": 23.4780,
          "lng": 120.4407
        }
      ]
    }
  ]
}
3. 只有在生成/修改行程時才包含 plan 欄位；純對話回覆可省略 plan。
4. 景點之間加入交通段（isTransport:true，transport 填對應方式）。
5. 午餐安排在 12:00-13:00（isMeal:true），晚餐在 18:00（isMeal:true）。

【嘉義常識】
- 推薦：雞肉飯、沙鍋魚頭、奮起湖便當、文化路夜市
- 常用座標：嘉義市區(23.4780,120.4407)、阿里山(23.5083,120.8034)、故宮南院(23.4372,120.3698)、檜意森活村(23.4793,120.4434)、嘉義公園(23.4855,120.4517)
- 公車：7229路連嘉義站與故宮南院，市區公車覆蓋中正路一帶
''';

  @override
  void initState() {
    super.initState();
    _sparkleCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _kApiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      systemInstruction: Content.system(_kSystemPrompt),
    );
  }

  @override
  void dispose() {
    _sparkleCtrl.dispose();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════
  // Gemini 核心呼叫
  // ════════════════════════════════════════════════════════════
  Future<({String reply, List<_DayPlan>? plan})> _callGemini(
    String prompt, {bool clearHistory = false}
  ) async {
    if (clearHistory) _history.clear();
    _history.add(Content.text(prompt));
    try {
      final response = await _model.generateContent(_history);
      final raw = response.text ?? '{"replyText":"抱歉，無法取得回覆"}';
      _history.add(Content.model([TextPart(raw)]));

      final clean = raw
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final data = jsonDecode(clean) as Map<String, dynamic>;
      final reply = data['replyText'] as String? ?? '好的，請稍候';
      final planData = data['plan'] as List?;
      final plan = planData != null ? _parsePlan(planData) : null;
      return (reply: reply, plan: plan);
    } catch (e) {
      _history.removeLast(); // 失敗時移除未完成的 user message
      return (reply: '抱歉，發生錯誤：$e', plan: null);
    }
  }

  List<_DayPlan> _parsePlan(List<dynamic> planData) {
    return planData.asMap().entries.map((dayEntry) {
      final d = dayEntry.value as Map<String, dynamic>;
      final day = (d['day'] as num?)?.toInt() ?? (dayEntry.key + 1);
      final color = _kDayColors[day % _kDayColors.length];
      final rawItems = (d['items'] as List? ?? []);
      final items = rawItems.map((raw) {
        final m = raw as Map<String, dynamic>;
        final transport = TransportModeExt.fromString(m['transport'] as String?);
        final isMeal = m['isMeal'] as bool? ?? false;
        final isTransport = m['isTransport'] as bool? ?? (transport != null);
        return _ScheduleItem(
          time: m['time'] as String? ?? '--:--',
          name: m['name'] as String? ?? '',
          duration: m['duration'] as String? ?? '',
          note: m['note'] as String? ?? '',
          icon: _iconFor(m['name'] as String? ?? '', isMeal, isTransport, transport),
          isMeal: isMeal,
          transport: isTransport ? transport : null,
          transportNote: m['transportNote'] as String?,
          stationName: m['stationName'] as String?,
          stationLat: (m['lat'] as num?)?.toDouble(),
          stationLng: (m['lng'] as num?)?.toDouble(),
        );
      }).toList();
      return _DayPlan(day: day, color: color, items: items);
    }).toList();
  }

  static IconData _iconFor(String name, bool isMeal, bool isTransport, TransportMode? transport) {
    if (isTransport && transport != null) return transport.icon;
    if (isMeal) return Icons.restaurant_rounded;
    if (name.contains('山') || name.contains('林') || name.contains('湖') || name.contains('溪')) return Icons.landscape_rounded;
    if (name.contains('館') || name.contains('博物') || name.contains('美術') || name.contains('文化')) return Icons.museum_rounded;
    if (name.contains('夜市') || name.contains('小吃') || name.contains('飯') || name.contains('咖啡')) return Icons.restaurant_rounded;
    if (name.contains('公園') || name.contains('花園')) return Icons.park_rounded;
    if (name.contains('寺') || name.contains('廟') || name.contains('教堂')) return Icons.temple_buddhist_rounded;
    return Icons.place_rounded;
  }

  // ── 智排行程 ─────────────────────────────────────────────────
  Future<void> _runSchedule() async {
    final spots = _activeSpots;
    if (spots.isEmpty) return;
    setState(() { _scheduling = true; _schedulePlan = null; });

    final depLabel = _depTime == 'morning' ? '早上 9 點' : _depTime == 'afternoon' ? '下午 2 點' : '彈性出發';
    final transportStr = _transportModes.map((m) => m.label).join('、');
    final prompt =
        '請幫我安排 $_days 天的嘉義行程。'
        '候選景點：${spots.join('、')}。'
        '出發時間：$depLabel。'
        '交通方式：$transportStr。'
        '請考慮順路程度並加入交通段與用餐時間，生成完整 JSON。';

    final result = await _callGemini(prompt, clearHistory: true);
    if (mounted) setState(() {
      _schedulePlan = result.plan;
      _scheduling = false;
    });
  }

  List<String> get _activeSpots {
    if (_selectedImportTrip != null &&
        widget.importedTrips?[_selectedImportTrip] != null) {
      return widget.importedTrips![_selectedImportTrip]!;
    }
    return widget.candidateSpots;
  }

  void _saveScheduleAsTrip() {
    if (_schedulePlan == null) return;
    final trip = AiGeneratedTrip(
      title: 'AI 嘉義 $_days 日行程',
      highlight: '由諸羅精靈智排，共 ${_activeSpots.length} 個景點',
      tips: '依照您的交通方式與出發時間最佳化安排',
      spots: _activeSpots,
      days: _days,
      budget: '一般',
      schedule: _schedulePlan!,
    );
    widget.onSaveTrip?.call(trip);
    _showSavedSnackbar(context, trip.title);
  }

  // ── 切換模式 ─────────────────────────────────────────────────
  void _switchMode(String m) {
    setState(() {
      _mode = m;
      _schedulePlan = null;
      _chatMessages.clear();
      _chatProposal = null;
      _chatProposalSaved = false;
      _history.clear();
    });
    if (m == 'chat_import' || m == 'chat_free') _initChat(m);
  }

  void _initChat(String mode) {
    final greeting = mode == 'chat_import'
        ? '嗨！你想把哪個行程交給我來優化或重新規劃呢？請先選擇行程，然後告訴我你的需求 📝'
        : '嗨！我是諸羅精靈 🌟\n\n為了幫你量身規劃，先問幾個問題：\n\n'
          '① 幾天幾夜？\n'
          '② 幾個人同行？\n'
          '③ 旅行風格（美食 / 文青 / 自然 / 打卡）？\n'
          '④ 大概預算（節省 / 一般 / 享受）？\n\n'
          '回答後我馬上幫你規劃！';
    setState(() {
      _chatMessages.add(_ChatMessage(isUser: false, text: greeting));
    });
  }

  // ── Chat 送出 ────────────────────────────────────────────────
  Future<void> _sendChat(String text) async {
    if (text.trim().isEmpty) return;
    _chatCtrl.clear();
    setState(() {
      _chatMessages.add(_ChatMessage(isUser: true, text: text));
      _chatThinking = true;
    });
    _scrollChatToBottom();

    // 讓 AI 知道目前的交通偏好
    final transportStr = _transportModes.map((m) => m.label).join('、');
    final contextNote = '（目前選擇的交通方式：$transportStr）';

    final result = await _callGemini(text + contextNote);
    if (mounted) {
      setState(() {
        _chatMessages.add(_ChatMessage(
          isUser: false,
          text: result.reply,
          generatedTrip: result.plan != null ? _planToTrip(result.plan!) : null,
        ));
        if (result.plan != null) _chatProposal = _planToTrip(result.plan!);
        _chatThinking = false;
      });
      _scrollChatToBottom();
    }
  }

  Future<void> _generateTripFromChat() async {
    setState(() { _chatThinking = true; _chatProposal = null; _chatProposalSaved = false; });
    _scrollChatToBottom();

    final transportStr = _transportModes.map((m) => m.label).join('、');
    final result = await _callGemini(
      '請根據我們的對話，生成完整的嘉義行程 JSON。交通方式：$transportStr。',
    );
    if (mounted) {
      final trip = result.plan != null ? _planToTrip(result.plan!) : null;
      setState(() {
        _chatThinking = false;
        _chatProposal = trip;
        _chatMessages.add(_ChatMessage(
          isUser: false,
          text: trip != null
              ? '✨ 已為你生成完整行程「${trip.title}」！查看下方預覽，喜歡就按「加入行程列表」，不滿意繼續告訴我怎麼調整。'
              : result.reply,
          generatedTrip: trip,
        ));
      });
      _scrollChatToBottom();
    }
  }

  AiGeneratedTrip _planToTrip(List<_DayPlan> plan) {
    final spots = plan.expand((d) => d.items
        .where((i) => i.transport == null && !i.isMeal)
        .map((i) => i.name)).toList();
    return AiGeneratedTrip(
      title: 'AI 嘉義 ${plan.length} 日遊',
      highlight: '諸羅精靈為你規劃，共 ${spots.length} 個景點',
      tips: '依照你的交通方式與偏好最佳化安排',
      spots: spots,
      days: plan.length,
      budget: '一般',
      schedule: plan,
    );
  }

  void _saveChatTrip() {
    if (_chatProposal == null) return;
    widget.onSaveTrip?.call(_chatProposal!);
    setState(() => _chatProposalSaved = true);
    _showSavedSnackbar(context, _chatProposal!.title);
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    });
  }

  void _showSavedSnackbar(BuildContext ctx, String title) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('「$title」已加入行程列表！')),
      ]),
      backgroundColor: const Color(0xFF5A9F6A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _buildHeader(primary)),
        SliverToBoxAdapter(child: _buildModeToggle(primary)),
        SliverToBoxAdapter(child: _buildTransportSelector(primary)),
        SliverToBoxAdapter(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: _mode == 'schedule'
              ? _buildScheduleMode(primary)
              : _buildChatMode(primary),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]),
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader(Color primary) {
    final dark = Color.lerp(primary, Colors.black, 0.25)!;
    return ClipPath(
      clipper: _AIHeaderClipper(),
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [primary, dark])),
        child: SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 52),
          child: Stack(children: [
            Positioned.fill(child: IgnorePointer(child: Stack(children: [
              Positioned(top: 12, right: 18, child: DoodleHeart(color: Colors.white.withValues(alpha: 0.14), size: 14)),
              Positioned(top: 55, right: 48, child: DoodleLightning(color: Colors.white.withValues(alpha: 0.12), size: 11)),
              Positioned(top: 100, right: 22, child: DoodleCloud(color: Colors.white.withValues(alpha: 0.10), width: 26)),
            ]))),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 16),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.white.withValues(alpha: 0.85)),
                    const SizedBox(width: 5),
                    Text('Gemini AI 旅遊規劃師', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
              const SizedBox(height: 24),
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
                          ? '從零開始規劃行程，對話即可！'
                          : '已有 ${widget.candidateSpots.length} 個候選景點可排程',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                    ),
                  ),
                ])),
              ]),
            ]),
          ]),
        )),
      ),
    );
  }

  Widget _buildSparkleOrb(Color primary) {
    return AnimatedBuilder(
      animation: _sparkleCtrl,
      builder: (_, __) {
        final t = _sparkleCtrl.value;
        return SizedBox(width: 72, height: 72, child: Stack(alignment: Alignment.center, children: [
          Transform.rotate(
            angle: t * 2 * math.pi,
            child: Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.25 + 0.15 * math.sin(t * math.pi)), width: 1.5))),
          ),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.20), border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5)),
            child: const Center(child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26)),
          ),
          Transform.translate(
            offset: Offset(32 * math.cos(t * 2 * math.pi), 32 * math.sin(t * 2 * math.pi)),
            child: Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
          ),
        ]));
      },
    );
  }

  // ── Mode toggle ──────────────────────────────────────────────
  Widget _buildModeToggle(Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _modeCard(icon: Icons.route_rounded, label: '智排行程', subtitle: '景點一鍵排程', number: '01', selected: _mode == 'schedule', primary: primary, onTap: () => _switchMode('schedule'))),
          const SizedBox(width: 10),
          Expanded(child: _modeCard(icon: Icons.upload_rounded, label: '行程匯入', subtitle: '帶著行程對話優化', number: '02', selected: _mode == 'chat_import', primary: primary, onTap: () => _switchMode('chat_import'))),
        ]),
        const SizedBox(height: 10),
        _modeCardWide(icon: Icons.forum_rounded, label: '自由對話規劃', subtitle: '從零開始，用對話讓精靈幫你打造嘉義專屬行程', number: '03', selected: _mode == 'chat_free', primary: primary, onTap: () => _switchMode('chat_free')),
      ]),
    );
  }

  Widget _modeCard({required IconData icon, required String label, required String subtitle, required String number, required bool selected, required Color primary, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: StitchedBox(
        color: selected ? primary : Colors.white,
        stitchColor: selected ? Colors.white.withValues(alpha: 0.3) : primary.withValues(alpha: 0.25),
        radius: 20, inset: 5, dashWidth: 5, dashGap: 4,
        boxShadow: [BoxShadow(color: selected ? primary.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.06), blurRadius: selected ? 16 : 6, offset: const Offset(0, 4))],
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: 0.2) : primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
              child: Text(number, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: selected ? Colors.white : primary, letterSpacing: 0.5)),
            ),
            const Spacer(),
            Icon(icon, size: 20, color: selected ? Colors.white.withValues(alpha: 0.9) : primary),
          ]),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: selected ? Colors.white : AppColors.textPrimary)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(fontSize: 10, height: 1.4, color: selected ? Colors.white.withValues(alpha: 0.72) : AppColors.textHint)),
        ]),
      ),
    );
  }

  Widget _modeCardWide({required IconData icon, required String label, required String subtitle, required String number, required bool selected, required Color primary, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: StitchedBox(
        color: selected ? primary : Colors.white,
        stitchColor: selected ? Colors.white.withValues(alpha: 0.3) : primary.withValues(alpha: 0.25),
        radius: 20, inset: 5, dashWidth: 5, dashGap: 4,
        boxShadow: [BoxShadow(color: selected ? primary.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.06), blurRadius: selected ? 16 : 6, offset: const Offset(0, 4))],
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: 0.2) : primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: Center(child: Icon(icon, size: 22, color: selected ? Colors.white : primary))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: selected ? Colors.white : AppColors.textPrimary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: 0.2) : primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
                child: Text(number, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: selected ? Colors.white : primary)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(fontSize: 11, height: 1.4, color: selected ? Colors.white.withValues(alpha: 0.75) : AppColors.textHint)),
          ])),
        ]),
      ),
    );
  }

  // ── Transport selector ───────────────────────────────────────
  Widget _buildTransportSelector(Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: StitchedBox(
        color: Colors.white, stitchColor: primary.withValues(alpha: 0.18),
        radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.directions_rounded, size: 15, color: primary),
            const SizedBox(width: 6),
            Text('您的交通方式（可複選）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: TransportMode.values.map((mode) {
              final sel = _transportModes.contains(mode);
              return GestureDetector(
                onTap: () => setState(() {
                  if (sel) { if (_transportModes.length > 1) _transportModes.remove(mode); }
                  else _transportModes.add(mode);
                  _schedulePlan = null; _chatProposal = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? primary.withValues(alpha: 0.12) : AppColors.surfaceMoss,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? primary : AppColors.divider)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(mode.icon, size: 14, color: sel ? primary : AppColors.textHint),
                    const SizedBox(width: 5),
                    Text(mode.label, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? primary : AppColors.textSecondary)),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text('AI 會根據你的交通方式推薦最佳路線及對應站牌', style: const TextStyle(fontSize: 10, color: AppColors.textHint, height: 1.4)),
        ]),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // MODE 1: Smart Schedule
  // ════════════════════════════════════════════════════════════
  Widget _buildScheduleMode(Color primary) {
    final key = const ValueKey('schedule');
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    final hasImported = widget.importedTrips?.isNotEmpty == true;

    // 問題 5 修正：候選景點可以直接使用，不需要匯入行程
    final activeSpots = _activeSpots;

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── 匯入行程下拉選單（問題 6：改為 Dropdown）──
        if (hasImported) ...[
          const Text('選擇景點來源', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          StitchedBox(
            color: Colors.white, stitchColor: primary.withValues(alpha: 0.18),
            radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedImportTrip,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: primary),
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Row(children: [
                      Icon(Icons.checklist_rounded, size: 16, color: primary),
                      const SizedBox(width: 8),
                      Text('候選清單（${widget.candidateSpots.length} 個景點）'),
                    ]),
                  ),
                  ...widget.importedTrips!.entries.map((e) => DropdownMenuItem<String?>(
                    value: e.key,
                    child: Row(children: [
                      Icon(Icons.map_rounded, size: 16, color: primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${e.key}（${e.value.length} 個景點）', overflow: TextOverflow.ellipsis)),
                    ]),
                  )),
                ],
                onChanged: (v) => setState(() { _selectedImportTrip = v; _schedulePlan = null; }),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── 候選景點預覽 ──
        if (activeSpots.isNotEmpty)
          StitchedBox(
            color: Colors.white, stitchColor: primary.withValues(alpha: 0.22),
            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.checklist_rounded, size: 15, color: primary),
                const SizedBox(width: 6),
                Text('${activeSpots.length} 個景點待排程', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: activeSpots.asMap().entries.map((e) =>
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(8), border: Border.all(color: primary.withValues(alpha: 0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 16, height: 16, decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                        child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
                    const SizedBox(width: 5),
                    Text(e.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ]),
                )).toList()),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: primary.withValues(alpha: 0.5), size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('沒有候選景點？先到地圖加入景點，或選擇已有行程匯入', style: TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.4))),
            ]),
          ),
        const SizedBox(height: 16),

        // ── 天數選擇 ──
        const Text('幾天的行程？', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(children: List.generate(5, (i) {
          final d = i + 1; final sel = _days == d;
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
                  boxShadow: sel ? [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))] : []),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$d', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: sel ? Colors.white : AppColors.textPrimary)),
                  Text('天', style: TextStyle(fontSize: 9, color: sel ? Colors.white.withValues(alpha: 0.8) : AppColors.textHint)),
                ]),
              ),
            ),
          );
        })),
        const SizedBox(height: 16),

        // ── 出發時間 ──
        const Text('幾點出發？', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(children: [
          _depChip('morning', Icons.wb_sunny_rounded, '早上', primary),
          const SizedBox(width: 8),
          _depChip('afternoon', Icons.wb_cloudy_rounded, '下午', primary),
          const SizedBox(width: 8),
          _depChip('flexible', Icons.shuffle_rounded, '彈性', primary),
        ]),
        const SizedBox(height: 20),

        // ── 排程按鈕 ──
        GestureDetector(
          onTap: (_scheduling || activeSpots.isEmpty) ? null : _runSchedule,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: (_scheduling || activeSpots.isEmpty) ? null : LinearGradient(colors: [primary, Color.lerp(primary, Colors.black, 0.2)!]),
              color: (_scheduling || activeSpots.isEmpty) ? AppColors.surfaceMoss : null,
              borderRadius: BorderRadius.circular(18),
              boxShadow: (_scheduling || activeSpots.isEmpty) ? [] : [BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6))]),
            child: _scheduling
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                    const SizedBox(width: 12),
                    const Text('諸羅精靈思考中…', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  ])
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('讓精靈排程', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ]),
          ),
        ),
        const SizedBox(height: 20),

        if (_schedulePlan != null) ...[
          _buildScheduleResult(primary),
          const SizedBox(height: 12),
          _buildSaveButton(label: '加入行程列表', icon: Icons.bookmark_add_rounded, primary: primary, onTap: _saveScheduleAsTrip),
        ],
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
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? primary : AppColors.textSecondary)),
        ]),
      ),
    ));
  }

  Widget _buildScheduleResult(Color primary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.check_circle_rounded, size: 16, color: primary),
        const SizedBox(width: 6),
        Text('精靈為你安排了 ${_schedulePlan!.length} 天行程', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary)),
      ]),
      const SizedBox(height: 12),
      ..._schedulePlan!.map((day) => _dayCard(day, primary)),
    ]);
  }

  // ════════════════════════════════════════════════════════════
  // MODE 2 & 3: Chat
  // ════════════════════════════════════════════════════════════
  Widget _buildChatMode(Color primary) {
    final isImport = _mode == 'chat_import';
    final key = ValueKey(_mode);

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── 匯入行程下拉選單（chat_import 模式）──
        if (isImport && widget.importedTrips?.isNotEmpty == true) ...[
          StitchedBox(
            color: Colors.white, stitchColor: primary.withValues(alpha: 0.18),
            radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedImportTrip,
                isExpanded: true,
                hint: Row(children: [
                  Icon(Icons.upload_rounded, size: 15, color: primary),
                  const SizedBox(width: 8),
                  Text('選擇要匯入的行程', style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: primary),
                items: widget.importedTrips!.entries.map((e) => DropdownMenuItem<String?>(
                  value: e.key,
                  child: Row(children: [
                    Icon(Icons.map_rounded, size: 15, color: primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${e.key}（${e.value.length} 個景點）', overflow: TextOverflow.ellipsis)),
                  ]),
                )).toList(),
                onChanged: (v) => setState(() => _selectedImportTrip = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── 對話視窗 ──
        Container(
          constraints: const BoxConstraints(maxHeight: 380),
          decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.divider)),
          child: _chatMessages.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 40, color: primary.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('開始對話，讓精靈幫你規劃行程', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                ])))
              : ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _chatMessages.length + (_chatThinking ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _chatMessages.length && _chatThinking) return _buildThinkingBubble(primary);
                    return _buildChatBubble(_chatMessages[i], primary);
                  },
                ),
        ),
        const SizedBox(height: 12),

        // ── 輸入框 ──
        Row(children: [
          Expanded(child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]),
            child: TextField(
              controller: _chatCtrl,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '告訴精靈你的需求…',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (v) => _sendChat(v),
              textInputAction: TextInputAction.send,
              maxLines: null,
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendChat(_chatCtrl.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48, height: 48,
              decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))]),
              child: const Center(child: Icon(Icons.send_rounded, color: Colors.white, size: 20)),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // ── 生成行程按鈕 ──
        GestureDetector(
          onTap: _chatThinking ? null : _generateTripFromChat,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: _chatThinking ? null : LinearGradient(colors: [primary, Color.lerp(primary, Colors.black, 0.2)!]),
              color: _chatThinking ? AppColors.surfaceMoss : null,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _chatThinking ? [] : [BoxShadow(color: primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))]),
            child: _chatThinking
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                    const SizedBox(width: 10),
                    const Text('精靈思考中…', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                  ])
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('✨ 生成完整行程', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                  ]),
          ),
        ),

        if (_chatProposal != null) ...[
          const SizedBox(height: 20),
          _buildChatProposalCard(_chatProposal!, primary),
          const SizedBox(height: 12),
          if (!_chatProposalSaved)
            _buildSaveButton(label: '加入行程列表', icon: Icons.bookmark_add_rounded, primary: primary, onTap: _saveChatTrip)
          else
            _buildSavedBadge(primary),
        ],
      ]),
    );
  }

  Widget _buildChatBubble(_ChatMessage msg, Color primary) {
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end, children: [
          const SizedBox(width: 48),
          Flexible(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4)),
              boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]),
            child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
          )),
          const SizedBox(width: 8),
          CircleAvatar(radius: 14, backgroundColor: primary.withValues(alpha: 0.15), child: Icon(Icons.person_rounded, size: 16, color: primary)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
            child: const Center(child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14))),
        const SizedBox(width: 8),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              border: Border.all(color: AppColors.divider),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]),
            child: Text(msg.text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.6)),
          ),
          if (msg.generatedTrip != null) ...[
            const SizedBox(height: 8),
            _buildChatProposalCard(msg.generatedTrip!, primary),
          ],
        ])),
        const SizedBox(width: 48),
      ]),
    );
  }

  Widget _buildThinkingBubble(Color primary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
            child: const Center(child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
            const SizedBox(width: 8),
            Text('諸羅精靈思考中…', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildChatProposalCard(AiGeneratedTrip trip, Color primary) {
    return StitchedBox(
      color: primary.withValues(alpha: 0.06), stitchColor: primary.withValues(alpha: 0.3),
      radius: 20, inset: 4, dashWidth: 5, dashGap: 4,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, size: 16, color: primary),
          const SizedBox(width: 6),
          Expanded(child: Text(trip.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: primary))),
        ]),
        const SizedBox(height: 6),
        Text(trip.highlight, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: trip.spots.asMap().entries.map((e) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: primary.withValues(alpha: 0.2))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 16, height: 16, decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                  child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
              const SizedBox(width: 5),
              Text(e.value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
            ]),
          )).toList()),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('查看詳細行程安排', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary)),
          children: trip.schedule.map((day) => _dayCard(day, primary)).toList(),
        ),
        if (trip.tips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceMoss, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.tips_and_updates_rounded, size: 14, color: primary),
              const SizedBox(width: 8),
              Expanded(child: Text(trip.tips, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.6))),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Day card ─────────────────────────────────────────────────
  Widget _dayCard(_DayPlan day, Color primary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: day.color.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: day.color.withValues(alpha: 0.3))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: day.color, borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
          child: Row(children: [
            Text('第 ${day.day} 天', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('${day.items.where((i) => !i.isMeal && i.transport == null).length} 個景點',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(children: day.items.asMap().entries.map((e) {
            final item = e.value;
            final isLast = e.key == day.items.length - 1;
            final isTransport = item.transport != null;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: isTransport ? day.color.withValues(alpha: 0.07) : item.isMeal ? AppColors.surfaceMoss : day.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: isTransport ? day.color.withValues(alpha: 0.25) : item.isMeal ? AppColors.divider : day.color.withValues(alpha: 0.4))),
                  child: Center(child: Icon(item.icon, size: 14,
                      color: isTransport ? day.color.withValues(alpha: 0.6) : item.isMeal ? AppColors.textHint : day.color)),
                ),
                if (!isLast) Container(width: 2, height: isTransport ? 22 : 32, color: day.color.withValues(alpha: isTransport ? 0.12 : 0.2)),
              ]),
              const SizedBox(width: 10),
              Expanded(child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 5),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: isTransport ? AppColors.surfaceMoss : day.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(item.time, style: TextStyle(fontSize: 10, color: isTransport ? AppColors.textHint : day.color, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 6),
                    Text(item.duration, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                  ]),
                  const SizedBox(height: 3),
                  Text(item.name, style: TextStyle(fontSize: isTransport ? 12 : 13, fontWeight: FontWeight.w700,
                      color: isTransport ? AppColors.textHint : item.isMeal ? AppColors.textHint : AppColors.textPrimary)),
                  if (item.note.isNotEmpty)
                    Text(item.note, style: const TextStyle(fontSize: 11, color: AppColors.textHint, height: 1.4)),
                  if (isTransport && item.stationName != null) ...[
                    const SizedBox(height: 5),
                    GestureDetector(
                      onTap: () => _openStationMap(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: day.color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: day.color.withValues(alpha: 0.25))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.location_on_rounded, size: 12, color: day.color),
                          const SizedBox(width: 4),
                          Text(item.stationName!, style: TextStyle(fontSize: 11, color: day.color, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new_rounded, size: 10, color: day.color.withValues(alpha: 0.7)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              )),
            ]);
          }).toList()),
        ),
      ]),
    );
  }

  void _openStationMap(_ScheduleItem item) {
    if (item.stationLat == null || item.stationLng == null) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _StationMapSheet(
        stationName: item.stationName!, lat: item.stationLat!, lng: item.stationLng!, transport: item.transport ?? TransportMode.bus,
      ),
    );
  }

  Widget _buildSaveButton({required String label, required IconData icon, required Color primary, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(border: Border.all(color: primary, width: 2), borderRadius: BorderRadius.circular(16), color: primary.withValues(alpha: 0.05)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: primary, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: primary, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _buildSavedBadge(Color primary) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFF5A9F6A).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF5A9F6A).withValues(alpha: 0.4))),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_rounded, color: Color(0xFF5A9F6A), size: 18),
        SizedBox(width: 8),
        Text('已加入行程列表！', style: TextStyle(color: Color(0xFF5A9F6A), fontSize: 15, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _emptyState(Key key, Color primary, String title, String body, IconData icon) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
      child: Column(children: [
        Icon(icon, size: 56, color: primary.withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.6)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Station Map Bottom Sheet
// ════════════════════════════════════════════════════════════════
class _StationMapSheet extends StatelessWidget {
  final String stationName;
  final double lat, lng;
  final TransportMode transport;
  const _StationMapSheet({required this.stationName, required this.lat, required this.lng, required this.transport});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.only(top: 12), child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(transport.icon, color: primary, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stationName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              Text('${transport.label} 站點', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: AppColors.surfaceMoss,
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.map_rounded, size: 48, color: primary.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                Text('$stationName\n${lat.toStringAsFixed(4)}°N, ${lng.toStringAsFixed(4)}°E',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.5)),
              ])),
            ),
          ),
        )),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Clips
// ════════════════════════════════════════════════════════════════
class _AIHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) {
    final base = s.height - 32.0;
    final p = Path()..lineTo(0, base + 6);
    p.cubicTo(s.width * 0.20, base - 18, s.width * 0.55, base + 26, s.width * 0.78, base - 10);
    p.cubicTo(s.width * 0.88, base - 20, s.width * 0.95, base + 8, s.width, base + 2);
    p.lineTo(s.width, 0);
    p.lineTo(0, 0);
    p.close();
    return p;
  }
  @override bool shouldReclip(_AIHeaderClipper old) => false;
}
