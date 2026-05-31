import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';

// ═══════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════

class Member {
  final String id;
  final String name;
  final String emoji;
  double balance; // 正 = 被欠；負 = 欠人

  Member({
    required this.id,
    required this.name,
    required this.emoji,
    this.balance = 0,
  });
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
  const ExpenseScreen({super.key, this.embedded = false});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Trips ──
  final List<_TripEntry> _trips = [
    _TripEntry(id: 'trip1', name: '嘉義週末輕旅行', icon: '🗓️'),
    _TripEntry(id: 'trip2', name: '親子阿里山一日遊', icon: '⛰️'),
  ];
  String? _selectedTripId;    // null = 全部
  String? _selectedCategory;  // null = 全部分類

  // ── Members ──
  final List<Member> _members = [
    Member(id: 'm1', name: '我', emoji: '🙋'),
    Member(id: 'm2', name: '小美', emoji: '👩'),
    Member(id: 'm3', name: '小明', emoji: '👦'),
    Member(id: 'm4', name: '阿強', emoji: '🧑'),
  ];

  // ── Expenses ──
  late List<ExpenseItem> _expenses;

  List<ExpenseItem> get _filteredExpenses {
    var list = _selectedTripId == null
        ? _expenses
        : _expenses.where((e) => e.tripId == _selectedTripId).toList();
    if (_selectedCategory != null) {
      list = list.where((e) => e.category == _selectedCategory).toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _expenses = _buildDummyExpenses();
  }

  List<ExpenseItem> _buildDummyExpenses() {
    final allIds = _members.map((m) => m.id).toList();
    return [
      ExpenseItem(
        id: 'e1', icon: '🏠', title: '民宿住宿（兩晚）',
        category: '住宿', amount: 3600,
        paidById: 'm3', splitMemberIds: allIds,
        date: DateTime(2025, 6, 7), tripId: 'trip1',
      ),
      ExpenseItem(
        id: 'e2', icon: '🚗', title: '租車費用',
        category: '交通', amount: 1800,
        paidById: 'm1', splitMemberIds: allIds,
        date: DateTime(2025, 6, 7), tripId: 'trip1',
      ),
      ExpenseItem(
        id: 'e3', icon: '🎫', title: '阿里山門票',
        category: '門票', amount: 800,
        paidById: 'm2', splitMemberIds: allIds,
        date: DateTime(2025, 5, 18), tripId: 'trip2',
      ),
      ExpenseItem(
        id: 'e4', icon: '🍜', title: '林聰明沙鍋魚頭午餐',
        category: '餐飲', amount: 680,
        paidById: 'm1', splitMemberIds: allIds,
        date: DateTime(2025, 6, 8), tripId: 'trip1',
      ),
      ExpenseItem(
        id: 'e5', icon: '🌙', title: '文化路夜市晚餐',
        category: '餐飲', amount: 520,
        paidById: 'm4', splitMemberIds: allIds,
        date: DateTime(2025, 6, 8), tripId: 'trip1',
      ),
      ExpenseItem(
        id: 'e6', icon: '🧃', title: '便利商店零食',
        category: '餐飲', amount: 240,
        paidById: 'm2', splitMemberIds: ['m1', 'm2', 'm3'],
        date: DateTime(2025, 6, 9), tripId: 'trip1',
      ),
      ExpenseItem(
        id: 'e7', icon: '🎁', title: '嘉義伴手禮',
        category: '購物', amount: 960,
        paidById: 'm3', splitMemberIds: allIds,
        date: DateTime(2025, 6, 9), tripId: 'trip1',
      ),
      ExpenseItem(
        id: 'e8', icon: '⛽', title: '加油費',
        category: '交通', amount: 450,
        paidById: 'm1', splitMemberIds: allIds,
        date: DateTime(2025, 6, 9), tripId: 'trip1',
      ),
      ExpenseItem(
        id: 'e9', icon: '🍱', title: '嘉義火雞肉飯午餐',
        category: '餐飲', amount: 320,
        paidById: 'm1', splitMemberIds: allIds,
        date: DateTime(2025, 5, 18), tripId: 'trip2',
      ),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Computed ──

  int get _totalAmount =>
      _filteredExpenses.fold(0, (sum, e) => sum + e.amount);

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
    return {
      for (final m in _members)
        m.id: (paid[m.id] ?? 0) - (should[m.id] ?? 0)
    };
  }

  List<Settlement> get _settlements {
    final balance = Map<String, int>.from(_memberBalance);
    final settlements = <Settlement>[];

    while (true) {
      final debtors = balance.entries
          .where((e) => e.value < -1)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final creditors = balance.entries
          .where((e) => e.value > 1)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (debtors.isEmpty || creditors.isEmpty) break;

      final debtor = debtors.first;
      final creditor = creditors.first;
      final amount = debtor.value.abs() < creditor.value
          ? debtor.value.abs()
          : creditor.value;

      settlements.add(Settlement(
        fromId: debtor.key,
        toId: creditor.key,
        amount: amount,
      ));

      balance[debtor.key] = balance[debtor.key]! + amount;
      balance[creditor.key] = balance[creditor.key]! - amount;
    }

    return settlements;
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
    // When embedded in trip detail, skip Scaffold+AppBar
    if (widget.embedded) {
      return Column(children: [
        Material(color: AppColors.surface, child: tabBar),
        Expanded(child: body),
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
              Text(
                _selectedTripId == null
                    ? '全部行程'
                    : _trips
                        .firstWhere((t) => t.id == _selectedTripId,
                            orElse: () => _TripEntry(
                                id: '', name: '全部行程', icon: '📋'))
                        .name,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 4),
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
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _tripPickerItem(null, '全部行程', '📋'),
            ..._trips.map((t) => _tripPickerItem(t.id, t.name, t.icon)),
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
          ],
        ),
      ),
    );
  }

  Widget _tripPickerItem(String? id, String name, String icon) {
    final isSelected = _selectedTripId == id;
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 20)),
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
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                setState(() => _trips.add(_TripEntry(
                  id: 'trip${DateTime.now().millisecondsSinceEpoch}',
                  name: name, icon: '🗓️',
                )));
              }
              Navigator.pop(context);
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseListTab() {
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
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('💰', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      _selectedTripId == null ? '尚無任何消費紀錄' : '此行程尚無消費紀錄',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    const Text('點下方「新增消費」開始記帳', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                  ]),
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
        orElse: () => Member(id: '', name: '?', emoji: '?'));
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
        setState(() => _expenses.removeWhere((x) => x.id == e.id));
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
              // Icon circle
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.13),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(e.icon,
                      style: const TextStyle(fontSize: 20)),
                ),
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
                          '${payer.emoji} ${payer.name} 付款',
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
                  const Text('💸',
                      style: TextStyle(fontSize: 20)),
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
                  const Text('🔄',
                      style: TextStyle(fontSize: 20)),
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
              if (settlements.isEmpty)
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
            '各人消費明細',
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surfaceMoss,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(m.emoji,
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
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
                  isPositive
                      ? (absVal == 0
                          ? '已結清 ✓'
                          : '應收 NT\$ $absVal')
                      : '應付 NT\$ $absVal',
                  style: TextStyle(
                    fontSize: 12,
                    color: absVal == 0
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
          // Balance bar
          _balanceBar(bal),
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
        orElse: () => Member(id: '', name: '?', emoji: '?'));
    final to = _members.firstWhere((m) => m.id == s.toId,
        orElse: () => Member(id: '', name: '?', emoji: '?'));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // From
          Column(children: [
            Text(from.emoji,
                style: const TextStyle(fontSize: 22)),
            Text(from.name,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ]),
          // Arrow + amount
          Expanded(
            child: Column(
              children: [
                Text(
                  'NT\$ ${s.amount}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.accentTerra,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                          height: 1.5,
                          color: AppColors.accentTerra
                              .withOpacity(0.3)),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded,
                          color: AppColors.accentTerra, size: 16),
                    ),
                    Expanded(
                      child: Container(
                          height: 1.5,
                          color: AppColors.accentTerra
                              .withOpacity(0.3)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('轉帳給',
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint)),
              ],
            ),
          ),
          // To
          Column(children: [
            Text(to.emoji,
                style: const TextStyle(fontSize: 22)),
            Text(to.name,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ]),
          // Mark done
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _markSettled(context, s, from, to),
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

  Widget _emptySettlement() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 40)),
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
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), shape: BoxShape.circle),
                child: Center(child: Text(m.emoji, style: const TextStyle(fontSize: 20))),
              ),
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
                          child: Center(child: Text(e.icon, style: const TextStyle(fontSize: 16)))),
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
                      Text(m.emoji,
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor:
                  AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayChart() {
    final dayTotals = <String, int>{};
    for (final e in _expenses) {
      final k =
          '${e.date.month}/${e.date.day}';
      dayTotals[k] = (dayTotals[k] ?? 0) + e.amount;
    }
    final keys = dayTotals.keys.toList()..sort();
    final maxVal =
        dayTotals.values.fold(0, (a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: keys.map((k) {
        final val = dayTotals[k]!;
        final ratio = maxVal > 0 ? val / maxVal : 0.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'NT\$$val',
                  style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  height: 80 * ratio + 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(k,
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ════════════════════════════════
  // DIALOGS / SHEETS
  // ════════════════════════════════

  void _showAddExpense(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(
        members: _members,
        trips: _trips,
        initialTripId: _selectedTripId,
        onAdd: (e) => setState(() => _expenses.insert(0, e)),
      ),
    );
  }

  void _showExpenseDetail(
      BuildContext context, ExpenseItem e) {
    final payer = _members.firstWhere((m) => m.id == e.paidById,
        orElse: () =>
            Member(id: '', name: '?', emoji: '?'));
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
                Text(e.icon,
                    style: const TextStyle(fontSize: 28)),
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
            _detailRow('付款人',
                '${payer.emoji} ${payer.name}'),
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
                        id: '', name: '?', emoji: '?'));
                return Builder(builder: (bCtx) {
                  final p = Theme.of(bCtx).colorScheme.primary;
                  return Chip(
                    label: Text('${m.emoji} ${m.name}'),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
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
              const Text('旅伴管理',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              ...(_members
                  .asMap()
                  .entries
                  .map((entry) => ListTile(
                        leading: Text(entry.value.emoji,
                            style: const TextStyle(
                                fontSize: 22)),
                        title: Text(entry.value.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        trailing: entry.key == 0
                            ? const Text('（我）',
                                style: TextStyle(
                                    color: AppColors.textHint,
                                    fontSize: 12))
                            : IconButton(
                                icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: AppColors.error),
                                onPressed: () {
                                  setState(() => _members
                                      .removeAt(entry.key));
                                  setLocal(() {});
                                },
                              ),
                      ))),
              const Divider(),
              TextButton.icon(
                onPressed: () =>
                    _showAddMember(context, setLocal),
                icon: Icon(Icons.person_add_outlined,
                    color: Theme.of(ctx).colorScheme.primary),
                label: const Text('新增旅伴'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMember(
      BuildContext context, StateSetter setLocal) {
    final emojis = [
      '😊','👩','👦','🧑','👴','👵','🧒','👶'
    ];
    String selectedEmoji = '😊';
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
              // Emoji picker
              Wrap(
                spacing: 8,
                children: emojis.map((e) {
                  return GestureDetector(
                    onTap: () =>
                        setDialog(() => selectedEmoji = e),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selectedEmoji == e
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                            : AppColors.surfaceMoss,
                        shape: BoxShape.circle,
                        border: selectedEmoji == e
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2)
                            : null,
                      ),
                      child: Center(
                          child: Text(e,
                              style: const TextStyle(
                                  fontSize: 20))),
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
                final m = Member(
                  id: 'm${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  emoji: selectedEmoji,
                );
                setState(() => _members.add(m));
                setLocal(() {});
              }
              Navigator.pop(context);
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  void _markSettled(BuildContext context, Settlement s,
      Member from, Member to) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '已標記 ${from.name} 轉帳 NT\$${s.amount} 給 ${to.name}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
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
// ADD EXPENSE SHEET
// ═══════════════════════════════════════════════

class _AddExpenseSheet extends StatefulWidget {
  final List<Member> members;
  final List<_TripEntry> trips;
  final String? initialTripId;
  final void Function(ExpenseItem) onAdd;

  const _AddExpenseSheet(
      {required this.members, required this.trips,
       required this.onAdd, this.initialTripId});

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
  String _selectedIcon = '🍜';
  bool _splitEvenly = true;
  String? _selectedTripId;

  final _categories = [
    '餐飲', '住宿', '交通', '門票', '購物', '其他'
  ];

  final _icons = [
    '🍜', '🏠', '🚗', '🎫', '🎁', '⛽',
    '🧃', '☕', '🍦', '🎭', '🌊', '📸',
  ];

  @override
  void initState() {
    super.initState();
    _selectedPayerId =
        widget.members.isNotEmpty ? widget.members[0].id : '';
    _selectedSplitIds =
        widget.members.map((m) => m.id).toSet();
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
          Text(icon, style: const TextStyle(fontSize: 13)),
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

              // Trip selector
              if (widget.trips.isNotEmpty) ...[
                const _Label('所屬行程'),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _sheetTripChip(null, '未指定', '📋'),
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
                    final ic = _icons[i];
                    final sel = _selectedIcon == ic;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedIcon = ic),
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? primaryMist
                              : AppColors.surfaceMoss,
                          borderRadius:
                              BorderRadius.circular(12),
                          border: sel
                              ? Border.all(
                                  color: primary,
                                  width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Text(ic,
                              style: const TextStyle(
                                  fontSize: 20)),
                        ),
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
                            Text(m.emoji,
                                style: const TextStyle(
                                    fontSize: 18)),
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
                            Text(m.emoji,
                                style: const TextStyle(
                                    fontSize: 16)),
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
  final String icon, title;

  const _SectionTitle(
      {required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
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
