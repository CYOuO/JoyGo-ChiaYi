import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/community_service.dart';
import '../theme/fabric_textures.dart';

/// 通用使用者個人頁面 BottomSheet
/// 可從通知、社群貼文等任何地方呼叫
Future<void> showUserProfileSheet(
  BuildContext context, {
  required String uid,
  required Color primary,
  String? knownName,
  String? knownPhoto,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _UserProfileSheetContent(
      uid: uid,
      primary: primary,
      knownName: knownName,
      knownPhoto: knownPhoto,
    ),
  );
}

class _UserProfileSheetContent extends StatefulWidget {
  final String uid;
  final Color primary;
  final String? knownName;
  final String? knownPhoto;
  const _UserProfileSheetContent({
    required this.uid,
    required this.primary,
    this.knownName,
    this.knownPhoto,
  });
  @override
  State<_UserProfileSheetContent> createState() => _UserProfileSheetContentState();
}

class _UserProfileSheetContentState extends State<_UserProfileSheetContent> {
  bool _isFollowing = false;
  bool _followLoading = true;
  Map<String, dynamic> _userData = {};
  List<Map<String, dynamic>> _posts = [];
  bool _dataLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 並行：用戶資料 + 追蹤狀態 + 貼文
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(widget.uid).get(),
        CommunityService.isFollowing(widget.uid),
        FirebaseFirestore.instance
            .collection('community_posts')
            .where('authorId', isEqualTo: widget.uid)
            .limit(9)
            .get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final following = results[1] as bool;
      final postsSnap = results[2] as QuerySnapshot;

      if (!mounted) return;
      setState(() {
        _userData = userDoc.data() as Map<String, dynamic>? ?? {};
        _isFollowing = following;
        _posts = postsSnap.docs
            .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
            .toList()
          ..sort((a, b) {
            final ta = (a['createdAt'] as dynamic)?.toDate()?.millisecondsSinceEpoch ?? 0;
            final tb = (b['createdAt'] as dynamic)?.toDate()?.millisecondsSinceEpoch ?? 0;
            return tb.compareTo(ta);
          });
        _dataLoading = false;
        _followLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _dataLoading = false; _followLoading = false; });
    }
  }

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    setState(() => _followLoading = true);
    final name = _userData['nickname'] ?? _userData['displayName'] ?? '使用者';
    try {
      final result = await CommunityService.toggleFollow(widget.uid, name.toString());
      if (mounted) setState(() { _isFollowing = result; _followLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.knownName?.isNotEmpty == true
        ? widget.knownName
        : (_userData['nickname'] ?? _userData['displayName'] ?? '使用者')) as String;
    final photo = (widget.knownPhoto?.isNotEmpty == true
        ? widget.knownPhoto
        : (_userData['photoURL'] ?? _userData['photoUrl'] ?? '')) as String;
    final followers = (_userData['followersCount'] as num?)?.toInt() ?? 0;
    final following = (_userData['followingCount'] as num?)?.toInt() ?? 0;
    final p = widget.primary;
    final myUid = CommunityService.currentUid;
    final isSelf = myUid == widget.uid;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // drag handle
          Container(width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),

          // ── 頭像 + 名字 ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Stack(children: [
                CircleAvatar(
                  radius: 34,
                  backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                  backgroundColor: p.withValues(alpha: 0.12),
                  child: photo.isEmpty ? Icon(Icons.person_rounded, size: 32, color: p) : null,
                ),
                if (_isFollowing)
                  Positioned(bottom: 0, right: 0,
                    child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(color: p, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    )),
              ]),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  if (!_dataLoading)
                    Row(children: [
                      _statChip('$followers', '追蹤者', p),
                      const SizedBox(width: 12),
                      _statChip('$following', '追蹤中', p),
                      const SizedBox(width: 12),
                      _statChip('${_posts.length}', '貼文', p),
                    ])
                  else
                    Container(height: 14, width: 120,
                        decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4))),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── 追蹤按鈕（自己不顯示）──────────────────────────
          if (!isSelf)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _followLoading ? null : _toggleFollow,
                  icon: _followLoading
                      ? SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(_isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined, size: 18),
                  label: Text(_isFollowing ? '取消追蹤' : '追蹤'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFollowing ? p.withValues(alpha: 0.12) : p,
                    foregroundColor: _isFollowing ? p : Colors.white,
                    side: _isFollowing ? BorderSide(color: p, width: 1.2) : null,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),
          JournalDivider(color: p.withValues(alpha: 0.15)),
          const SizedBox(height: 8),

          // ── 貼文標題 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Icon(Icons.grid_view_rounded, size: 15, color: p),
              const SizedBox(width: 6),
              Text('的貼文', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p)),
            ]),
          ),
          const SizedBox(height: 10),

          // ── 貼文格 ────────────────────────────────────────
          Expanded(
            child: _dataLoading
                ? Center(child: CircularProgressIndicator(color: p, strokeWidth: 2))
                : _posts.isEmpty
                    ? Center(child: Text('還沒有貼文', style: TextStyle(color: AppColors.textHint)))
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _posts.length,
                        itemBuilder: (_, i) => _postTile(_posts[i], p),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _statChip(String val, String label, Color p) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text(val, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p)),
    const SizedBox(width: 2),
    Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
  ]);

  Widget _postTile(Map<String, dynamic> post, Color p) {
    final content = post['content'] as String? ?? '';
    final imageUrl = (post['imageUrls'] as List?)?.firstOrNull as String?;
    final likes = (post['likeCount'] as num?)?.toInt() ?? 0;
    final ts = post['createdAt'];
    String timeStr = '';
    if (ts is Timestamp) {
      final diff = DateTime.now().difference(ts.toDate());
      if (diff.inDays > 0) timeStr = '${diff.inDays}天前';
      else if (diff.inHours > 0) timeStr = '${diff.inHours}小時前';
      else timeStr = '剛剛';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (imageUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(imageUrl, width: 60, height: 60, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 60, height: 60,
                decoration: BoxDecoration(color: p.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.image_outlined, color: p, size: 24)),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(content, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.5)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.favorite_rounded, size: 13, color: AppColors.textHint),
            const SizedBox(width: 3),
            Text('$likes', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            const Spacer(),
            Text(timeStr, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          ]),
        ])),
      ]),
    );
  }
}
