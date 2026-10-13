import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 管理員 Firestore 操作層
/// Firestore 結構：
///   users/{uid}                 → isAdmin: true
///   custom_spots/{spotId}       → 管理員手動新增景點
///   spot_categories/{catId}     → 景點類別
///   reports/{reportId}          → 舉報紀錄
///   admin_broadcasts/{id}       → 廣播通知紀錄
class AdminService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ─── 身份驗證 ────────────────────────────────────────────────

  /// 檢查目前使用者是否為管理員
  static Future<bool> isAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['isAdmin'] as bool? ?? false;
  }

  // ─── Dashboard 統計 ─────────────────────────────────────────

  static Future<Map<String, int>> fetchDashboardStats() async {
    final results = await Future.wait([
      _db.collection('users').count().get(),
      _db.collection('community_posts').count().get(),
      _db.collection('reports').where('status', isEqualTo: 'pending').count().get(),
      _db.collection('custom_spots').count().get(),
    ]);
    return {
      'users':        results[0].count ?? 0,
      'posts':        results[1].count ?? 0,
      'pendingReports': results[2].count ?? 0,
      'customSpots':  results[3].count ?? 0,
    };
  }

  // ─── 景點管理 ────────────────────────────────────────────────

  static Stream<QuerySnapshot> watchCustomSpots() =>
      _db.collection('custom_spots').orderBy('createdAt', descending: true).snapshots();

  static Future<void> addCustomSpot(Map<String, dynamic> data) async {
    final uid = _auth.currentUser?.uid ?? 'admin';
    await _db.collection('custom_spots').add({
      ...data,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'source': 'admin',
    });
  }

  static Future<void> updateCustomSpot(String id, Map<String, dynamic> data) =>
      _db.collection('custom_spots').doc(id).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> deleteCustomSpot(String id) =>
      _db.collection('custom_spots').doc(id).delete();

  // ─── 類別管理 ────────────────────────────────────────────────

  static Stream<QuerySnapshot> watchCategories() =>
      _db.collection('spot_categories').orderBy('order').snapshots();

  static Future<void> addCategory(String name, String icon, int order) =>
      _db.collection('spot_categories').add({
        'name': name,
        'icon': icon,
        'order': order,
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> deleteCategory(String id) =>
      _db.collection('spot_categories').doc(id).delete();

  // ─── 廣播通知 ────────────────────────────────────────────────

  /// 發送廣播：把通知寫入所有使用者的 notifications 子集合
  static Future<int> broadcastNotification({
    required String title,
    required String body,
    required String type, // 'event' | 'social' | 'achievement'
  }) async {
    final uid = _auth.currentUser?.uid ?? 'admin';
    // 1. 記錄廣播
    await _db.collection('admin_broadcasts').add({
      'title': title,
      'body': body,
      'type': type,
      'sentBy': uid,
      'sentAt': FieldValue.serverTimestamp(),
    });
    // 2. 批次寫入每位使用者（分批，每批 500）
    final usersSnap = await _db.collection('users').get();
    int sent = 0;
    final batches = <WriteBatch>[];
    WriteBatch batch = _db.batch();
    int count = 0;
    for (final userDoc in usersSnap.docs) {
      final ref = _db
          .collection('users')
          .doc(userDoc.id)
          .collection('notifications')
          .doc();
      batch.set(ref, {
        'title': title,
        'body': body,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      sent++;
      if (count == 499) {
        batches.add(batch);
        batch = _db.batch();
        count = 0;
      }
    }
    if (count > 0) batches.add(batch);
    await Future.wait(batches.map((b) => b.commit()));
    return sent;
  }

  // ─── 廣播歷史 ────────────────────────────────────────────────

  static Stream<QuerySnapshot> watchBroadcasts() =>
      _db.collection('admin_broadcasts')
          .orderBy('sentAt', descending: true)
          .limit(50)
          .snapshots();

  // ─── 舉報管理 ────────────────────────────────────────────────

  static Stream<QuerySnapshot> watchReports({String status = 'pending'}) =>
      _db.collection('reports')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots();

  static Future<void> resolveReport(String reportId, {required String action}) =>
      _db.collection('reports').doc(reportId).update({
        'status': action, // 'resolved' | 'dismissed'
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': _auth.currentUser?.uid,
      });

  /// 使用者舉報貼文 / 留言
  static Future<void> submitReport({
    required String type, // 'post' | 'comment' | 'user'
    required String targetId,
    required String targetContent,
    required String reason,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('請先登入');
    await _db.collection('reports').add({
      'type': type,
      'targetId': targetId,
      'targetContent': targetContent,
      'reporterId': uid,
      'reason': reason,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── 貼文審核 ────────────────────────────────────────────────

  static Stream<QuerySnapshot> watchAllPosts({int limit = 30}) =>
      _db.collection('community_posts')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots();

  static Future<void> adminDeletePost(String postId) async {
    final batch = _db.batch();
    // 刪除主文
    batch.delete(_db.collection('community_posts').doc(postId));
    // 刪除留言子集合
    final comments = await _db
        .collection('community_posts')
        .doc(postId)
        .collection('comments')
        .get();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    await batch.commit();
  }

  static Future<void> adminDeleteComment(String postId, String commentId) =>
      _db.collection('community_posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .delete();

  // ─── 使用者管理 ──────────────────────────────────────────────

  static Future<void> banUser(String uid, bool banned) =>
      _db.collection('users').doc(uid).update({'isBanned': banned});

  static Future<void> setAdmin(String uid, bool isAdmin) =>
      _db.collection('users').doc(uid).update({'isAdmin': isAdmin});

  static Stream<QuerySnapshot> watchUsers({int limit = 50}) =>
      _db.collection('users')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots();
}
