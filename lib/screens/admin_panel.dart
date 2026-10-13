import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart' show DoodleCircle, DoodleHeart, SlideUpFadeIn;
import '../services/admin_service.dart';

// ══════════════════════════════════════════════════════════════
// 入口：管理員身份驗證門衛
// ══════════════════════════════════════════════════════════════

class AdminGateScreen extends StatefulWidget {
  const AdminGateScreen({super.key});
  @override State<AdminGateScreen> createState() => _AdminGateScreenState();
}
class _AdminGateScreenState extends State<AdminGateScreen> {
  bool _checking = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await AdminService.isAdmin();
    if (mounted) setState(() { _checking = false; _isAdmin = ok; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.surface,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: () => Navigator.pop(context))),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_rounded, size: 64, color: AppColors.error.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          const Text('沒有管理員權限', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('請聯繫系統管理員', style: TextStyle(color: AppColors.textHint)),
        ])),
      );
    }
    return const AdminShell();
  }
}

// ══════════════════════════════════════════════════════════════
// Shell：底部導覽列
// ══════════════════════════════════════════════════════════════

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override State<AdminShell> createState() => _AdminShellState();
}
class _AdminShellState extends State<AdminShell> {
  int _tab = 0;
  static const _tabs = [
    (icon: Icons.dashboard_rounded,      label: '總覽'),
    (icon: Icons.place_rounded,          label: '景點'),
    (icon: Icons.campaign_rounded,       label: '通知'),
    (icon: Icons.report_rounded,         label: '舉報'),
    (icon: Icons.article_rounded,        label: '審核'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final pages = [
      const AdminDashboard(),
      const AdminSpotsScreen(),
      const AdminNotificationsScreen(),
      const AdminReportsScreen(),
      const AdminModerationScreen(),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          DoodleCircle(size: 22, color: primary.withValues(alpha: 0.2),
            child: Icon(Icons.admin_panel_settings_rounded, size: 14, color: primary)),
          const SizedBox(width: 8),
          Text(_tabs[_tab].label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: primary.withValues(alpha: 0.15),
        destinations: _tabs.map((t) => NavigationDestination(
          icon: Icon(t.icon),
          label: t.label,
        )).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 1. 總覽 Dashboard
// ══════════════════════════════════════════════════════════════

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override State<AdminDashboard> createState() => _AdminDashboardState();
}
class _AdminDashboardState extends State<AdminDashboard> {
  Map<String, int>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AdminService.fetchDashboardStats();
    if (mounted) setState(() { _stats = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return RefreshIndicator(
      onRefresh: () async { setState(() => _loading = true); await _load(); },
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _sectionHeader('系統狀態', Icons.bar_chart_rounded, primary),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    _statCard('使用者', '${_stats!['users']}', Icons.people_rounded, const Color(0xFF5B7CE8), primary),
                    _statCard('社群貼文', '${_stats!['posts']}', Icons.article_rounded, const Color(0xFF8FBF8F), primary),
                    _statCard('待處理舉報', '${_stats!['pendingReports']}', Icons.report_rounded,
                        _stats!['pendingReports']! > 0 ? AppColors.error : AppColors.textHint, primary),
                    _statCard('自訂景點', '${_stats!['customSpots']}', Icons.place_rounded, AppColors.accentTerra, primary),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionHeader('廣播歷史', Icons.history_rounded, primary),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot>(
                  stream: AdminService.watchBroadcasts(),
                  builder: (ctx, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return _emptyHint('尚未發送過廣播通知');
                    }
                    return Column(
                      children: docs.take(5).toList().asMap().entries.map((e) {
                        final d = e.value.data() as Map<String, dynamic>;
                        return SlideUpFadeIn(
                          index: e.key,
                          child: _broadcastTile(d, primary),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
        ]),
      ]),
    );
  }

  Widget _broadcastTile(Map<String, dynamic> d, Color primary) {
    final ts = d['sentAt'] as Timestamp?;
    final dt = ts?.toDate();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(children: [
        Icon(Icons.campaign_rounded, size: 20, color: primary.withValues(alpha: 0.6)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(d['body'] as String? ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        if (dt != null) Text('${dt.month}/${dt.day}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 2. 景點管理
// ══════════════════════════════════════════════════════════════

class AdminSpotsScreen extends StatefulWidget {
  const AdminSpotsScreen({super.key});
  @override State<AdminSpotsScreen> createState() => _AdminSpotsScreenState();
}
class _AdminSpotsScreenState extends State<AdminSpotsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override
  void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(children: [
      TabBar(
        controller: _tc,
        labelColor: primary,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: primary,
        tabs: const [Tab(text: '自訂景點'), Tab(text: '類別管理')],
      ),
      Expanded(child: TabBarView(controller: _tc, children: const [
        _CustomSpotsList(),
        _CategoryList(),
      ])),
    ]);
  }
}

class _CustomSpotsList extends StatelessWidget {
  const _CustomSpotsList();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('新增景點', style: TextStyle(color: Colors.white)),
        onPressed: () => _showSpotEditor(context),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: AdminService.watchCustomSpots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return _emptyHint('還沒有自訂景點\n點右下角 + 新增');
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return SlideUpFadeIn(
                index: i,
                child: _spotCard(ctx, docs[i].id, d, primary),
              );
            },
          );
        },
      ),
    );
  }

  Widget _spotCard(BuildContext context, String id, Map<String, dynamic> d, Color primary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 6)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: DoodleCircle(size: 44, color: primary.withValues(alpha: 0.15),
          child: Icon(Icons.place_rounded, color: primary, size: 20)),
        title: Text(d['name'] as String? ?? '(未命名)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(d['address'] as String? ?? '無地址',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(Icons.edit_rounded, size: 18, color: primary),
            onPressed: () => _showSpotEditor(context, id: id, existing: d),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, size: 18, color: AppColors.error),
            onPressed: () => _confirmDelete(context, id, d['name'] as String? ?? ''),
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String id, String name) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('確認刪除'),
      content: Text('確定要刪除景點「$name」嗎？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await AdminService.deleteCustomSpot(id);
          },
          child: const Text('刪除', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ));
  }
}

void _showSpotEditor(BuildContext context, {String? id, Map<String, dynamic>? existing}) {
  final nameCtrl    = TextEditingController(text: existing?['name'] as String? ?? '');
  final addrCtrl    = TextEditingController(text: existing?['address'] as String? ?? '');
  final descCtrl    = TextEditingController(text: existing?['description'] as String? ?? '');
  final phoneCtrl   = TextEditingController(text: existing?['phone'] as String? ?? '');
  final timeCtrl    = TextEditingController(text: existing?['openTime'] as String? ?? '');
  final latCtrl     = TextEditingController(text: '${existing?['lat'] ?? ''}');
  final lngCtrl     = TextEditingController(text: '${existing?['lng'] ?? ''}');
  String category   = existing?['category'] as String? ?? '景點';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setS) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx2).viewInsets.bottom + 20,
          ),
          child: ListView(controller: sc, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(id == null ? '新增景點' : '編輯景點',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            _fieldLabel('景點名稱 *'),
            _field(nameCtrl, '例：檜意森活村'),
            const SizedBox(height: 12),
            _fieldLabel('類別'),
            DropdownButtonFormField<String>(
              value: category,
              decoration: _inputDeco('選擇類別'),
              items: ['景點','美食','住宿','商店','活動','其他'].map((c) =>
                  DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) { if (v != null) setS(() => category = v); },
            ),
            const SizedBox(height: 12),
            _fieldLabel('地址'),
            _field(addrCtrl, '例：嘉義市東區林森西路2號'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _fieldLabel('緯度'),
                _field(latCtrl, '23.480', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _fieldLabel('經度'),
                _field(lngCtrl, '120.449', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ])),
            ]),
            const SizedBox(height: 12),
            _fieldLabel('電話'),
            _field(phoneCtrl, '05-XXX-XXXX', keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _fieldLabel('開放時間'),
            _field(timeCtrl, '09:00-17:00'),
            const SizedBox(height: 12),
            _fieldLabel('景點介紹'),
            TextField(
              controller: descCtrl,
              minLines: 3, maxLines: 6,
              decoration: _inputDeco('輸入景點介紹…'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx2).colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final data = {
                    'name': nameCtrl.text.trim(),
                    'category': category,
                    'address': addrCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'openTime': timeCtrl.text.trim(),
                    'lat': double.tryParse(latCtrl.text) ?? 0.0,
                    'lng': double.tryParse(lngCtrl.text) ?? 0.0,
                  };
                  if (id == null) {
                    await AdminService.addCustomSpot(data);
                  } else {
                    await AdminService.updateCustomSpot(id, data);
                  }
                  if (ctx2.mounted) Navigator.pop(ctx2);
                },
                child: Text(id == null ? '新增景點' : '儲存變更',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}

class _CategoryList extends StatelessWidget {
  const _CategoryList();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('新增類別', style: TextStyle(color: Colors.white)),
        onPressed: () => _showCategoryEditor(context),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: AdminService.watchCategories(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return _emptyHint('還沒有自訂類別');
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return SlideUpFadeIn(
                index: i,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: ListTile(
                    leading: DoodleCircle(size: 36, color: primary.withValues(alpha: 0.15),
                      child: Icon(Icons.label_rounded, color: primary, size: 16)),
                    title: Text(d['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_rounded, size: 18, color: AppColors.error),
                      onPressed: () => AdminService.deleteCategory(docs[i].id),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCategoryEditor(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新增類別'),
      content: TextField(
        controller: nameCtrl,
        decoration: const InputDecoration(hintText: '輸入類別名稱', border: OutlineInputBorder()),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(
          onPressed: () async {
            if (nameCtrl.text.trim().isEmpty) return;
            await AdminService.addCategory(nameCtrl.text.trim(), 'label', 99);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('新增'),
        ),
      ],
    ));
  }
}

// ══════════════════════════════════════════════════════════════
// 3. 廣播通知
// ══════════════════════════════════════════════════════════════

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});
  @override State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}
class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl  = TextEditingController();
  String _type = 'event';
  bool _sending = false;

  static const _types = [
    ('event',       '活動通知',   Icons.celebration_rounded,   Color(0xFFE8A87C)),
    ('social',      '社群動態',   Icons.thumb_up_rounded,      Color(0xFF8FBF8F)),
    ('achievement', '成就解鎖',   Icons.military_tech_rounded, Color(0xFFCFA84C)),
    ('nearby',      '附近資訊',   Icons.place_rounded,         Color(0xFFD4A8C7)),
  ];

  Future<void> _send() async {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('標題與內容不能空白'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _sending = true);
    try {
      final sent = await AdminService.broadcastNotification(
        title: _titleCtrl.text.trim(),
        body:  _bodyCtrl.text.trim(),
        type:  _type,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ 已發送給 $sent 位使用者'), behavior: SnackBarBehavior.floating));
        _titleCtrl.clear();
        _bodyCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('發送失敗：$e'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() { _titleCtrl.dispose(); _bodyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionHeader('廣播通知', Icons.campaign_rounded, primary),
        const SizedBox(height: 4),
        const Text('發送給所有已登入的使用者', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
        const SizedBox(height: 20),
        // 通知類型選擇
        const Text('通知類型', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: _types.map((t) {
            final selected = _type == t.$1;
            return ChoiceChip(
              selected: selected,
              avatar: Icon(t.$3, size: 14, color: selected ? Colors.white : t.$4),
              label: Text(t.$2),
              selectedColor: t.$4,
              labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _type = t.$1),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _fieldLabel('通知標題 *'),
        _field(_titleCtrl, '例：嘉義跨年活動開始報名囉！'),
        const SizedBox(height: 12),
        _fieldLabel('通知內容 *'),
        TextField(
          controller: _bodyCtrl,
          minLines: 4,
          maxLines: 8,
          decoration: _inputDeco('輸入通知詳細內容…'),
        ),
        const SizedBox(height: 20),
        // 預覽卡
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: primary.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.preview_rounded, size: 14, color: primary.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text('預覽', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: Listenable.merge([_titleCtrl, _bodyCtrl]),
              builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_titleCtrl.text.isEmpty ? '（標題）' : _titleCtrl.text,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(_bodyCtrl.text.isEmpty ? '（內容）' : _bodyCtrl.text,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, color: Colors.white),
            label: Text(_sending ? '發送中…' : '發送廣播通知',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _sending ? null : _send,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 4. 舉報管理
// ══════════════════════════════════════════════════════════════

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}
class _AdminReportsScreenState extends State<AdminReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override
  void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(children: [
      TabBar(
        controller: _tc,
        labelColor: primary,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: primary,
        tabs: const [Tab(text: '待處理'), Tab(text: '已處理')],
      ),
      Expanded(child: TabBarView(controller: _tc, children: [
        _ReportList(status: 'pending'),
        _ReportList(status: 'resolved'),
      ])),
    ]);
  }
}

class _ReportList extends StatelessWidget {
  final String status;
  const _ReportList({required this.status});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return StreamBuilder<QuerySnapshot>(
      stream: AdminService.watchReports(status: status),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _emptyHint(status == 'pending' ? '目前沒有待處理舉報 🎉' : '沒有已處理記錄');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final ts = d['createdAt'] as Timestamp?;
            final typeLabel = {'post': '貼文', 'comment': '留言', 'user': '使用者'}[d['type']] ?? '其他';
            return SlideUpFadeIn(
              index: i,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: status == 'pending'
                      ? AppColors.error.withValues(alpha: 0.3)
                      : AppColors.divider),
                  boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 6)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(typeLabel, style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d['reason'] as String? ?? '未說明原因',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                      if (ts != null) Text('${ts.toDate().month}/${ts.toDate().day}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    ]),
                  ),
                  if ((d['targetContent'] as String? ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceWarm,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(d['targetContent'] as String? ?? '',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  if (status == 'pending')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Row(children: [
                        Expanded(child: OutlinedButton.icon(
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('標記已解決'),
                          onPressed: () => AdminService.resolveReport(docs[i].id, action: 'resolved'),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton.icon(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('忽略舉報'),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.textHint),
                          onPressed: () => AdminService.resolveReport(docs[i].id, action: 'dismissed'),
                        )),
                      ]),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                      child: Row(children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text('${d['status'] == 'dismissed' ? '已忽略' : '已解決'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                      ]),
                    ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 5. 貼文審核
// ══════════════════════════════════════════════════════════════

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});
  @override State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}
class _AdminModerationScreenState extends State<AdminModerationScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override
  void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(children: [
      TabBar(
        controller: _tc,
        labelColor: primary,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: primary,
        tabs: const [Tab(text: '社群貼文'), Tab(text: '使用者管理')],
      ),
      Expanded(child: TabBarView(controller: _tc, children: const [
        _PostModerationList(),
        _UserManagementList(),
      ])),
    ]);
  }
}

class _PostModerationList extends StatelessWidget {
  const _PostModerationList();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return StreamBuilder<QuerySnapshot>(
      stream: AdminService.watchAllPosts(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _emptyHint('目前沒有貼文');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final images = List<String>.from(d['imageURLs'] ?? []);
            return SlideUpFadeIn(
              index: i,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 5)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundImage: (d['authorPhoto'] as String? ?? '').isNotEmpty
                          ? NetworkImage(d['authorPhoto'] as String) : null,
                      backgroundColor: primary.withValues(alpha: 0.15),
                      child: (d['authorPhoto'] as String? ?? '').isEmpty
                          ? Icon(Icons.person_rounded, size: 18, color: primary) : null,
                    ),
                    title: Text(d['authorName'] as String? ?? '匿名旅人',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: Text(_formatTs(d['createdAt']),
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                      tooltip: '刪除貼文',
                      onPressed: () => _confirmDeletePost(ctx, docs[i].id,
                          d['authorName'] as String? ?? ''),
                    ),
                  ),
                  if ((d['content'] as String? ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Text(d['content'] as String? ?? '',
                          style: const TextStyle(fontSize: 13, height: 1.4),
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                  if (images.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(images.first, height: 100, width: double.infinity, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Row(children: [
                      Icon(Icons.thumb_up_outlined, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text('${d['likeCount'] ?? 0}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                      const SizedBox(width: 12),
                      Icon(Icons.comment_outlined, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text('${d['commentCount'] ?? 0}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeletePost(BuildContext context, String postId, String author) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('刪除貼文', style: TextStyle(color: AppColors.error)),
      content: Text('確定要刪除 $author 的這篇貼文嗎？此操作無法撤回。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () async {
            Navigator.pop(ctx);
            await AdminService.adminDeletePost(postId);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('貼文已刪除'), behavior: SnackBarBehavior.floating));
            }
          },
          child: const Text('確認刪除', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }
}

class _UserManagementList extends StatelessWidget {
  const _UserManagementList();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return StreamBuilder<QuerySnapshot>(
      stream: AdminService.watchUsers(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _emptyHint('沒有使用者資料');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final isBanned = d['isBanned'] as bool? ?? false;
            final isAdmin  = d['isAdmin']  as bool? ?? false;
            final photoUrl = d['photoURL'] as String? ?? d['photoUrl'] as String? ?? '';
            return SlideUpFadeIn(
              index: i,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isBanned ? AppColors.error.withValues(alpha: 0.05) : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isBanned ? AppColors.error.withValues(alpha: 0.2) : AppColors.divider),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    backgroundColor: primary.withValues(alpha: 0.15),
                    child: photoUrl.isEmpty ? Icon(Icons.person_rounded, color: primary) : null,
                  ),
                  title: Row(children: [
                    Flexible(child: Text(d['displayName'] as String? ?? d['email'] as String? ?? '匿名',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
                    if (isAdmin) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: const Text('管理員', style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w700)),
                      ),
                    ],
                    if (isBanned) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                        child: const Text('已封禁', style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  subtitle: Text(d['email'] as String? ?? docs[i].id,
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint), overflow: TextOverflow.ellipsis),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.textHint),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'ban',
                          child: Text(isBanned ? '解除封禁' : '封禁使用者',
                              style: TextStyle(color: isBanned ? AppColors.success : AppColors.error))),
                      PopupMenuItem(value: 'admin',
                          child: Text(isAdmin ? '移除管理員' : '設為管理員',
                              style: const TextStyle(color: AppColors.info))),
                    ],
                    onSelected: (v) {
                      if (v == 'ban')   AdminService.banUser(docs[i].id, !isBanned);
                      if (v == 'admin') AdminService.setAdmin(docs[i].id, !isAdmin);
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 共用元件 / 工具
// ══════════════════════════════════════════════════════════════

Widget _sectionHeader(String title, IconData icon, Color primary) {
  return Row(children: [
    DoodleCircle(size: 28, color: primary.withValues(alpha: 0.15),
      child: Icon(icon, size: 14, color: primary)),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
  ]);
}

Widget _fieldLabel(String label) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
);

Widget _field(TextEditingController ctrl, String hint, {TextInputType? keyboardType}) => TextField(
  controller: ctrl,
  keyboardType: keyboardType,
  decoration: _inputDeco(hint),
);

InputDecoration _inputDeco(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: AppColors.divider),
  ),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  isDense: true,
);

Widget _emptyHint(String msg) => Center(
  child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.inbox_rounded, size: 48, color: AppColors.textHint.withValues(alpha: 0.4)),
    const SizedBox(height: 12),
    Text(msg, textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textHint, fontSize: 14, height: 1.6)),
  ]),
);

String _formatTs(dynamic ts) {
  if (ts == null) return '';
  if (ts is Timestamp) {
    final dt = ts.toDate();
    return '${dt.year}/${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')}';
  }
  return '';
}
