import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════
//  Theme Presets
//  Colors are slightly deeper than the calendar event dots so the
//  active nav/button colour stays visually distinct.
// ═══════════════════════════════════════════════════════════

class ThemePreset {
  final String name;    // zh name
  final String nameEn;
  final String nameJa;
  final Color  primary;
  final Color  primaryDark;
  final Color  primaryMist;
  final Color  accent;
  const ThemePreset({
    required this.name,
    this.nameEn = '',
    this.nameJa = '',
    String emoji = '',
    required this.primary, required this.primaryDark, required this.primaryMist,
    required this.accent,
  });

  String localizedName(String langCode) {
    if (langCode == 'en' && nameEn.isNotEmpty) return nameEn;
    if (langCode == 'ja' && nameJa.isNotEmpty) return nameJa;
    return name;
  }
}

// Calendar category colors (reference):
//   政府活動 #26C6DA (cyan) → 嘉義青 deeper
//   政府新聞 #42A5F5 (blue) → 嘉義藍 deeper
//   個人行程 #66BB6A (green)→ 嘉義綠 deeper
//   個人活動 #FFA726 (orange)→ 嘉義橙 deeper
//   bonus:  deep purple      → 嘉義紫

const kThemePresets = <ThemePreset>[
  ThemePreset(
    name: '嘉義青', nameEn: 'Chiayi Cyan',    nameJa: 'CYシアン', emoji: '🌊',
    primary:     Color(0xFF00838F),
    primaryDark: Color(0xFF006064),
    primaryMist: Color(0xFFE0F7FA),
    accent:      Color(0xFFC04848),
  ),
  ThemePreset(
    name: '嘉義藍', nameEn: 'Chiayi Blue',    nameJa: 'CYブルー', emoji: '🌌',
    primary:     Color(0xFF1565C0),
    primaryDark: Color(0xFF003C8F),
    primaryMist: Color(0xFFE3F2FD),
    accent:      Color(0xFF2E8B5C),
  ),
  ThemePreset(
    name: '嘉義綠', nameEn: 'Chiayi Green',   nameJa: 'CYグリーン', emoji: '🌿',
    primary:     Color(0xFF5B8A5F),
    primaryDark: Color(0xFF3D6B42),
    primaryMist: Color(0xFFEDF2ED),
    accent:      Color(0xFFD4873A),
  ),
  ThemePreset(
    name: '嘉義橙', nameEn: 'Chiayi Orange',  nameJa: 'CYオレンジ', emoji: '🍊',
    primary:     Color(0xFFE65100),
    primaryDark: Color(0xFFBF360C),
    primaryMist: Color(0xFFFBE9E7),
    accent:      Color(0xFF1565C0),
  ),
  ThemePreset(
    name: '嘉義紫', nameEn: 'Chiayi Purple',  nameJa: 'CYパープル', emoji: '💜',
    primary:     Color(0xFF6A1B9A),
    primaryDark: Color(0xFF38006B),
    primaryMist: Color(0xFFF3E5F5),
    accent:      Color(0xFF2565D0),
  ),
  ThemePreset(
    name: '甜蜜桃', nameEn: 'Sweet Peach',    nameJa: 'スイートピーチ', emoji: '🍑',
    primary:     Color(0xFFE07858),
    primaryDark: Color(0xFFC05030),
    primaryMist: Color(0xFFFFEDE6),
    accent:      Color(0xFF9070C0),
  ),
  ThemePreset(
    name: '少女粉', nameEn: 'Blush Pink',     nameJa: 'ブラッシュピンク', emoji: '🌸',
    primary:     Color(0xFFD05878),
    primaryDark: Color(0xFFAA3055),
    primaryMist: Color(0xFFFFF0F4),
    accent:      Color(0xFF00858A),
  ),
  ThemePreset(
    name: '薰衣紫', nameEn: 'Lavender',       nameJa: 'ラベンダー', emoji: '💜',
    primary:     Color(0xFF9070C0),
    primaryDark: Color(0xFF6A4898),
    primaryMist: Color(0xFFF4F0FC),
    accent:      Color(0xFF4A90C0),
  ),
  ThemePreset(
    name: '夢幻綠', nameEn: 'Dream Green',    nameJa: 'ドリームグリーン', emoji: '🌱',
    primary:     Color(0xFF58A880),
    primaryDark: Color(0xFF38865E),
    primaryMist: Color(0xFFEEFBF4),
    accent:      Color(0xFF8060B0),
  ),
  ThemePreset(
    name: '檸檬黃', nameEn: 'Lemon Yellow',   nameJa: 'レモンイエロー', emoji: '🍋',
    primary:     Color(0xFFB89020),
    primaryDark: Color(0xFF906E00),
    primaryMist: Color(0xFFFFF9E0),
    accent:      Color(0xFFC0394A),
  ),
  ThemePreset(
    name: '天空藍', nameEn: 'Sky Blue',       nameJa: 'スカイブルー', emoji: '☁️',
    primary:     Color(0xFF5090C0),
    primaryDark: Color(0xFF306898),
    primaryMist: Color(0xFFEEF7FF),
    accent:      Color(0xFF3A9A6A),
  ),
  ThemePreset(
    name: '莓果紅', nameEn: 'Berry Red',      nameJa: 'ベリーレッド', emoji: '🍓',
    primary:     Color(0xFFC0394A),
    primaryDark: Color(0xFF97202F),
    primaryMist: Color(0xFFFFECEE),
    accent:      Color(0xFF00838F),
  ),
  ThemePreset(
    name: '深海綠', nameEn: 'Emerald',        nameJa: 'エメラルド', emoji: '🐊',
    primary:     Color(0xFF2E8B5C),
    primaryDark: Color(0xFF1A6640),
    primaryMist: Color(0xFFE8F6EF),
    accent:      Color(0xFFD05878),
  ),
  ThemePreset(
    name: '咖啡棕', nameEn: 'Coffee Brown',   nameJa: 'コーヒーブラウン', emoji: '☕',
    primary:     Color(0xFF7B5E42),
    primaryDark: Color(0xFF5A3F28),
    primaryMist: Color(0xFFF5EDE5),
    accent:      Color(0xFFD05878),
  ),
  ThemePreset(
    name: '暮光藍', nameEn: 'Twilight Blue',  nameJa: 'トワイライトブルー', emoji: '🌆',
    primary:     Color(0xFF4A6FA5),
    primaryDark: Color(0xFF2D4F80),
    primaryMist: Color(0xFFECF1F9),
    accent:      Color(0xFF3A9A6A),
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
  String get more         => _t({'zh':'更多', 'en':'More', 'ja':'もっと見る'});
  String get all          => _t({'zh':'全部', 'en':'All',  'ja':'すべて'});
  String get publish      => _t({'zh':'發布', 'en':'Publish', 'ja':'投稿'});
  String get report       => _t({'zh':'舉報', 'en':'Report',  'ja':'報告'});
  String get reply        => _t({'zh':'回覆', 'en':'Reply',   'ja':'返信'});
  String get reset        => _t({'zh':'重設', 'en':'Reset',   'ja':'リセット'});
  String get apply        => _t({'zh':'套用', 'en':'Apply',   'ja':'適用'});
  String get noLimit      => _t({'zh':'不限', 'en':'No Limit','ja':'制限なし'});
  String get navigate     => _t({'zh':'導航', 'en':'Navigate','ja':'ナビ'});
  String get updateFail   => _t({'zh':'更新失敗', 'en':'Update failed', 'ja':'更新失敗'});
  String get signIn       => _t({'zh':'登入', 'en':'Sign In', 'ja':'ログイン'});
  String get signOut      => _t({'zh':'登出', 'en':'Sign Out','ja':'ログアウト'});

  // ── Home screen
  String get homeGreeting        => _t({'zh':'嘉義・在地旅遊全攻略', 'en':'Your Chiayi Travel Guide', 'ja':'嘉義旅行ガイド'});
  String get homeQuickAccess     => _t({'zh':'快速入口', 'en':'Quick Access', 'ja':'クイックアクセス'});
  String get homeQuickNav        => _t({'zh':'快速導覽', 'en':'Quick Nav',    'ja':'クイックナビ'});
  String get homeNearbySpots     => _t({'zh':'附近景點', 'en':'Nearby Spots', 'ja':'近くの観光地'});
  String get homeHotFood         => _t({'zh':'人氣美食', 'en':'Popular Food',  'ja':'人気グルメ'});
  String get homeLatestNews      => _t({'zh':'最新消息', 'en':'Latest News',   'ja':'最新ニュース'});
  String get homeLatestEvents    => _t({'zh':'近期活動', 'en':'Upcoming Events','ja':'近日のイベント'});
  String get homeTransport       => _t({'zh':'交通動態', 'en':'Transport',     'ja':'交通情報'});
  String get homeSearchHint      => _t({'zh':'搜尋景點、美食、活動…', 'en':'Search spots, food, events…', 'ja':'スポット・グルメ・イベント…'});
  String get homeMapExplore      => _t({'zh':'地圖探索', 'en':'Map',          'ja':'マップ'});
  String get homeTripPlan        => _t({'zh':'行程管理', 'en':'Trip Plan',    'ja':'旅程管理'});
  String get homeExpenseSplit    => _t({'zh':'旅遊分帳', 'en':'Expense',      'ja':'旅費精算'});
  String get homeCommunityNav    => _t({'zh':'旅遊社群', 'en':'Community',    'ja':'コミュニティ'});
  String get homeEventCal        => _t({'zh':'活動行事曆','en':'Calendar',    'ja':'カレンダー'});
  String get homeStamps          => _t({'zh':'集章成就', 'en':'Stamps',       'ja':'スタンプ'});
  String get homeCamera          => _t({'zh':'打卡相機', 'en':'Camera',       'ja':'チェックイン'});
  String get homeViewMore        => _t({'zh':'點此查看 ›', 'en':'View ›',    'ja':'見る ›'});
  String get homeNewsLoadFail    => _t({'zh':'載入失敗，點此重試', 'en':'Load failed, tap to retry', 'ja':'読込失敗'});
  String get homeNoNews          => _t({'zh':'目前無最新消息', 'en':'No news available', 'ja':'ニュースなし'});
  String get homeReadFull        => _t({'zh':'看完整', 'en':'Read more', 'ja':'続きを読む'});
  String get homeNewsEventLabel  => _t({'zh':'活動', 'en':'Event',  'ja':'イベント'});
  String get homeNewsNewsLabel   => _t({'zh':'新聞', 'en':'News',   'ja':'ニュース'});
  String get homeNearbyTurkeyRice   => _t({'zh':'附近雞肉飯', 'en':'Nearby Turkey Rice', 'ja':'近くのチキンライス'});
  String get homeFeaturedTurkeyRice => _t({'zh':'精選雞肉飯', 'en':'Featured Turkey Rice','ja':'おすすめチキンライス'});

  // ── Map screen
  String get mapSearch          => _t({'zh':'搜尋名稱或地址', 'en':'Search name or address', 'ja':'名前または住所を検索'});
  String get mapLayerControl    => _t({'zh':'圖層控制', 'en':'Layer Control', 'ja':'レイヤー管理'});
  String get mapDetailFilter    => _t({'zh':'細節篩選', 'en':'Detail Filter', 'ja':'詳細フィルター'});
  String get mapShowAll         => _t({'zh':'全部顯示', 'en':'Show All', 'ja':'すべて表示'});
  String get mapHideAll         => _t({'zh':'全部隱藏', 'en':'Hide All', 'ja':'すべて非表示'});
  String get mapNoResult        => _t({'zh':'目前沒有符合條件的地點', 'en':'No matching places', 'ja':'条件に合う場所なし'});
  String get mapNoLayerHint     => _t({'zh':'請先在圖層控制中開啟景點類別。', 'en':'Enable a category in Layer Control first.', 'ja':'まずレイヤー管理でカテゴリを有効にしてください。'});
  String get mapFilterHintAll   => _t({'zh':'未選則顯示全部', 'en':'Empty = show all', 'ja':'未選択は全表示'});
  String get mapToiletType      => _t({'zh':'公廁類型', 'en':'Toilet Type',  'ja':'トイレタイプ'});
  String get mapParkingType     => _t({'zh':'停車場型式','en':'Parking Type', 'ja':'駐車場タイプ'});
  String get mapImageError      => _t({'zh':'圖片無法載入', 'en':'Image unavailable', 'ja':'画像を読み込めません'});

  // ── Explore screen
  String get exploreTitle       => _t({'zh':'探索嘉義', 'en':'Explore Chiayi', 'ja':'嘉義を探索'});
  String get exploreCatAll      => _t({'zh':'全部', 'en':'All',         'ja':'すべて'});
  String get exploreCatAttract  => _t({'zh':'景點', 'en':'Attractions', 'ja':'観光地'});
  String get exploreCatFood     => _t({'zh':'美食', 'en':'Food',        'ja':'グルメ'});
  String get exploreCatHotel    => _t({'zh':'住宿', 'en':'Stay',        'ja':'宿泊'});
  String get exploreFilterSort  => _t({'zh':'篩選與排序', 'en':'Filter & Sort', 'ja':'フィルター＆ソート'});
  String get exploreSortBy      => _t({'zh':'排序方式', 'en':'Sort by',       'ja':'並び替え'});
  String get exploreApplyFilter => _t({'zh':'套用篩選', 'en':'Apply Filter',  'ja':'フィルターを適用'});
  String get exploreAddTrip     => _t({'zh':'加入行程', 'en':'Add to Trip',   'ja':'旅程に追加'});
  String get exploreSortRating  => _t({'zh':'評分最高', 'en':'Top Rated',     'ja':'評価順'});
  String get exploreSortNearest => _t({'zh':'距離最近', 'en':'Nearest',       'ja':'近い順'});
  String get exploreSearchPrefix=> _t({'zh':'搜尋：', 'en':'Search: ', 'ja':'検索：'});
  String get exploreNoCatSpots  => _t({'zh':'此分類暫無景點', 'en':'No spots in this category', 'ja':'このカテゴリのスポットなし'});
  String get exploreTryOther    => _t({'zh':'試試其他分類或搜尋關鍵字', 'en':'Try another category or keyword', 'ja':'他のカテゴリやキーワードを試してください'});
  String exploreResultCount(int n) => langCode == 'en' ? '$n results'
      : langCode == 'ja' ? '$n 件' : '共 $n 個結果';
  String exploreNoSearchResult(String q) => langCode == 'en' ? 'No results for "$q"'
      : langCode == 'ja' ? '「$q」は見つかりません' : '找不到「$q」';
  String exploreCatLabel(String cat) {
    switch (cat) {
      case 'attraction': return exploreCatAttract;
      case 'restaurant': return exploreCatFood;
      case 'hotel':      return exploreCatHotel;
      case 'youbike':    return 'YouBike';
      default:           return cat;
    }
  }

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
  String get commTitle          => _t({'zh':'旅遊社群', 'en':'Community',    'ja':'コミュニティ'});
  String get commPopular        => _t({'zh':'熱門貼文', 'en':'Popular',      'ja':'人気投稿'});
  String get commFollowing      => _t({'zh':'追蹤中',   'en':'Following',    'ja':'フォロー中'});
  String get commNearby         => _t({'zh':'附近',     'en':'Nearby',       'ja':'近く'});
  String get commMyPosts        => _t({'zh':'我的貼文', 'en':'My Posts',     'ja':'マイ投稿'});
  String get commFollowingTab   => _t({'zh':'追蹤的貼文','en':'Following',   'ja':'フォロー'});
  String get commExploreAll     => _t({'zh':'探索全部', 'en':'Explore',      'ja':'探索'});
  String get commDeletePost     => _t({'zh':'刪除貼文', 'en':'Delete Post',  'ja':'投稿を削除'});
  String get commBudgetFilter   => _t({'zh':'預算篩選', 'en':'Budget Filter','ja':'予算フィルター'});
  String get commApplyFilter    => _t({'zh':'套用篩選', 'en':'Apply Filter', 'ja':'フィルターを適用'});
  String get commCreatePost     => _t({'zh':'發文',     'en':'Post',         'ja':'投稿'});
  String get commShareTrip      => _t({'zh':'分享行程', 'en':'Share Trip',   'ja':'旅程をシェア'});
  String get commNoDiscussion   => _t({'zh':'還沒有討論', 'en':'No discussions yet', 'ja':'まだ議論なし'});
  String get commCommentSection => _t({'zh':'留言區',   'en':'Comments',     'ja':'コメント'});
  String get commWeeklyFeature  => _t({'zh':'本週精選', 'en':'Weekly Picks', 'ja':'今週のピック'});
  String get commComment        => _t({'zh':'留言',     'en':'Comment',      'ja':'コメント'});
  String get commAddedFav       => _t({'zh':'已加入收藏','en':'Saved',       'ja':'保存済み'});
  String get commNoFollowing    => _t({'zh':'還沒有追蹤任何人', 'en':'Not following anyone', 'ja':'フォロー中なし'});
  String get commExploreComm    => _t({'zh':'探索社群', 'en':'Explore Community', 'ja':'コミュニティを探索'});
  String get commNoFollowPosts  => _t({'zh':'追蹤的人還沒有發文', 'en':'Following hasn\'t posted yet', 'ja':'フォロー中はまだ投稿なし'});
  String get commNoPost         => _t({'zh':'還沒有發布貼文', 'en':'No posts yet', 'ja':'まだ投稿なし'});
  String get commPublishTrip    => _t({'zh':'發布行程', 'en':'Share Trip',   'ja':'旅程を投稿'});
  String get commApplyTrip      => _t({'zh':'套用行程', 'en':'Apply to Trip','ja':'旅程に適用'});
  String get commTripIntro      => _t({'zh':'行程介紹', 'en':'Trip Overview','ja':'旅程概要'});
  String get commTripSpots      => _t({'zh':'行程景點', 'en':'Trip Spots',   'ja':'旅程スポット'});
  String get commSpots          => _t({'zh':'景點',     'en':'Spots',        'ja':'スポット'});
  String get commReportComment  => _t({'zh':'舉報留言', 'en':'Report Comment','ja':'コメントを報告'});
  String get commNoTripYet      => _t({'zh':'你還沒有建立任何行程', 'en':'No trips yet. Create one first.', 'ja':'まだ旅程がありません'});
  String get commSelectTrip     => _t({'zh':'選擇行程', 'en':'Select Trip',  'ja':'旅程を選択'});
  String get commFillRequired   => _t({'zh':'請填寫標題和內容', 'en':'Please fill in title and content', 'ja':'タイトルと内容を入力してください'});
  String get commTripShareNoTrip=> _t({'zh':'行程分享請先選擇一個行程', 'en':'Select a trip to share', 'ja':'シェアする旅程を選択してください'});
  String get commPublishPost    => _t({'zh':'發布貼文', 'en':'Create Post',  'ja':'投稿を作成'});
  String get commLoginRequired  => _t({'zh':'請先登入才能套用行程', 'en':'Sign in to apply trip', 'ja':'旅程を適用するにはログインしてください'});
  String get commNoSpotInfo     => _t({'zh':'此貼文沒有景點資訊', 'en':'No spot info in this post', 'ja':'このポストにスポット情報がありません'});
  String get commApplyToTrip    => _t({'zh':'套用到哪個行程？', 'en':'Apply to which trip?', 'ja':'どの旅程に適用しますか？'});
  String commAddSpotsDesc(int n, List<String> names) {
    final preview = names.take(3).join(langCode == 'ja' ? '・' : '、');
    final suffix = names.length > 3 ? '…' : '';
    return langCode == 'en'
        ? 'Adding $n spot${n > 1 ? 's' : ''}: $preview$suffix'
        : langCode == 'ja'
            ? '$n スポットを追加：$preview$suffix'
            : '將加入 $n 個景點：$preview$suffix';
  }
  String commApplySuccess(int n, String tripTitle) => langCode == 'en'
      ? 'Added $n spot${n > 1 ? 's' : ''} to "$tripTitle"'
      : langCode == 'ja'
          ? '$n スポットを「$tripTitle」に追加しました'
          : '已將 $n 個景點加入「$tripTitle」';
  String get commApplyFailPrefix => _t({'zh':'套用失敗：', 'en':'Apply failed: ', 'ja':'適用失敗：'});
  String commTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (langCode == 'en') {
      if (diff.inMinutes < 1)  return 'just now';
      if (diff.inHours   < 1)  return '${diff.inMinutes}m ago';
      if (diff.inDays    < 1)  return '${diff.inHours}h ago';
      if (diff.inDays    < 7)  return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}';
    }
    if (langCode == 'ja') {
      if (diff.inMinutes < 1)  return 'たった今';
      if (diff.inHours   < 1)  return '${diff.inMinutes}分前';
      if (diff.inDays    < 1)  return '${diff.inHours}時間前';
      if (diff.inDays    < 7)  return '${diff.inDays}日前';
      return '${dt.month}/${dt.day}';
    }
    if (diff.inMinutes < 1)  return '剛剛';
    if (diff.inHours   < 1)  return '${diff.inMinutes} 分鐘前';
    if (diff.inDays    < 1)  return '${diff.inHours} 小時前';
    if (diff.inDays    < 7)  return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }

  // ── Stamp screen
  String get stampTitle         => _t({'zh':'集章成就',    'en':'Stamps',        'ja':'スタンプ'});
  String get stampSpots         => _t({'zh':'景點印章',    'en':'Spot Stamps',   'ja':'スポット印章'});
  String get stampAchievements  => _t({'zh':'成就徽章',    'en':'Achievements',  'ja':'実績バッジ'});
  String get stampMiniMap       => _t({'zh':'小地圖',      'en':'Mini Map',      'ja':'ミニマップ'});

  // ── Expense screen
  String get expTitle           => _t({'zh':'旅遊分帳',  'en':'Trip Expense',  'ja':'旅費精算'});

  // ── Profile screen
  String get profileAboutMe      => _t({'zh':'關於我',   'en':'About Me',         'ja':'プロフィール'});
  String get profileGuest        => _t({'zh':'訪客',     'en':'Guest',            'ja':'ゲスト'});
  String get profileLoginPrompt  => _t({'zh':'登入以儲存你的旅行足跡', 'en':'Sign in to save your travels', 'ja':'旅の記録を保存するにはログイン'});
  String get profileTripCount    => _t({'zh':'旅行次數', 'en':'Trips',            'ja':'旅行回数'});
  String get profileSavedSpots   => _t({'zh':'收藏景點', 'en':'Saved Spots',      'ja':'お気に入り'});
  String get profileStampCount   => _t({'zh':'集章數',   'en':'Stamps',           'ja':'スタンプ数'});
  String get profileMyCollection => _t({'zh':'收藏貼文', 'en':'Saved Posts',      'ja':'保存済み投稿'});
  String get profileCoupons      => _t({'zh':'優惠券',   'en':'Coupons',          'ja':'クーポン'});
  String get profileStats        => _t({'zh':'旅行統計', 'en':'Travel Stats',     'ja':'旅行統計'});
  String get profileCheckIn      => _t({'zh':'打卡景點', 'en':'Check-ins',        'ja':'チェックイン'});
  String get profileStreak       => _t({'zh':'連續打卡', 'en':'Streak',           'ja':'連続チェックイン'});
  String get profileTripStat     => _t({'zh':'行程數',   'en':'Trips',            'ja':'旅程数'});
  String get profileSavedCount   => _t({'zh':'收藏數',   'en':'Saved',            'ja':'保存数'});
  String get profileMyData       => _t({'zh':'我的資料', 'en':'My Data',          'ja':'マイデータ'});
  String get profilePhotos       => _t({'zh':'打卡照片', 'en':'Photos',           'ja':'チェックイン写真'});
  String get profileAchievements => _t({'zh':'成就徽章', 'en':'Achievements',     'ja':'実績バッジ'});
  String get profileFootprint    => _t({'zh':'我的足跡', 'en':'Footprint',        'ja':'足跡'});
  String get profileSavedSpotsNav=> _t({'zh':'收藏景點', 'en':'Saved Spots',      'ja':'お気に入り'});
  String get profileShareTitle   => _t({'zh':'分享旅行，賺取回饋！', 'en':'Share & Earn!',           'ja':'旅をシェアして特典ゲット！'});
  String get profileShareDesc    => _t({'zh':'邀請好友註冊，雙方都能獲得優惠獎勵！', 'en':'Invite friends, earn rewards!', 'ja':'友達を招待して特典をゲット！'});
  String get profileInvite       => _t({'zh':'立即邀請', 'en':'Invite Now',       'ja':'今すぐ招待'});
  String get profilePrivacyPolicy=> _t({'zh':'隱私政策', 'en':'Privacy Policy',   'ja':'プライバシーポリシー'});
  String get profileFAQ          => _t({'zh':'常見問題', 'en':'FAQ',              'ja':'よくある質問'});
  String get profileAboutUs      => _t({'zh':'關於我們', 'en':'About Us',         'ja':'私たちについて'});
  String get profileEditName     => _t({'zh':'修改名稱', 'en':'Edit Name',        'ja':'名前を編集'});
  String get profileNameHint     => _t({'zh':'輸入新的暱稱', 'en':'Enter nickname','ja':'ニックネームを入力'});
  String get profileNameUpdated  => _t({'zh':'名稱已更新', 'en':'Name updated',   'ja':'名前を更新しました'});
  String get profileSelectAlbum  => _t({'zh':'從相簿選取', 'en':'Select from Album','ja':'アルバムから選択'});
  String get profileTakePhoto    => _t({'zh':'拍照',     'en':'Take Photo',        'ja':'写真を撮る'});
  String get profileConfirmLogout=> _t({'zh':'確認登出', 'en':'Confirm Sign Out', 'ja':'ログアウト確認'});
  String get profileMyProfile    => _t({'zh':'我的',     'en':'Profile',          'ja':'マイページ'});
  String profileStampMotivation(int stamps) {
    if (langCode == 'en') {
      if (stamps >= 10) return 'You\'ve checked in $stamps spots — a seasoned explorer! 🌟';
      if (stamps >= 5)  return 'Keep going! ${10 - stamps} more to reach 10 🌟';
      return 'Start your first check-in and explore Chiayi! 🗺️';
    }
    if (langCode == 'ja') {
      if (stamps >= 10) return '$stamps スポットをチェックイン！ベテラン探索者！🌟';
      if (stamps >= 5)  return 'あと ${10 - stamps} スポットで 10 達成！✨';
      return '最初のチェックインをして嘉義を探索しよう！🗺️';
    }
    if (stamps >= 10) return '你已打卡 $stamps 個景點，是資深探索者！🌟';
    if (stamps >= 5)  return '繼續探索，還有 ${10 - stamps} 個景點等你！✨';
    return '開始你的第一次打卡，探索嘉義的美！🗺️';
  }

  // ── Login page
  String get loginWelcomeBack    => _t({'zh':'歡迎回來！',       'en':'Welcome back!',        'ja':'おかえりなさい！'});
  String get loginSignInSubtitle => _t({'zh':'登入帳號繼續探索嘉義', 'en':'Sign in to explore Chiayi', 'ja':'ログインして嘉義を探索'});
  String get loginEmail          => _t({'zh':'電子郵件',         'en':'Email',                'ja':'メールアドレス'});
  String get loginPassword       => _t({'zh':'密碼',             'en':'Password',             'ja':'パスワード'});
  String get loginPasswordMin    => _t({'zh':'密碼（至少 6 位）', 'en':'Password (min. 6 chars)', 'ja':'パスワード（6文字以上）'});
  String get loginConfirmPw      => _t({'zh':'確認密碼',         'en':'Confirm Password',     'ja':'パスワード確認'});
  String get loginForgotPw       => _t({'zh':'忘記密碼？',       'en':'Forgot password?',     'ja':'パスワードを忘れましたか？'});
  String get loginNickname       => _t({'zh':'暱稱',             'en':'Nickname',             'ja':'ニックネーム'});
  String get loginBtn            => _t({'zh':'登入 ✦',           'en':'Sign In ✦',            'ja':'ログイン ✦'});
  String get loginRegisterTitle  => _t({'zh':'建立帳號',         'en':'Create Account',       'ja':'アカウント作成'});
  String get loginRegisterSub    => _t({'zh':'加入探索諸羅，嘉義等你', 'en':'Join Explore Chiayi', 'ja':'嘉義を一緒に探索しよう'});
  String get loginCreateBtn      => _t({'zh':'建立帳號 ✦',       'en':'Create Account ✦',     'ja':'アカウントを作成 ✦'});
  String get loginResetTitle     => _t({'zh':'重設密碼',         'en':'Reset Password',       'ja':'パスワードリセット'});
  String get loginResetDesc      => _t({'zh':'請輸入你的電子郵件，\n我們將寄送密碼重設連結。', 'en':'Enter your email and we\'ll send a reset link.', 'ja':'メールを入力してリセットリンクを送信します。'});
  String get loginSendBtn        => _t({'zh':'發送',             'en':'Send',                 'ja':'送信'});
  String get loginResetSent      => _t({'zh':'密碼重設郵件已寄出，請檢查收件匣', 'en':'Reset email sent, check inbox', 'ja':'リセットメールを送信しました'});
  String get loginTerms          => _t({'zh':'登入即代表同意 JoyGo ', 'en':'By signing in you agree to JoyGo ', 'ja':'ログインすることでJoyGoの'});
  String get loginTermsLink      => _t({'zh':'服務條款與隱私政策', 'en':'Terms & Privacy Policy', 'ja':'利用規約とプライバシーポリシーに同意します'});
  String get loginBrandSubtitle  => _t({'zh':'嘉義旅遊夥伴，陪你玩遍嘉義！', 'en':'Your Chiayi travel companion!', 'ja':'嘉義旅行のパートナー！'});
  String get loginOrDivider      => _t({'zh':'或', 'en':'or', 'ja':'または'});
  String loginComingSoon(String platform) => langCode == 'en'
      ? '$platform Sign In — Coming Soon'
      : langCode == 'ja' ? '$platformログイン — 近日公開' : '$platform 登入 — 即將推出';
  String loginWithPlatform(String platform) => langCode == 'en'
      ? 'Sign in with $platform'
      : langCode == 'ja' ? '$platformでログイン' : '使用 $platform 帳號登入';
  String loginWelcomeNew(String nickname) => langCode == 'en'
      ? 'Welcome to Explore Chiayi, $nickname!'
      : langCode == 'ja' ? '嘉義を探索へようこそ、$nickname！'
      : '歡迎加入探索諸羅，$nickname！';

  // ── Profile member card
  String get memberCardGuest     => _t({'zh':'登入享探索旅人特權', 'en':'Sign in for traveler perks', 'ja':'ログインして旅人特典を獲得'});
  String get memberCardGuestDesc => _t({'zh':'行程管理 · 集章成就 · 旅行分享', 'en':'Trip Plan · Stamps · Sharing', 'ja':'旅程管理・スタンプ・旅行シェア'});
  String get profileNoSavedPosts => _t({'zh':'還沒有收藏的貼文', 'en':'No saved posts yet',  'ja':'保存した投稿なし'});
  String get profileNoSavedSpotsTxt => _t({'zh':'還沒有收藏景點', 'en':'No saved spots yet', 'ja':'保存済みスポットなし'});
  String get profileLoginRequired=> _t({'zh':'請先登入', 'en':'Please sign in', 'ja':'ログインしてください'});
  String get profileCouponsTitle => _t({'zh':'優惠券', 'en':'Coupons',   'ja':'クーポン'});
  String get profileCouponLoginNeeded => _t({'zh':'登入後即可領取優惠券！', 'en':'Sign in to claim coupons!', 'ja':'クーポンを獲得するにはログイン！'});

  // ── Trip screen
  String get tripLoginTitle      => _t({'zh':'登入後開始規劃旅程', 'en':'Sign in to start planning', 'ja':'ログインして旅程を計画'});
  String get tripLoginDesc       => _t({'zh':'建立嘉義行程、收藏景點，\n讓諸羅精靈幫你安排完美旅程！', 'en':'Create trips, save spots,\nlet our AI plan the perfect journey!', 'ja':'旅程を作成し、スポットを保存しよう！'});
  String get tripLoginBtn        => _t({'zh':'前往登入 / 註冊', 'en':'Sign In / Register', 'ja':'ログイン / 登録'});
  String get tripGuestHint       => _t({'zh':'訪客也可以先收藏景點，登入後自動同步', 'en':'Guests can save spots, auto-sync after login', 'ja':'ゲストもスポットを保存できます'});
  String get tripNoTrip          => _t({'zh':'還沒有行程', 'en':'No trips yet', 'ja':'旅程なし'});
  String get tripNoTripBody      => _t({'zh':'嘉義在等你！點右上角 + 建立第一個旅程', 'en':'Chiayi awaits! Tap + to create your first trip', 'ja':'嘉義が待っています！+ で最初の旅程を作成'});
  String get tripCreateBtn       => _t({'zh':'建立行程', 'en':'Create Trip', 'ja':'旅程を作成'});
  String get tripNoSaved         => _t({'zh':'還沒有收藏景點', 'en':'No saved spots yet', 'ja':'お気に入りスポットなし'});
  String get tripNoCandidates    => _t({'zh':'還沒有候選景點', 'en':'No candidates yet', 'ja':'候補スポットなし'});
  String get tripPlanningStatus  => _t({'zh':'規劃中', 'en':'Planning', 'ja':'計画中'});
  String get tripCompletedStatus => _t({'zh':'已完成', 'en':'Completed', 'ja':'完了'});
  String get tripNextTripLabel   => _t({'zh':'下一趟旅程', 'en':'Next Trip', 'ja':'次の旅程'});
  String get tripCountdownUnit   => _t({'zh':'天', 'en':'d', 'ja':'日'});
  String get tripCountdownLabel  => _t({'zh':'倒數', 'en':'In', 'ja':'あと'});
  String get tripView            => _t({'zh':'查看', 'en':'View', 'ja':'表示'});
  String get tripViewEdit        => _t({'zh':'查看 / 編輯', 'en':'View / Edit', 'ja':'表示 / 編集'});
  String get tripAddCandidates   => _t({'zh':'＋ 加入景點到候選清單', 'en':'+ Add spots to candidates', 'ja':'+ スポットを候補に追加'});
  String get tripRestoreProgress => _t({'zh':'恢復進行中', 'en':'Restore to In Progress', 'ja':'進行中に戻す'});
  String get tripMarkDone        => _t({'zh':'標記完成', 'en':'Mark as Complete', 'ja':'完了にする'});
  String get tripDeleteTrip      => _t({'zh':'刪除行程', 'en':'Delete Trip', 'ja':'旅程を削除'});
  String get tripAISchedule      => _t({'zh':'AI 排程', 'en':'AI Schedule', 'ja':'AIスケジュール'});
  String tripNoSpotDay(bool filtered) => filtered
      ? _t({'zh':'這天還沒有景點', 'en':'No spots for this day', 'ja':'この日のスポットなし'})
      : _t({'zh':'還沒有景點', 'en':'No spots yet', 'ja':'スポットなし'});
  String tripDaysSpots(int days, int spots) => langCode == 'en'
      ? '$days day${days > 1 ? 's' : ''} · $spots spot${spots > 1 ? 's' : ''}'
      : langCode == 'ja' ? '$days日 · ${spots}スポット' : '${days}天 · ${spots}個景點';
  String get tripDeleteConfirm   => _t({'zh':'確定要刪除這個行程嗎？此操作無法復原。', 'en':'Delete this trip? This cannot be undone.', 'ja':'この旅程を削除しますか？'});
  String tripDeleteTitle(String title) => langCode == 'en' ? 'Delete "$title"?' : langCode == 'ja' ? '「$title」を削除しますか？' : '確定要刪除「$title」嗎？此操作無法復原。';
  String tripMarkedComplete(String title) => langCode == 'en' ? '"$title" marked as complete ✓' : langCode == 'ja' ? '「$title」を完了にしました ✓' : '「$title」已標記為完成 ✓';
  String tripRestoredInProgress(String title) => langCode == 'en' ? '"$title" restored to In Progress' : langCode == 'ja' ? '「$title」を進行中に戻しました' : '「$title」已恢復為進行中';
  String get tripStatPlanning    => _t({'zh':'規劃中', 'en':'Planning', 'ja':'計画中'});
  String get tripStatCompleted   => _t({'zh':'已完成', 'en':'Done',     'ja':'完了'});
  String get tripSyncMsg         => _t({'zh':'收藏景點已同步', 'en':'Saved spots synced', 'ja':'保存済みスポットを同期しました'});
  String get tripAlreadyInList   => _t({'zh':'已在候選清單中', 'en':'Already in candidates', 'ja':'既に候補リストにあります'});
  String get tripAddedToList     => _t({'zh':'已加入候選清單 ✓', 'en':'Added to candidates ✓', 'ja':'候補リストに追加 ✓'});

  // ── Community extra
  String get commNoTripsShared   => _t({'zh':'還沒有行程分享', 'en':'No trips shared yet', 'ja':'旅程のシェアなし'});
  String get commShareTripHint   => _t({'zh':'點下方按鈕分享你的行程！', 'en':'Tap below to share your trip!', 'ja':'下のボタンで旅程をシェア！'});
  String get commNoDiscussionHint=> _t({'zh':'點下方按鈕發起第一個討論！', 'en':'Tap below to start a discussion!', 'ja':'下のボタンで最初のディスカッションを始めよう！'});
  String get commDiscussionLabel => _t({'zh':'討論', 'en':'Discussion', 'ja':'ディスカッション'});
  String get commWelcomeOpinion  => _t({'zh':'歡迎分享你的看法與建議，讓更多旅人參考！', 'en':'Share your thoughts to help other travelers!', 'ja':'他の旅行者のために感想や提案をシェアしよう！'});
  String get commLike            => _t({'zh':'留言', 'en':'Comment', 'ja':'コメント'});
  String get commShareAction     => _t({'zh':'分享', 'en':'Share', 'ja':'シェア'});
  String get commNoFollowingPeople => _t({'zh':'還沒有追蹤任何人', 'en':'Not following anyone yet', 'ja':'まだフォローしていません'});
  String get commGoExplore       => _t({'zh':'去探索頁面找找志同道合的旅伴吧！', 'en':'Go explore to find fellow travelers!', 'ja':'探索して仲間の旅行者を見つけよう！'});
  String get commFollowingNoPosts=> _t({'zh':'追蹤的人還沒有發文', 'en':'Following hasn\'t posted yet', 'ja':'フォロー中はまだ投稿なし'});
  String get commFollowingWait   => _t({'zh':'等等看他們分享新旅程！', 'en':'Wait for them to share a new trip!', 'ja':'新しい旅程のシェアをお待ちください！'});
  String get commNoMyPost        => _t({'zh':'還沒有發布貼文', 'en':'No posts yet', 'ja':'まだ投稿なし'});
  String get commShareEncourage  => _t({'zh':'分享你的嘉義旅行，讓更多人看見！', 'en':'Share your Chiayi trip for others to see!', 'ja':'嘉義の旅行をシェアして、みんなに見せよう！'});
  String get commSortLatest      => _t({'zh':'最新', 'en':'Latest',  'ja':'新着'});
  String get commSortHot         => _t({'zh':'熱門', 'en':'Popular', 'ja':'人気'});
  String get commNoComment       => _t({'zh':'還沒有留言，來搶頭香！', 'en':'Be the first to comment!', 'ja':'最初のコメントをしよう！'});
  String get commNoTripInCreate  => _t({'zh':'還沒有行程，請先建立行程', 'en':'No trips yet, create one first', 'ja':'旅程がありません。まず作成してください'});
  String get commLoginToPost     => _t({'zh':'請先登入才能發布貼文', 'en':'Sign in to post', 'ja':'投稿するにはログインしてください'});
  String get commReplyTo         => _t({'zh':'回覆 @', 'en':'Reply to @', 'ja':'@に返信 '});
  String get commReported        => _t({'zh':'已送出舉報，感謝你的回報', 'en':'Report submitted, thank you!', 'ja':'報告を送信しました。ありがとうございます！'});
  String get commReportReason    => _t({'zh':'請選擇舉報原因：', 'en':'Select a reason:', 'ja':'理由を選択してください：'});
  String commSearchNoResult(String q) => langCode == 'en' ? 'No trips found for "$q"' : langCode == 'ja' ? '「$q」に関する旅程が見つかりません' : '找不到「$q」相關行程';
  String get commNoTripsYetExplore => _t({'zh':'還沒有行程分享', 'en':'No trips shared yet', 'ja':'旅程のシェアなし'});
  String get commSpotsLabel      => _t({'zh':'景點', 'en':'Spots', 'ja':'スポット'});
  String get commTripIntroLabel  => _t({'zh':'行程介紹', 'en':'Trip Overview', 'ja':'旅程概要'});
  String get commTripSpotsLabel  => _t({'zh':'行程景點', 'en':'Trip Spots', 'ja':'旅程スポット'});
  String get commApplyTripBtn    => _t({'zh':'套用行程', 'en':'Apply to Trip', 'ja':'旅程に適用'});
  String get commCancelTxt       => _t({'zh':'取消', 'en':'Cancel', 'ja':'キャンセル'});
  String get commDeleteTxt       => _t({'zh':'刪除', 'en':'Delete', 'ja':'削除'});
  String get commDeleteConfirm   => _t({'zh':'確定要刪除這篇貼文嗎？此操作無法復原。', 'en':'Delete this post? This cannot be undone.', 'ja':'この投稿を削除しますか？元に戻せません。'});
  String get commCommentFail     => _t({'zh':'留言失敗：', 'en':'Comment failed: ', 'ja':'コメント失敗：'});
  String get commSharePostInfo   => _t({'zh':'這是社群分享行程，可截圖收藏', 'en':'This is a shared trip. Screenshot to save!', 'ja':'これはシェアされた旅程です。スクリーンショットで保存！'});

  // ── Map screen extra
  String get mapNoLocation       => _t({'zh':'無法取得位置，請確認已開啟定位權限', 'en':'Unable to get location. Check location permission.', 'ja':'位置情報を取得できません。権限を確認してください。'});
  String get mapNoExtraInfo      => _t({'zh':'（無額外資訊）', 'en':'(No additional info)', 'ja':'（追加情報なし）'});
  String get mapViewOnMap        => _t({'zh':'查看地圖', 'en':'View on Map', 'ja':'地図で見る'});

  // ── Settings preview demo labels
  String get previewButton          => _t({'zh':'按鈕',   'en':'Button',   'ja':'ボタン'});
  String get previewSecondary       => _t({'zh':'次要',   'en':'Secondary','ja':'セカンダリ'});
  List<String> get previewNavLabels => [navHome, navMap, navTrip, stampTitle.split(' ').first];

  // ── Settings screen
  String get settingsPreview        => _t({'zh':'預覽效果',   'en':'Preview',           'ja':'プレビュー'});
  String get settingsNotifications  => _t({'zh':'通知設定',   'en':'Notifications',     'ja':'通知設定'});
  String get settingsDevTools       => _t({'zh':'開發者工具', 'en':'Developer Tools',   'ja':'開発者ツール'});
  String get settingsFirebaseSeed   => _t({'zh':'Firebase 測試資料', 'en':'Firebase Test Data', 'ja':'Firebaseテストデータ'});
  String get settingsFirebaseSeedSub=> _t({'zh':'上傳假貼文測試按讚/收藏', 'en':'Upload test posts for likes/saves', 'ja':'テスト投稿をアップロード'});
  String get settingsNotifPush      => _t({'zh':'推播通知', 'en':'Push Notifications', 'ja':'プッシュ通知'});
  String get settingsNotifPushSub   => _t({'zh':'接收 App 所有通知', 'en':'Receive all app notifications', 'ja':'すべての通知を受信'});
  String get settingsNotifNews      => _t({'zh':'最新消息', 'en':'Latest News',  'ja':'最新ニュース'});
  String get settingsNotifNewsSub   => _t({'zh':'嘉義市政府新聞與活動', 'en':'Gov news & events', 'ja':'行政ニュース・イベント'});
  String get settingsNotifComm      => _t({'zh':'社群互動', 'en':'Community',    'ja':'コミュニティ'});
  String get settingsNotifCommSub   => _t({'zh':'按讚、留言、追蹤通知', 'en':'Likes, comments, follows', 'ja':'いいね・コメント・フォロー'});
  String get settingsNotifTrip      => _t({'zh':'行程提醒', 'en':'Trip Reminders','ja':'旅程リマインダー'});
  String get settingsNotifTripSub   => _t({'zh':'出發前一天自動提醒', 'en':'Auto-remind day before trip', 'ja':'出発1日前に自動リマインド'});

  // ── News screen
  String get newsCannotOpen   => _t({'zh':'無法開啟連結',   'en':'Cannot open link',  'ja':'リンクを開けません'});
  String get newsOpenOriginal => _t({'zh':'開啟原始連結',   'en':'Open Link',         'ja':'リンクを開く'});
  String get newsCopied       => _t({'zh':'已複製連結',     'en':'Link copied',       'ja':'リンクをコピーしました'});
  String get newsNoItems      => _t({'zh':'目前無相關消息',   'en':'No news available',              'ja':'ニュースなし'});
  String get newsOpenLink     => _t({'zh':'開啟連結',         'en':'Open Link',                      'ja':'リンクを開く'});
  String get newsCopyLink     => _t({'zh':'複製',             'en':'Copy',                           'ja':'コピー'});
  String get newsEventDetail  => _t({'zh':'詳細活動資訊請點擊下方連結查看。', 'en':'See full event details at the link below.', 'ja':'詳細はリンクからご確認ください。'});
  String get newsArticleDetail=> _t({'zh':'詳細新聞內容請點擊下方連結查看。', 'en':'See full article at the link below.',        'ja':'全文はリンクからご確認ください。'});
  String get newsTabAll       => _t({'zh':'全部', 'en':'All',    'ja':'すべて'});
  String get newsTabEvent     => _t({'zh':'活動', 'en':'Events', 'ja':'イベント'});
  String get newsTabNews      => _t({'zh':'新聞', 'en':'News',   'ja':'ニュース'});

  // ── Transport screen
  List<String> get transportTabNames => langCode == 'en'
      ? ['Bus', 'YouBike', 'Train', 'Alishan', 'HSR']
      : langCode == 'ja'
          ? ['バス', 'YouBike', '台鉄', '阿里山', '高鉄']
          : ['公車', 'YouBike', '台鐵', '阿里山', '高鐵'];
  List<String> get transportTabTitles => langCode == 'en'
      ? ['City Bus', 'YouBike Stations', 'TRA Schedule', 'Alishan Forest Railway', 'HSR Schedule']
      : langCode == 'ja'
          ? ['路線バス', 'YouBike ステーション', '台鉄時刻表', '阿里山森林鉄道', '高鉄時刻表']
          : ['公車動態查詢', 'YouBike 租借站', '台鐵時刻查詢', '阿里山森林鐵路', '高鐵時刻查詢'];
  String get transPopularSearch   => _t({'zh':'熱門搜尋',   'en':'Popular Searches', 'ja':'人気の検索'});
  String get transMyRoutes        => _t({'zh':'我的路線',   'en':'My Routes',        'ja':'マイルート'});
  String get transSaveRouteHint   => _t({'zh':'點搜尋結果右側書籤即可收藏路線', 'en':'Tap the bookmark to save a route', 'ja':'ブックマークでルートを保存'});
  String get transMapBtn          => _t({'zh':'地圖',       'en':'Map',              'ja':'地図'});
  String get transNearbyRoutes    => _t({'zh':'附近路線',   'en':'Nearby Routes',    'ja':'近くの路線'});
  String get transRecenter        => _t({'zh':'重新定位',   'en':'Recenter',         'ja':'再センタリング'});
  String get transGettingLocation => _t({'zh':'正在取得您的位置…', 'en':'Getting location…', 'ja':'位置情報取得中…'});
  String get transLocating        => _t({'zh':'定位中…',   'en':'Locating…',        'ja':'定位中…'});
  String get transEnableLocation  => _t({'zh':'點此開啟定位','en':'Enable location',  'ja':'位置情報を有効にする'});
  String get transNoBikeData      => _t({'zh':'目前沒有車位資料', 'en':'No dock data', 'ja':'ドック情報なし'});
  String get transBikeAvail       => _t({'zh':'可借', 'en':'Avail.', 'ja':'貸出可'});
  String get transBikeUnit        => _t({'zh':'輛',  'en':'',        'ja':'台'});
  String get transBikeReturn      => _t({'zh':'可還', 'en':'Return',  'ja':'返却'});
  String get transDockUnit        => _t({'zh':'格',  'en':'',        'ja':'台'});
  String get transBackToFirst     => _t({'zh':'點此回到第一頁', 'en':'Back to page 1', 'ja':'最初のページへ'});
  String get transSwipeLeft       => _t({'zh':'左滑翻下一頁',  'en':'Swipe left for next', 'ja':'左スワイプで次へ'});
  String get transDiffStation     => _t({'zh':'請選擇不同的起迄站', 'en':'Select different stations', 'ja':'異なる駅を選択してください'});
  String get transLastUpdated     => _t({'zh':'最後更新', 'en':'Updated', 'ja':'最終更新'});
  String get transFromStation     => _t({'zh':'出發站', 'en':'From', 'ja':'出発駅'});
  String get transToStation       => _t({'zh':'抵達站', 'en':'To',   'ja':'到着駅'});
  String get transNoArrivalInfo   => _t({'zh':'暫無即時進站資訊', 'en':'No live arrival info', 'ja':'リアルタイム情報なし'});
  String get transArriving        => _t({'zh':'即將進站', 'en':'Arriving soon', 'ja':'まもなく到着'});
  String get transAlertSet        => _t({'zh':'已設定到站提醒', 'en':'Arrival alert set', 'ja':'到着アラート設定済み'});
  String get transNoBusPos        => _t({'zh':'暫無公車位置資料', 'en':'No bus location data', 'ja':'バス位置情報なし'});
  String get transNoStopData      => _t({'zh':'無法取得停靠站資料', 'en':'Failed to get stop data', 'ja':'停車駅情報取得失敗'});
  String get transNoLiveInfo      => _t({'zh':'無法取得即時資訊', 'en':'Live info unavailable', 'ja':'リアルタイム情報取得不可'});
  String get transTouristTrain    => _t({'zh':'觀光列車', 'en':'Tourist Train', 'ja':'観光列車'});
  String get transNearby          => _t({'zh':'附近：', 'en':'Nearby: ', 'ja':'近く：'});
  String get transSearchStop      => _t({'zh':'搜尋路牌', 'en':'Search stop', 'ja':'停留所を検索'});
  String get transArrivingSoon    => _t({'zh':'即將到站', 'en':'Arriving soon', 'ja':'まもなく到着'});
  String get transBusCity         => _t({'zh':'嘉義市', 'en':'Chiayi City', 'ja':'嘉義市'});
  String get transBusCounty       => _t({'zh':'嘉義縣', 'en':'Chiayi County', 'ja':'嘉義県'});
  String transMinAgo(int n)   => langCode == 'en' ? '${n}min ago' : langCode == 'ja' ? '${n}分前' : '$n分鐘前';
  String transAlertDetail(String stop, int mins) => langCode == 'en'
      ? 'Alert set: $stop (in ~$mins min)'
      : langCode == 'ja' ? 'アラート設定：$stop（約${mins}分後）'
      : '已設定到站提醒：$stop（約 $mins 分鐘後）';
  String get transChiayiTo        => _t({'zh':'嘉義', 'en':'Chiayi', 'ja':'嘉義'});

  // ── Weather screen
  String get weatherTitle         => _t({'zh':'嘉義天氣', 'en':'Chiayi Weather', 'ja':'嘉義の天気'});
  String get weatherLoadFail      => _t({'zh':'無法取得天氣資料，請稍後重試', 'en':'Unable to load weather data', 'ja':'天気データを取得できません'});
  String get weatherRefresh       => _t({'zh':'重新整理', 'en':'Refresh', 'ja':'更新'});
  String get weather7Day          => _t({'zh':'7 天天氣預報', 'en':'7-Day Forecast', 'ja':'7日間予報'});

  // ── Notifications screen
  String get notifCenter          => _t({'zh':'通知中心', 'en':'Notifications', 'ja':'通知センター'});
  String notifUnread(int n)       => langCode == 'en' ? '$n unread' : langCode == 'ja' ? '$n 件未読' : '$n 則未讀';
  String get notifMarkAllRead     => _t({'zh':'全部已讀', 'en':'Mark all read', 'ja':'すべて既読'});

  // ── Common widgets (SpotRatingSection)
  String get widgetSpotIntro      => _t({'zh':'簡介',   'en':'Overview',   'ja':'概要'});
  String get widgetMyRating       => _t({'zh':'我的評分', 'en':'My Rating',  'ja':'マイ評価'});
  String get widgetClear          => _t({'zh':'清除',     'en':'Clear',      'ja':'クリア'});
  String get widgetNotes          => _t({'zh':'備註',     'en':'Notes',      'ja':'メモ'});
  String get widgetNoteHint       => _t({'zh':'記下你的感想、提醒或重要資訊…', 'en':'Jot down thoughts, tips, or important info…', 'ja':'感想やメモを記録…'});
  String get widgetSaveRating     => _t({'zh':'儲存評分與備註', 'en':'Save Rating & Notes', 'ja':'評価とメモを保存'});
  String get widgetViewDetails    => _t({'zh':'查看詳情', 'en':'View Details', 'ja':'詳細を見る'});

  // ── Auth Drawer
  String get drawerSignInUnlock   => _t({'zh':'登入後解鎖功能', 'en':'Sign in to unlock features', 'ja':'ログインして機能を解放'});
  String get drawerSignInRegister => _t({'zh':'登入 / 註冊',   'en':'Sign In / Register',         'ja':'ログイン / 登録'});
  String get drawerNotifSettings  => _t({'zh':'通知設定',     'en':'Notification Settings',       'ja':'通知設定'});
  String get drawerEventReminders => _t({'zh':'活動提醒',     'en':'Event Reminders',             'ja':'イベントリマインダー'});
  String get drawerCommNotif      => _t({'zh':'社群通知',     'en':'Community Notifications',     'ja':'コミュニティ通知'});
  String get drawerMarketing      => _t({'zh':'行銷推播',     'en':'Marketing Push',              'ja':'マーケティング通知'});
  String get drawerProfileUpdated => _t({'zh':'個人資料已更新 ✓', 'en':'Profile updated ✓',      'ja':'プロフィール更新済み ✓'});
  String get drawerSaveFail       => _t({'zh':'儲存失敗：',   'en':'Save failed: ',               'ja':'保存失敗：'});
  String get drawerEditProfile    => _t({'zh':'編輯個人資料', 'en':'Edit Profile',                'ja':'プロフィール編集'});
  String get drawerChangePhoto    => _t({'zh':'點擊更換相片', 'en':'Tap to change photo',         'ja':'タップして写真を変更'});
  String get drawerChooseAvatar   => _t({'zh':'或選擇圖示頭像', 'en':'Or choose an icon avatar',  'ja':'またはアイコンを選択'});
  String get drawerRemovePhoto    => _t({'zh':'移除照片，改用圖示', 'en':'Remove photo, use icon','ja':'写真を削除してアイコンを使用'});
  String get drawerBasicInfo      => _t({'zh':'基本資料',     'en':'Basic Info',                  'ja':'基本情報'});
  String get drawerSavedList      => _t({'zh':'收藏清單',     'en':'Saved List',                  'ja':'保存リスト'});
  String get drawerSavedHint      => _t({'zh':'在地圖或景點詳情頁點愛心即可收藏', 'en':'Tap ♥ on map or spot details to save', 'ja':'地図またはスポット詳細で♥をタップして保存'});
  String get drawerRemove         => _t({'zh':'移除', 'en':'Remove', 'ja':'削除'});
  String get drawerMyTrips        => _t({'zh':'我的行程',     'en':'My Trips',                    'ja':'マイ旅程'});
  String get drawerCreateTripHint => _t({'zh':'請至「行程管理」頁面建立新行程', 'en':'Create a trip in Trip Planner', 'ja':'旅程管理で旅程を作成'});
  String get drawerAllAchievements=> _t({'zh':'全部成就',     'en':'All Achievements',            'ja':'すべての実績'});
  String get drawerFollow         => _t({'zh':'追蹤', 'en':'Follow', 'ja':'フォロー'});
  String drawerTripCount(int n)   => langCode == 'en' ? '$n trip${n > 1 ? 's' : ''}' : langCode == 'ja' ? '$n 件の旅程' : '$n 篇行程';
  String drawerUnlocked(int earned, int total) => langCode == 'en'
      ? 'Unlocked $earned / $total achievements'
      : langCode == 'ja' ? '$earned / $total 個の実績を解放'
      : '已解鎖 $earned / $total 個成就';
  String get drawerExploreMore    => _t({'zh':'繼續探索嘉義，解鎖更多成就！', 'en':'Keep exploring Chiayi to unlock more!', 'ja':'嘉義を探索して実績を解放しよう！'});
  String drawerPhotoCount(int n)  => langCode == 'en' ? '$n photo${n > 1 ? 's' : ''}' : langCode == 'ja' ? '$n 枚' : '$n 張';

  // ── Profile extra
  String get profileTravelCompanions => _t({'zh':'旅伴管理', 'en':'Travel Companions', 'ja':'旅仲間管理'});

  // ── Community extra tabs
  String get commTripShareTab     => _t({'zh':'行程分享', 'en':'Trip Sharing', 'ja':'旅程シェア'});
  String get commDiscussionTab    => _t({'zh':'討論區',   'en':'Discussion',   'ja':'ディスカッション'});
  String get commShareThoughts    => _t({'zh':'分享你的想法', 'en':'Share your thoughts…', 'ja':'感想をシェア…'});

  // ── Stamp screen
  String get stampNoPhotos        => _t({'zh':'還沒有打卡照片', 'en':'No check-in photos yet', 'ja':'チェックイン写真なし'});
  String get stampPhotosHint      => _t({'zh':'拍下你的探索瞬間\n儲存後就會出現在這裡！', 'en':'Capture your exploration moments!\nThey\'ll appear here.', 'ja':'探索の瞬間を撮影しよう！\n保存するとここに表示されます。'});
  String get stampOpenCamera      => _t({'zh':'開啟相機', 'en':'Open Camera', 'ja':'カメラを開く'});
  String stampPhotoCount(int n)   => langCode == 'en' ? '$n photo${n > 1 ? 's' : ''}' : langCode == 'ja' ? '$n 枚の写真' : '共 $n 張照片';
  String get stampTakePhoto       => _t({'zh':'拍照', 'en':'Photo', 'ja':'写真'});
  String get stampVisitCount      => _t({'zh':'已踩點', 'en':'Visited', 'ja':'訪問済み'});
  String get stampNotVisited      => _t({'zh':'尚未踩點', 'en':'Not visited', 'ja':'未訪問'});
  String get stampClose           => _t({'zh':'關閉', 'en':'Close', 'ja':'閉じる'});
  String get stampNoLeaderboard   => _t({'zh':'還沒有人上榜！快去集章吧', 'en':'No entries yet! Go collect stamps!', 'ja':'まだランキングなし！スタンプを集めよう！'});
  String get stampSpotsUnit       => _t({'zh':'景點', 'en':'spots', 'ja':'スポット'});
  String get stampStreakDays       => _t({'zh':'連續', 'en':'streak', 'ja':'連続'});

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
  static const _kLangKey  = 'settings_lang';

  int    _themeIndex = 7;
  String _langCode   = 'zh';

  int    get themeIndex   => _themeIndex;
  String get langCode     => _langCode;

  ThemePreset get currentTheme => kThemePresets[_themeIndex];
  AppL10n     get l10n         => AppL10n(_langCode);

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  AppSettingsProvider() { _load(); }

  Future<void> _load() async {
    final prefs = await _sp;
    _themeIndex = (prefs.getInt(_kThemeKey) ?? 7).clamp(0, kThemePresets.length - 1);
    _langCode   = prefs.getString(_kLangKey) ?? 'zh';
    notifyListeners();
  }

  Future<void> setTheme(int index) async {
    final i = index.clamp(0, kThemePresets.length - 1);
    if (i == _themeIndex) return;
    _themeIndex = i;
    notifyListeners();
    (await _sp).setInt(_kThemeKey, i);
  }

  Future<void> setLang(String code) async {
    if (code == _langCode) return;
    _langCode = code;
    notifyListeners();
    (await _sp).setString(_kLangKey, code);
  }
}
