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
  final String icon; // custom emoji / icon for the trip
  final DateTime createdAt;

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
    this.icon = '🗺️',
    required this.createdAt,
  });

  factory FirebaseTrip.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
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
      icon:        d['icon']        as String? ?? '🗺️',
      createdAt:   (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
    );
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
    return _db
        .collection('trips')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(FirebaseTrip.fromDoc).toList());
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
    String icon = '🗺️',
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

  static Future<void> updateTrip(String tripId, Map<String, dynamic> data) =>
      _db.collection('trips').doc(tripId).update(data);

  static Future<void> deleteTrip(String tripId) =>
      _db.collection('trips').doc(tripId).delete();

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
  /// Returns full saved-spot data (spotId, spotName, imageUrl, rating, savedAt)
  static Stream<List<Map<String, dynamic>>> savedSpotsDataStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users').doc(uid).collection('saved_spots')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {...d.data(), '__id': d.id}).toList());
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
    String imageUrl = '',
    double rating = 0.0,
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
        'spotId':   spotId,
        'spotName': spotName,
        'imageUrl': imageUrl,
        'rating':   rating,
        'savedAt':  FieldValue.serverTimestamp(),
      });
      return true;
    }
  }
}
