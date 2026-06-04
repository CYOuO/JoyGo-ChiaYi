import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/trip_service.dart';

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
  const TravelCompanionsPage({super.key});
  @override
  State<TravelCompanionsPage> createState() => _TravelCompanionsPageState();
}

class _TravelCompanionsPageState extends State<TravelCompanionsPage> {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ── 加入旅伴（支援 Firebase 用戶搜尋）─────────────────────
  Future<void> _addCompanion(String tripId, Color primary) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCompanionSheet(
        primary: primary,
        onAdd: (name, email, uid, photoUrl) async {
          await _db.collection('trips').doc(tripId).collection('companions').add({
            'name':     name,
            'email':    email,
            'uid':      uid ?? '',
            'photoUrl': photoUrl ?? '',
            'addedBy':  _uid ?? '',
            'addedAt':  FieldValue.serverTimestamp(),
          });
        },
      ),
    );
  }

  // ── 移除旅伴 ────────────────────────────────────────────────
  Future<void> _removeCompanion(String tripId, String companionId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('移除旅伴', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('確定要移除「$name」嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    await _db.collection('trips').doc(tripId).collection('companions').doc(companionId).delete();
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
          : StreamBuilder<List<FirebaseTrip>>(
              stream: TripService.tripsStream(),
              builder: (ctx, tripSnap) {
                final trips = tripSnap.data ?? [];
                if (tripSnap.connectionState == ConnectionState.waiting && trips.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (trips.isEmpty) {
                  return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.map_rounded, size: 48, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      const Text('還沒有任何行程', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('先在「行程管理」建立行程', style: TextStyle(color: AppColors.textHint)),
                    ],
                  ));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: trips.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (_, i) => _TripCompanionCard(
                    trip: trips[i],
                    primary: primary,
                    onAddCompanion: () => _addCompanion(trips[i].id, primary),
                    onRemoveCompanion: (cid, name) =>
                        _removeCompanion(trips[i].id, cid, name),
                  ),
                );
              },
            ),
    );
  }
}

/// 每個行程的旅伴卡片
class _TripCompanionCard extends StatelessWidget {
  final FirebaseTrip trip;
  final Color primary;
  final VoidCallback onAddCompanion;
  final void Function(String, String) onRemoveCompanion;
  const _TripCompanionCard({
    required this.trip,
    required this.primary,
    required this.onAddCompanion,
    required this.onRemoveCompanion,
  });

  @override
  Widget build(BuildContext context) {
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 行程標題
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
            IconButton(
              icon: Icon(Icons.person_add_rounded, color: primary, size: 22),
              onPressed: onAddCompanion,
              tooltip: '新增旅伴',
            ),
          ]),
        ),

        // 旅伴列表
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
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.group_outlined, size: 16, color: AppColors.textHint),
                  const SizedBox(width: 8),
                  Text('尚無旅伴，點擊 + 新增',
                    style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                ]),
              );
            }
            return Column(
              children: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final name     = d['name']  as String? ?? '旅伴';
                final email    = d['email'] as String? ?? '';
                // 相容新（photoURL）舊（photoUrl）欄位名稱
                final photoUrl = (d['photoURL'] ?? d['photoUrl'] ?? '') as String;
                final isReal   = (d['uid'] as String? ?? '').isNotEmpty;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: primary.withValues(alpha: 0.12),
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? Text(name.isNotEmpty ? name[0] : '?',
                            style: TextStyle(color: primary, fontWeight: FontWeight.w800))
                        : null,
                  ),
                  title: Row(children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (isReal) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(4)),
                        child: Text('已連結', style: TextStyle(fontSize: 9, color: primary, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  subtitle: email.isNotEmpty
                      ? Text(email, style: const TextStyle(fontSize: 11, color: AppColors.textHint))
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded,
                        color: AppColors.error, size: 20),
                    onPressed: () => onRemoveCompanion(doc.id, name),
                  ),
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

// ═══════════════════════════════════════════════════════════
//  新增旅伴 Sheet（支援搜尋 Firebase 用戶，含 Google 帳號）
// ═══════════════════════════════════════════════════════════
class _AddCompanionSheet extends StatefulWidget {
  final Color primary;
  final Future<void> Function(String name, String email, String? uid, String? photoUrl) onAdd;
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
      // 先搜尋 email 欄位
      var q = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      // 若找不到，嘗試搜尋 Google 帳號（uid 對應的 email）
      if (q.docs.isEmpty) {
        q = await FirebaseFirestore.instance
            .collection('users')
            .where('emailAddress', isEqualTo: email)
            .limit(1)
            .get();
      }
      if (q.docs.isEmpty) {
        setState(() { _searching = false; _notFound = true; });
      } else {
        final d = q.docs.first.data();
        setState(() {
          _searching = false;
          _foundUser = {
            ...d,
            'uid': q.docs.first.id,
          };
        });
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
    // 相容新（photoURL）舊（photoUrl）欄位名稱
    final photo = (user?['photoURL'] ?? user?['photoUrl'] ?? '') as String;
    await widget.onAdd(name.toString(), email.toString(), uid, photo);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addManual() async {
    if (_adding || _nameCtrl.text.trim().isEmpty) return;
    setState(() => _adding = true);
    await widget.onAdd(_nameCtrl.text.trim(), _emailCtrl.text.trim(), null, null);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

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
          // 搜尋結果
          if (_notFound) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.person_off_rounded, size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                const Expanded(child: Text('找不到此 Email 的用戶，可改用手動輸入', style: TextStyle(fontSize: 12, color: AppColors.error))),
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
                    found['nickname'] ?? found['displayName'] ?? found['name'] ?? '用戶',
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
        ]),
      ),
    );
  }
}
