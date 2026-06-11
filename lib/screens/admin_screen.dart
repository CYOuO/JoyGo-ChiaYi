import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';
import '../services/spot_service.dart';
import '../services/aws_s3_service.dart';

// ─────────────────────────────────────────────────────────────
// 管理員介面入口：驗證身份後才進入
// 管理員 UID 儲存於 Firestore admin_users/{uid} 文件
// ─────────────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _checking = true;
  bool _isAdmin   = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this);
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() { _checking = false; _isAdmin = false; }); return; }
    final doc = await FirebaseFirestore.instance.collection('admin_users').doc(uid).get();
    if (mounted) setState(() { _checking = false; _isAdmin = doc.exists; });
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('管理員介面')),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_rounded, size: 64, color: primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('無存取權限', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('此帳號不具備管理員權限', style: TextStyle(color: AppColors.textHint)),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
            child: Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: primary, letterSpacing: 2)),
          ),
          const SizedBox(width: 10),
          const Text('管理員介面', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        bottom: TabBar(
          controller: _tab,
          labelColor: primary,
          indicatorColor: primary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: EdgeInsets.zero,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded,      size: 18), text: '儀表板'),
            Tab(icon: Icon(Icons.people_rounded,         size: 18), text: '使用者'),
            Tab(icon: Icon(Icons.flag_rounded,           size: 18), text: '舉報'),
            Tab(icon: Icon(Icons.article_rounded,        size: 18), text: '內容'),
            Tab(icon: Icon(Icons.upload_file_rounded,    size: 18), text: '匯入/匯出'),
            Tab(icon: Icon(Icons.campaign_rounded,       size: 18), text: '推播'),
            Tab(icon: Icon(Icons.local_offer_rounded,    size: 18), text: '優惠券'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _DashboardTab(primary: primary),
          _UsersTab(primary: primary),
          _ReportsTab(primary: primary),
          _ContentTab(primary: primary),
          _ImportExportTab(primary: primary),
          _NotifyTab(primary: primary),
          _CouponTab(primary: primary),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 儀表板
// ═══════════════════════════════════════════════
class _DashboardTab extends StatefulWidget {
  final Color primary;
  const _DashboardTab({required this.primary});
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  final Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = FirebaseFirestore.instance;

    // Ensure SpotService cache is loaded
    if (SpotService.cached.isEmpty) {
      try { await SpotService.loadAllSpots(); } catch (_) {}
    }

    Future<int> countCol(String col) async {
      try {
        final snap = await db.collection(col).get();
        return snap.docs.length;
      } catch (_) { return -1; }
    }

    Future<int> countColWhere(String col, String field, dynamic val) async {
      try {
        final snap = await db.collection(col).where(field, isEqualTo: val).get();
        return snap.docs.length;
      } catch (_) { return -1; }
    }

    final results = await Future.wait([
      countCol('users').then((v) => MapEntry('users', v)),
      countCol('trips').then((v) => MapEntry('trips', v)),
      countColWhere('community_posts', 'type', 'trip').then((v) => MapEntry('posts_trip', v)),
      countCol('community_posts').then((v) => MapEntry('community_posts', v)),
      countCol('reports').then((v) => MapEntry('reports', v)),
      countCol('restaurants').then((v) => MapEntry('restaurants', v)),
    ]);
    final map = Map.fromEntries(results);
    // 討論區 = 全部貼文 - 行程分享
    final totalPosts = map['community_posts'] ?? 0;
    final tripPosts = map['posts_trip'] ?? 0;
    map['posts_discussion'] = (totalPosts >= 0 && tripPosts >= 0) ? totalPosts - tripPosts : -1;

    // Spots: use SpotService static data count (Firestore 'spots' col may be empty)
    map['spots'] = SpotService.cached.isNotEmpty ? SpotService.cached.length : -1;

    if (mounted) setState(() { _counts
      ..clear()
      ..addAll(map);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('資料統計', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p)),
        const SizedBox(height: 12),
        if (_loading) const Center(child: CircularProgressIndicator())
        else Wrap(spacing: 10, runSpacing: 10, children: [
          _statCard('用戶',     _counts['users']             ?? 0, Icons.person_rounded,        const Color(0xFF5C8EC1), p),
          _statCard('行程',     _counts['trips']             ?? 0, Icons.luggage_rounded,        const Color(0xFF7AAA8A), p),
          _statCard('討論區',   _counts['posts_discussion']  ?? 0, Icons.forum_rounded,          const Color(0xFFCB9E5A), p),
          _statCard('行程分享', _counts['posts_trip']        ?? 0, Icons.share_rounded,          const Color(0xFF5AAFCB), p),
          _statCard('舉報待處理',
            _counts['reports'] ?? 0,
            Icons.flag_rounded, const Color(0xFFB86878), p),
          _statCard('景點',     _counts['spots']             ?? 0, Icons.place_rounded,          const Color(0xFF8878B0), p),
          _statCard('餐廳',     _counts['restaurants']       ?? 0, Icons.restaurant_rounded,     const Color(0xFFD08878), p),
        ]),
      ]),
    );
  }

  Widget _statCard(String label, int count, IconData icon, Color color, Color p) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 8),
        Text(count >= 0 ? '$count' : '—',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
      ]),
    );
  }

  Widget _quickTile(IconData icon, String title, String sub, Color p, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.divider)),
      child: ListTile(
        leading: Icon(icon, color: p),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        onTap: onTap,
      ),
    );
  }

  Widget _codeHint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Text(text, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textSecondary)),
  );
}

// ═══════════════════════════════════════════════
// 舉報管理
// ═══════════════════════════════════════════════
class _ReportsTab extends StatelessWidget {
  final Color primary;
  const _ReportsTab({required this.primary});

  Future<void> _clearAllReports(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空全部舉報', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('確定要刪除所有舉報記錄？此操作無法還原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('確定清空', style: TextStyle(color: Color(0xFFB86878), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('reports').limit(500).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('已清空全部舉報'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('清空失敗：$e'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, size: 56, color: Colors.green.shade300),
            const SizedBox(height: 12),
            const Text('目前沒有舉報', style: TextStyle(fontWeight: FontWeight.w700)),
          ]));
        }
        return Column(children: [
          // 頂部工具列
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Text('共 ${docs.length} 筆舉報',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _clearAllReports(ctx),
                icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                label: const Text('清空全部', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB86878),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFB86878), width: 0.8)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final status = d['status'] as String? ?? 'pending';
                final isPending = status == 'pending';
                final type      = d['type']      as String? ?? '';
                final postId    = d['postId']    as String? ?? '';
                final commentId = d['commentId'] as String? ?? '';
                final targetId  = type == 'comment' ? '${postId}_$commentId' : postId;
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isPending
                        ? const Color(0xFFB86878).withValues(alpha: 0.4)
                        : AppColors.divider)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isPending ? const Color(0xFFB86878) : Colors.green)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            isPending ? '待處理' : (status == 'resolved' ? '已處理' : '已忽略'),
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: isPending ? const Color(0xFFB86878) : Colors.green),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_typeLabel(type),
                          style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(_formatTime(d['createdAt']),
                          style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                      ]),
                      const SizedBox(height: 8),
                      _ReporterInfo(reportedBy: d['reportedBy'] as String? ?? '', primary: primary),
                      const SizedBox(height: 4),
                      Text('舉報原因：${d['reason'] ?? '（無）'}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      _ReportedContentPreview(
                        targetType: type,
                        targetId:   targetId,
                        primary: primary,
                        onContentMissing: isPending ? () async {
                          await docs[i].reference.delete();
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('已刪除此筆舉報（原始內容不存在）'),
                              behavior: SnackBarBehavior.floating));
                        } : null,
                      ),
                      if (isPending) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          _actionBtn('刪除內容', const Color(0xFFB86878), () async {
                            await _deleteTarget(ctx, d);
                            await docs[i].reference.update({'status': 'resolved'});
                          }),
                          const SizedBox(width: 8),
                          _actionBtn('忽略舉報', Colors.grey, () async {
                            await docs[i].reference.update({'status': 'dismissed'});
                          }),
                        ]),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  String _typeLabel(String type) => switch (type) {
    'post'    => '社群貼文',
    'comment' => '留言',
    'user'    => '用戶',
    _         => type,
  };

  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }

  Future<void> _deleteTarget(BuildContext ctx, Map<String, dynamic> d) async {
    final type      = d['type']      as String? ?? '';
    final postId    = d['postId']    as String? ?? '';
    final commentId = d['commentId'] as String? ?? '';
    final id = type == 'comment' ? '${postId}_$commentId' : postId;
    if (id.isEmpty) return;
    try {
      if (type == 'post') {
        await FirebaseFirestore.instance.collection('community_posts').doc(id).delete();
      } else if (type == 'comment') {
        // comments 是 community_posts/{postId}/comments/{id}
        // targetId 格式：{postId}_{commentId}
        final parts = id.split('_');
        if (parts.length >= 2) {
          await FirebaseFirestore.instance
              .collection('community_posts').doc(parts[0])
              .collection('comments').doc(parts[1]).delete();
        }
      }
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('內容已刪除'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('刪除失敗：$e'), behavior: SnackBarBehavior.floating));
    }
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35))),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }
}

// ── 舉報內容預覽（動態從 Firestore 讀取被舉報的貼文/留言） ──────────
// ─── 舉報者資訊（從 Firestore users/{uid} 取暱稱）────────────────
class _ReporterInfo extends StatefulWidget {
  final String reportedBy;
  final Color primary;
  const _ReporterInfo({required this.reportedBy, required this.primary});
  @override State<_ReporterInfo> createState() => _ReporterInfoState();
}

class _ReporterInfoState extends State<_ReporterInfo> {
  String? _name;

  @override
  void initState() {
    super.initState();
    if (widget.reportedBy.isNotEmpty) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(widget.reportedBy).get();
      if (doc.exists) {
        final d = doc.data()!;
        final nick = (d['nickname'] as String? ?? '').trim();
        final disp = (d['displayName'] as String? ?? '').trim();
        final email = (d['email'] as String? ?? '').trim();
        if (mounted) setState(() =>
          _name = nick.isNotEmpty ? nick
              : disp.isNotEmpty ? disp
              : email.isNotEmpty ? email.split('@').first : null);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reportedBy.isEmpty) return const SizedBox.shrink();
    final displayName = _name != null
        ? _name!
        : (_name == null && widget.reportedBy.isNotEmpty ? '載入中…' : '未知用戶');
    return Row(children: [
      Icon(Icons.person_rounded, size: 13, color: widget.primary.withValues(alpha: 0.7)),
      const SizedBox(width: 4),
      Expanded(child: Text(
        '舉報者：$displayName',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: widget.primary.withValues(alpha: 0.85)),
        overflow: TextOverflow.ellipsis,
      )),
    ]);
  }
}

class _ReportedContentPreview extends StatefulWidget {
  final String targetType;
  final String targetId;
  final Color primary;
  // 當原始內容不存在時的回調（僅待處理狀態才傳入）
  final VoidCallback? onContentMissing;
  const _ReportedContentPreview({
    required this.targetType,
    required this.targetId,
    required this.primary,
    this.onContentMissing,
  });
  @override
  State<_ReportedContentPreview> createState() => _ReportedContentPreviewState();
}

class _ReportedContentPreviewState extends State<_ReportedContentPreview> {
  String? _content;
  String? _author;
  List<String> _images = [];
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (widget.targetId.isEmpty) {
      if (mounted) setState(() { _loading = false; _notFound = true; });
      return;
    }
    try {
      if (widget.targetType == 'post') {
        final doc = await FirebaseFirestore.instance
            .collection('community_posts').doc(widget.targetId).get();
        if (doc.exists) {
          final d = doc.data()!;
          _content = (d['content'] as String? ?? '').isNotEmpty
              ? d['content'] as String
              : (d['title'] as String? ?? '');
          _author  = (d['authorName'] as String? ?? '').trim();
          if (_author!.isEmpty) {
            final authorId = d['authorId'] as String? ?? '';
            if (authorId.isNotEmpty) {
              final uDoc = await FirebaseFirestore.instance.collection('users').doc(authorId).get();
              final ud = uDoc.data() ?? {};
              final nick = (ud['nickname'] as String? ?? '').trim();
              final disp = (ud['displayName'] as String? ?? '').trim();
              _author = nick.isNotEmpty ? nick : disp.isNotEmpty ? disp : '匿名';
            }
          }
          _images = (d['imageURLs'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        } else {
          _notFound = true;
        }
      } else if (widget.targetType == 'comment') {
        final parts = widget.targetId.split('_');
        if (parts.length >= 2) {
          final doc = await FirebaseFirestore.instance
              .collection('community_posts').doc(parts[0])
              .collection('comments').doc(parts[1]).get();
          if (doc.exists) {
            final d = doc.data()!;
            _content = (d['text'] as String? ?? '').isNotEmpty
                ? d['text'] as String
                : (d['content'] as String? ?? '');
            _author = (d['authorName'] as String? ?? '').isNotEmpty
                ? d['authorName'] as String
                : (d['displayName'] as String? ?? '');
            final imgUrl = d['imageUrl'] as String? ?? '';
            _images = imgUrl.isNotEmpty ? [imgUrl] : [];
          } else {
            _notFound = true;
          }
        } else {
          _notFound = true;
        }
      }
    } catch (_) {
      _notFound = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
    );

    // 原始內容已不存在（被刪除或從未存在）
    if (_notFound || ((_content == null || _content!.isEmpty) && _images.isEmpty)) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200)),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 14, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text('原始內容已不存在（可能已被刪除）',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w600))),
          if (widget.onContentMissing != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: widget.onContentMissing,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade300)),
                child: Text('刪除此舉報',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
              ),
            ),
          ],
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_author != null && _author!.isNotEmpty)
          Row(children: [
            const Icon(Icons.person_pin_rounded, size: 13, color: Color(0xFFB86878)),
            const SizedBox(width: 4),
            Expanded(child: Text('被舉報者：$_author',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB86878)))),
          ]),
        if (_content != null && _content!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('內容：', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textHint)),
          const SizedBox(height: 2),
          Text(_content!, maxLines: 5, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
        ],
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, j) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(_images[j],
                  width: 80, height: 80, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80, height: 80, color: AppColors.divider,
                    child: const Icon(Icons.broken_image_outlined, size: 22))),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════
// 內容管理（貼文 + 留言刪除）
// ═══════════════════════════════════════════════
class _ContentTab extends StatefulWidget {
  final Color primary;
  const _ContentTab({required this.primary});
  @override
  State<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<_ContentTab> {
  String _query = '';
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return Column(children: [
      Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            hintText: '搜尋貼文標題或作者名稱',
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            filled: true, fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            suffixIcon: _query.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () { _ctrl.clear(); setState(() => _query = ''); })
                : null,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('community_posts')
              .orderBy('createdAt', descending: true)
              .limit(200)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            var docs = snap.data?.docs ?? [];
            if (_query.isNotEmpty) {
              final q = _query.toLowerCase();
              docs = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['title'] as String? ?? '').toLowerCase().contains(q) ||
                    (data['authorName'] as String? ?? '').toLowerCase().contains(q);
              }).toList();
            }
            if (docs.isEmpty) return const Center(child: Text('無符合的貼文'));
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.divider)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    title: Text(d['title'] as String? ?? '（無標題）',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('作者：${d['authorName'] ?? '—'}  ·  類型：${d['type'] ?? '—'}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                      if ((d['content'] as String? ?? '').isNotEmpty)
                        Text(d['content'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      // 查看留言
                      IconButton(
                        icon: Icon(Icons.comment_rounded, size: 18, color: p.withValues(alpha: 0.7)),
                        tooltip: '查看留言',
                        onPressed: () => _showComments(ctx, docs[i].id, d['title'] as String? ?? '', p),
                      ),
                      // 刪除貼文
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFB86878)),
                        tooltip: '刪除貼文',
                        onPressed: () => _confirmDelete(ctx, '確定刪除此貼文？此操作不可恢復。', () async {
                          await FirebaseFirestore.instance.collection('community_posts').doc(docs[i].id).delete();
                        }),
                      ),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  void _showComments(BuildContext ctx, String postId, String postTitle, Color p) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(ctx).size.height * 0.65,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              Expanded(child: Text('留言：$postTitle',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('community_posts').doc(postId)
                  .collection('comments')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                final comments = snap.data?.docs ?? [];
                if (comments.isEmpty) return const Center(child: Text('沒有留言'));
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: comments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = comments[i].data() as Map<String, dynamic>;
                    // 留言文字欄位是 text
                    final text = (c['text'] as String? ?? '').isNotEmpty
                        ? c['text'] as String
                        : (c['content'] as String? ?? '');
                    final author = (c['authorName'] as String? ?? '').isNotEmpty
                        ? c['authorName'] as String
                        : (c['displayName'] as String? ?? '匿名');
                    // 留言圖片欄位是 imageUrl（單一字串）
                    final imgUrl = c['imageUrl'] as String? ?? '';
                    final images = imgUrl.isNotEmpty ? [imgUrl] : <String>[];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(author, style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          if (text.isNotEmpty)
                            Text(text, style: const TextStyle(fontSize: 13)),
                          if (images.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 70,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: images.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 6),
                                itemBuilder: (_, j) => ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(images[j],
                                    width: 70, height: 70, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 70, height: 70,
                                      color: AppColors.divider,
                                      child: const Icon(Icons.broken_image_outlined, size: 20))),
                                ),
                              ),
                            ),
                          ],
                          if (text.isEmpty && images.isEmpty)
                            const Text('（無內容）', style: TextStyle(
                              fontSize: 12, color: AppColors.textHint, fontStyle: FontStyle.italic)),
                        ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFB86878)),
                          onPressed: () => _confirmDelete(ctx, '確定刪除此留言？', () async {
                            await comments[i].reference.delete();
                          }),
                        ),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, String msg, Future<void> Function() action) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('確認刪除', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await action();
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('已刪除'), behavior: SnackBarBehavior.floating));
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('刪除失敗：$e'), behavior: SnackBarBehavior.floating));
              }
            },
            child: const Text('刪除', style: TextStyle(color: Color(0xFFB86878))),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 推播通知
// ═══════════════════════════════════════════════
class _NotifyTab extends StatefulWidget {
  final Color primary;
  const _NotifyTab({required this.primary});
  @override
  State<_NotifyTab> createState() => _NotifyTabState();
}

class _NotifyTabState extends State<_NotifyTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl  = TextEditingController();
  bool _sending = false;

  // ── 寫入 broadcasts 集合，由 Cloud Functions 自動發送 FCM ──
  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body  = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) return;

    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('broadcasts').add({
        'title':     title,
        'body':      body,
        'sentBy':    FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'fcmSent':   false,  // Cloud Functions 發送後會更新為 true
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('通知已排入發送佇列，Cloud Functions 正在處理'),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: widget.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _titleCtrl.clear();
      _bodyCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('錯誤：$e'), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() { _titleCtrl.dispose(); _bodyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        const SizedBox(height: 20),
        Text('發送全體通知', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p)),
        const SizedBox(height: 4),
        const Text('發送至所有訂閱推播的用戶', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
        const SizedBox(height: 14),

        _field('通知標題', _titleCtrl, maxLines: 1),
        const SizedBox(height: 10),
        _field('通知內容', _bodyCtrl, maxLines: 3),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(_sending ? '發送中…' : '發送通知'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: p,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
        ),

        const SizedBox(height: 28),

        // ── 發送記錄（從 broadcasts 集合讀取）──────────────────
        Text('發送記錄', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('broadcasts')
              .orderBy('createdAt', descending: true)
              .limit(20)
              .snapshots(),
          builder: (_, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('尚無發送記錄', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
              );
            }
            return Column(
              children: docs.map((d) {
                final data = d.data() as Map<String, dynamic>;
                final ts      = data['createdAt'] as Timestamp?;
                final fcmSent = data['fcmSent']   as bool? ?? false;
                final hasErr  = data['fcmError']  != null;

                // 狀態圖示
                Widget statusIcon;
                if (hasErr) {
                  statusIcon = const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error);
                } else if (fcmSent) {
                  statusIcon = Icon(Icons.check_circle_rounded, size: 16, color: p);
                } else {
                  statusIcon = const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.textHint));
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    statusIcon,
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(data['title'] as String? ?? '',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(data['body'] as String? ?? '',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                      if (hasErr) ...[
                        const SizedBox(height: 4),
                        Text('發送失敗：${data['fcmError']}',
                          style: const TextStyle(fontSize: 10, color: AppColors.error)),
                      ],
                    ])),
                    if (ts != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${ts.toDate().month}/${ts.toDate().day}\n${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 9, color: AppColors.textHint, height: 1.4)),
                    ],
                  ]),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _field(String hint, TextEditingController ctrl, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 優惠券管理
// ═══════════════════════════════════════════════
class _CouponTab extends StatefulWidget {
  final Color primary;
  const _CouponTab({required this.primary});
  @override
  State<_CouponTab> createState() => _CouponTabState();
}

class _CouponTabState extends State<_CouponTab> {
  final _titleCtrl = TextEditingController();
  final _codeCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController();
  String _type = 'percent'; // 'percent' | 'fixed'
  DateTime? _expiresAt;
  bool _saving = false;

  // 預設顏色選項
  static const _colorOptions = [
    '#88B8C8', '#7AAA8A', '#CB9E5A', '#B86878', '#8878B0', '#5AAFCB',
  ];
  String _selectedColor = '#88B8C8';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    final code  = _codeCtrl.text.trim().toUpperCase();
    final desc  = _descCtrl.text.trim();
    final value = double.tryParse(_valueCtrl.text.trim());
    final maxUses = int.tryParse(_maxUsesCtrl.text.trim()) ?? 9999;
    if (title.isEmpty || code.isEmpty || value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填寫名稱、優惠碼與折扣值'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _saving = true);
    final autoDesc = desc.isEmpty ? (_type == 'percent' ? '折扣 $value%' : '折抵 NT\$$value') : desc;
    try {
      await FirebaseFirestore.instance.collection('coupons').doc(code).set({
        // 共用欄位（profile_screen 讀取）
        'title':      title,
        'desc':       autoDesc,
        'couponCode': code,
        'colorHex':   _selectedColor,
        'iconName':   'local_offer',
        'expiryDate': _expiresAt != null ? Timestamp.fromDate(_expiresAt!) : null,
        'maxUses':    maxUses,
        'usedCount':  0,
        // 舊欄位（admin 列表讀取）
        'code':        code,
        'type':        _type,
        'value':       value,
        'description': autoDesc,
        'isActive':    true,
        'expiresAt':   _expiresAt != null ? Timestamp.fromDate(_expiresAt!) : null,
        'createdAt':   FieldValue.serverTimestamp(),
        'createdBy':   FirebaseAuth.instance.currentUser?.uid,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 優惠券「$code」已建立'), behavior: SnackBarBehavior.floating));
        _titleCtrl.clear();
        _codeCtrl.clear();
        _descCtrl.clear();
        _valueCtrl.clear();
        _maxUsesCtrl.clear();
        setState(() { _expiresAt = null; _selectedColor = '#88B8C8'; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('建立失敗：$e'), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(String code, bool current) async {
    await FirebaseFirestore.instance.collection('coupons').doc(code)
        .update({'isActive': !current});
  }

  Future<void> _delete(String code) async {
    await FirebaseFirestore.instance.collection('coupons').doc(code).delete();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('優惠券已刪除'), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── 建立優惠券 ──────────────────────────────────
        Text('新增優惠券', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 名稱（顯示給使用者看）
            _adminField('優惠券名稱（例：夏季九折優惠）', _titleCtrl),
            const SizedBox(height: 10),
            // 優惠碼
            _adminField('優惠碼（例：WELCOME20）', _codeCtrl),
            const SizedBox(height: 10),
            // 折扣類型
            Row(children: [
              const Text('折扣類型', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              _typeBtn('percent', '百分比折扣', p),
              const SizedBox(width: 8),
              _typeBtn('fixed', '固定折抵', p),
            ]),
            const SizedBox(height: 10),
            // 折扣值
            _adminField(
              _type == 'percent' ? '折扣百分比（例：20 = 八折）' : '折抵金額（NT\$）',
              _valueCtrl,
              inputType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            // 使用上限
            _adminField('使用上限（不填則無限制）', _maxUsesCtrl, inputType: TextInputType.number),
            const SizedBox(height: 10),
            // 說明
            _adminField('優惠說明（選填）', _descCtrl),
            const SizedBox(height: 10),
            // 顏色選擇
            const Text('主題色彩', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: _colorOptions.map((hex) {
              final c = Color(int.parse('FF${hex.substring(1)}', radix: 16));
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = hex),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedColor == hex ? Colors.black54 : Colors.transparent,
                      width: 2.5)),
                ),
              );
            }).toList()),
            const SizedBox(height: 10),
            // 到期日
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2030),
                  helpText: '選擇到期日',
                );
                if (d != null) setState(() => _expiresAt = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider)),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: p),
                  const SizedBox(width: 8),
                  Text(
                    _expiresAt != null
                        ? '到期日：${_expiresAt!.year}/${_expiresAt!.month}/${_expiresAt!.day}'
                        : '設定到期日（選填，不設則永久有效）',
                    style: TextStyle(
                      fontSize: 13,
                      color: _expiresAt != null ? AppColors.textPrimary : AppColors.textHint),
                  ),
                  if (_expiresAt != null) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _expiresAt = null),
                      child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textHint)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _create,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_rounded, size: 16),
                label: Text(_saving ? '建立中…' : '建立優惠券'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 24),

        // ── 現有優惠券列表 ────────────────────────────
        Text('現有優惠券', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p)),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('coupons')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('尚無優惠券', style: TextStyle(color: AppColors.textHint))),
              );
            }
            return Column(children: docs.map<Widget>((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final code     = d['code']     as String? ?? doc.id;
              final type     = d['type']     as String? ?? 'percent';
              final value    = (d['value']   as num?)?.toDouble() ?? 0;
              final desc     = d['description'] as String? ?? '';
              final isActive = d['isActive'] as bool? ?? true;
              final expTs    = d['expiresAt'] as Timestamp?;
              final isExpired = expTs != null && expTs.toDate().isBefore(DateTime.now());

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isActive && !isExpired
                        ? p.withValues(alpha: 0.3)
                        : AppColors.divider)),
                child: Row(children: [
                  // 票券圖示
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: (isActive && !isExpired ? p : AppColors.textHint)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Icon(
                      Icons.local_offer_rounded,
                      size: 20,
                      color: isActive && !isExpired ? p : AppColors.textHint)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(code, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isExpired ? AppColors.error : (isActive ? p : AppColors.textHint))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          isExpired ? '已過期' : (isActive ? '啟用中' : '已停用'),
                          style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            color: isExpired ? AppColors.error : (isActive ? p : AppColors.textHint))),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      type == 'percent' ? '折扣 $value%' : '折抵 NT\$$value',
                      style: TextStyle(fontSize: 12, color: p, fontWeight: FontWeight.w700)),
                    if (desc.isNotEmpty)
                      Text(desc, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    if (expTs != null) Text(
                      '到期：${expTs.toDate().year}/${expTs.toDate().month}/${expTs.toDate().day}',
                      style: TextStyle(fontSize: 10, color: isExpired ? AppColors.error : AppColors.textHint)),
                  ])),
                  // 操作按鈕
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () => _toggleActive(code, isActive),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isActive ? Colors.orange : Colors.green).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (isActive ? Colors.orange : Colors.green).withValues(alpha: 0.35))),
                        child: Text(
                          isActive ? '停用' : '啟用',
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: isActive ? Colors.orange.shade700 : Colors.green.shade700)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _delete(code),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.30))),
                        child: const Text('刪除',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error)),
                      ),
                    ),
                  ]),
                ]),
              );
            }).toList());
          },
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _typeBtn(String value, String label, Color p) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? p.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? p : AppColors.divider)),
        child: Text(label,
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? p : AppColors.textSecondary)),
      ),
    );
  }

  Widget _adminField(String hint, TextEditingController ctrl,
      {TextInputType inputType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: inputType,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12),
        filled: true, fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 使用者帳號管理
// ═══════════════════════════════════════════════
class _UsersTab extends StatefulWidget {
  final Color primary;
  const _UsersTab({required this.primary});
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _db   = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _adminUids = {};
  bool _adminLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  Future<void> _loadAdmins() async {
    final snap = await _db.collection('admin_users').get();
    if (mounted) setState(() {
      _adminUids.addAll(snap.docs.map((d) => d.id));
      _adminLoaded = true;
    });
  }

  Future<void> _toggleAdmin(String uid, bool isAdmin) async {
    if (isAdmin) {
      await _db.collection('admin_users').doc(uid).delete();
    } else {
      await _db.collection('admin_users').doc(uid).set({'grantedAt': FieldValue.serverTimestamp()});
    }
    if (mounted) setState(() {
      if (isAdmin) _adminUids.remove(uid); else _adminUids.add(uid);
    });
  }

  Future<void> _toggleDisabled(String uid, bool disabled) async {
    final newDisabled = !disabled;
    // disabled=true 時同步設定 isBanned=true（禁言），解除時一併清除
    await _db.collection('users').doc(uid).update({
      'disabled': newDisabled,
      'isBanned': newDisabled,
    });
  }

  void _showDetail(BuildContext context, Map<String, dynamic> data, String uid) {
    final p = widget.primary;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: (data['photoUrl'] ?? '').isNotEmpty
                  ? NetworkImage(data['photoUrl'] as String) : null,
              backgroundColor: p.withValues(alpha: 0.15),
              child: (data['photoUrl'] ?? '').isEmpty
                  ? Icon(Icons.person_rounded, color: p) : null,
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(() {
                final n = data['displayName'] as String? ?? '';
                final e = data['email'] as String? ?? '';
                return n.isNotEmpty ? n : (e.isNotEmpty ? e.split('@').first : '(無名稱)');
              }(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text(data['email'] ?? '',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ])),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          _detailRow('UID', uid),
          _detailRow('電子郵件', data['email'] ?? '—'),
          _detailRow('顯示名稱', data['displayName'] ?? '—'),
          _detailRow('帳號狀態', (data['disabled'] == true) ? '🔒 已停用' : '✅ 正常'),
          _detailRow('管理員', _adminUids.contains(uid) ? '⭐ 是' : '否'),
          if (data['createdAt'] != null)
            _detailRow('加入日期',
              (data['createdAt'] as Timestamp).toDate().toString().substring(0, 10)),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _actionBtn(
              icon: _adminUids.contains(uid) ? Icons.star_rounded : Icons.star_border_rounded,
              label: _adminUids.contains(uid) ? '撤銷管理員' : '設為管理員',
              color: const Color(0xFFCB9E5A),
              onTap: () { Navigator.pop(context); _toggleAdmin(uid, _adminUids.contains(uid)); },
            )),
            const SizedBox(width: 10),
            Expanded(child: _actionBtn(
              icon: (data['disabled'] == true) ? Icons.lock_open_rounded : Icons.block_rounded,
              label: (data['disabled'] == true) ? '解除停用' : '停用帳號',
              color: const Color(0xFFB86878),
              onTap: () { Navigator.pop(context); _toggleDisabled(uid, data['disabled'] == true); },
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80,
        child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textHint, fontWeight: FontWeight.w700))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]),
  );

  Widget _actionBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: '搜尋姓名或電子郵件…',
            hintStyle: const TextStyle(fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            suffixIcon: _query.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 16),
                    onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })
                : null,
            filled: true, fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
          ),
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('users').orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData || !_adminLoaded) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs.where((d) {
              if (_query.isEmpty) return true;
              final data = d.data() as Map<String, dynamic>;
              final name  = (data['displayName'] ?? '').toString().toLowerCase();
              final email = (data['email'] ?? '').toString().toLowerCase();
              return name.contains(_query) || email.contains(_query);
            }).toList();
            if (docs.isEmpty) {
              return Center(child: Text('找不到符合的用戶',
                style: const TextStyle(color: AppColors.textHint)));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final uid  = docs[i].id;
                final data = docs[i].data() as Map<String, dynamic>;
                final isAdmin    = _adminUids.contains(uid);
                final isDisabled = data['disabled'] == true;
                final email = data['email']       as String? ?? '';
                final photo = data['photoUrl']    as String? ?? '';
                // 優先暱稱 → displayName → email 前綴
                final nickname    = (data['nickname']     as String? ?? '').trim();
                final displayName = (data['displayName']  as String? ?? '').trim();
                final name = nickname.isNotEmpty ? nickname
                    : displayName.isNotEmpty ? displayName
                    : email.isNotEmpty ? email.split('@').first : '(無名稱)';
                return GestureDetector(
                  onTap: () => _showDetail(context, data, uid),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDisabled
                        ? Colors.red.withValues(alpha: 0.25)
                        : AppColors.divider)),
                    child: Row(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                          backgroundColor: p.withValues(alpha: 0.15),
                          child: photo.isEmpty ? Icon(Icons.person_rounded, size: 18, color: p) : null,
                        ),
                        if (isAdmin) Positioned(
                          right: -3, bottom: -3,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Color(0xFFCB9E5A), shape: BoxShape.circle),
                            child: const Icon(Icons.star_rounded, size: 10, color: Colors.white),
                          ),
                        ),
                      ]),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (isDisabled) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6)),
                            child: const Text('停用', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w700)),
                          ),
                          if (isAdmin) Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Color(0xFFCB9E5A).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6)),
                            child: const Text('管理員', style: TextStyle(fontSize: 10, color: Color(0xFFCB9E5A), fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(email.isNotEmpty ? email : uid,
                          style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textHint),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════
// 資料匯入 / 匯出備份
// ═══════════════════════════════════════════════
class _ImportExportTab extends StatefulWidget {
  final Color primary;
  const _ImportExportTab({required this.primary});
  @override
  State<_ImportExportTab> createState() => _ImportExportTabState();
}

class _ImportExportTabState extends State<_ImportExportTab> {
  final _db = FirebaseFirestore.instance;

  // ── 匯入 ─────────────────────────────────────
  final _importCtrl = TextEditingController();
  String _importTarget = 'spots';
  bool _importing = false;
  String? _importMsg;

  // ── 匯出 ─────────────────────────────────────
  final Map<String, bool> _exportLoading = {};
  String? _exportResult;

  final _exportCollections = const [
    ('users',           '用戶資料',  Icons.person_rounded),
    ('trips',           '行程資料',  Icons.luggage_rounded),
    ('community_posts', '社群貼文',  Icons.article_rounded),
    ('spots',           '景點資料',  Icons.place_rounded),
    ('restaurants',     '餐廳資料',  Icons.restaurant_rounded),
    ('reports',         '舉報記錄',  Icons.flag_rounded),
  ];

  Future<void> _doImport() async {
    final raw = _importCtrl.text.trim();
    if (raw.isEmpty) { setState(() => _importMsg = '❌ 請貼上 JSON 資料'); return; }
    List<dynamic> list;
    try {
      final decoded = jsonDecode(raw);
      list = decoded is List ? decoded : [decoded];
    } catch (e) {
      setState(() => _importMsg = '❌ JSON 格式錯誤：$e'); return;
    }
    if (list.isEmpty) { setState(() => _importMsg = '❌ 資料為空'); return; }
    setState(() { _importing = true; _importMsg = null; });
    try {
      int count = 0;
      const batchSize = 400;
      for (var i = 0; i < list.length; i += batchSize) {
        final batch = _db.batch();
        final chunk = list.sublist(i, (i + batchSize).clamp(0, list.length));
        for (final item in chunk) {
          if (item is! Map) continue;
          final data = Map<String, dynamic>.from(item);
          final id   = data.remove('__id') as String?;
          final ref  = id != null
              ? _db.collection(_importTarget).doc(id)
              : _db.collection(_importTarget).doc();
          batch.set(ref, data, SetOptions(merge: true));
          count++;
        }
        await batch.commit();
      }
      if (mounted) setState(() {
        _importing = false;
        _importMsg = '✅ 成功匯入 $count 筆資料至「$_importTarget」集合';
        _importCtrl.clear();
      });
    } catch (e) {
      if (mounted) setState(() { _importing = false; _importMsg = '❌ 匯入失敗：$e'; });
    }
  }

  /// 把 Firestore 原生型別轉成可 JSON 序列化的形式
  dynamic _toJsonSafe(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is GeoPoint)  return {'lat': v.latitude, 'lng': v.longitude};
    if (v is Map)  return v.map((k, vv) => MapEntry(k.toString(), _toJsonSafe(vv)));
    if (v is List) return v.map(_toJsonSafe).toList();
    return v;
  }

  Future<void> _doExport(String collection) async {
    setState(() { _exportLoading[collection] = true; _exportResult = null; });
    try {
      final snap = await _db.collection(collection).get();
      final list = snap.docs.map((d) => _toJsonSafe({'__id': d.id, ...d.data()})).toList();
      const encoder = JsonEncoder.withIndent('  ');
      final json = encoder.convert(list);

      // 同時複製到剪貼簿
      await Clipboard.setData(ClipboardData(text: json));

      // 上傳到 AWS S3
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final key = 'firestore-data/$collection/$collection-$timestamp.json';
      final url = await AwsS3Service().uploadJson(key: key, jsonContent: json);

      if (mounted) setState(() {
        _exportLoading[collection] = false;
        _exportResult = '✅ 已上傳「$collection」共 ${list.length} 筆\n$url';
      });
    } catch (e) {
      if (mounted) setState(() {
        _exportLoading[collection] = false;
        _exportResult = '❌ 匯出失敗：$e';
      });
    }
  }

  Future<void> _exportAll() async {
    setState(() {
      for (final c in _exportCollections) _exportLoading[c.$1] = true;
      _exportResult = null;
    });
    try {
      final Map<String, dynamic> allData = {};
      for (final c in _exportCollections) {
        final snap = await _db.collection(c.$1).get();
        allData[c.$1] = snap.docs.map((d) => _toJsonSafe({'__id': d.id, ...d.data()})).toList();
      }
      const encoder = JsonEncoder.withIndent('  ');
      final json = encoder.convert(allData);

      // 同時複製到剪貼簿
      await Clipboard.setData(ClipboardData(text: json));

      // 上傳到 AWS S3（全部合併成一個檔案）
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final key = 'firestore-data/all/joygo-backup-$timestamp.json';
      final url = await AwsS3Service().uploadJson(key: key, jsonContent: json);

      if (mounted) setState(() {
        for (final c in _exportCollections) _exportLoading[c.$1] = false;
        final total = allData.values.fold<int>(0, (s, v) => s + (v as List).length);
        _exportResult = '✅ 全部備份完成，共 $total 筆\n$url';
      });
    } catch (e) {
      if (mounted) setState(() {
        for (final c in _exportCollections) _exportLoading[c.$1] = false;
        _exportResult = '❌ 匯出失敗：$e';
      });
    }
  }

  @override
  void dispose() { _importCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return ListView(padding: const EdgeInsets.all(16), children: [

      // ── 資料匯入 ──────────────────────────────
      Row(children: [
        Icon(Icons.upload_rounded, size: 18, color: p),
        const SizedBox(width: 6),
        Text('資料匯入', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        const Text('目標集合：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        ...['spots', 'restaurants'].map((col) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(col, style: const TextStyle(fontSize: 12)),
            selected: _importTarget == col,
            selectedColor: p.withValues(alpha: 0.15),
            onSelected: (_) => setState(() => _importTarget = col),
          ),
        )),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _importCtrl,
        maxLines: 7,
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: '貼上 JSON 陣列，例如：\n[{"name":"仁愛路景點","category":"attractions",...},...]',
          hintStyle: const TextStyle(fontSize: 11, color: AppColors.textHint),
          filled: true, fillColor: AppColors.background,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: _importing ? null : _doImport,
          icon: _importing
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_rounded, size: 16),
          label: Text(_importing ? '匯入中…' : '開始匯入', style: const TextStyle(fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: p, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        )),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: () { _importCtrl.clear(); setState(() => _importMsg = null); },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: const Text('清除', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      ]),
      if (_importMsg != null) ...[
        const SizedBox(height: 8),
        _msgBox(_importMsg!),
      ],

      const SizedBox(height: 28),

      // ── 匯出備份 ──────────────────────────────
      Row(children: [
        Icon(Icons.download_rounded, size: 18, color: p),
        const SizedBox(width: 6),
        Text('匯出備份', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p)),
      ]),
      const SizedBox(height: 4),
      const Text('匯出後資料將自動複製到剪貼簿，可貼入文字編輯器存為 .json 檔。',
        style: TextStyle(fontSize: 11, color: AppColors.textHint)),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: (_exportLoading.values.any((v) => v)) ? null : _exportAll,
          icon: const Icon(Icons.download_for_offline_rounded, size: 18),
          label: const Text('匯出全部集合', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5C8EC1), foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      ..._exportCollections.map((c) {
        final loading = _exportLoading[c.$1] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider)),
            child: ListTile(
              dense: true,
              leading: Icon(c.$3, size: 18, color: p.withValues(alpha: 0.7)),
              title: Text(c.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text(c.$1, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              trailing: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: () => _doExport(c.$1),
                      child: const Text('匯出', style: TextStyle(fontSize: 12)),
                    ),
            ),
          ),
        );
      }),
      if (_exportResult != null) ...[
        const SizedBox(height: 4),
        _msgBox(_exportResult!),
      ],
      const SizedBox(height: 20),
    ]);
  }

  Widget _msgBox(String msg) {
    final ok = msg.startsWith('✅');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? Colors.green.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ok ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2)),
      ),
      child: Text(msg, style: TextStyle(fontSize: 12, color: ok ? Colors.green.shade700 : Colors.red.shade700)),
    );
  }
}
