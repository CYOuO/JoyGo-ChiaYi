import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/community_service.dart';
import 'community_screen.dart' show FirebasePostDetailPage;

class SavedPostsPage extends StatelessWidget {
  const SavedPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final primary  = Theme.of(context).colorScheme.primary;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: uid == null
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.textHint.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              const Text('請先登入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]))
          : _SavedPostsList(uid: uid, primary: primary),
    );
  }
}

class _SavedPostsList extends StatelessWidget {
  final String uid;
  final Color primary;
  const _SavedPostsList({required this.uid, required this.primary});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('saved_posts')
          .orderBy('savedAt', descending: true)
          .snapshots(),
      builder: (ctx, savedSnap) {
        if (savedSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final savedIds = savedSnap.data?.docs.map((d) => d.id).toList() ?? [];
        if (savedIds.isEmpty) {
          return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bookmark_border_rounded, size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              const Text('還沒有收藏貼文', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('在社群頁面點擊收藏圖示即可收藏', style: TextStyle(color: AppColors.textHint)),
            ],
          ));
        }

        // 逐一讀取貼文
        return FutureBuilder<List<CommunityPost>>(
          future: _fetchSavedPosts(savedIds),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = snap.data ?? [];
            if (posts.isEmpty) {
              return Center(child: Text('收藏的貼文已被刪除或無法讀取',
                style: TextStyle(color: AppColors.textHint)));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _SavedPostCard(post: posts[i], primary: primary, uid: uid),
            );
          },
        );
      },
    );
  }

  Future<List<CommunityPost>> _fetchSavedPosts(List<String> ids) async {
    final futures = ids.map((id) => FirebaseFirestore.instance
        .collection('community_posts').doc(id).get());
    final snaps = await Future.wait(futures);
    return snaps
        .where((s) => s.exists)
        .map(CommunityPost.fromDoc)
        .toList();
  }
}

class _SavedPostCard extends StatelessWidget {
  final CommunityPost post;
  final Color primary;
  final String uid;
  const _SavedPostCard({required this.post, required this.primary, required this.uid});

  @override
  Widget build(BuildContext context) {
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FirebasePostDetailPage(post: post))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          // 封面圖
          if (post.imageURLs.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: Image.network(post.imageURLs.first,
                width: 80, height: 90, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 80, height: 90,
                  color: mist,
                  child: const Icon(Icons.image_not_supported_rounded, color: AppColors.textHint)),
              ),
            )
          else
            Container(
              width: 80, height: 90,
              decoration: BoxDecoration(
                color: mist,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
              child: Center(child: Text(
                post.type == 'trip' ? '🧳' : '💬',
                style: const TextStyle(fontSize: 28))),
            ),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(8)),
                child: Text(post.type == 'trip' ? '🧳 行程分享' : '💬 討論區',
                  style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 6),
              Text(post.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.favorite_rounded, size: 12, color: AppColors.error.withValues(alpha: 0.7)),
                const SizedBox(width: 3),
                Text('${post.likeCount}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                const SizedBox(width: 10),
                Icon(Icons.chat_bubble_outline_rounded, size: 12, color: AppColors.textHint),
                const SizedBox(width: 3),
                Text('${post.commentCount}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ]),
            ]),
          )),
          // 取消收藏
          IconButton(
            icon: const Icon(Icons.bookmark_rounded, color: AppColors.accentTerra, size: 20),
            onPressed: () async {
              await CommunityService.toggleSave(post.id);
            },
          ),
        ]),
      ),
    );
  }
}
