import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ── Firestore 路徑常數 ─────────────────────────────────────────
// community_posts/{postId}
// community_posts/{postId}/comments/{commentId}
// users/{uid}/liked_posts/{postId}
// users/{uid}/saved_posts/{postId}
// users/{uid}/liked_comments/{commentId}

class CommunityPost {
  final String id;
  final String authorId;
  final String authorName;
  final String authorPhoto;
  final String title;
  final String content;
  final List<String> imageURLs;
  final List<String> spotNames;
  final String type; // 'trip' | 'discussion'
  final int likeCount;
  final int commentCount;
  final int saveCount;
  final DateTime createdAt;

  const CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhoto,
    required this.title,
    required this.content,
    required this.imageURLs,
    required this.spotNames,
    required this.type,
    required this.likeCount,
    required this.commentCount,
    required this.saveCount,
    required this.createdAt,
  });

  factory CommunityPost.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CommunityPost(
      id:           doc.id,
      authorId:     d['authorId']    as String? ?? '',
      authorName:   d['authorName']  as String? ?? '匿名旅人',
      authorPhoto:  d['authorPhoto'] as String? ?? '',
      title:        d['title']       as String? ?? '',
      content:      d['content']     as String? ?? '',
      imageURLs:    List<String>.from(d['imageURLs'] ?? []),
      spotNames:    List<String>.from(d['spotNames'] ?? []),
      type:         d['type']        as String? ?? 'trip',
      likeCount:    (d['likeCount']    as num?)?.toInt() ?? 0,
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
      saveCount:    (d['saveCount']    as num?)?.toInt() ?? 0,
      createdAt:    (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'authorId':    authorId,
    'authorName':  authorName,
    'authorPhoto': authorPhoto,
    'title':       title,
    'content':     content,
    'imageURLs':   imageURLs,
    'spotNames':   spotNames,
    'type':        type,
    'likeCount':   likeCount,
    'commentCount':commentCount,
    'saveCount':   saveCount,
    'createdAt':   FieldValue.serverTimestamp(),
  };
}

class CommunityComment {
  final String id;
  final String authorId;
  final String authorName;
  final String authorPhoto;
  final String text;
  final String? imageUrl;
  final int likeCount;
  final DateTime createdAt;

  const CommunityComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhoto,
    required this.text,
    this.imageUrl,
    required this.likeCount,
    required this.createdAt,
  });

  factory CommunityComment.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CommunityComment(
      id:          doc.id,
      authorId:    d['authorId']    as String? ?? '',
      authorName:  d['authorName']  as String? ?? '匿名旅人',
      authorPhoto: d['authorPhoto'] as String? ?? '',
      text:        d['text']        as String? ?? '',
      imageUrl:    d['imageUrl']    as String?,
      likeCount:   (d['likeCount'] as num?)?.toInt() ?? 0,
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class CommunityService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static final _storage = FirebaseStorage.instance;

  static String? get _uid => _auth.currentUser?.uid;

  // ── 貼文集合 ──────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('community_posts');

  // ── 讀取貼文串流（避免複合索引問題，用 Dart 端過濾）──────────
  static Stream<List<CommunityPost>> postsStream({
    String type = 'all',
    bool byLikes = false,
  }) {
    // Single-field orderBy avoids composite index requirements.
    // Type filtering is done client-side.
    final query = _posts.orderBy(
      byLikes ? 'likeCount' : 'createdAt',
      descending: true,
    );
    return query.snapshots().map((snap) {
      var posts = snap.docs.map(CommunityPost.fromDoc).toList();
      if (type != 'all') posts = posts.where((p) => p.type == type).toList();
      return posts;
    });
  }

  // ── 建立貼文 ──────────────────────────────────────────────────
  static Future<String> createPost({
    required String title,
    required String content,
    required String type,
    List<File> images = const [],
    List<String> spotNames = const [],
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('未登入');

    // 上傳圖片
    final imageURLs = <String>[];
    for (final img in images) {
      final ref = _storage.ref(
          'community_posts/${DateTime.now().millisecondsSinceEpoch}_${img.path.split('/').last}');
      await ref.putFile(img);
      imageURLs.add(await ref.getDownloadURL());
    }

    final post = CommunityPost(
      id: '', authorId: user.uid,
      authorName:  user.displayName ?? '旅人',
      authorPhoto: user.photoURL ?? '',
      title: title, content: content,
      imageURLs: imageURLs, spotNames: spotNames,
      type: type, likeCount: 0, commentCount: 0, saveCount: 0,
      createdAt: DateTime.now(),
    );

    final ref = await _posts.add(post.toMap());
    return ref.id;
  }

  // ── 按讚 / 取消讚 ─────────────────────────────────────────────
  static Future<bool> toggleLike(String postId) async {
    final uid = _uid;
    if (uid == null) return false;
    final likedRef = _db.collection('users').doc(uid)
        .collection('liked_posts').doc(postId);
    final postRef  = _posts.doc(postId);

    final liked = await likedRef.get();
    if (liked.exists) {
      await Future.wait([
        likedRef.delete(),
        postRef.update({'likeCount': FieldValue.increment(-1)}),
      ]);
      return false;
    } else {
      await Future.wait([
        likedRef.set({'likedAt': FieldValue.serverTimestamp()}),
        postRef.update({'likeCount': FieldValue.increment(1)}),
      ]);
      return true;
    }
  }

  // ── 檢查是否已按讚 ────────────────────────────────────────────
  static Future<bool> isLiked(String postId) async {
    final uid = _uid;
    if (uid == null) return false;
    final snap = await _db.collection('users').doc(uid)
        .collection('liked_posts').doc(postId).get();
    return snap.exists;
  }

  // ── 批次檢查按讚狀態 ──────────────────────────────────────────
  static Future<Set<String>> getLikedPostIds(List<String> postIds) async {
    final uid = _uid;
    if (uid == null || postIds.isEmpty) return {};
    final snaps = await Future.wait(postIds.map((id) =>
        _db.collection('users').doc(uid).collection('liked_posts').doc(id).get()));
    return snaps.where((s) => s.exists).map((s) => s.id).toSet();
  }

  // ── 收藏 / 取消收藏 ──────────────────────────────────────────
  static Future<bool> toggleSave(String postId) async {
    final uid = _uid;
    if (uid == null) return false;
    final savedRef = _db.collection('users').doc(uid)
        .collection('saved_posts').doc(postId);
    final postRef  = _posts.doc(postId);

    final saved = await savedRef.get();
    if (saved.exists) {
      await Future.wait([
        savedRef.delete(),
        postRef.update({'saveCount': FieldValue.increment(-1)}),
      ]);
      return false;
    } else {
      await Future.wait([
        savedRef.set({'savedAt': FieldValue.serverTimestamp()}),
        postRef.update({'saveCount': FieldValue.increment(1)}),
      ]);
      return true;
    }
  }

  static Future<Set<String>> getSavedPostIds(List<String> ids) async {
    final uid = _uid;
    if (uid == null || ids.isEmpty) return {};
    final snaps = await Future.wait(ids.map((id) =>
        _db.collection('users').doc(uid).collection('saved_posts').doc(id).get()));
    return snaps.where((s) => s.exists).map((s) => s.id).toSet();
  }

  // ── 留言 ──────────────────────────────────────────────────────
  static Stream<List<CommunityComment>> commentsStream(String postId) =>
      _posts.doc(postId).collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((s) => s.docs.map(CommunityComment.fromDoc).toList());

  static Future<void> addComment(String postId, String text, {File? image}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('未登入');
    String? imageUrl;
    if (image != null) {
      final ref = _storage.ref(
          'comment_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_${image.path.split('/').last}');
      await ref.putFile(image);
      imageUrl = await ref.getDownloadURL();
    }
    await Future.wait([
      _posts.doc(postId).collection('comments').add({
        'authorId':    user.uid,
        'authorName':  user.displayName ?? '旅人',
        'authorPhoto': user.photoURL ?? '',
        'text':        text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'likeCount':   0,
        'createdAt':   FieldValue.serverTimestamp(),
      }),
      _posts.doc(postId).update({'commentCount': FieldValue.increment(1)}),
    ]);
  }

  // ── 留言按讚 ──────────────────────────────────────────────────
  static Future<bool> toggleCommentLike(String postId, String commentId) async {
    final uid = _uid;
    if (uid == null) return false;
    final likedRef = _db.collection('users').doc(uid)
        .collection('liked_comments').doc(commentId);
    final commentRef = _posts.doc(postId).collection('comments').doc(commentId);

    final liked = await likedRef.get();
    if (liked.exists) {
      await Future.wait([
        likedRef.delete(),
        commentRef.update({'likeCount': FieldValue.increment(-1)}),
      ]);
      return false;
    } else {
      await Future.wait([
        likedRef.set({'likedAt': FieldValue.serverTimestamp()}),
        commentRef.update({'likeCount': FieldValue.increment(1)}),
      ]);
      return true;
    }
  }

  static Future<Set<String>> getLikedCommentIds(List<String> ids) async {
    final uid = _uid;
    if (uid == null || ids.isEmpty) return {};
    final snaps = await Future.wait(ids.map((id) =>
        _db.collection('users').doc(uid).collection('liked_comments').doc(id).get()));
    return snaps.where((s) => s.exists).map((s) => s.id).toSet();
  }

  // ── 刪除貼文（僅作者） ────────────────────────────────────────
  static Future<void> deletePost(String postId) async {
    if (_uid == null) return;
    await _posts.doc(postId).delete();
  }

  // ── 追蹤 / 取消追蹤（以 authorId 為 key）────────────────────
  static Future<bool> toggleFollow(String targetUserId, String targetName) async {
    final uid = _uid;
    if (uid == null) return false;
    final ref = _db.collection('users').doc(uid)
        .collection('following').doc(targetUserId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return false;
    } else {
      await ref.set({'userId': targetUserId, 'name': targetName,
          'followedAt': FieldValue.serverTimestamp()});
      return true;
    }
  }

  static Future<bool> isFollowing(String targetUserId) async {
    final uid = _uid;
    if (uid == null) return false;
    final snap = await _db.collection('users').doc(uid)
        .collection('following').doc(targetUserId).get();
    return snap.exists;
  }

  static Stream<Set<String>> followingIdsStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _db.collection('users').doc(uid).collection('following')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  /// Posts from followed authors
  static Stream<List<CommunityPost>> followingPostsStream(Set<String> followingIds) {
    if (followingIds.isEmpty) return Stream.value([]);
    // Firestore whereIn supports max 30 values
    final ids = followingIds.take(30).toList();
    return _posts
        .where('authorId', whereIn: ids)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CommunityPost.fromDoc).toList());
  }
}
