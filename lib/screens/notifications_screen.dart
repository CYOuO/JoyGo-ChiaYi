import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart' show IllustratedEmptyState, EmptyScene;
import '../theme/fabric_textures.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _kDismissedKey = 'notif_dismissed_ids_v1';
  static const _kReadKey      = 'notif_read_ids_v1';

  Set<String> _dismissed = {};
  Set<String> _readIds   = {};

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
  };

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dismissed = Set.from(prefs.getStringList(_kDismissedKey) ?? []);
      _readIds   = Set.from(prefs.getStringList(_kReadKey) ?? []);
    });
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
            const Text('通知中心', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            DoodleLightning(color: p.withValues(alpha: 0.55), size: 10),
          ]);
        }),
      ),
      body: uid == null
          ? _buildGuest(primary)
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users').doc(uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (ctx, snap) {
                // Build combined list from Firebase + local cache
                final fbDocs = snap.data?.docs ?? [];
                final items = fbDocs
                    .where((d) => !_dismissed.contains(d.id))
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
                      );
                    })
                    .toList();

                final unreadCount = items.where((i) => !i.isRead).length;

                if (items.isEmpty) {
                  return _buildEmpty(primary);
                }

                return Column(children: [
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
                          child: Text('$unreadCount 則未讀',
                              style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _markAllRead(items),
                          child: Text('全部已讀',
                              style: TextStyle(color: primary, fontSize: 13)),
                        ),
                      ]),
                    ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) => _buildNotifTile(items[i], primary, ctx),
                    ),
                  ),
                ]);
              },
            ),
    );
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
        onTap: () => _markRead(n.id),
        child: Container(
          color: n.isRead
              ? Colors.transparent
              : Color.lerp(primary, Colors.white, 0.88)!.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

  Widget _buildEmpty(Color primary) => IllustratedEmptyState(
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
  const _NotifItem({
    required this.id, required this.title, required this.body,
    required this.type, required this.time, required this.isRead,
  });
}
