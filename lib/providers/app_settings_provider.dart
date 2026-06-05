import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════
//  Theme Presets
//  Colors are slightly deeper than the calendar event dots so the
//  active nav/button colour stays visually distinct.
// ═══════════════════════════════════════════════════════════

class ThemePreset {
  final String name;
  final Color  primary;
  final Color  primaryDark;
  final Color  primaryMist;
  final Color  accent;
  const ThemePreset({
    required this.name,
    String emoji = '',   // retained for backward compat, unused
    required this.primary, required this.primaryDark, required this.primaryMist,
    required this.accent,
  });
}

// Calendar category colors (reference):
//   政府活動 #26C6DA (cyan) → 嘉義青 deeper
//   政府新聞 #42A5F5 (blue) → 嘉義藍 deeper
//   個人行程 #66BB6A (green)→ 嘉義綠 deeper
//   個人活動 #FFA726 (orange)→ 嘉義橙 deeper
//   bonus:  deep purple      → 嘉義紫

const kThemePresets = <ThemePreset>[
  ThemePreset(
    name: '嘉義青',  emoji: '🌊',
    primary:     Color(0xFF00838F),
    primaryDark: Color(0xFF006064),
    primaryMist: Color(0xFFE0F7FA),
    accent:      Color(0xFFC04848), // 珊瑚紅搭青
  ),
  ThemePreset(
    name: '嘉義藍',  emoji: '🌌',
    primary:     Color(0xFF1565C0),
    primaryDark: Color(0xFF003C8F),
    primaryMist: Color(0xFFE3F2FD),
    accent:      Color(0xFF2E8B5C), // 祖母綠搭深藍
  ),
  ThemePreset(
    name: '嘉義綠',  emoji: '🌿',
    primary:     Color(0xFF5B8A5F),
    primaryDark: Color(0xFF3D6B42),
    primaryMist: Color(0xFFEDF2ED),
    accent:      Color(0xFFD4873A), // 琥珀橙搭苔綠
  ),
  ThemePreset(
    name: '嘉義橙',  emoji: '🍊',
    primary:     Color(0xFFE65100),
    primaryDark: Color(0xFFBF360C),
    primaryMist: Color(0xFFFBE9E7),
    accent:      Color(0xFF1565C0), // 深藍搭燒橙
  ),
  ThemePreset(
    name: '嘉義紫',  emoji: '💜',
    primary:     Color(0xFF6A1B9A),
    primaryDark: Color(0xFF38006B),
    primaryMist: Color(0xFFF3E5F5),
    accent:      Color(0xFF2565D0), // 藍搭深紫
  ),
  // ── Pastel candy colors ──────────────────────────────────────
  ThemePreset(
    name: '甜蜜桃',  emoji: '🍑',
    primary:     Color(0xFFE07858),
    primaryDark: Color(0xFFC05030),
    primaryMist: Color(0xFFFFEDE6),
    accent:      Color(0xFF9070C0), // 薰衣紫搭珊瑚橘
  ),
  ThemePreset(
    name: '少女粉',  emoji: '🌸',
    primary:     Color(0xFFD05878),
    primaryDark: Color(0xFFAA3055),
    primaryMist: Color(0xFFFFF0F4),
    accent:      Color(0xFF00858A), // 青綠搭玫瑰粉
  ),
  ThemePreset(
    name: '薰衣紫',  emoji: '💜',
    primary:     Color(0xFF9070C0),
    primaryDark: Color(0xFF6A4898),
    primaryMist: Color(0xFFF4F0FC),
    accent:      Color(0xFF4A90C0), // 天藍搭薰衣紫
  ),
  ThemePreset(
    name: '夢幻綠',  emoji: '🌱',
    primary:     Color(0xFF58A880),
    primaryDark: Color(0xFF38865E),
    primaryMist: Color(0xFFEEFBF4),
    accent:      Color(0xFF8060B0), // 紫搭薄荷
  ),
  ThemePreset(
    name: '檸檬黃',  emoji: '🍋',
    primary:     Color(0xFFB89020),
    primaryDark: Color(0xFF906E00),
    primaryMist: Color(0xFFFFF9E0),
    accent:      Color(0xFFC0394A), // 莓紅搭芥末金
  ),
  ThemePreset(
    name: '天空藍',  emoji: '☁️',
    primary:     Color(0xFF5090C0),
    primaryDark: Color(0xFF306898),
    primaryMist: Color(0xFFEEF7FF),
    accent:      Color(0xFF3A9A6A), // 翠綠搭晴空藍
  ),
  // ── Extra four ──────────────────────────────────────────────
  ThemePreset(
    name: '莓果紅',  emoji: '🍓',
    primary:     Color(0xFFC0394A),
    primaryDark: Color(0xFF97202F),
    primaryMist: Color(0xFFFFECEE),
    accent:      Color(0xFF00838F), // 青搭莓紅
  ),
  ThemePreset(
    name: '深海綠',  emoji: '🐊',
    primary:     Color(0xFF2E8B5C),
    primaryDark: Color(0xFF1A6640),
    primaryMist: Color(0xFFE8F6EF),
    accent:      Color(0xFFD05878), // 玫瑰粉搭祖母綠
  ),
  ThemePreset(
    name: '咖啡棕',  emoji: '☕',
    primary:     Color(0xFF7B5E42),
    primaryDark: Color(0xFF5A3F28),
    primaryMist: Color(0xFFF5EDE5),
    accent:      Color(0xFFD05878), // 玫瑰粉搭咖啡棕
  ),
  ThemePreset(
    name: '暮光藍',  emoji: '🌆',
    primary:     Color(0xFF4A6FA5),
    primaryDark: Color(0xFF2D4F80),
    primaryMist: Color(0xFFECF1F9),
    accent:      Color(0xFF3A9A6A), // 翠綠搭暮光藍
  ),
];

// ═══════════════════════════════════════════════════════════
//  Localisation helper  (zh / en / ja)
// ═══════════════════════════════════════════════════════════
class AppL10n {
  final String langCode;
  const AppL10n(this.langCode);

  // ── Bottom nav
  String get navHome      => _t({'zh':'首頁',  'en':'Home',    'ja':'ホーム'});
  String get navMap       => _t({'zh':'地圖',  'en':'Map',     'ja':'マップ'});
  String get navTrip      => _t({'zh':'行程',  'en':'Trip',    'ja':'旅程'});
  String get navExpense   => _t({'zh':'分帳',  'en':'Split',   'ja':'割り勘'});
  String get navCommunity => _t({'zh':'社群',  'en':'Social',  'ja':'コミュニティ'});
  String get navStamp     => _t({'zh':'集章',  'en':'Stamps',  'ja':'スタンプ'});

  // ── App-level
  String get appTitle     => _t({'zh':'探索諸羅',  'en':'Explore Chiayi', 'ja':'諸羅探索'});
  String get settings     => _t({'zh':'設定',      'en':'Settings',       'ja':'設定'});
  String get themeColor   => _t({'zh':'主題顏色',  'en':'Theme Color',    'ja':'テーマカラー'});
  String get language     => _t({'zh':'語言',      'en':'Language',       'ja':'言語'});

  // ── Common actions
  String get save         => _t({'zh':'儲存', 'en':'Save',   'ja':'保存'});
  String get cancel       => _t({'zh':'取消', 'en':'Cancel', 'ja':'キャンセル'});
  String get confirm      => _t({'zh':'確認', 'en':'OK',     'ja':'確認'});
  String get edit         => _t({'zh':'編輯', 'en':'Edit',   'ja':'編集'});
  String get delete       => _t({'zh':'刪除', 'en':'Delete', 'ja':'削除'});
  String get share        => _t({'zh':'分享', 'en':'Share',  'ja':'シェア'});
  String get close        => _t({'zh':'關閉', 'en':'Close',  'ja':'閉じる'});
  String get add          => _t({'zh':'新增', 'en':'Add',    'ja':'追加'});
  String get search       => _t({'zh':'搜尋', 'en':'Search', 'ja':'検索'});
  String get filter       => _t({'zh':'篩選', 'en':'Filter', 'ja':'フィルター'});
  String get clearAll     => _t({'zh':'清除全部', 'en':'Clear All', 'ja':'すべてクリア'});
  String get loading      => _t({'zh':'載入中…', 'en':'Loading…', 'ja':'読み込み中…'});
  String get retry        => _t({'zh':'重試', 'en':'Retry', 'ja':'再試行'});
  String get noData       => _t({'zh':'暫無資料', 'en':'No data', 'ja':'データなし'});
  String get comingSoon   => _t({'zh':'敬請期待', 'en':'Coming Soon', 'ja':'近日公開'});
  String get done         => _t({'zh':'完成', 'en':'Done', 'ja':'完了'});

  // ── Home screen
  String get homeGreeting       => _t({'zh':'嘉義・在地旅遊全攻略', 'en':'Your Chiayi Travel Guide', 'ja':'嘉義旅行ガイド'});
  String get homeQuickAccess    => _t({'zh':'快速入口', 'en':'Quick Access', 'ja':'クイックアクセス'});
  String get homeNearbySpots    => _t({'zh':'附近景點', 'en':'Nearby Spots', 'ja':'近くの観光地'});
  String get homeHotFood        => _t({'zh':'人氣美食', 'en':'Popular Food', 'ja':'人気グルメ'});
  String get homeLatestNews     => _t({'zh':'嘉義消息', 'en':'Chiayi News', 'ja':'嘉義ニュース'});
  String get homeLatestEvents   => _t({'zh':'近期活動', 'en':'Upcoming Events', 'ja':'近日のイベント'});
  String get homeTransport      => _t({'zh':'交通動態', 'en':'Transport', 'ja':'交通情報'});

  // ── Map screen
  String get mapSearch          => _t({'zh':'搜尋名稱或地址', 'en':'Search name or address', 'ja':'名前または住所を検索'});
  String get mapLayerControl    => _t({'zh':'圖層控制', 'en':'Layer Control', 'ja':'レイヤー管理'});
  String get mapDetailFilter    => _t({'zh':'細節篩選', 'en':'Detail Filter', 'ja':'詳細フィルター'});
  String get mapShowAll         => _t({'zh':'全部顯示', 'en':'Show All', 'ja':'すべて表示'});
  String get mapHideAll         => _t({'zh':'全部隱藏', 'en':'Hide All', 'ja':'すべて非表示'});
  String get mapNoResult        => _t({'zh':'目前沒有符合條件的地點', 'en':'No matching places', 'ja':'条件に合う場所なし'});

  // ── Trip screen
  String get tripManage         => _t({'zh':'行程管理', 'en':'Trip Planner', 'ja':'旅程管理'});
  String get tripMyTrips        => _t({'zh':'我的行程', 'en':'My Trips',    'ja':'マイ旅程'});
  String get tripCandidates     => _t({'zh':'候選清單', 'en':'Candidates',  'ja':'候補リスト'});
  String get tripSaved          => _t({'zh':'收藏景點', 'en':'Saved Spots', 'ja':'お気に入り'});
  String get tripCalendar       => _t({'zh':'行事曆',   'en':'Calendar',    'ja':'カレンダー'});
  String get tripPlanning       => _t({'zh':'規劃中', 'en':'Planning', 'ja':'計画中'});
  String get tripCompleted      => _t({'zh':'已完成', 'en':'Completed', 'ja':'完了済み'});
  String get tripTotalSpots     => _t({'zh':'總景點', 'en':'Total Spots', 'ja':'合計スポット'});

  // ── Calendar screen
  String get calGovEvent        => _t({'zh':'政府活動', 'en':'Gov Event',    'ja':'公式イベント'});
  String get calGovNews         => _t({'zh':'政府新聞', 'en':'Gov News',     'ja':'公式ニュース'});
  String get calUserTrip        => _t({'zh':'個人行程', 'en':'My Trip',      'ja':'マイ旅程'});
  String get calPersonal        => _t({'zh':'個人活動', 'en':'Personal',     'ja':'個人予定'});
  String get calAddEvent        => _t({'zh':'新增活動', 'en':'Add Event',    'ja':'予定を追加'});
  String get calNoEvent         => _t({'zh':'當天沒有活動', 'en':'No events', 'ja':'予定なし'});
  String get calEventTitle      => _t({'zh':'活動名稱', 'en':'Event Name',   'ja':'イベント名'});
  String get calEventDate       => _t({'zh':'日期',     'en':'Date',         'ja':'日付'});
  String get calEventNote       => _t({'zh':'備註',     'en':'Notes',        'ja':'メモ'});

  // ── Community screen
  String get commTitle          => _t({'zh':'旅遊社群', 'en':'Community',   'ja':'コミュニティ'});
  String get commPopular        => _t({'zh':'熱門貼文', 'en':'Popular',     'ja':'人気投稿'});
  String get commFollowing      => _t({'zh':'追蹤中',   'en':'Following',   'ja':'フォロー中'});
  String get commNearby         => _t({'zh':'附近',     'en':'Nearby',      'ja':'近く'});

  // ── Stamp screen
  String get stampTitle         => _t({'zh':'集章成就',    'en':'Stamps',        'ja':'スタンプ'});
  String get stampSpots         => _t({'zh':'景點印章',    'en':'Spot Stamps',   'ja':'スポット印章'});
  String get stampAchievements  => _t({'zh':'成就徽章',    'en':'Achievements',  'ja':'実績バッジ'});
  String get stampMiniMap       => _t({'zh':'小地圖',      'en':'Mini Map',      'ja':'ミニマップ'});

  // ── Expense screen
  String get expTitle           => _t({'zh':'旅遊分帳',  'en':'Trip Expense',  'ja':'旅費精算'});

  // ── Weekdays  (Sunday-first)
  List<String> get weekdayShort => langCode == 'en'
      ? ['S', 'M', 'T', 'W', 'T', 'F', 'S']
      : langCode == 'ja'
          ? ['日', '月', '火', '水', '木', '金', '土']
          : ['日', '一', '二', '三', '四', '五', '六'];

  // ── Month names
  String monthName(int month) {
    if (langCode == 'en') {
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return m[(month - 1).clamp(0, 11)];
    }
    if (langCode == 'ja') return '$month月';
    return '$month月';
  }

  // ── Language name options
  static const langOptions = <({String code, String native, String emoji})>[
    (code: 'zh', native: '繁體中文', emoji: '🇹🇼'),
    (code: 'en', native: 'English',  emoji: '🇺🇸'),
    (code: 'ja', native: '日本語',  emoji: '🇯🇵'),
  ];

  String _t(Map<String, String> map) => map[langCode] ?? map['zh']!;
}

// ═══════════════════════════════════════════════════════════
//  Provider
// ═══════════════════════════════════════════════════════════
class AppSettingsProvider extends ChangeNotifier {
  static const _kThemeKey = 'settings_theme_index';

  int _themeIndex = 7; // default: 薰衣紫

  int get themeIndex => _themeIndex;

  ThemePreset get currentTheme => kThemePresets[_themeIndex];
  // Language is always 繁體中文
  AppL10n get l10n => const AppL10n('zh');

  // Cache the SharedPreferences instance so we don't re-resolve it on every op.
  SharedPreferences? _prefs;
  Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  AppSettingsProvider() { _load(); }

  Future<void> _load() async {
    final prefs = await _sp;
    _themeIndex = (prefs.getInt(_kThemeKey) ?? 7)  // default: 薰衣紫
        .clamp(0, kThemePresets.length - 1);
    notifyListeners();
  }

  Future<void> setTheme(int index) async {
    final i = index.clamp(0, kThemePresets.length - 1);
    if (i == _themeIndex) return;
    _themeIndex = i;
    notifyListeners();
    final prefs = await _sp;
    await prefs.setInt(_kThemeKey, i);
  }
}
