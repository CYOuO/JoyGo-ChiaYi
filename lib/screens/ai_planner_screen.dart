import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart'
    show StitchedBox, DoodleHeart, DoodleCloud, DoodleLightning;
import 'news_transport_screens.dart' show TransportScreen;

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
  final void Function(AiGeneratedTrip trip, String? targetTripTitle)? onSaveTrip;

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

  // ── 可編輯的候選景點（本地副本，支援刪除）─────────────────────
  late List<String> _localCandidates;

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

  static List<Color> _dayColors(Color primary, Color accent) => [
    primary,
    accent,
    Color.lerp(primary, accent, 0.45)!,
    Color.lerp(primary, Colors.black, 0.18)!,
    Color.lerp(accent, Colors.black, 0.18)!,
  ];

  static const _kSystemPrompt = '''
你是嘉義在地旅遊達人「諸羅精靈」，協助規劃嘉義行程。

【回覆規則】
1. 必須回傳純 JSON，不含 Markdown 標記。
2. 格式固定如下：
{
  "replyText": "繁體中文口語回覆，語氣熱情親切",
  "tripName": "根據行程特色命名，例如「奮起湖雲霧慢步兩日遊」「嘉義美食文青二日漫遊」（有 plan 時必填）",
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
3. 只有在生成/修改行程時才包含 plan 與 tripName 欄位；純對話回覆可省略。
4. 景點之間加入交通段（isTransport:true，transport 填對應方式，stationName 填站名）。
5. ⚠️ 地理順路原則：必須確保每天的景點安排「極度順路」。請先在腦中比對景點的實際地理位置（例如：市區、東區蘭潭、嘉義縣太保、阿里山），將位置相鄰的景點排在一起，絕對避免在地圖上來回折返跑。
6. 午餐安排在 12:00-13:00（isMeal:true），晚餐在 18:00（isMeal:true）。
7. 有交通段時 transportNote 填乘車資訊（如搭公車7229路）。

【嘉義常識】
- 推薦：雞肉飯、沙鍋魚頭、奮起湖便當、文化路夜市
- 常用座標：嘉義市區(23.4780,120.4407)、阿里山(23.5083,120.8034)、故宮南院(23.4372,120.3698)、檜意森活村(23.4793,120.4434)、嘉義公園(23.4855,120.4517)
- 公車：7229路連嘉義站與故宮南院，市區公車覆蓋中正路一帶
''';

  @override
  void initState() {
    super.initState();
    _localCandidates = List.from(widget.candidateSpots);
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
  Future<({String reply, List<_DayPlan>? plan, String? tripName})> _callGemini(
    String prompt, {bool clearHistory = false}
  ) async {
    if (_kApiKey.isEmpty) {
      return (reply: '尚未設定 Gemini API Key，請在 local.env.json 填入 GEMINI_API_KEY 後以 --dart-define-from-file=local.env.json 重新執行。', plan: null, tripName: null);
    }
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
      final tripName = data['tripName'] as String?;
      final primary = context.appPrimary;
      final accent  = context.appAccent;
      final plan = planData != null ? _parsePlan(planData, primary, accent) : null;
      return (reply: reply, plan: plan, tripName: tripName);
    } catch (e) {
      _history.removeLast(); // 失敗時移除未完成的 user message
      return (reply: '抱歉，發生錯誤：$e', plan: null, tripName: null);
    }
  }

  List<_DayPlan> _parsePlan(List<dynamic> planData, Color primary, Color accent) {
    final colors = _dayColors(primary, accent);
    return planData.asMap().entries.map((dayEntry) {
      final d = dayEntry.value as Map<String, dynamic>;
      final day = (d['day'] as num?)?.toInt() ?? (dayEntry.key + 1);
      final color = colors[day % colors.length];
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
  String? _scheduleTripName;

  Future<void> _runSchedule() async {
    final spots = _activeSpots;
    if (spots.isEmpty) return;
    setState(() { _scheduling = true; _schedulePlan = null; _scheduleTripName = null; });

    final depLabel = _depTime == 'morning' ? '早上 9 點' : _depTime == 'afternoon' ? '下午 2 點' : '彈性出發';
    final transportStr = _transportModes.map((m) => m.label).join('、');
    
    // 🌟 升級版提示詞：加入天氣考量與安插舊行程的邏輯
    // 🌟 升級版提示詞：加入天氣考量與安插舊行程的邏輯
    String prompt = '請幫我安排 $_days 天的嘉義行程。\n';
    
    if (_selectedImportTrip != null && widget.importedTrips != null && widget.importedTrips!.containsKey(_selectedImportTrip)) {
      final rawSpots = widget.importedTrips![_selectedImportTrip]!;
      
      // 🌟 計算原行程天數
      int tripDays = 0;
      final cleanSpots = <String>[];
      for (var s in rawSpots) {
        if (s.startsWith('__DAY_')) {
          tripDays++;
        } else {
          cleanSpots.add(s);
        }
      }
      if (tripDays > 0) setState(() => _days = tripDays); // 強制將 UI 天數與原行程同步

      prompt = '請幫我安排 $_days 天的嘉義行程。\n'; // 覆寫開頭的天數
      prompt += '【既有行程名稱】：$_selectedImportTrip\n';
      prompt += '【既有原景點】：${cleanSpots.join('、')}\n';
      prompt += '🌟 重要任務：此為 $_days 天的行程，請務必排滿 $_days 天。\n';
      if (_localCandidates.isNotEmpty) {
        prompt += '【待安插的新景點】：${_localCandidates.join('、')}\n';
        prompt += '任務要求：請將「待安插的新景點」巧妙加入「既有行程」中。請盡量保留既有行程的架構與順序，並考量順路程度。\n';
      } else {
        prompt += '任務要求：請幫我重新審視並優化這個行程的時間與交通。\n';
      }
    } else {
      prompt += '需安排的景點：${spots.join('、')}。\n';
    }
    
    prompt += '出發時間：$depLabel。\n交通方式：$transportStr。\n';
    prompt += '請考慮「天氣狀況與交通時間」，將戶外景點盡量安排在白天避開降雨。\n';
    prompt += '⚠️ 強烈要求：請務必根據嘉義的真實地圖方位來排序景點！每天的路線必須是一條順暢的線或環狀，【絕對不可以】安排東西南北來回折返的亂跑行程。\n';
    prompt += '請考慮順路程度並加入交通段（含站名）與用餐時間，同時幫行程取一個有特色的 tripName，生成完整 JSON。';

    final result = await _callGemini(prompt, clearHistory: true);
    if (mounted) setState(() {
      _schedulePlan = result.plan;
      _scheduleTripName = result.tripName;
      _scheduling = false;
    });
  }

  List<String> get _activeSpots {
    if (_selectedImportTrip != null &&
        widget.importedTrips?[_selectedImportTrip] != null) {
      // 🌟 過濾掉 __DAY_ 標籤，只保留純景點與候選景點合併
      final rawSpots = widget.importedTrips![_selectedImportTrip]!;
      final combined = Set<String>.from(rawSpots.where((s) => !s.startsWith('__DAY_')));
      combined.addAll(_localCandidates);
      return combined.toList();
    }
    return _localCandidates;
  }

  void _saveScheduleAsTrip() {
    if (_schedulePlan == null) return;
    // 🌟 優先使用匯入行程的原始名稱
    final titleToUse = _selectedImportTrip ?? _scheduleTripName ?? 'AI 嘉義 $_days 日行程';
    final trip = AiGeneratedTrip(
      title: titleToUse,
      highlight: '由諸羅精靈智排，共 ${_activeSpots.length} 個景點',
      tips: '依照您的交通方式與出發時間最佳化安排',
      spots: _activeSpots,
      days: _days,
      budget: '一般',
      schedule: _schedulePlan!,
    );
    widget.onSaveTrip?.call(trip, _selectedImportTrip);
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
        ? '嗨！請先選擇上方的行程，然後告訴我你的需求 📝\n\n'
          '例如：\n'
          '• 「幫我豐富行程，加入更多美食和景點」\n'
          '• 「重新安排順序，讓景點更順路」\n'
          '• 「加入交通資訊和站牌」\n\n'
          '選好行程後，我會根據你現有的景點進行加強規劃！'
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

    final transportStr = _transportModes.map((m) => m.label).join('、');
    String contextNote = '（目前選擇的交通方式：$transportStr）';

    // 行程匯入模式：把已選行程的景點傳給 AI 做上下文
    if (_mode == 'chat_import' && _selectedImportTrip != null &&
        widget.importedTrips?[_selectedImportTrip] != null) {
      final rawSpots = widget.importedTrips![_selectedImportTrip!]!;
      
      // 🌟 智慧計算原行程天數，並過濾出純景點
      int tripDays = 0;
      final cleanSpots = <String>[];
      for (var s in rawSpots) {
        if (s.startsWith('__DAY_')) {
          tripDays++;
        } else {
          cleanSpots.add(s);
        }
      }
      if (tripDays == 0) tripDays = 2; // 防呆預設

      contextNote += '。【現有行程「$_selectedImportTrip」景點清單】：${cleanSpots.join('、')}。'
                     '🌟 重要任務：這個現有行程原本是 $tripDays 天的規劃！請你務必輸出完整「$tripDays 天」的 plan。'
                     '請在此基礎上豐富行程，主動在現有景點之間插入推薦的嘉義景點、特色餐廳、交通段（含站牌）。'
                     '⚠️ 最重要：請務必根據真實地圖打散並重新排序所有景點，保證每天的路線「極度順路、絕對不折返跑」。'
                     '無論使用者說什麼，只要他希望優化/豐富/加強/修改行程，你必須輸出包含 plan 和 tripName 的完整 JSON，';
    }

    final result = await _callGemini(text + contextNote);
    if (mounted) {
      // 🌟 如果是匯入行程模式，強制保留原行程名稱，拒絕使用 AI 新取的名字
      final tripName = _selectedImportTrip ?? result.tripName;
      final trip = result.plan != null ? _planToTrip(result.plan!, name: tripName) : null;
      setState(() {
        _chatMessages.add(_ChatMessage(
          isUser: false,
          text: result.reply,
          generatedTrip: trip,
        ));
        if (trip != null) _chatProposal = trip;
        _chatThinking = false;
      });
      _scrollChatToBottom();
    }
  }

  AiGeneratedTrip _planToTrip(List<_DayPlan> plan, {String? name}) {
    final spots = plan.expand((d) => d.items
        .where((i) => i.transport == null && !i.isMeal)
        .map((i) => i.name)).toList();
    return AiGeneratedTrip(
      title: name?.isNotEmpty == true ? name! : 'AI 嘉義 ${plan.length} 日遊',
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
    final titleToUse = _selectedImportTrip ?? _chatProposal!.title;
    widget.onSaveTrip?.call(_chatProposal!, _selectedImportTrip);
    setState(() => _chatProposalSaved = true);
    // 🌟 Snackbar 顯示原始名稱
    _showSavedSnackbar(context, titleToUse);
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
    final primary = Theme.of(ctx).colorScheme.primary;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('「$title」已成功套用！')),
      ]),
      backgroundColor: primary,
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
    final accent  = context.appAccent;
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
              : _buildChatMode(primary, accent),
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
                    color: sel ? primary.withValues(alpha: 0.12) : primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? primary : primary.withValues(alpha: 0.20))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(mode.icon, size: 14, color: sel ? primary : primary.withValues(alpha: 0.45)),
                    const SizedBox(width: 5),
                    Text(mode.label, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? primary : primary.withValues(alpha: 0.6))),
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
          GestureDetector(
            onTap: _showTripPickerBottomSheet,
            child: StitchedBox(
              color: Colors.white, stitchColor: primary.withValues(alpha: 0.18),
              radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(_selectedImportTrip == null ? Icons.checklist_rounded : Icons.map_rounded, size: 18, color: primary),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _selectedImportTrip == null 
                      ? '一般候選清單（${widget.candidateSpots.length} 個景點）' 
                      : '$_selectedImportTrip（${widget.importedTrips![_selectedImportTrip!]!.length} 個景點）',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                )),
                Icon(Icons.keyboard_arrow_down_rounded, color: primary),
              ]),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── 候選景點預覽（排程後隱藏）──
        if (_schedulePlan == null) ...[
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
                const Spacer(),
                if (_selectedImportTrip == null)
                  Text('點 × 可移除', style: TextStyle(fontSize: 10, color: primary.withValues(alpha: 0.5))),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: activeSpots.asMap().entries.map((e) =>
                Container(
                  // 🌟 同樣加上最大寬度限制
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                  decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(8), border: Border.all(color: primary.withValues(alpha: 0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 16, height: 16, decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                        child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
                    const SizedBox(width: 5),
                    // 🌟 加入 Flexible 解決溢位
                    Flexible(
                      child: Text(e.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    // 只有候選清單（非匯入行程）才顯示刪除按鈕
                    if (_selectedImportTrip == null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() {
                          _localCandidates.removeAt(e.key);
                          _schedulePlan = null;
                        }),
                        child: Icon(Icons.close_rounded, size: 13, color: primary.withValues(alpha: 0.55)),
                      ),
                    ],
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
        ], // end if (_schedulePlan == null)
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
              color: (_scheduling || activeSpots.isEmpty) ? primary.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(18),
              boxShadow: (_scheduling || activeSpots.isEmpty) ? [] : [BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6))]),
            child: _scheduling
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                    const SizedBox(width: 12),
                    Text('諸羅精靈思考中…', style: TextStyle(fontWeight: FontWeight.w700, color: primary.withValues(alpha: 0.7))),
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
          // 📝 按鈕改名為套用行程
          _buildSaveButton(label: '套用行程', icon: Icons.playlist_add_check_rounded, primary: primary, onTap: _saveScheduleAsTrip),
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
  Widget _buildChatMode(Color primary, Color accent) {
    final isImport = _mode == 'chat_import';
    final key = ValueKey(_mode);

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── 匯入行程下拉選單（chat_import 模式）──
        if (isImport && widget.importedTrips?.isNotEmpty == true) ...[
          GestureDetector(
            onTap: _showTripPickerBottomSheet,
            child: StitchedBox(
              color: Colors.white, stitchColor: primary.withValues(alpha: 0.18),
              radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(Icons.upload_rounded, size: 18, color: primary),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _selectedImportTrip == null 
                      ? '點此選擇要匯入的行程...' 
                      : '$_selectedImportTrip（${widget.importedTrips![_selectedImportTrip!]!.length} 個景點）',
                  style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.w700, 
                      color: _selectedImportTrip == null ? primary : AppColors.textPrimary),
                )),
                Icon(Icons.keyboard_arrow_down_rounded, color: primary),
              ]),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── 對話視窗 ──
        Container(
          constraints: const BoxConstraints(maxHeight: 380),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: accent.withValues(alpha: 0.20))),
          child: _chatMessages.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 40, color: primary.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('開始對話，讓精靈幫你規劃行程', style: TextStyle(color: primary.withValues(alpha: 0.45), fontSize: 13)),
                ])))
              : ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _chatMessages.length + (_chatThinking ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _chatMessages.length && _chatThinking) return _buildThinkingBubble(primary, accent);
                    return _buildChatBubble(_chatMessages[i], primary, accent);
                  },
                ),
        ),
        const SizedBox(height: 12),

        // ── 輸入框 ──
        Row(children: [
          Expanded(child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: primary.withValues(alpha: 0.20)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]),
            child: TextField(
              controller: _chatCtrl,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '告訴精靈你的需求…',
                hintStyle: TextStyle(color: primary.withValues(alpha: 0.4), fontSize: 13),
                border: InputBorder.none,
                filled: false,
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
        if (_chatProposal != null) ...[
          const SizedBox(height: 20),
          _buildChatProposalCard(_chatProposal!, primary, accent),
          const SizedBox(height: 12),
          if (!_chatProposalSaved)
            _buildSaveButton(label: '套用行程', icon: Icons.playlist_add_check_rounded, primary: primary, onTap: _saveChatTrip)
          else
            _buildSavedBadge(primary),
        ],
      ]),
    );
  }

  Widget _buildChatBubble(_ChatMessage msg, Color primary, Color accent) {
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
              border: Border.all(color: accent.withValues(alpha: 0.25)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]),
            child: Text(msg.text, style: const TextStyle(color: Color(0xFF2C3030), fontSize: 13, height: 1.6)),
          ),
          if (msg.generatedTrip != null) ...[
            const SizedBox(height: 8),
            _buildChatProposalCard(msg.generatedTrip!, primary, accent),
          ],
        ])),
        const SizedBox(width: 48),
      ]),
    );
  }

  Widget _buildThinkingBubble(Color primary, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
            child: const Center(child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: 0.30))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
            const SizedBox(width: 8),
            Text('諸羅精靈思考中…', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildChatProposalCard(AiGeneratedTrip trip, Color primary, Color accent) {
    return StitchedBox(
      color: accent.withValues(alpha: 0.05), stitchColor: accent.withValues(alpha: 0.28),
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
            // 🌟 限制最大寬度為螢幕的 65%，避免超長文字溢位
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: primary.withValues(alpha: 0.2))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 16, height: 16, decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                  child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
              const SizedBox(width: 5),
              // 🌟 加入 Flexible 與 TextOverflow.ellipsis，過長文字自動變 ...
              Flexible(
                child: Text(e.value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
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
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: accent.withValues(alpha: 0.25))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.tips_and_updates_rounded, size: 14, color: accent),
              const SizedBox(width: 8),
              Expanded(child: Text(trip.tips, style: TextStyle(fontSize: 11, color: accent.withValues(alpha: 0.80), height: 1.6))),
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
                    color: isTransport ? day.color.withValues(alpha: 0.07) : item.isMeal ? day.color.withValues(alpha: 0.08) : day.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: isTransport ? day.color.withValues(alpha: 0.25) : item.isMeal ? day.color.withValues(alpha: 0.22) : day.color.withValues(alpha: 0.4))),
                  child: Center(child: Icon(item.icon, size: 14,
                      color: isTransport ? day.color.withValues(alpha: 0.6) : item.isMeal ? day.color.withValues(alpha: 0.55) : day.color)),
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
                      decoration: BoxDecoration(color: isTransport ? day.color.withValues(alpha: 0.07) : day.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(item.time, style: TextStyle(fontSize: 10, color: isTransport ? day.color.withValues(alpha: 0.5) : day.color, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 6),
                    Text(item.duration, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                  ]),
                  const SizedBox(height: 3),
                  Text(item.name, style: TextStyle(fontSize: isTransport ? 12 : 13, fontWeight: FontWeight.w700,
                      color: isTransport ? AppColors.textHint : item.isMeal ? AppColors.textHint : AppColors.textPrimary)),
                  if (item.note.isNotEmpty)
                    Text(item.note, style: const TextStyle(fontSize: 11, color: AppColors.textHint, height: 1.4)),
                  // 只有公車、火車、捷運等有站牌意義的交通段才顯示跳轉按鈕
                  if (isTransport && (item.transport == TransportMode.bus ||
                      item.transport == TransportMode.train ||
                      item.transport == TransportMode.hsr)) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _openStationMap(item),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: day.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: day.color.withValues(alpha: 0.25)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(item.transport!.icon, size: 11, color: day.color),
                              const SizedBox(width: 4),
                              // ConstrainedBox 限制最大寬度，避免 overflow
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 120),
                                child: Text(
                                  item.stationName ?? item.transportNote ?? '查看時刻表',
                                  style: TextStyle(fontSize: 11, color: day.color, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, size: 10, color: day.color.withValues(alpha: 0.7)),
                            ]),
                          ),
                        ],
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
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _StationMapSheet(
        stationName: item.stationName ?? item.name,
        lat: item.stationLat ?? 23.4780,
        lng: item.stationLng ?? 120.4407,
        transport: item.transport ?? TransportMode.bus,
        onGoTransport: () {
          Navigator.pop(context); // 關掉 bottom sheet
          final tab = _transportTabFor(item.transport ?? TransportMode.bus);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TransportScreen(initialTab: tab)));
        },
      ),
    );
  }

  static int _transportTabFor(TransportMode mode) {
    switch (mode) {
      case TransportMode.bus:   return 0;
      case TransportMode.bike:  return 1;
      case TransportMode.train: return 2;
      default: return 0;
    }
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
      decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16), border: Border.all(color: primary.withValues(alpha: 0.4))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_rounded, color: primary, size: 18),
        const SizedBox(width: 8),
        Text('已成功套用行程！', style: TextStyle(color: primary, fontSize: 15, fontWeight: FontWeight.w800)),
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

  void _showTripPickerBottomSheet() {
    final hasImported = widget.importedTrips != null && widget.importedTrips!.isNotEmpty;

    final primary = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 🌟 解決鍵盤擋住的關鍵
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)))),
            Text('選擇要匯入的行程', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: primary)),
            const SizedBox(height: 16),

            // 🌟 安全寫法：永遠顯示一般候選清單，不依賴 _mode 變數
            ListTile(
              leading: Icon(Icons.checklist_rounded, color: primary),
              title: Text('一般候選清單（${widget.candidateSpots.length} 個景點）', style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                setState(() { _selectedImportTrip = null; });
                Navigator.pop(context);
              },
            ),

            if (hasImported)
              ...widget.importedTrips!.entries.map((e) => ListTile(
                leading: Icon(Icons.map_rounded, color: primary),
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${e.value.length} 個景點'),
                onTap: () {
                  setState(() { _selectedImportTrip = e.key; });
                  Navigator.pop(context);
                },
              )),
          ]),
        ),
      ),
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
  final VoidCallback? onGoTransport;
  const _StationMapSheet({
    required this.stationName, required this.lat, required this.lng,
    required this.transport, this.onGoTransport,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.only(top: 12), child: Container(width: 40, height: 4, decoration: BoxDecoration(color: primary.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(2)))),
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
            if (onGoTransport != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onGoTransport,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.open_in_new_rounded, size: 13, color: primary),
                    const SizedBox(width: 4),
                    Text('時刻表', style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: primary.withValues(alpha: 0.05),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(transport.icon, size: 48, color: primary.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                Text('$stationName\n${lat.toStringAsFixed(4)}°N, ${lng.toStringAsFixed(4)}°E',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: primary.withValues(alpha: 0.5), height: 1.5)),
                const SizedBox(height: 16),
                if (onGoTransport != null)
                  TextButton.icon(
                    onPressed: onGoTransport,
                    icon: Icon(Icons.open_in_new_rounded, size: 14, color: primary),
                    label: Text('前往${transport.label}頁面查看時刻表', style: TextStyle(color: primary, fontSize: 12)),
                  ),
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
