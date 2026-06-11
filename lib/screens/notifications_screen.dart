import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';
import '../widgets/common_widgets.dart' show IllustratedEmptyState, EmptyScene;
import '../theme/fabric_textures.dart' show DoodleCircle, DoodleHeart, DoodleLightning, SlideUpFadeIn;
import '../widgets/user_profile_sheet.dart';
import 'travel_companions_page.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  static const _kDismissedKey = 'notif_dismissed_ids_v1';
  static const _kReadKey      = 'notif_read_ids_v1';
  static const _kPrefix       = 'notif_setting_';

  Set<String> _dismissed = {};
  Set<String> _readIds   = {};

  // 通知開關偏好設定（從 settings_screen 的 SharedPreferences 讀取）
  bool _prefPush      = true;
  bool _prefCommunity = false;
  bool _prefTrip      = true;

  static IconData _typeIconData(String type) {
    switch (type) {
      case 'event':       return Icons.celebration_rounded;
      case 'social':      return Icons.thumb_up_rounded;
      case 'follow':      return Icons.person_add_rounded;
      case 'achievement': return Icons.military_tech_rounded;
      case 'transport':   return Icons.directions_bus_rounded;
      case 'nearby':      return Icons.place_rounded;
      case 'weather':     return Icons.cloud_rounded;
      case 'invite':      return Icons.group_add_rounded;
      case 'broadcast':   return Icons.campaign_rounded;
      default:            return Icons.notifications_rounded;
    }
  }

  final _typeColor = const {
    'event':       Color(0xFFE8A87C),
    'social':      Color(0xFF8FBF8F),
    'follow':      Color(0xFF5B7CE8),
    'achievement': Color(0xFFCFA84C),
    'transport':   Color(0xFF88B8C8),
    'nearby':      Color(0xFFD4A8C7),
    'weather':     Color(0xFF8FBFD8),
    'invite':      Color(0xFF7B6BAE),
    'broadcast':   Color(0xFF9B59B6),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 從設定頁返回後重新讀取偏好
    if (state == AppLifecycleState.resumed) _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dismissed      = Set.from(prefs.getStringList(_kDismissedKey) ?? []);
      _readIds        = Set.from(prefs.getStringList(_kReadKey) ?? []);
      _prefPush       = prefs.getBool('${_kPrefix}push')      ?? true;
      _prefCommunity  = prefs.getBool('${_kPrefix}community') ?? false;
      _prefTrip       = prefs.getBool('${_kPrefix}trip')      ?? true;
    });
  }

  /// 通知類型是否被使用者的偏好設定允許顯示
  bool _isTypeAllowed(String type) {
    if (!_prefPush) return false;              // 總推播關閉 → 全部不顯示
    if (!_prefCommunity && (type == 'social' || type == 'follow')) return false;
    if (!_prefTrip && (type == 'invite' || type == 'event')) return false;
    return true;
  }

  Future<void> _markRead(String id) async {
    _readIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kReadKey, _readIds.toList());
    if (mounted) setState(() {});
  }

  Future<void> _dismiss(String id) async {
    _dismissed.add(id);
    _readIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDismissedKey, _dismissed.toList());
    await prefs.setStringList(_kReadKey, _readIds.toList());
    // Also mark as read in Firebase
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('notifications').doc(id)
            .update({'isRead': true});
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _markAllRead(List<_NotifItem> items) async {
    for (final item in items) { _readIds.add(item.id); }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kReadKey, _readIds.toList());
    // Mark all as read in Firebase
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in items.where((i) => !i.isRead)) {
        final ref = FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('notifications').doc(item.id);
        batch.update(ref, {'isRead': true});
      }
      try { await batch.commit(); } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Builder(builder: (bCtx) {
          final p = Theme.of(bCtx).colorScheme.primary;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            DoodleHeart(color: p.withValues(alpha: 0.55), size: 10),
            const SizedBox(width: 6),
            Text(context.watch<AppSettingsProvider>().l10n.notifCenter, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            DoodleLightning(color: p.withValues(alpha: 0.55), size: 10),
          ]);
        }),
      ),
      body: uid == null
          ? _buildGuest(primary)
          : StreamBuilder<QuerySnapshot>(
              // 廣播通知
              stream: FirebaseFirestore.instance
                  .collection('broadcasts')
                  .where('fcmSent', isEqualTo: true)
                  .orderBy('createdAt', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (ctx, broadcastSnap) {
              return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users').doc(uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (ctx, snap) {
                // 個人通知
                final fbDocs = snap.data?.docs ?? [];
                final personalItems = fbDocs
                    .where((d) => !_dismissed.contains(d.id))
                    .where((d) {
                      final type = (d.data() as Map<String, dynamic>)['type'] as String? ?? 'event';
                      return _isTypeAllowed(type);
                    })
                    .map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final isReadFb = data['isRead'] as bool? ?? false;
                      return _NotifItem(
                        id: d.id,
                        title: data['title'] as String? ?? '通知',
                        body: data['body'] as String? ?? '',
                        type: data['type'] as String? ?? 'event',
                        time: _formatTime(data['createdAt']),
                        isRead: isReadFb || _readIds.contains(d.id),
                        fromUid: data['fromUid'] as String?,
                        fromPhotoUrl: data['fromPhotoUrl'] as String?,
                        fromName: data['fromName'] as String?,
                        tripId: data['tripId'] as String?,
                        companionId: data['companionId'] as String?,
                        inviteStatus: data['inviteStatus'] as String?,
                      );
                    })
                    .toList();

                // 廣播通知（管理員發送）
                final broadcastItems = (broadcastSnap.data?.docs ?? [])
                    .where((d) => !_dismissed.contains('bc_${d.id}'))
                    .where((_) => _prefPush) // 推播總開關
                    .map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return _NotifItem(
                        id: 'bc_${d.id}',
                        title: data['title'] as String? ?? '系統公告',
                        body: data['body'] as String? ?? '',
                        type: 'broadcast',
                        time: _formatTime(data['createdAt']),
                        isRead: _readIds.contains('bc_${d.id}'),
                      );
                    })
                    .toList();

                // 合併並依時間排序
                final items = [...broadcastItems, ...personalItems];

                final unreadCount = items.where((i) => !i.isRead).length;

                if (items.isEmpty && snap.connectionState != ConnectionState.waiting) {
                  return _buildEmpty(primary, disabledByPref: !_prefPush);
                }
                if (items.isEmpty) return const Center(child: CircularProgressIndicator());

                return Column(children: [
                  // 推播已關閉的提示 banner
                  if (!_prefPush)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                      child: Row(children: [
                        const Icon(Icons.notifications_off_rounded, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('推播通知已關閉，請至設定開啟',
                          style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  // Header row
                  if (unreadCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(context.read<AppSettingsProvider>().l10n.notifUnread(unreadCount),
                              style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _markAllRead(items),
                          child: Text(context.read<AppSettingsProvider>().l10n.notifMarkAllRead,
                              style: TextStyle(color: primary, fontSize: 13)),
                        ),
                      ]),
                    ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) => SlideUpFadeIn(
                        index: i,
                        staggerDelay: const Duration(milliseconds: 40),
                        child: _buildNotifTile(items[i], primary, ctx),
                      ),
                    ),
                  ),
                ]);
              },   // 個人通知 StreamBuilder builder
            );     // 個人通知 StreamBuilder
              },   // 廣播 StreamBuilder builder
            ),     // 廣播 StreamBuilder
    );
  }

  void _handleNotifTap(_NotifItem n, BuildContext ctx) {
    switch (n.type) {
      case 'follow':
        if (n.fromUid != null && n.fromUid!.isNotEmpty) {
          final primary = Theme.of(ctx).colorScheme.primary;
          showUserProfileSheet(ctx,
            uid: n.fromUid!,
            primary: primary,
            knownName: n.fromName,
            knownPhoto: n.fromPhotoUrl,
          );
        }
        break;
      case 'invite':
        // 跳到旅伴管理頁，並聚焦到對應行程
        Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => TravelCompanionsPage(focusTripId: n.tripId),
        ));
        break;
      default:
        break;
    }
  }

  // ── 邀請通知：接受 ────────────────────────────────────────────
  Future<void> _acceptInvite(_NotifItem n) async {
    if (n.tripId == null || n.companionId == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await Future.wait([
        FirebaseFirestore.instance
            .collection('trips').doc(n.tripId!)
            .collection('companions').doc(n.companionId!)
            .update({'status': 'confirmed'}),
        FirebaseFirestore.instance
            .collection('trips').doc(n.tripId!)
            .update({'members': FieldValue.arrayUnion([uid])}),
      ]);
      // 同步更新通知狀態
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('notifications').doc(n.id)
          .update({'isRead': true, 'inviteStatus': 'accepted'});
      // 刪除 invitations 記錄
      try {
        await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('invitations').doc(n.companionId!).delete();
      } catch (_) {}
      _markRead(n.id);
    } catch (_) {}
  }

  // ── 邀請通知：拒絕 ────────────────────────────────────────────
  Future<void> _declineInvite(_NotifItem n) async {
    if (n.tripId == null || n.companionId == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('trips').doc(n.tripId!)
          .collection('companions').doc(n.companionId!).delete();
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('notifications').doc(n.id)
          .update({'isRead': true, 'inviteStatus': 'declined'});
      try {
        await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('invitations').doc(n.companionId!).delete();
      } catch (_) {}
      _markRead(n.id);
    } catch (_) {}
  }

  Widget _buildNotifTile(_NotifItem n, Color primary, BuildContext ctx) {
    final color = _typeColor[n.type] ?? AppColors.textHint;
    return Dismissible(
      key: Key(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.error.withValues(alpha: 0.1),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
      ),
      onDismissed: (_) => _dismiss(n.id),
      child: InkWell(
        onTap: () {
          _markRead(n.id);
          _handleNotifTap(n, ctx);
        },
        child: Container(
          color: n.isRead
              ? Colors.transparent
              : Color.lerp(primary, Colors.white, 0.88)!.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // follow 型通知：顯示對方頭貼；其他通知：顯示圖示
            if (n.type == 'follow' && n.fromPhotoUrl != null && n.fromPhotoUrl!.isNotEmpty)
              DoodleCircle(
                size: 44,
                color: color.withValues(alpha: 0.35),
                child: ClipOval(child: Image.network(n.fromPhotoUrl!, width: 44, height: 44, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: color.withValues(alpha: 0.12),
                    child: Center(child: Icon(Icons.person_rounded, size: 20, color: color))))),
              )
            else if (n.type == 'follow' && n.fromUid != null)
              _FutureAvatar(uid: n.fromUid!, fallbackColor: color)
            else
              DoodleCircle(
                size: 44,
                color: color.withValues(alpha: 0.35),
                child: Container(
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Center(child: Icon(_typeIconData(n.type), size: 20, color: color)),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(n.title,
                  style: TextStyle(
                    fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                    fontSize: 14, color: AppColors.textPrimary,
                  ),
                )),
                Text(n.time, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ]),
              const SizedBox(height: 4),
              Text(n.body, style: TextStyle(
                fontSize: 13,
                color: n.isRead ? AppColors.textHint : AppColors.textSecondary,
                height: 1.4,
              )),
              // 邀請通知：顯示接受 / 拒絕按鈕（僅在 pending 狀態）
              if (n.type == 'invite' && (n.inviteStatus == 'pending' || n.inviteStatus == null)) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _declineInvite(n),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('拒絕', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acceptInvite(n),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('接受邀請', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ],
              if (n.type == 'invite' && n.inviteStatus == 'accepted')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text('已接受邀請', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                  ]),
                ),
              if (n.type == 'invite' && n.inviteStatus == 'declined')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('已拒絕', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                ),
            ])),
            if (!n.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildEmpty(Color primary, {bool disabledByPref = false}) =>
    disabledByPref
        ? IllustratedEmptyState(
            scene: EmptyScene.notification,
            title: '推播通知已關閉',
            body: '請至「設定 → 通知」開啟推播，即可收到旅伴邀請、行程提醒等通知',
            color: Colors.orange,
          )
        : IllustratedEmptyState(
            scene: EmptyScene.notification,
            title: '目前沒有通知',
            body: '新活動、有人追蹤你、行程按讚\n都會在這裡出現',
            color: primary,
          );

  Widget _buildGuest(Color primary) => IllustratedEmptyState(
    scene: EmptyScene.notification,
    title: '登入後查看通知',
    body: '登入後即可收到行程按讚、追蹤、成就解鎖等通知',
    color: primary,
  );

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return '';
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return '剛剛';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分鐘前';
    if (diff.inHours < 24)   return '${diff.inHours}小時前';
    if (diff.inDays < 7)     return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }
}

class _NotifItem {
  final String id, title, body, type, time;
  final bool isRead;
  final String? fromUid;      // 觸發通知的使用者 uid
  final String? fromPhotoUrl; // 對方頭貼（follow 通知用）
  final String? fromName;     // 對方名稱（快取用）
  final String? tripId;       // 邀請通知：行程 ID
  final String? companionId;  // 邀請通知：companions 文件 ID
  final String? inviteStatus; // 邀請狀態：pending / accepted / declined
  const _NotifItem({
    required this.id, required this.title, required this.body,
    required this.type, required this.time, required this.isRead,
    this.fromUid, this.fromPhotoUrl, this.fromName,
    this.tripId, this.companionId, this.inviteStatus,
  });
}

// 當通知文件沒有 fromPhotoUrl 時，lazy 從 Firestore 取頭貼
class _FutureAvatar extends StatefulWidget {
  final String uid;
  final Color fallbackColor;
  const _FutureAvatar({required this.uid, required this.fallbackColor});
  @override State<_FutureAvatar> createState() => _FutureAvatarState();
}
class _FutureAvatarState extends State<_FutureAvatar> {
  String? _photoUrl;
  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('users').doc(widget.uid).get().then((d) {
      if (mounted) setState(() {
        _photoUrl = d.data()?['photoURL'] as String? ?? d.data()?['photoUrl'] as String?;
      });
    }).catchError((_) {});
  }
  @override
  Widget build(BuildContext context) {
    final c = widget.fallbackColor;
    return DoodleCircle(size: 44, color: c.withValues(alpha: 0.35),
      child: ClipOval(child: _photoUrl != null && _photoUrl!.isNotEmpty
        ? Image.network(_photoUrl!, width: 44, height: 44, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(c))
        : _fallback(c)),
    );
  }
  Widget _fallback(Color c) => Container(color: c.withValues(alpha: 0.12),
    child: Center(child: Icon(Icons.person_rounded, size: 20, color: c)));
}
