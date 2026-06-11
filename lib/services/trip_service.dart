import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────
// FirebaseTrip model
// ─────────────────────────────────────────────────────────────
class FirebaseTrip {
  final String id;
  final String uid;
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final List<String> spots;
  final int days;
  final bool isCompleted;
  final String? coverUrl;
  final String icon;
  final DateTime createdAt;

  // ── 景點詳細資訊（存在行程文件內）────────────────────────────
  /// 各景點到達時間  key = spotName, value = 'HH:mm'
  final Map<String, String> spotTimes;
  /// 各景點預算（元）key = spotName, value = budget int
  final Map<String, int> spotBudgets;
  /// 各景點備注       key = spotName, value = note string
  final Map<String, String> spotNotes;

  /// 被邀請加入的成員 UIDs（不包含建立者）
  final List<String> members;

  const FirebaseTrip({
    required this.id,
    required this.uid,
    required this.title,
    required this.startDate,
    this.endDate,
    required this.spots,
    required this.days,
    required this.isCompleted,
    this.coverUrl,
    this.icon = 'map',
    required this.createdAt,
    this.members    = const [],
    this.spotTimes  = const {},
    this.spotBudgets= const {},
    this.spotNotes  = const {},
  });

  factory FirebaseTrip.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    Map<String, T> _toMap<T>(dynamic raw, T Function(dynamic) cast) {
      if (raw is Map) {
        return {for (final e in raw.entries) e.key.toString(): cast(e.value)};
      }
      return {};
    }
    return FirebaseTrip(
      id:          doc.id,
      uid:         d['uid']         as String? ?? '',
      title:       d['title']       as String? ?? '未命名行程',
      startDate:   (d['startDate']  as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate:     (d['endDate']    as Timestamp?)?.toDate(),
      spots:       List<String>.from(d['spots'] ?? []),
      days:        (d['days']       as num?)?.toInt() ?? 1,
      isCompleted: d['isCompleted'] as bool? ?? false,
      coverUrl:    d['coverUrl']    as String?,
      icon:        d['icon']        as String? ?? 'map',
      createdAt:   (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
      members:     List<String>.from(d['members'] ?? []),
      spotTimes:   _toMap<String>(d['spotTimes'],   (v) => v.toString()),
      spotBudgets: _toMap<int>   (d['spotBudgets'], (v) => (v as num).toInt()),
      spotNotes:   _toMap<String>(d['spotNotes'],   (v) => v.toString()),
    );
  }

  /// 從 spots 的 __DAY_X__ 標記推算實際天數（AI 套用後 days 欄位可能未更新）
  int get actualDays {
    final maxFromSpots = spots
        .where((s) => s.startsWith('__DAY_'))
        .map((s) => int.tryParse(RegExp(r'__DAY_(\d+)__').firstMatch(s)?.group(1) ?? '0') ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    return maxFromSpots > 0 ? maxFromSpots : days;
  }

  String get dateDisplay {
    final s = '${startDate.year}-${_pad(startDate.month)}-${_pad(startDate.day)}';
    if (endDate == null) return s;
    return '$s ～ ${_pad(endDate!.month)}-${_pad(endDate!.day)}';
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────
// TripService — Firestore CRUD
// ─────────────────────────────────────────────────────────────
class TripService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static String? get _uid => _auth.currentUser?.uid;

  // ── Trips ─────────────────────────────────────────────────
  static Stream<List<FirebaseTrip>> tripsStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    // 合併兩個 stream：自己的行程 + 被邀請加入的行程
    final ownStream = _db.collection('trips').where('uid', isEqualTo: uid).snapshots();
    final memberStream = _db.collection('trips').where('members', arrayContains: uid).snapshots();

    QuerySnapshot? latestOwn;
    QuerySnapshot? latestMember;

    List<FirebaseTrip> _merge() {
      final seen = <String>{};
      final merged = <FirebaseTrip>[];
      for (final doc in [
        ...?latestOwn?.docs,
        ...?latestMember?.docs,
      ]) {
        if (seen.add(doc.id)) merged.add(FirebaseTrip.fromDoc(doc));
      }
      merged.sort((x, y) => y.createdAt.compareTo(x.createdAt));
      return merged;
    }

    late StreamController<List<FirebaseTrip>> ctrl;
    ctrl = StreamController<List<FirebaseTrip>>.broadcast(
      onListen: () {
        ownStream.listen((s) { latestOwn = s; ctrl.add(_merge()); });
        memberStream.listen((s) { latestMember = s; ctrl.add(_merge()); });
      },
    );
    return ctrl.stream;
  }

  /// 即時監聽單一行程文件（行程詳情頁用，景點加入後即時更新）
  static Stream<FirebaseTrip?> tripDocStream(String tripId) =>
      _db.collection('trips').doc(tripId).snapshots().map((snap) {
        if (!snap.exists) return null;
        return FirebaseTrip.fromDoc(snap);
      });

  static Future<String> createTrip({
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    List<String> spots = const [],
    String? coverUrl,
    String icon = 'map',
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('未登入');
    final days = endDate != null
        ? endDate.difference(startDate).inDays + 1
        : 1;
    final ref = await _db.collection('trips').add({
      'uid':         uid,
      'title':       title,
      'startDate':   Timestamp.fromDate(startDate),
      if (endDate != null) 'endDate': Timestamp.fromDate(endDate),
      'spots':       spots,
      'days':        days,
      'isCompleted': false,
      'coverUrl':    coverUrl ?? 'https://picsum.photos/seed/${title.hashCode.abs()}/600/200',
      'icon':        icon,
      'createdAt':   FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> addSpotToTrip(String tripId, String spotName) async {
    await _db.collection('trips').doc(tripId).update({
      'spots': FieldValue.arrayUnion([spotName]),
    });
  }

  /// 批次套用景點清單到行程（來自社群貼文的「套用行程」功能）
  static Future<void> applySpots(String tripId, List<String> spotNames) async {
    if (spotNames.isEmpty) return;
    await _db.collection('trips').doc(tripId).update({
      'spots': FieldValue.arrayUnion(spotNames),
    });
  }

  /// 更新景點排序（整體替換 spots 陣列）
  static Future<void> updateSpotOrder(String tripId, List<String> ordered) =>
      _db.collection('trips').doc(tripId).update({'spots': ordered});

  /// 儲存景點到達時間
  static Future<void> setSpotTime(String tripId, String spotName, String time) =>
      _db.collection('trips').doc(tripId).update({'spotTimes.$spotName': time});

  /// 儲存景點預算
  static Future<void> setSpotBudget(String tripId, String spotName, int budget) =>
      _db.collection('trips').doc(tripId).update({'spotBudgets.$spotName': budget});

  /// 儲存景點備注
  static Future<void> setSpotNote(String tripId, String spotName, String note) =>
      _db.collection('trips').doc(tripId).update({'spotNotes.$spotName': note});

  static Future<void> updateTrip(String tripId, Map<String, dynamic> data) =>
      _db.collection('trips').doc(tripId).update(data);

  static Future<void> deleteTrip(String tripId) =>
      _db.collection('trips').doc(tripId).delete();

  /// 退出共享行程：從 members 陣列移除自己的 uid
  static Future<void> leaveTrip(String tripId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('trips').doc(tripId).update({
      'members': FieldValue.arrayRemove([uid]),
    });
  }

  static Future<void> setCompleted(String tripId, {required bool completed}) =>
      _db.collection('trips').doc(tripId).update({'isCompleted': completed});

  static Future<void> setIcon(String tripId, String icon) =>
      _db.collection('trips').doc(tripId).update({'icon': icon});

  // ── Per-Trip Candidates (stored under trips/{tripId}/candidates) ──────
  static CollectionReference<Map<String, dynamic>> _tripCandidatesRef(String tripId) =>
      _db.collection('trips').doc(tripId).collection('candidates');

  static Stream<List<Map<String, dynamic>>> tripCandidatesStream(String tripId) =>
      _tripCandidatesRef(tripId)
          .orderBy('order')
          .snapshots()
          .map((s) => s.docs.map((d) => {...d.data(), '__id': d.id}).toList());

  static Future<void> addTripCandidate(String tripId, {
    required String spotId,
    required String spotName,
    required String category,
    required int order,
  }) async {
    await _tripCandidatesRef(tripId).doc(spotId).set({
      'spotId': spotId, 'spotName': spotName, 'category': category,
      'order': order, 'addedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeTripCandidate(String tripId, String spotId) =>
      _tripCandidatesRef(tripId).doc(spotId).delete();

  static Future<void> reorderTripCandidates(String tripId, List<String> spotIds) async {
    final batch = _db.batch();
    for (var i = 0; i < spotIds.length; i++) {
      batch.update(_tripCandidatesRef(tripId).doc(spotIds[i]), {'order': i});
    }
    await batch.commit();
  }

  // Add spot name to the trip's spots array (for timeline display)
  static Future<void> convertCandidatesToSpots(String tripId) async {
    final snap = await _tripCandidatesRef(tripId).orderBy('order').get();
    final names = snap.docs.map((d) => d['spotName'].toString()).toList();
    if (names.isEmpty) return;
    await _db.collection('trips').doc(tripId).update({
      'spots': FieldValue.arrayUnion(names),
    });
    // Clear candidates after converting
    final batch = _db.batch();
    for (final doc in snap.docs) batch.delete(doc.reference);
    await batch.commit();
  }

  // ── Saved spots ───────────────────────────────────────────
  /// Returns full saved-spot data (spotId, spotName, imageUrl, rating, savedAt, description, address, category)
  static Stream<List<Map<String, dynamic>>> savedSpotsDataStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    // 不加 orderBy，client-side sort，避免需要 composite index
    return _db
        .collection('users').doc(uid).collection('saved_spots')
        .snapshots()
        .map((s) {
          final list = s.docs.map((d) => {...d.data(), '__id': d.id}).toList();
          list.sort((a, b) {
            final ta = (a['savedAt'] as dynamic)?.toDate()?.millisecondsSinceEpoch ?? 0;
            final tb = (b['savedAt'] as dynamic)?.toDate()?.millisecondsSinceEpoch ?? 0;
            return tb.compareTo(ta);
          });
          return list;
        });
  }

  static Stream<Set<String>> savedSpotIdsStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users').doc(uid).collection('saved_spots')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  // ── Global candidates (user-level, not trip-specific) ──────────
  static Future<void> addCandidate({
    required String spotId,
    required String spotName,
    required String category,
    required int order,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).collection('candidates').doc(spotId).set({
      'spotId':   spotId,
      'spotName': spotName,
      'category': category,
      'order':    order,
      'addedAt':  FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeCandidate(String spotId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).collection('candidates').doc(spotId).delete();
  }

  static Future<void> reorderCandidates(List<String> spotIds) async {
    final uid = _uid;
    if (uid == null) return;
    final batch = _db.batch();
    final ref = _db.collection('users').doc(uid).collection('candidates');
    for (var i = 0; i < spotIds.length; i++) {
      batch.update(ref.doc(spotIds[i]), {'order': i});
    }
    await batch.commit();
  }

  static Future<bool> toggleSavedSpot(
    String spotId, {
    required String spotName,
    String imageUrl  = '',
    double rating    = 0.0,
    String description = '',
    String address   = '',
    String category  = '',
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    final ref = _db.collection('users').doc(uid).collection('saved_spots').doc(spotId);
    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
      return false;
    } else {
      await ref.set({
        'spotId':      spotId,
        'spotName':    spotName,
        'imageUrl':    imageUrl,
        'rating':      rating,
        if (description.isNotEmpty) 'description': description,
        if (address.isNotEmpty)     'address':     address,
        if (category.isNotEmpty)    'category':    category,
        'savedAt':     FieldValue.serverTimestamp(),
      });
      return true;
    }
  }
}
