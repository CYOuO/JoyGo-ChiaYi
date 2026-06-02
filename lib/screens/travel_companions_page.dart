import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

  // ── 加入旅伴 ────────────────────────────────────────────────
  Future<void> _addCompanion(String tripId, Color primary) async {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('新增旅伴', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
            decoration: const InputDecoration(labelText: '旅伴姓名', hintText: '例如：小明')),
          const SizedBox(height: 10),
          TextField(controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email（選填）', hintText: 'example@mail.com')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim().isNotEmpty),
            child: Text('新增', style: TextStyle(color: primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    await _db.collection('trips').doc(tripId).collection('companions').add({
      'name':     nameCtrl.text.trim(),
      'email':    emailCtrl.text.trim(),
      'addedBy':  _uid ?? '',
      'addedAt':  FieldValue.serverTimestamp(),
    });
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
                final name  = d['name']  as String? ?? '旅伴';
                final email = d['email'] as String? ?? '';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: primary.withValues(alpha: 0.12),
                    child: Text(name.isNotEmpty ? name[0] : '?',
                      style: TextStyle(color: primary, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
