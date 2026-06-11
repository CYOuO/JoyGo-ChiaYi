import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import '../widgets/common_widgets.dart' show IllustratedEmptyState, EmptyScene, ShimmerBox;
import '../services/expense_service.dart';
import '../services/trip_service.dart';

// Map trip icon key (emoji or named) → IconData
IconData _tripIconFromKey(String key) {
  switch (key) {
    case 'map':   case '🗺️': return Icons.map_rounded;
    case 'flight':case '✈️': return Icons.flight_rounded;
    case 'train': case '🚂': return Icons.train_rounded;
    case 'beach': case '🏖️': case '🏝️': return Icons.beach_access_rounded;
    case 'mountain': case '🏔️': case '⛰️': return Icons.landscape_rounded;
    case 'flower': case '🌸': return Icons.local_florist_rounded;
    case 'ramen': case '🍜': return Icons.ramen_dining_rounded;
    case 'attractions': case '🎡': return Icons.attractions_rounded;
    case 'castle': case '🏯': case '🏛️': return Icons.account_balance_rounded;
    case 'camera': case '📸': return Icons.camera_alt_rounded;
    case 'list':  case '📋': return Icons.list_alt_rounded;
    default: return Icons.map_rounded;
  }
}

// ─── Expense icon map (key → IconData + Color) ─────────────
const _kExpIconMap = <String, (IconData, Color)>{
  'ramen':   (Icons.ramen_dining_rounded,       Color(0xFFE57373)),
  'lunch':   (Icons.lunch_dining_rounded,        Color(0xFFFF8A65)),
  'cafe':    (Icons.local_cafe_rounded,          Color(0xFF8D6E63)),
  'dessert': (Icons.icecream_rounded,            Color(0xFFF48FB1)),
  'tea':     (Icons.emoji_food_beverage_rounded, Color(0xFFA8D5BA)),
  'bar':     (Icons.local_bar_rounded,           Color(0xFFFFB300)),
  'hotel':   (Icons.hotel_rounded,               Color(0xFF5C6BC0)),
  'train':   (Icons.train_rounded,               Color(0xFF42A5F5)),
  'bus':     (Icons.directions_bus_rounded,      Color(0xFF26C6DA)),
  'ticket':  (Icons.confirmation_number_rounded, Color(0xFFEC407A)),
  'shop':    (Icons.shopping_bag_rounded,        Color(0xFF7E57C2)),
  'other':   (Icons.more_horiz_rounded,         Color(0xFF78909C)),
};
(IconData, Color) _expIcon(String key) =>
    _kExpIconMap[key] ?? (Icons.receipt_long_rounded, Color(0xFF9E9E9E));

// ═══════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════

class Member {
  final String id;
  final String name;
  final String? photoUrl;
  final String? uid;        // Firebase UID（外部成員為 null）
  final bool isExternal;
  double balance;

  Member({
    required this.id,
    required this.name,
    this.photoUrl,
    this.uid,
    this.isExternal = false,
    this.balance = 0,
  });

  /// 從 TripMember 轉換
  factory Member.fromTripMember(TripMember m) =>
      Member(id: m.id, name: m.name, photoUrl: m.photoUrl, uid: m.uid, isExternal: m.isExternal);

  String get initial => name.isNotEmpty ? name[0] : '?';
}

/// 將 List<TripMember> 同步回 _members (Member 格式)
List<Member> _toMemberList(List<TripMember> list) =>
    list.map(Member.fromTripMember).toList();

/// 頂層函式，可在任意 State 使用
Widget _buildMemberAvatar(BuildContext context, Member m, {double radius = 18}) {
  final primary = Theme.of(context).colorScheme.primary;
  if (m.photoUrl != null && m.photoUrl!.isNotEmpty) {
    return CircleAvatar(radius: radius, backgroundImage: NetworkImage(m.photoUrl!));
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: m.isExternal
        ? const Color(0xFFE8A020).withValues(alpha: 0.25)
        : primary.withValues(alpha: 0.15),
    child: Text(m.initial,
      style: TextStyle(
        fontSize: radius * 0.75, fontWeight: FontWeight.w700,
        color: m.isExternal ? const Color(0xFFB06010) : primary)),
  );
}

class ExpenseItem {
  final String id;
  final String icon;
  final String title;
  final String category;
  final int amount;
  final String paidById;
  final List<String> splitMemberIds; // 參與分攤的人
  final DateTime date;
  final String? tripId;

  ExpenseItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.category,
    required this.amount,
    required this.paidById,
    required this.splitMemberIds,
    required this.date,
    this.tripId,
  });
}

class _TripEntry {
  final String id;
  final String name;
  final String icon;
  _TripEntry({required this.id, required this.name, required this.icon});
}

class Settlement {
  final String fromId;
  final String toId;
  final int amount;

  Settlement({
    required this.fromId,
    required this.toId,
    required this.amount,
  });
}

// ═══════════════════════════════════════════════
// MAIN EXPENSE SCREEN
// ═══════════════════════════════════════════════

class ExpenseScreen extends StatefulWidget {
  final bool embedded;
  /// 嵌入在行程詳情時傳入 tripId；獨立使用時為 null
  final String? tripId;
  const ExpenseScreen({super.key, this.embedded = false, this.tripId});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Firebase streams ──────────────────────────────────────
  StreamSubscription<List<TripMember>>?    _membersSub;
  StreamSubscription<List<ExpenseRecord>>? _expensesSub;
  StreamSubscription<List<FirebaseTrip>>?  _tripsSub;
  StreamSubscription<Set<String>>?         _settledSub;

  // ── Live data (Firebase → local models) ──────────────────
  List<TripMember>   _fbMembers  = [];
  List<ExpenseRecord> _fbExpenses = [];
  List<FirebaseTrip>  _fbTrips   = [];

  // ── 已標記完成的分帳對（fromId_toId）────────────────────
  final Set<String> _settledPairs = {};

  // ── 轉換後的 local models（UI 使用）─────────────────────
  List<Member>      get _members  => _toMemberList(_fbMembers);
  List<ExpenseItem> get _expenses =>
      _fbExpenses.map((r) => ExpenseItem(
        id:             r.id,
        icon:           _catIcon(r.category),
        title:          r.title,
        category:       r.category,
        amount:         r.amount,
        paidById:       r.paidByMemberId,
        splitMemberIds: r.splitMemberIds,
        date:           r.date,
        tripId:         _activeTripId,
      )).toList();

  // 選取的行程（獨立模式用）
  String? _selectedTripId;
  String? _selectedCategory;

  String? get _activeTripId => widget.tripId ?? _selectedTripId;

  List<ExpenseItem> get _filteredExpenses {
    var list = _expenses;
    if (_selectedCategory != null) {
      list = list.where((e) => e.category == _selectedCategory).toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _subscribeToData();
  }

  void _subscribeToData() {
    // 訂閱行程列表（獨立模式）
    _tripsSub = TripService.tripsStream().listen((trips) {
      if (mounted) setState(() {
        _fbTrips = trips;
        // 自動選取第一個行程（獨立模式且尚未選取）
        if (_selectedTripId == null && widget.tripId == null && trips.isNotEmpty) {
          _selectedTripId = trips.first.id;
          _subscribeToTrip(trips.first.id);
        }
      });
    });

    // 若有 tripId（嵌入 or 已選取行程），訂閱成員 + 消費
    final tid = _activeTripId;
    if (tid != null) _subscribeToTrip(tid);
  }

  void _subscribeToTrip(String tripId) {
    _membersSub?.cancel();
    _expensesSub?.cancel();
    _settledSub?.cancel();

    _membersSub = ExpenseService.membersStream(tripId).listen((m) {
      if (mounted) setState(() => _fbMembers = m);
      // 自動同步有 uid 的成員名稱（確保顯示最新暱稱）
      for (final member in m) {
        if (member.uid != null && !member.isExternal) {
          ExpenseService.syncMemberName(tripId, member.uid!);
        }
      }
    });
    _expensesSub = ExpenseService.expensesStream(tripId).listen((e) {
      if (mounted) setState(() => _fbExpenses = e);
    });

    _settledSub = ExpenseService.settledPairsStream(tripId).listen((pairs) {
      if (mounted) {
        setState(() {
          _settledPairs.clear();
          _settledPairs.addAll(pairs);
        });
      }
    });

    // 確保自己在成員清單
    ExpenseService.ensureSelfInMembers(tripId);
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _expensesSub?.cancel();
    _tripsSub?.cancel();
    _settledSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ── Computed ──────────────────────────────────────────────

  int get _totalAmount => _filteredExpenses.fold(0, (s, e) => s + e.amount);

  Map<String, int> get _memberTotals {
    final map = {for (final m in _members) m.id: 0};
    for (final e in _filteredExpenses) {
      map[e.paidById] = (map[e.paidById] ?? 0) + e.amount;
    }
    return map;
  }

  Map<String, int> get _memberShouldPay {
    final map = {for (final m in _members) m.id: 0};
    for (final e in _filteredExpenses) {
      if (e.splitMemberIds.isEmpty) continue;
      final share = (e.amount / e.splitMemberIds.length).round();
      for (final mid in e.splitMemberIds) {
        map[mid] = (map[mid] ?? 0) + share;
      }
    }
    return map;
  }

  Map<String, int> get _memberBalance {
    final paid = _memberTotals;
    final should = _memberShouldPay;
    return {for (final m in _members) m.id: (paid[m.id] ?? 0) - (should[m.id] ?? 0)};
  }

  List<Settlement> get _settlements {
    final balance = Map<String, int>.from(_memberBalance);
    final result = <Settlement>[];
    while (true) {
      final debtors   = balance.entries.where((e) => e.value < -1).toList()..sort((a,b) => a.value.compareTo(b.value));
      final creditors = balance.entries.where((e) => e.value > 1) .toList()..sort((a,b) => b.value.compareTo(a.value));
      if (debtors.isEmpty || creditors.isEmpty) break;
      final debtor = debtors.first, creditor = creditors.first;
      final amt = debtor.value.abs() < creditor.value ? debtor.value.abs() : creditor.value;
      result.add(Settlement(fromId: debtor.key, toId: creditor.key, amount: amt));
      balance[debtor.key]   = balance[debtor.key]!   + amt;
      balance[creditor.key] = balance[creditor.key]! - amt;
    }
    return result;
  }

  // ── Category helpers ──
  static const _categoryColors = <String, Color>{
    '住宿': Color(0xFF88B8C8),
    '交通': Color(0xFF8FBF8F),
    '餐飲': Color(0xFFD4A847),
    '門票': Color(0xFFC4856A),
    '購物': Color(0xFFA888C8),
    '其他': Color(0xFFA0AFA0),
  };

  Color _catColor(String cat) =>
      _categoryColors[cat] ?? AppColors.textHint;

  static const _categoryIcons = <String, IconData>{
    '住宿': Icons.hotel_rounded,
    '交通': Icons.directions_car_rounded,
    '餐飲': Icons.restaurant_rounded,
    '門票': Icons.confirmation_number_rounded,
    '購物': Icons.shopping_bag_rounded,
    '其他': Icons.more_horiz_rounded,
  };
  String _catIcon(String cat) {
    // 已移除 emoji；icon widget 另外用 _catIconData
    return cat;
  }
  IconData _catIconData(String cat) =>
      _categoryIcons[cat] ?? Icons.receipt_long_rounded;

  /// 成員頭像（有 photoUrl 用圖，否則顯示首字）
  Widget _memberAvatar(Member m, {double radius = 20}) {
    final primary = Theme.of(context).colorScheme.primary;
    if (m.photoUrl != null && m.photoUrl!.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(m.photoUrl!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: m.isExternal
          ? AppColors.accentStraw.withValues(alpha: 0.25)
          : primary.withValues(alpha: 0.15),
      child: Text(m.initial,
        style: TextStyle(
          fontSize: radius * 0.8, fontWeight: FontWeight.w700,
          color: m.isExternal ? AppColors.accentTerra : primary)),
    );
  }

  // ── 分類篩選列 ──
  Widget _buildCategoryFilter() {
    final cats = _categoryColors.keys.toList();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _catChip(null, '全部', '📊'),
            ...cats.map((c) => _catChip(c, c, '')),
          ],
        ),
      ),
    );
  }

  Widget _catChip(String? cat, String label, String icon) {
    final isSelected = _selectedCategory == cat;
    final color = cat == null ? Theme.of(context).colorScheme.primary : _catColor(cat);
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = cat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon.isNotEmpty) ...[
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ]),
      ),
    );
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final primaryMist = Color.lerp(primary, Colors.white, 0.88)!;
    final tabBar = TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: '帳單明細'),
        Tab(text: '分帳結算'),
        Tab(text: '統計圖表'),
      ],
    );
    final body = TabBarView(
      controller: _tabController,
      children: [
        _buildExpenseListTab(),
        _buildSettlementTab(),
        _buildChartTab(),
      ],
    );
    // When embedded in trip detail, skip Scaffold+AppBar but keep FAB
    if (widget.embedded) {
      return Stack(children: [
        Column(children: [
          Material(color: AppColors.surface, child: tabBar),
          Expanded(child: body),
        ]),
        Positioned(
          right: 16, bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'expense_embedded_fab',
            onPressed: () => _showAddExpense(context),
            backgroundColor: primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增消費', style: TextStyle(fontWeight: FontWeight.w700)),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ]);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 12,
        title: GestureDetector(
          onTap: () => _showTripPicker(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _selectedTripId == null
                      ? '選擇行程'
                      : _fbTrips
                          .where((t) => t.id == _selectedTripId)
                          .map((t) => t.title)
                          .firstOrNull ?? '選擇行程',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down_rounded, size: 20),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: '管理成員',
            onPressed: () => _showMemberManager(context),
          ),
        ],
        bottom: tabBar,
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddExpense(context),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增消費',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // ════════════════════════════════
  // TAB 1 : EXPENSE LIST
  // ════════════════════════════════

  void _showTripPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('選擇行程',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ..._fbTrips.map((t) => _tripPickerItem(t.id, t.title, t.icon)),
                    const Divider(height: 20),
                    Builder(builder: (bCtx) {
                      final p = Theme.of(bCtx).colorScheme.primary;
                      return ListTile(
                        leading: Icon(Icons.add_rounded, color: p),
                        title: Text('新增行程',
                            style: TextStyle(color: p, fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.pop(context);
                          _showAddTripDialog();
                        },
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripPickerItem(String? id, String name, String icon) {
    final isSelected = _selectedTripId == id;
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: (isSelected ? primary : AppColors.textHint).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          _tripIconFromKey(icon),
          size: 20,
          color: isSelected ? primary : AppColors.textSecondary,
        ),
      ),
      title: Text(name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
            color: isSelected ? primary : AppColors.textPrimary,
          )),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: primary)
          : null,
      onTap: () {
        setState(() => _selectedTripId = id);
        Navigator.pop(context);
        if (id != null) _subscribeToTrip(id);
      },
    );
  }

  void _showAddTripDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('新增記帳行程', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：墾丁三天兩夜'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              // 記帳行程在 TripScreen 建立；這裡只提示
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('請到「行程管理」頁面建立行程'),
                behavior: SnackBarBehavior.floating));
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseListTab() {
    // 獨立模式且未選行程 → 提示
    if (_activeTripId == null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_rounded, size: 52, color: AppColors.textHint.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        const Text('請先選擇行程', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        const Text('點上方行程名稱選擇', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
      ]));
    }

    // Group by date
    final grouped = <String, List<ExpenseItem>>{};
    for (final e in _filteredExpenses) {
      final key = '${e.date.year}/${e.date.month.toString().padLeft(2, '0')}/${e.date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        // Summary strip
        _buildSummaryStrip(),
        // List
        Expanded(
          child: _filteredExpenses.isEmpty
              ? IllustratedEmptyState(
                  scene: EmptyScene.expense,
                  title: _selectedTripId == null ? '尚無任何消費紀錄' : '此行程尚無消費紀錄',
                  body: '點擊右下角 + 新增第一筆消費',
                  color: Theme.of(context).colorScheme.primary,
                )
              : Builder(builder: (ctx) {
                  final p = Theme.of(ctx).colorScheme.primary;
                  return NotebookBackground(
                    lineColor: p.withValues(alpha: 0.07),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                      children: [
                        for (final dateKey in sortedKeys) ...[
                          _dateHeader(dateKey),
                          ...grouped[dateKey]!.map((e) => _expenseCard(e)),
                        ],
                      ],
                    ),
                  );
                }),
        ),
      ],
    );
  }

  Widget _buildSummaryStrip() {
    final primary = Theme.of(context).colorScheme.primary;
    final perPerson = _members.isNotEmpty ? (_totalAmount / _members.length).round() : 0;
    return NotebookBackground(
      lineColor: primary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: StitchedBox(
          color: Colors.white,
          stitchColor: primary.withValues(alpha: 0.22),
          radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
          child: Row(children: [
            _stripStat('總花費', 'NT\$ $_totalAmount', primary),
            _vLine(),
            _stripStat('人數', '${_members.length} 人', AppColors.textSecondary),
            _vLine(),
            _stripStat('筆數', '${_expenses.length} 筆', AppColors.textSecondary),
            _vLine(),
            _stripStat('均攤', 'NT\$ $perPerson', AppColors.accentTerra),
          ]),
        ),
      ),
    );
  }

  Widget _stripStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _vLine() => Container(
      width: 1, height: 28, color: AppColors.divider);

  Widget _dateHeader(String date) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 4, 6),
      child: Row(children: [
        DoodleHeart(color: primary.withValues(alpha: 0.50), size: 10),
        const SizedBox(width: 6),
        HandDrawnUnderline(
          color: primary.withValues(alpha: 0.25),
          child: Text(date,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: primary)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.7, color: primary.withValues(alpha: 0.18))),
        const SizedBox(width: 6),
        DoodleLightning(color: primary.withValues(alpha: 0.35), size: 7),
      ]),
    );
  }

  Widget _expenseCard(ExpenseItem e) {
    final payer = _members.firstWhere((m) => m.id == e.paidById,
        orElse: () => Member(id: '', name: '?'));
    final catColor = _catColor(e.category);
    final shareCount = e.splitMemberIds.length;
    final perShare = shareCount > 0 ? (e.amount / shareCount).round() : 0;

    return Dismissible(
      key: Key(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.error),
      ),
      confirmDismiss: (_) async {
        return await _confirmDelete(context);
      },
      onDismissed: (_) {
        final tid = _activeTripId;
        if (tid != null) {
          ExpenseService.deleteExpense(tid, e.id);
        }
        setState(() => _fbExpenses.removeWhere((x) => x.id == e.id));
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
        onTap: () => _showExpenseDetail(context, e),
        child: StitchedBox(
          color: Colors.white,
          stitchColor: catColor.withValues(alpha: 0.28),
          radius: 16, inset: 4, dashWidth: 4, dashGap: 3.5,
          padding: const EdgeInsets.all(14),
          boxShadow: [BoxShadow(color: catColor.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 2))],
          child: Row(
            children: [
              // Category icon circle (Material icon)
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: catColor.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: Center(child: Icon(_catIconData(e.category), color: catColor, size: 22)),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _tag(e.category, catColor),
                        const SizedBox(width: 6),
                        Text(
                          '${payer.name} 付款',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '每人 NT\$ $perShare（$shareCount 人分攤）',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'NT\$ ${e.amount}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.textHint),
                ],
              ),
            ],
          ),
        ),
        ), // GestureDetector
      ), // Padding
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ════════════════════════════════
  // TAB 2 : SETTLEMENT
  // ════════════════════════════════
  Widget _buildSettlementTab() {
    final balance = _memberBalance;
    final settlements = _settlements;

    return Column(
      children: [
        _buildCategoryFilter(),
        Expanded(child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header card ──
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  const Text('成員結算',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  Text(
                    '共 ${_members.length} 人',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...(_members.map((m) => _memberBalanceRow(m, balance[m.id] ?? 0))),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Settlements ──
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sync_alt_rounded, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  const Text('最少轉帳方案',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '以下方式可讓大家結清，轉帳次數最少',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint),
              ),
              const SizedBox(height: 14),
              if (_members.length <= 1 && _expenses.isNotEmpty)
                _singlePersonSummary() // 單人模式專屬 UI
              else if (settlements.isEmpty && _expenses.isEmpty)
                _noExpensesSettlement()
              else if (settlements.isEmpty)
                _emptySettlement()
              else
                ...settlements.map((s) => _settlementRow(s)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Per member detail ──
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            '成員消費明細',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.textPrimary),
          ),
        ),
        ...(_members.map((m) => _memberDetailCard(m))),

        const SizedBox(height: 100),
      ],
    )),  // Expanded + ListView
      ],
    );  // Column
  }

  Widget _memberBalanceRow(Member m, int bal) {
    final isPositive = bal >= 0;
    final absVal = bal.abs();
    final isSingle = _members.length <= 1;
    final totalPaid = _memberTotals[m.id] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _memberAvatar(m, radius: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
                Text(
                  isSingle 
                      ? '總花費 NT\$ $totalPaid'
                      : isPositive
                          ? (absVal == 0
                              ? '已結清 ✓'
                              : '應收 NT\$ $absVal')
                          : '應付 NT\$ $absVal',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSingle 
                        ? Theme.of(context).colorScheme.primary
                        : absVal == 0
                            ? AppColors.textHint
                            : (isPositive
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.error),
                    fontWeight: FontWeight.w600,
                  ),
                ),

              ],
            ),
          ),
          // Balance bar（僅顯示於 Row 右側）
          if (!isSingle) _balanceBar(bal),
        ],
      ),
    );
  }

  Widget _balanceBar(int bal) {
    final max = _memberBalance.values
        .map((v) => v.abs())
        .fold(0, (a, b) => a > b ? a : b);
    if (max == 0) return const SizedBox(width: 80);
    final ratio = bal.abs() / max;

    return SizedBox(
      width: 80,
      child: Column(
        crossAxisAlignment: bal >= 0
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            '${bal >= 0 ? '+' : ''}NT\$$bal',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: bal > 0
                  ? Theme.of(context).colorScheme.primary
                  : bal < 0
                      ? AppColors.error
                      : AppColors.textHint,
            ),
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                  height: 4,
                  width: 80,
                  decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2))),
              Container(
                height: 4,
                width: 80 * ratio,
                decoration: BoxDecoration(
                  color: bal >= 0 ? Theme.of(context).colorScheme.primary : AppColors.error,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settlementRow(Settlement s) {
    final from = _members.firstWhere((m) => m.id == s.fromId,
        orElse: () => Member(id: '', name: '?'));
    final to = _members.firstWhere((m) => m.id == s.toId,
        orElse: () => Member(id: '', name: '?'));
    final isSettled = _settledPairs.contains('${s.fromId}_${s.toId}');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSettled ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06) : AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSettled ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.45) : AppColors.divider),
      ),
      child: Row(
        children: [
          // From
          Column(children: [
            _memberAvatar(from, radius: 18),
            const SizedBox(height: 4),
            Text(from.name,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ]),
          // Transfer arrow + amount
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentTerra.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accentTerra.withOpacity(0.30)),
                  ),
                  child: Text(
                    'NT\$ ${s.amount}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: AppColors.accentTerra,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: Container(height: 1, color: AppColors.accentTerra.withOpacity(0.25))),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.accentTerra,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.accentTerra.withOpacity(0.30), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.payments_rounded, color: Colors.white, size: 13),
                    ),
                    Expanded(child: Container(height: 1, color: AppColors.accentTerra.withOpacity(0.25))),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('轉帳給', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
              ],
            ),
          ),
          // To
          Column(children: [
            _memberAvatar(to, radius: 18),
            const SizedBox(height: 4),
            Text(to.name,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ]),
          // Mark done
          const SizedBox(width: 10),
          if (isSettled)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
            )
          else
            GestureDetector(
              onTap: () async => await _markSettled(context, s, from, to),
              child: Builder(builder: (bCtx) {
                final p = Theme.of(bCtx).colorScheme.primary;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '標記\n完成',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: p,
                      height: 1.3,
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _noExpensesSettlement() {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 40, color: primary.withValues(alpha: 0.35)),
          const SizedBox(height: 8),
          Text('尚未新增任何消費',
              style: TextStyle(fontWeight: FontWeight.w700, color: primary, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('新增消費後即可計算最少轉帳方案',
              style: TextStyle(color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _emptySettlement() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Icon(Icons.celebration_rounded, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text('大家都結清了！',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 15)),
          const SizedBox(height: 4),
          const Text('不需要任何轉帳',
              style: TextStyle(
                  color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _singlePersonSummary() {
  final primary = Theme.of(context).colorScheme.primary;
  final totalPaid = _totalAmount;
  
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.self_improvement_rounded, size: 48, color: primary), 
        ),
        const SizedBox(height: 16),
        Text('獨旅記帳模式',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: primary,
                fontSize: 16)),
        const SizedBox(height: 6),
        Text('目前總共花費了 NT\$ $totalPaid',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
      ],
    ),
  );
}

  Widget _memberDetailCard(Member m) {
    final paid = _expenses
        .where((e) => e.paidById == m.id)
        .fold(0, (sum, e) => sum + e.amount);
    final owed = _memberShouldPay[m.id] ?? 0;
    final paidExpenses =
        _expenses.where((e) => e.paidById == m.id).toList();

    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StitchedBox(
        color: Colors.white,
        stitchColor: primary.withValues(alpha: 0.20),
        radius: 16, inset: 4, dashWidth: 4, dashGap: 3.5,
        padding: EdgeInsets.zero,
        boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: _memberAvatar(m, radius: 20),
              title: Row(children: [
                Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(width: 6),
                DoodleHeart(color: primary.withValues(alpha: 0.30), size: 9),
              ]),
              subtitle: Text('代墊 NT\$$paid  應付 NT\$$owed',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              trailing: _balanceChip(_memberBalance[m.id] ?? 0),
              children: [
                // 展開內容：JournalDivider + 消費明細
                JournalDivider(color: primary, label: '消費明細'),
                if (paidExpenses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text('本次未代墊費用',
                      style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                  )
                else
                  ...paidExpenses.map((e) {
                    final catColor = _catColor(e.category);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Icon(_expIcon(e.icon).$1, color: _expIcon(e.icon).$2, size: 18))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(e.category, style: TextStyle(fontSize: 10, color: catColor)),
                        ])),
                        Text('NT\$ ${e.amount}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: catColor)),
                      ]),
                    );
                  }),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceChip(int bal) {
    final isPositive = bal > 0;
    final isZero = bal == 0;
    final primary = Theme.of(context).colorScheme.primary;
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isZero
            ? AppColors.surfaceMoss
            : isPositive
                ? mist
                : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isZero
            ? '結清'
            : (isPositive ? '+NT\$$bal' : '-NT\$${bal.abs()}'),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: isZero
              ? AppColors.textHint
              : (isPositive ? primary : AppColors.error),
        ),
      ),
    );
  }

  // ════════════════════════════════
  // TAB 3 : CHART
  // ════════════════════════════════
  Widget _buildChartTab() {
    // Category breakdown — use _filteredExpenses to respect category filter
    final catTotals = <String, int>{};
    for (final e in _filteredExpenses) {
      catTotals[e.category] =
          (catTotals[e.category] ?? 0) + e.amount;
    }
    final sortedCats = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Per-member totals
    final memberTotals = _memberTotals;

    return Column(
      children: [
        _buildCategoryFilter(),
        Expanded(child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Category donut-style bars ──
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(icon: '🗂️', title: '消費分類'),
              const SizedBox(height: 16),
              ...sortedCats.map((entry) =>
                  _catBar(entry.key, entry.value)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Per-member paid ──
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(icon: '👤', title: '各人代墊金額'),
              const SizedBox(height: 16),
              ...(_members.map((m) {
                final paid = memberTotals[m.id] ?? 0;
                final maxPaid = memberTotals.values
                    .fold(0, (a, b) => a > b ? a : b);
                final ratio =
                    maxPaid > 0 ? paid / maxPaid : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      _memberAvatar(m, radius: 14),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 36,
                        child: Text(m.name,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(4),
                              child:
                                  LinearProgressIndicator(
                                value: ratio,
                                minHeight: 8,
                                backgroundColor:
                                    AppColors.divider,
                                valueColor:
                                    AlwaysStoppedAnimation<
                                        Color>(
                                  Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.35)!,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'NT\$$paid',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              })),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Simple day-by-day ──
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                  icon: '📅', title: '每日消費趨勢'),
              const SizedBox(height: 16),
              _buildDayChart(),
            ],
          ),
        ),

        const SizedBox(height: 100),
      ],
    )),  // Expanded + ListView
      ],
    );  // Column
  }

  Widget _catBar(String cat, int amount) {
    final ratio =
        _totalAmount > 0 ? amount / _totalAmount : 0.0;
    final color = _catColor(cat);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              _tag(cat, color),
              const Spacer(),
              Text(
                'NT\$ $amount',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(width: 6),
              Text(
                '${(ratio * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (ctx, box) => Stack(children: [
            Container(height: 10, decoration: BoxDecoration(
              color: AppColors.divider, borderRadius: BorderRadius.circular(5))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              height: 10,
              width: box.maxWidth * ratio,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.white, 0.35)!]),
                borderRadius: BorderRadius.circular(5),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1))]),
            ),
          ])),
        ],
      ),
    );
  }

  Widget _buildDayChart() {
    final dayTotals = <String, int>{};
    for (final e in _expenses) {
      final k = '${e.date.month}/${e.date.day}';
      dayTotals[k] = (dayTotals[k] ?? 0) + e.amount;
    }
    if (dayTotals.isEmpty) {
      return const Center(child: Text('尚無消費資料', style: TextStyle(color: AppColors.textHint, fontSize: 12)));
    }
    final keys   = dayTotals.keys.toList()..sort();
    final maxVal = dayTotals.values.fold(0, (a, b) => a > b ? a : b);
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: keys.asMap().entries.map((entry) {
          final k     = entry.value;
          final val   = dayTotals[k]!;
          final ratio = maxVal > 0 ? val / maxVal : 0.0;
          // Color varies by day index — creates a gentle gradient feel
          final barColor = Color.lerp(primary, Color.lerp(primary, Colors.white, 0.4)!, entry.key / math.max(keys.length - 1, 1))!;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (val > 0) Text(
                  val >= 1000 ? '${(val / 1000).toStringAsFixed(1)}k' : '$val',
                  style: TextStyle(fontSize: 8, color: primary, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: Duration(milliseconds: 500 + entry.key * 60),
                  curve: Curves.easeOutCubic,
                  height: 80 * ratio + 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [barColor, Color.lerp(barColor, Colors.white, 0.25)!]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    boxShadow: [BoxShadow(color: barColor.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                ),
                const SizedBox(height: 6),
                Text(k, style: const TextStyle(fontSize: 9, color: AppColors.textHint), textAlign: TextAlign.center),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ════════════════════════════════
  // DIALOGS / SHEETS
  // ════════════════════════════════

  void _showAddExpense(BuildContext context) {
    final tid = _activeTripId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(
        members: _members,
        trips: _fbTrips.map((t) => _TripEntry(id: t.id, name: t.title, icon: t.icon)).toList(),
        initialTripId: _activeTripId,
        lockTrip: widget.embedded && widget.tripId != null,
        onAdd: (e) {
          // 儲存到 Firebase（若有 tripId）
          if (tid != null) {
            ExpenseService.addExpense(tid, ExpenseRecord(
              id: '',
              title:          e.title,
              category:       e.category,
              amount:         e.amount,
              paidByMemberId: e.paidById,
              splitMemberIds: e.splitMemberIds,
              date:           e.date,
              createdAt:      DateTime.now(),
            ));
          }
          // Firebase stream 會自動更新 _fbExpenses，不需要 setState
        },
      ),
    );
  }

  void _showExpenseDetail(
      BuildContext context, ExpenseItem e) {
    final payer = _members.firstWhere((m) => m.id == e.paidById,
        orElse: () =>
            Member(id: '', name: '?'));
    final perShare = e.splitMemberIds.isNotEmpty
        ? (e.amount / e.splitMemberIds.length).round()
        : 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Builder(builder: (_) {
                  final (ic, col) = _expIcon(e.icon);
                  return Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: col.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Center(child: Icon(ic, color: col, size: 26)));
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppColors.textPrimary)),
                      Text(
                          '${e.date.year}/${e.date.month}/${e.date.day}',
                          style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 12)),
                    ],
                  ),
                ),
                Builder(builder: (bCtx) => Text(
                  'NT\$ ${e.amount}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: Theme.of(bCtx).colorScheme.primary),
                )),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _detailRow('分類', e.category),
            _detailRow('付款人', payer.name),
            _detailRow('分攤方式',
                '${e.splitMemberIds.length} 人平均分攤'),
            _detailRow(
                '每人', 'NT\$ $perShare'),
            const SizedBox(height: 12),
            const Text('分攤成員',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: e.splitMemberIds.map((mid) {
                final m = _members.firstWhere(
                    (x) => x.id == mid,
                    orElse: () => Member(
                        id: '', name: '?'));
                return Builder(builder: (bCtx) {
                  final p = Theme.of(bCtx).colorScheme.primary;
                  return Chip(
                    label: Text(m.name),
                    backgroundColor: p.withValues(alpha: 0.12),
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                        color: p,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  );
                });
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12)),
          ),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontSize: 14)),
        ],
      ),
    );
  }

  void _showMemberManager(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final tid = _activeTripId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MemberManagerSheet(
        primary: primary,
        tripId: tid,
        members: _members,
        memberAvatar: _memberAvatar,
        onAddExternal: () => _showAddExternalMember(context),
        onRemove: (mid) async {
          if (tid != null) await ExpenseService.removeMember(tid, mid);
        },
        onAddAppUser: (uid, name, photoUrl) async {
          if (tid == null) return;
          final ref = ExpenseService.membersRef(tid);
          await ref.doc(uid).set({
            'uid': uid, 'name': name, 'photoUrl': photoUrl,
            'isExternal': false, 'addedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        },
      ),
    );
  }

  // legacy: kept for _showMemberManager compat
  void _showMemberManager_OLD(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final tid = _activeTripId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            const Text('旅伴管理', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddExternalMember(context),
              icon: Icon(Icons.person_add_outlined, color: primary, size: 18),
              label: Text('加外部旅伴', style: TextStyle(color: primary)),
            ),
          ]),
          const SizedBox(height: 8),
          ..._members.map((m) => ListTile(
            leading: _memberAvatar(m, radius: 18),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: m.isExternal ? Text('外部成員', style: TextStyle(fontSize: 11, color: AppColors.textHint)) : null,
            trailing: m.uid == FirebaseAuth.instance.currentUser?.uid
                ? const Text('（我）', style: TextStyle(color: AppColors.textHint, fontSize: 12))
                : IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
                    onPressed: () async {
                      if (tid != null) await ExpenseService.removeMember(tid, m.id);
                    },
                  ),
          )),
        ]),
      ),
    );
  }

  void _showAddExternalMember(BuildContext context) {
    final ctrl = TextEditingController();
    final primary = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('加入外部旅伴', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('外部旅伴沒有 app 帳號，只需要輸入姓名即可參與分帳。',
            style: TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.5)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(labelText: '旅伴姓名', hintText: '例如：阿強、小美')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              final tid = _activeTripId;
              if (tid != null) await ExpenseService.addExternalMember(tid, name);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primary),
            child: const Text('加入', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddMember(
      BuildContext context, StateSetter setLocal) {
    const avatarIcons = <(IconData, Color)>[
      (Icons.person_rounded,           Color(0xFF6B9FD4)),
      (Icons.face_3_rounded,           Color(0xFFE891BD)),
      (Icons.face_2_rounded,           Color(0xFF8BC34A)),
      (Icons.person_2_rounded,         Color(0xFF9C27B0)),
      (Icons.elderly_rounded,          Color(0xFF795548)),
      (Icons.child_care_rounded,       Color(0xFFFF9800)),
      (Icons.child_friendly_rounded,   Color(0xFF4CAF50)),
      (Icons.person_3_rounded,         Color(0xFF607D8B)),
    ];
    int selectedIdx = 0;
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('新增旅伴',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon picker
              Wrap(
                spacing: 8,
                children: avatarIcons.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final (iconData, iconColor) = entry.value;
                  final sel = selectedIdx == idx;
                  final primary = Theme.of(context).colorScheme.primary;
                  return GestureDetector(
                    onTap: () => setDialog(() => selectedIdx = idx),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: sel ? primary.withValues(alpha: 0.12) : AppColors.surfaceMoss,
                        shape: BoxShape.circle,
                        border: sel ? Border.all(color: primary, width: 2) : null,
                      ),
                      child: Center(child: Icon(iconData, size: 20, color: sel ? primary : iconColor)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    hintText: '旅伴姓名或暱稱'),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                // 已改為 _showAddExternalMember (Firebase 版)
                // This old dialog is no longer used
              }
              Navigator.pop(context);
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Future<void> _markSettled(BuildContext context, Settlement s,
      Member from, Member to) async {
    final primary = Theme.of(context).colorScheme.primary;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('確認結清？', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          '確認「${from.name}」已轉帳 NT\$${s.amount} 給「${to.name}」嗎？',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認結清', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      // 🌟 改成寫入 Firebase
      final tid = _activeTripId;
      if (tid != null) {
        await ExpenseService.markSettled(tid, '${s.fromId}_${s.toId}');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已標記 ${from.name} 轉帳 NT\$${s.amount} 給 ${to.name} ✓'),
          backgroundColor: primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('刪除此筆消費？'),
            content: const Text('此動作無法復原'),
            actions: [
              TextButton(
                  onPressed: () =>
                      Navigator.pop(context, false),
                  child: const Text('取消')),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error),
                child: const Text('刪除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── helpers ──
  Widget _sectionCard({required Widget child}) {
    final primary = Theme.of(context).colorScheme.primary;
    return StitchedBox(
      color: Colors.white,
      stitchColor: primary.withValues(alpha: 0.20),
      radius: 18, inset: 4.5, dashWidth: 4, dashGap: 3,
      padding: const EdgeInsets.all(16),
      boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════
// ═══════════════════════════════════════════════
// 旅伴管理 Sheet（Email 搜尋 App 用戶 + 加外部旅伴）
// ═══════════════════════════════════════════════
class _MemberManagerSheet extends StatefulWidget {
  final Color primary;
  final String? tripId;
  final List<Member> members;
  final Widget Function(Member, {required double radius}) memberAvatar;
  final VoidCallback onAddExternal;
  final Future<void> Function(String mid) onRemove;
  final Future<void> Function(String uid, String name, String? photoUrl) onAddAppUser;

  const _MemberManagerSheet({
    required this.primary, required this.tripId, required this.members,
    required this.memberAvatar, required this.onAddExternal,
    required this.onRemove, required this.onAddAppUser,
  });
  @override State<_MemberManagerSheet> createState() => _MemberManagerSheetState();
}

class _MemberManagerSheetState extends State<_MemberManagerSheet> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _notFound = false;
  Map<String, dynamic>? _foundUser;
  bool _adding = false;

  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _notFound = false; _foundUser = null; });
    try {
      final db = FirebaseFirestore.instance;
      // 先試 email，再試 nickname
      QuerySnapshot? snap;
      snap = await db.collection('users').where('email', isEqualTo: q).limit(1).get();
      if (snap.docs.isEmpty) {
        snap = await db.collection('users').where('nickname', isEqualTo: q).limit(1).get();
      }
      if (snap.docs.isEmpty) {
        setState(() { _searching = false; _notFound = true; });
      } else {
        final d = snap.docs.first.data() as Map<String, dynamic>;
        setState(() { _searching = false; _foundUser = {...d, 'uid': snap!.docs.first.id}; });
      }
    } catch (_) {
      setState(() { _searching = false; _notFound = true; });
    }
  }

  Future<void> _addFoundUser() async {
    if (_foundUser == null || _adding) return;
    setState(() => _adding = true);
    final uid = _foundUser!['uid'] as String;
    final name = (_foundUser!['nickname'] ?? _foundUser!['displayName'] ?? _foundUser!['name'] ?? uid).toString();
    final photo = (_foundUser!['photoURL'] ?? _foundUser!['photoUrl'] as String? ?? '');
    await widget.onAddAppUser(uid, name, photo.isEmpty ? null : photo);
    setState(() { _adding = false; _foundUser = null; _searching = false; _notFound = false; _searchCtrl.clear(); });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已加入 $name'),
      backgroundColor: widget.primary, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 把手
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),

          // 標題 + 加外部旅伴
          Row(children: [
            const Text('旅伴管理', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onAddExternal,
              icon: Icon(Icons.person_add_alt_1_outlined, color: p, size: 18),
              label: Text('加外部旅伴', style: TextStyle(color: p, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 10),

          // ── 搜尋 App 用戶 ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.withValues(alpha: 0.15)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('搜尋 App 用戶', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '輸入 Email 或暱稱',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.withValues(alpha: 0.2))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.withValues(alpha: 0.2))),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _searching ? null : _search,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: p, borderRadius: BorderRadius.circular(10)),
                    child: _searching
                        ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ]),
              // 搜尋結果
              if (_notFound)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('找不到此用戶', style: TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              if (_foundUser != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: p.withValues(alpha: 0.15),
                      backgroundImage: (_foundUser!['photoURL'] ?? _foundUser!['photoUrl'] ?? '').toString().isNotEmpty
                          ? NetworkImage((_foundUser!['photoURL'] ?? _foundUser!['photoUrl']).toString()) : null,
                      child: (_foundUser!['photoURL'] ?? _foundUser!['photoUrl'] ?? '').toString().isEmpty
                          ? Text(
                              (_foundUser!['nickname'] ?? _foundUser!['displayName'] ?? '?').toString().isNotEmpty
                                  ? (_foundUser!['nickname'] ?? _foundUser!['displayName']).toString()[0]
                                  : '?',
                              style: TextStyle(color: p, fontWeight: FontWeight.w700),
                            ) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((_foundUser!['nickname'] ?? _foundUser!['displayName'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text((_foundUser!['email'] ?? _foundUser!['emailAddress'] ?? '').toString(),
                          style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    ])),
                    GestureDetector(
                      onTap: _adding ? null : _addFoundUser,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: p, borderRadius: BorderRadius.circular(8)),
                        child: _adding
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('加入', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          // ── 現有成員列表 ────────────────────────────────────
          const Text('目前成員', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          ...widget.members.map((m) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            leading: widget.memberAvatar(m, radius: 18),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: m.isExternal
                ? const Text('外部成員', style: TextStyle(fontSize: 11, color: AppColors.textHint))
                : null,
            trailing: m.uid == myUid
                ? const Text('（我）', style: TextStyle(color: AppColors.textHint, fontSize: 12))
                : IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
                    onPressed: () => widget.onRemove(m.id),
                  ),
          )),
        ]),
      ),
    );
  }
}

// ADD EXPENSE SHEET
// ═══════════════════════════════════════════════

class _AddExpenseSheet extends StatefulWidget {
  final List<Member> members;
  final List<_TripEntry> trips;
  final String? initialTripId;
  /// 若為 true，隱藏行程選擇器（從行程內部開啟時已知行程）
  final bool lockTrip;
  final void Function(ExpenseItem) onAdd;

  const _AddExpenseSheet(
      {required this.members, required this.trips,
       required this.onAdd, this.initialTripId, this.lockTrip = false});

  @override
  State<_AddExpenseSheet> createState() =>
      _AddExpenseSheetState();
}

class _AddExpenseSheetState
    extends State<_AddExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  String _selectedCategory = '餐飲';
  String _selectedPayerId = '';
  late Set<String> _selectedSplitIds;
  String _selectedIcon = 'ramen';
  bool _splitEvenly = true;
  String? _selectedTripId;

  final _categories = ['餐飲', '住宿', '交通', '門票', '購物', '其他'];

  static const _icons = [
    'ramen', 'lunch', 'cafe', 'dessert', 'tea', 'bar',
    'hotel', 'train', 'bus',  'ticket',  'shop', 'other',
  ];

  @override
  void initState() {
    super.initState();
    
    // 🌟 修正：讓預設付款人（代墊人）自動選擇「我」
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final me = widget.members.where((m) => m.uid == currentUserUid).firstOrNull;
    _selectedPayerId = me?.id ?? (widget.members.isNotEmpty ? widget.members[0].id : '');
    
    // 預設所有人一起平分
    _selectedSplitIds = widget.members.map((m) => m.id).toSet();
    _selectedTripId = widget.initialTripId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Widget _sheetTripChip(String? id, String name, String icon) {
    final sel = _selectedTripId == id;
    final primary = Theme.of(context).colorScheme.primary;
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return GestureDetector(
      onTap: () => setState(() => _selectedTripId = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? mist : AppColors.surfaceMoss,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? primary : AppColors.divider, width: sel ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_tripIconFromKey(icon), size: 13, color: sel ? primary : AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(name, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: sel ? primary : AppColors.textSecondary,
          )),
        ]),
      ),
    );
  }

  void _submit() {
    final amount = int.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0 ||
        _titleCtrl.text.trim().isEmpty) return;
    HapticFeedback.mediumImpact(); // ⑤ 新增消費觸覺

    final e = ExpenseItem(
      id: 'e${DateTime.now().millisecondsSinceEpoch}',
      icon: _selectedIcon,
      title: _titleCtrl.text.trim(),
      category: _selectedCategory,
      amount: amount,
      paidById: _selectedPayerId,
      splitMemberIds: _selectedSplitIds.toList(),
      date: DateTime.now(),
      tripId: _selectedTripId,
    );
    widget.onAdd(e);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final primaryMist = Color.lerp(primary, Colors.white, 0.88)!;
    final primaryLight = Color.lerp(primary, Colors.white, 0.35)!;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const Text('新增消費',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppColors.textPrimary)),

              const SizedBox(height: 20),

              // Amount – big
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryMist,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text('NT\$',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            color: primary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType:
                            TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter
                              .digitsOnly
                        ],
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                            color: primary),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                              color: primaryLight,
                              fontSize: 28,
                              fontWeight: FontWeight.w300),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        autofocus: true,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Title
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  hintText: '消費項目名稱',
                  prefixIcon: Icon(
                      Icons.receipt_outlined,
                      size: 18),
                ),
              ),

              const SizedBox(height: 14),

              // Trip selector（行程內開啟時隱藏，因為已知行程）
              if (widget.trips.isNotEmpty && !widget.lockTrip) ...[
                const _Label('所屬行程'),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _sheetTripChip(null, '未指定', 'list'),
                      ...widget.trips.map((t) => _sheetTripChip(t.id, t.name, t.icon)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Icon picker
              const _Label('選擇圖示'),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _icons.length,
                  itemBuilder: (_, i) {
                    final key = _icons[i];
                    final (iconData, iconColor) = _expIcon(key);
                    final sel = _selectedIcon == key;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedIcon = key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44, height: 44,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: sel ? iconColor.withValues(alpha: 0.15) : AppColors.surfaceMoss,
                          borderRadius: BorderRadius.circular(12),
                          border: sel ? Border.all(color: iconColor, width: 1.5) : null,
                        ),
                        child: Center(child: Icon(iconData, color: iconColor, size: 22)),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              // Category
              const _Label('消費分類'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _categories.map((cat) {
                  final sel = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? primary
                            : AppColors.surfaceMoss,
                        borderRadius:
                            BorderRadius.circular(20),
                        border: Border.all(
                          color: sel
                              ? primary
                              : AppColors.divider,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),

              // Payer
              const _Label('付款人'),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: widget.members.map((m) {
                    final sel = _selectedPayerId == m.id;
                    return GestureDetector(
                      onTap: () => setState(
                          () => _selectedPayerId = m.id),
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? primaryMist
                              : AppColors.surfaceMoss,
                          borderRadius:
                              BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? primary
                                : AppColors.divider,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMemberAvatar(context, m, radius: 12),
                            const SizedBox(width: 6),
                            Text(
                              m.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: sel
                                    ? primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 14),

              // Split
              Row(
                children: [
                  const _Label('分攤方式'),
                  const Spacer(),
                  Row(
                    children: [
                      const Text('全部平分',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint)),
                      const SizedBox(width: 6),
                      Switch(
                        value: _splitEvenly,
                        onChanged: (v) {
                          setState(() {
                            _splitEvenly = v;
                            if (v) {
                              _selectedSplitIds = widget
                                  .members
                                  .map((m) => m.id)
                                  .toSet();
                            }
                          });
                        },
                        activeColor: primary,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),

              if (!_splitEvenly) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: widget.members.map((m) {
                    final sel =
                        _selectedSplitIds.contains(m.id);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) {
                          _selectedSplitIds.remove(m.id);
                        } else {
                          _selectedSplitIds.add(m.id);
                        }
                      }),
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? primaryMist
                              : AppColors.surfaceMoss,
                          borderRadius:
                              BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? primary
                                : AppColors.divider,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (sel)
                              Icon(
                                  Icons.check_circle_rounded,
                                  size: 14,
                                  color: primary),
                            if (sel)
                              const SizedBox(width: 4),
                            _buildMemberAvatar(context, m, radius: 10),
                            const SizedBox(width: 4),
                            Text(m.name,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? primary
                                        : AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize:
                      const Size(double.infinity, 52),
                ),
                child: const Text('確認新增'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String icon;
  final String title;

  const _SectionTitle(
      {required this.icon, required this.title});

  static IconData _iconFromKey(String key) {
    switch (key) {
      case '🗂️': return Icons.folder_rounded;
      case '👤': return Icons.person_rounded;
      case '📅': return Icons.calendar_today_rounded;
      default:   return Icons.bar_chart_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_iconFromKey(icon), size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
