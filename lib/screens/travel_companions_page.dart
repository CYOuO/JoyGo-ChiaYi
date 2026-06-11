import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/trip_service.dart';
import '../widgets/common_widgets.dart' show IllustratedEmptyState, EmptyScene;

IconData _tripIconFromKey(String key) {
  switch (key) {
    case 'map':   case '🗺️': return Icons.map_rounded;
    case 'flight':case '✈️': return Icons.flight_rounded;
    case 'train': case '🚂': return Icons.train_rounded;
    case 'beach': case '🏖️': case '🏝️': return Icons.beach_access_rounded;
    case 'mountain': case '🏔️': case '⛰️': return Icons.landscape_rounded;
    case 'flower': case '🌸': return Icons.local_florist_rounded;
    case 'ramen': case '🍜': return Icons.ramen_dining_rounded;
    case 'castle': case '🏯': case '🏛️': return Icons.account_balance_rounded;
    case 'camera': case '📸': return Icons.camera_alt_rounded;
    default: return Icons.map_rounded;
  }
}

/// 旅伴管理頁面
/// 顯示每個行程的旅伴，可新增/移除旅伴
class TravelCompanionsPage extends StatefulWidget {
  /// 若從通知跳入，可直接聚焦到特定行程
  final String? focusTripId;
  const TravelCompanionsPage({super.key, this.focusTripId});
  @override
  State<TravelCompanionsPage> createState() => _TravelCompanionsPageState();

  // ── 靜態工具：寫出邀請通知（同時寫 invitations + notifications）
  static Future<void> sendInviteNotification({
    required FirebaseFirestore db,
    required String tripId,
    required String tripTitle,
    required String foundUid,
    required String companionDocId,
    required String myUid,
    required String myName,
    required String myPhotoUrl,
  }) async {
    // invitations（舊流程，保留相容性）
    await db.collection('users').doc(foundUid).collection('invitations').doc(companionDocId).set({
      'tripId':      tripId,
      'companionId': companionDocId,
      'fromUid':     myUid,
      'fromName':    myName,
      'tripTitle':   tripTitle,
      'status':      'pending',
      'sentAt':      FieldValue.serverTimestamp(),
    });
    // notifications（新：讓通知頁面可以顯示邀請）
    await db.collection('users').doc(foundUid).collection('notifications').doc(companionDocId).set({
      'type':         'invite',
      'title':        '$myName 邀請你加入行程',
      'body':         '「$tripTitle」— 點擊確認是否加入',
      'tripId':       tripId,
      'tripTitle':    tripTitle,
      'companionId':  companionDocId,
      'fromUid':      myUid,
      'fromName':     myName,
      'fromPhotoUrl': myPhotoUrl,
      'isRead':       false,
      'inviteStatus': 'pending',
      'createdAt':    FieldValue.serverTimestamp(),
    });
  }
}

class _TravelCompanionsPageState extends State<TravelCompanionsPage> {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ── 加入旅伴（支援 Firebase 用戶搜尋 + 假人頭）──────────────
  Future<void> _addCompanion(FirebaseTrip trip, Color primary) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCompanionSheet(
        primary: primary,
        onAdd: (name, email, foundUid, photoUrl, isDummy) async {
          final myUid = _uid ?? '';

          if (isDummy) {
            await _db.collection('trips').doc(trip.id).collection('companions').add({
              'name': name, 'email': email, 'uid': '', 'photoURL': '',
              'status': 'dummy', 'addedBy': myUid,
              'addedAt': FieldValue.serverTimestamp(),
            });
          } else if (foundUid != null && foundUid.isNotEmpty) {
            final docRef = await _db.collection('trips').doc(trip.id).collection('companions').add({
              'name': name, 'email': email, 'uid': foundUid, 'photoURL': photoUrl ?? '',
              'status': 'pending', 'addedBy': myUid,
              'addedAt': FieldValue.serverTimestamp(),
            });
            final myDoc = await _db.collection('users').doc(myUid).get();
            final myName = (myDoc.data()?['nickname'] ?? myDoc.data()?['displayName'] ?? '旅伴').toString();
            final myPhoto = (myDoc.data()?['photoURL'] ?? myDoc.data()?['photoUrl'] ?? '').toString();
            try {
              await TravelCompanionsPage.sendInviteNotification(
                db: _db, tripId: trip.id, tripTitle: trip.title,
                foundUid: foundUid, companionDocId: docRef.id,
                myUid: myUid, myName: myName, myPhotoUrl: myPhoto,
              );
            } catch (_) {}
          } else {
            await _db.collection('trips').doc(trip.id).collection('companions').add({
              'name': name, 'email': email, 'uid': '', 'photoURL': '',
              'status': 'manual', 'addedBy': myUid,
              'addedAt': FieldValue.serverTimestamp(),
            });
          }
        },
      ),
    );
  }

  // ── 確認旅伴（接受邀請）────────────────────────────────────
  Future<void> _acceptInvitation(String invitationId, String tripId, String companionId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await Future.wait([
        _db.collection('trips').doc(tripId).collection('companions').doc(companionId)
            .update({'status': 'confirmed'}),
        _db.collection('trips').doc(tripId)
            .update({'members': FieldValue.arrayUnion([uid])}),
      ]);
      // 刪除邀請記錄 + 更新通知
      await _db.collection('users').doc(uid).collection('invitations').doc(invitationId).delete();
      try {
        await _db.collection('users').doc(uid).collection('notifications').doc(invitationId)
            .update({'isRead': true, 'inviteStatus': 'accepted'});
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已接受邀請，成為正式旅伴！'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {}
  }

  Future<void> _declineInvitation(String invitationId, String tripId, String companionId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('trips').doc(tripId).collection('companions').doc(companionId).delete();
      await _db.collection('users').doc(uid).collection('invitations').doc(invitationId).delete();
      try {
        await _db.collection('users').doc(uid).collection('notifications').doc(invitationId)
            .update({'isRead': true, 'inviteStatus': 'declined'});
      } catch (_) {}
    } catch (_) {}
  }

  // ── 移除旅伴 / 退出行程 ─────────────────────────────────────
  Future<void> _removeCompanion(String tripId, String companionId, String companionUid, String name) async {
    final isMe = companionUid == _uid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(isMe ? '退出行程' : '移除旅伴',
          style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(isMe ? '確定要退出此行程嗎？' : '確定要移除「$name」嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isMe ? '退出' : '移除',
              style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    await _db.collection('trips').doc(tripId).collection('companions').doc(companionId).delete();
    // 如果被移除的是已確認成員，也從 members 陣列移除
    if (companionUid.isNotEmpty) {
      try {
        await _db.collection('trips').doc(tripId)
            .update({'members': FieldValue.arrayRemove([companionUid])});
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final uid = _uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('旅伴管理', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
      ),
      body: uid == null
          ? const Center(child: Text('請先登入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))
          : CustomScrollView(
              slivers: [
                // ── 收到的邀請 ────────────────────────────────
                SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _db.collection('users').doc(uid)
                        .collection('invitations')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (ctx, snap) {
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) return const SizedBox.shrink();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${docs.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: primary)),
                            ),
                            const SizedBox(width: 6),
                            Text('旅伴邀請待確認', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary)),
                          ]),
                        ),
                        ...docs.map((doc) {
                          final d = Map<String, dynamic>.from(doc.data() as Map);
                          return _InvitationCard(
                            docId: doc.id,
                            data: d,
                            primary: primary,
                            onAccept: () => _acceptInvitation(doc.id, d['tripId'] ?? '', d['companionId'] ?? ''),
                            onDecline: () => _declineInvitation(doc.id, d['tripId'] ?? '', d['companionId'] ?? ''),
                          );
                        }),
                        Divider(height: 24, color: AppColors.divider),
                      ]);
                    },
                  ),
                ),
                // ── 行程旅伴列表 ──────────────────────────────
                SliverToBoxAdapter(
                  child: StreamBuilder<List<FirebaseTrip>>(
                    stream: TripService.tripsStream(),
                    builder: (ctx, tripSnap) {
                      final trips = tripSnap.data ?? [];
                      if (tripSnap.connectionState == ConnectionState.waiting && trips.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (trips.isEmpty) {
                        return IllustratedEmptyState(
                          scene: EmptyScene.companion,
                          title: '還沒有任何行程',
                          body: '先在「行程管理」建立行程\n再來這裡新增旅伴一起出發！',
                        );
                      }
                      // 若有 focusTripId，把該行程排到最前面
                      final sorted = [...trips];
                      if (widget.focusTripId != null) {
                        sorted.sort((a, b) {
                          if (a.id == widget.focusTripId) return -1;
                          if (b.id == widget.focusTripId) return 1;
                          return 0;
                        });
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: sorted.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => _TripCompanionCard(
                          trip: sorted[i],
                          primary: primary,
                          currentUid: uid,
                          highlighted: sorted[i].id == widget.focusTripId,
                          onAddCompanion: () => _addCompanion(sorted[i], primary),
                          onRemoveCompanion: (cid, cUid, name) =>
                              _removeCompanion(sorted[i].id, cid, cUid, name),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 每個行程的旅伴卡片（顯示管理員 + 成員 + 角色保護）
// ════════════════════════════════════════════════════════════════
class _TripCompanionCard extends StatelessWidget {
  final FirebaseTrip trip;
  final Color primary;
  final String currentUid;
  final bool highlighted;
  final VoidCallback onAddCompanion;
  final void Function(String companionId, String companionUid, String name) onRemoveCompanion;

  const _TripCompanionCard({
    required this.trip,
    required this.primary,
    required this.currentUid,
    required this.highlighted,
    required this.onAddCompanion,
    required this.onRemoveCompanion,
  });

  bool get _isAdmin => trip.uid == currentUid;

  @override
  Widget build(BuildContext context) {
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: highlighted
            ? Border.all(color: primary, width: 2)
            : null,
        boxShadow: [BoxShadow(
          color: highlighted
              ? primary.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.05),
          blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 行程標題列
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: mist,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            Icon(_tripIconFromKey(trip.icon), size: 20, color: primary),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(trip.dateDisplay,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ])),
            // 只有管理員可以新增旅伴
            if (_isAdmin)
              IconButton(
                icon: Icon(Icons.person_add_rounded, color: primary, size: 22),
                onPressed: onAddCompanion,
                tooltip: '新增旅伴',
              ),
          ]),
        ),

        // ── 管理員行（一定顯示）──────────────────────────────
        _AdminRow(
          creatorUid: trip.uid,
          isCurrentUser: trip.uid == currentUid,
          primary: primary,
        ),

        // ── 旅伴列表 ─────────────────────────────────────────
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('trips').doc(trip.id)
              .collection('companions')
              .orderBy('addedAt', descending: false)
              .snapshots(),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(children: [
                  Icon(Icons.group_outlined, size: 16, color: AppColors.textHint),
                  const SizedBox(width: 8),
                  Text(_isAdmin ? '尚無旅伴，點擊 + 新增' : '尚無其他旅伴',
                    style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
                ]),
              );
            }
            return Column(
              children: docs.map((doc) {
                final rawData = doc.data();
                if (rawData == null) return const SizedBox.shrink();
                final d = Map<String, dynamic>.from(rawData as Map);
                final name     = (d['name']  ?? '旅伴').toString();
                final email    = (d['email'] ?? '').toString();
                final photoUrl = ((d['photoURL'] ?? d['photoUrl']) ?? '').toString();
                final companionUid = (d['uid'] ?? '').toString();
                final status   = (d['status'] ?? 'manual').toString();
                final isMe     = companionUid == currentUid;
                // 管理員不能被列在旅伴清單裡移除（他本來就是 owner）
                // 如果因為 bug 重複加了，也顯示但不讓移除
                final isCreator = companionUid == trip.uid;

                // 是否可以顯示移除按鈕
                // - 管理員：可移除任何人（除了自己 / creator）
                // - 成員：只能移除自己
                final canRemove = !isCreator && (_isAdmin || isMe);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: _CompanionAvatar(
                    photoUrl: photoUrl,
                    name: name,
                    primary: primary,
                  ),
                  title: Row(children: [
                    Flexible(child: Text(name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    _StatusChip(status: status, primary: primary),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(4)),
                        child: Text('你', style: TextStyle(fontSize: 9, color: primary, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ]),
                  subtitle: email.isNotEmpty
                      ? Text(email, style: const TextStyle(fontSize: 11, color: AppColors.textHint))
                      : null,
                  trailing: canRemove
                      ? IconButton(
                          icon: Icon(
                            isMe ? Icons.exit_to_app_rounded : Icons.remove_circle_outline_rounded,
                            color: AppColors.error, size: 20),
                          tooltip: isMe ? '退出行程' : '移除旅伴',
                          onPressed: () => onRemoveCompanion(doc.id, companionUid, name),
                        )
                      : const SizedBox(width: 48), // 佔位，讓 UI 對齊
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 8),
      ]),
    );
  }
}

// ── 管理員行（從 Firestore 抓取 creator 資料）──────────────────
class _AdminRow extends StatefulWidget {
  final String creatorUid;
  final bool isCurrentUser;
  final Color primary;
  const _AdminRow({required this.creatorUid, required this.isCurrentUser, required this.primary});
  @override
  State<_AdminRow> createState() => _AdminRowState();
}
class _AdminRowState extends State<_AdminRow> {
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.creatorUid).get();
      if (mounted && doc.exists) setState(() => _userData = doc.data());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = (_userData?['nickname'] ?? _userData?['displayName'] ?? '管理員').toString();
    final photo = (_userData?['photoURL'] ?? _userData?['photoUrl'] ?? '').toString();
    final email = (_userData?['email'] ?? _userData?['emailAddress'] ?? '').toString();
    final p = widget.primary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: _CompanionAvatar(photoUrl: photo, name: name, primary: p),
      title: Row(children: [
        Flexible(child: Text(name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        // 管理員皇冠徽章
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('👑', style: TextStyle(fontSize: 9)),
            const SizedBox(width: 2),
            const Text('管理員', style: TextStyle(fontSize: 9, color: Color(0xFFB8860B), fontWeight: FontWeight.w800)),
          ]),
        ),
        if (widget.isCurrentUser) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: p.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(4)),
            child: Text('你', style: TextStyle(fontSize: 9, color: p, fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
      subtitle: email.isNotEmpty
          ? Text(email, style: const TextStyle(fontSize: 11, color: AppColors.textHint))
          : null,
      trailing: const SizedBox(width: 48), // 管理員不能被移除，佔位
    );
  }
}

// ── 頭像 ─────────────────────────────────────────────────────
class _CompanionAvatar extends StatelessWidget {
  final String photoUrl;
  final String name;
  final Color primary;
  const _CompanionAvatar({required this.photoUrl, required this.name, required this.primary});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 18,
    backgroundColor: primary.withValues(alpha: 0.12),
    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
    child: photoUrl.isEmpty
        ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: primary, fontWeight: FontWeight.w800, fontSize: 13))
        : null,
  );
}

// ════════════════════════════════════════════════════════════════
// 新增旅伴 Sheet
// ════════════════════════════════════════════════════════════════
class _AddCompanionSheet extends StatefulWidget {
  final Color primary;
  final Future<void> Function(String name, String email, String? uid, String? photoUrl, bool isDummy) onAdd;
  const _AddCompanionSheet({required this.primary, required this.onAdd});

  @override
  State<_AddCompanionSheet> createState() => _AddCompanionSheetState();
}

class _AddCompanionSheetState extends State<_AddCompanionSheet> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  bool   _searching = false;
  bool   _notFound  = false;
  Map<String, dynamic>? _foundUser;
  bool   _adding = false;

  Future<void> _search() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _searching = true; _notFound = false; _foundUser = null; });
    try {
      var q = await FirebaseFirestore.instance
          .collection('users').where('email', isEqualTo: email).limit(1).get();
      if (q.docs.isEmpty) {
        q = await FirebaseFirestore.instance
            .collection('users').where('emailAddress', isEqualTo: email).limit(1).get();
      }
      if (q.docs.isEmpty) {
        setState(() { _searching = false; _notFound = true; });
      } else {
        final d = q.docs.first.data();
        setState(() { _searching = false; _foundUser = {...d, 'uid': q.docs.first.id}; });
      }
    } catch (e) {
      setState(() { _searching = false; _notFound = true; });
    }
  }

  Future<void> _addUser() async {
    if (_adding) return;
    setState(() => _adding = true);
    final user = _foundUser;
    final name = user?['nickname'] ?? user?['displayName'] ?? user?['name'] ?? _nameCtrl.text.trim();
    final email = user?['email'] ?? user?['emailAddress'] ?? _emailCtrl.text.trim();
    final uid = user?['uid'] as String?;
    final photo = (user?['photoURL'] ?? user?['photoUrl'] ?? '') as String;
    await widget.onAdd(name.toString(), email.toString(), uid, photo, false);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addManual() async {
    if (_adding || _nameCtrl.text.trim().isEmpty) return;
    setState(() => _adding = true);
    await widget.onAdd(_nameCtrl.text.trim(), _emailCtrl.text.trim(), null, null, false);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addDummy() async {
    if (_adding || _nameCtrl.text.trim().isEmpty) return;
    setState(() => _adding = true);
    await widget.onAdd(_nameCtrl.text.trim(), '', null, null, true);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() { _emailCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    final found = _foundUser;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
          const Text('新增旅伴', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('輸入對方的 Email 搜尋帳號（支援 Google 登入）',
            style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          const SizedBox(height: 16),
          // Email 搜尋列
          Row(children: [
            Expanded(
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'example@gmail.com',
                  prefixIcon: Icon(Icons.email_outlined, size: 18, color: p),
                  filled: true, fillColor: AppColors.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _searching ? null : _search,
                style: ElevatedButton.styleFrom(
                  backgroundColor: p, foregroundColor: Colors.white,
                  elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _searching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('搜尋', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (_notFound) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.person_off_rounded, size: 18, color: AppColors.error),
                SizedBox(width: 8),
                Expanded(child: Text('找不到此 Email 的用戶，可改用手動輸入', style: TextStyle(fontSize: 12, color: AppColors.error))),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '旅伴姓名',
                hintText: '輸入旅伴名稱',
                filled: true, fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () {
                  final email = _emailCtrl.text.trim();
                  Share.share('邀請你加入我們的行程！下載「探索諸羅」App 並用此 Email 註冊：$email');
                },
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('立即邀請'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p, side: BorderSide(color: p),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: _addManual,
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: const Text('手動新增'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p, foregroundColor: Colors.white,
                  elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              )),
            ]),
          ],
          if (found != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: p.withValues(alpha: 0.12),
                  backgroundImage: ((found['photoURL'] ?? found['photoUrl'] ?? '') as String).isNotEmpty
                      ? NetworkImage((found['photoURL'] ?? found['photoUrl'] ?? '') as String) : null,
                  child: ((found['photoURL'] ?? found['photoUrl'] ?? '') as String).isEmpty
                      ? Icon(Icons.person_rounded, color: p, size: 22) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    (found['nickname'] ?? found['displayName'] ?? found['name'] ?? '用戶').toString(),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  Row(children: [
                    Icon(Icons.verified_rounded, size: 13, color: p),
                    const SizedBox(width: 4),
                    Text('已找到 App 帳號', style: TextStyle(fontSize: 11, color: p, fontWeight: FontWeight.w600)),
                  ]),
                ])),
                Icon(Icons.check_circle_rounded, color: p, size: 24),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _adding ? null : _addUser,
                icon: _adding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.group_add_rounded, size: 18),
                label: const Text('加入為旅伴', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p, foregroundColor: Colors.white,
                  elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          if (!_notFound && found == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('✦  若對方尚未下載 App，可先手動新增，待其加入後自動連結',
                style: TextStyle(fontSize: 11, color: AppColors.textHint.withValues(alpha: 0.7))),
            ),

          // ── 虛擬旅伴區 ────────────────────────────────────
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: const Text('或新增虛擬旅伴（分帳用）',
                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: '名字（如：小明、媽媽）',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 18, color: p),
                  filled: true, fillColor: AppColors.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _adding ? null : _addDummy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentTerra, foregroundColor: Colors.white,
                  elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('新增', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('★  虛擬旅伴不需要 App 帳號，方便分帳計算使用',
            style: TextStyle(fontSize: 10, color: AppColors.textHint.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }
}

// ── 邀請狀態 Chip ──────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String status;
  final Color primary;
  const _StatusChip({required this.status, required this.primary});
  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'pending':
        bg = AppColors.warning.withValues(alpha: 0.15); fg = AppColors.warning; label = '邀請中';
      case 'confirmed':
        bg = primary.withValues(alpha: 0.10); fg = primary; label = '已連結';
      case 'dummy':
        bg = AppColors.accentTerra.withValues(alpha: 0.12); fg = AppColors.accentTerra; label = '虛擬';
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 9, color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

// ── 邀請確認卡片 ────────────────────────────────────────────────
class _InvitationCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final Color primary;
  final VoidCallback onAccept, onDecline;
  const _InvitationCard({
    required this.docId, required this.data, required this.primary,
    required this.onAccept, required this.onDecline,
  });
  @override
  Widget build(BuildContext context) {
    final fromName  = (data['fromName']  ?? '').toString();
    final tripTitle = (data['tripTitle'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(Icons.person_add_rounded, color: primary, size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$fromName 邀請你加入旅伴',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (tripTitle.isNotEmpty)
            Text('「$tripTitle」', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ])),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onDecline,
          style: TextButton.styleFrom(foregroundColor: AppColors.error, minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
          child: const Text('拒絕', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: onAccept,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary, foregroundColor: Colors.white,
            elevation: 0, minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('接受', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
