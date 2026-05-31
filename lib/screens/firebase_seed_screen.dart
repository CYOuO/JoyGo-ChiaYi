import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

// ════════════════════════════════════════════════════════════
// Firebase 假資料上傳頁（測試用）
// 讓開發者上傳測試貼文，以測試按讚/收藏功能
// ════════════════════════════════════════════════════════════
class FirebaseSeedScreen extends StatefulWidget {
  const FirebaseSeedScreen({super.key});
  @override
  State<FirebaseSeedScreen> createState() => _FirebaseSeedScreenState();
}

class _FirebaseSeedScreenState extends State<FirebaseSeedScreen> {
  bool _seeding = false;
  String _status = '';
  final List<String> _log = [];

  void _addLog(String msg) {
    setState(() => _log.insert(0, msg));
  }

  Future<void> _seedCommunityPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _status = '❌ 請先登入才能上傳資料');
      return;
    }
    setState(() { _seeding = true; _status = '上傳中…'; });
    try {
      final db = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();
      final uid = user.uid;
      final name = user.displayName ?? '測試旅人';
      final photo = user.photoURL ?? '';

      final tripPosts = [
        {
          'authorId': uid, 'authorName': name, 'authorPhoto': photo,
          'title': '嘉義兩天一夜文青輕旅行',
          'content': '第一天早上從台北高鐵出發，中午抵達嘉義，先在民雄鄉吃一碗熱騰騰的鵝肉飯！下午前往阿里山欣賞雲海，傍晚回市區探索文化路夜市。第二天去北門車站拍網美照，再到嘉義市立美術館感受藝文氣息，最後在御品元冰菓室吃一碗紅豆牛奶冰，滿足離開！',
          'imageURLs': ['https://picsum.photos/seed/chiayi1/800/500'],
          'spotNames': ['阿里山國家風景區', '北門車站', '文化路夜市', '嘉義市立美術館'],
          'type': 'trip', 'likeCount': 47, 'commentCount': 8, 'saveCount': 23,
          'createdAt': now,
        },
        {
          'authorId': uid, 'authorName': name, 'authorPhoto': photo,
          'title': '親子一日遊：嘉義公園 × 動物園',
          'content': '帶小孩來嘉義一日遊，嘉義公園的古蹟池塘超美！旁邊的射日塔可以俯瞰整個嘉義市。北門也很適合拍照，孩子很喜歡爬上古老的火車！',
          'imageURLs': ['https://picsum.photos/seed/chiayikid/800/500'],
          'spotNames': ['嘉義公園', '射日塔', '北門車站'],
          'type': 'trip', 'likeCount': 33, 'commentCount': 5, 'saveCount': 17,
          'createdAt': now,
        },
        {
          'authorId': uid, 'authorName': name, 'authorPhoto': photo,
          'title': '阿里山三日兩夜深度之旅',
          'content': '阿里山四季各有特色，這次五月去剛好趕上神木區的嫩綠新芽。清晨五點起床看日出，雲霧繚繞的感覺真的很震撼。推薦住在山上，感受不一樣的夜晚！',
          'imageURLs': ['https://picsum.photos/seed/alishan3/800/500'],
          'spotNames': ['阿里山國家風景區'],
          'type': 'trip', 'likeCount': 89, 'commentCount': 15, 'saveCount': 41,
          'createdAt': now,
        },
      ];

      final discussionPosts = [
        {
          'authorId': uid, 'authorName': name, 'authorPhoto': photo,
          'title': '嘉義必去景點推薦？',
          'content': '最近計畫去嘉義旅遊，請問大家覺得嘉義最值得去的景點是哪幾個？想去文青一點的地方，不要太商業化的那種！',
          'imageURLs': [],
          'spotNames': [],
          'type': 'discussion', 'likeCount': 34, 'commentCount': 12, 'saveCount': 5,
          'createdAt': now,
        },
        {
          'authorId': uid, 'authorName': name, 'authorPhoto': photo,
          'title': '阿里山幾月去最好看？',
          'content': '第一次想去阿里山，想問問什麼季節最適合？聽說春天有櫻花、秋天有楓葉，不知道哪個季節CP值更高？',
          'imageURLs': [],
          'spotNames': ['阿里山國家風景區'],
          'type': 'discussion', 'likeCount': 67, 'commentCount': 20, 'saveCount': 8,
          'createdAt': now,
        },
        {
          'authorId': uid, 'authorName': name, 'authorPhoto': photo,
          'title': '文化路夜市必吃清單整理',
          'content': '在地人整理的文化路夜市必吃清單！火雞肉飯、方塊酥、蔥油餅、豆花、紅茶…這些都是我從小吃到大的味道，保證正宗！',
          'imageURLs': ['https://picsum.photos/seed/nightmarket/800/400'],
          'spotNames': ['文化路夜市'],
          'type': 'discussion', 'likeCount': 128, 'commentCount': 35, 'saveCount': 62,
          'createdAt': now,
        },
        {
          'authorId': uid, 'authorName': name, 'authorPhoto': photo,
          'title': '嘉義車站附近租機車推薦',
          'content': '打算騎機車探索嘉義，有人知道嘉義火車站附近哪裡租機車比較好？或是有推薦的電動機車租借嗎？',
          'imageURLs': [],
          'spotNames': [],
          'type': 'discussion', 'likeCount': 21, 'commentCount': 8, 'saveCount': 3,
          'createdAt': now,
        },
      ];

      int count = 0;
      for (final post in [...tripPosts, ...discussionPosts]) {
        await db.collection('community_posts').add(post);
        count++;
        _addLog('✅ 已上傳：${post['title']}');
      }
      setState(() => _status = '🎉 完成！共上傳 $count 則貼文');
    } catch (e) {
      setState(() => _status = '❌ 失敗: $e');
      _addLog('❌ 錯誤: $e');
    } finally {
      setState(() => _seeding = false);
    }
  }

  Future<void> _seedTestComments() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _status = '❌ 請先登入');
      return;
    }
    setState(() { _seeding = true; _status = '查詢貼文中…'; });
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('community_posts').limit(3).get();
      if (snap.docs.isEmpty) {
        setState(() => _status = '❌ 請先上傳貼文再上傳留言');
        return;
      }
      final uid = user.uid;
      final name = user.displayName ?? '測試旅人';
      int count = 0;
      for (final doc in snap.docs) {
        final comments = [
          {'authorId': uid, 'authorName': name, 'authorPhoto': user.photoURL ?? '',
           'text': '超棒的行程！我也想去，請問大概花了多少錢？', 'likeCount': 5,
           'createdAt': FieldValue.serverTimestamp()},
          {'authorId': uid, 'authorName': '旅遊達人小芳', 'authorPhoto': '',
           'text': '謝謝分享！這個路線我很推，北門車站的日落真的美極了。', 'likeCount': 12,
           'createdAt': FieldValue.serverTimestamp()},
        ];
        for (final c in comments) {
          await db.collection('community_posts').doc(doc.id).collection('comments').add(c);
          count++;
        }
        await db.collection('community_posts').doc(doc.id).update({'commentCount': FieldValue.increment(2)});
        _addLog('✅ 留言已上傳至：${doc['title']}');
      }
      setState(() => _status = '🎉 完成！共上傳 $count 則留言');
    } catch (e) {
      setState(() => _status = '❌ 失敗: $e');
    } finally {
      setState(() => _seeding = false);
    }
  }

  Future<void> _clearAllPosts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認清除'),
        content: const Text('確定要清除所有社群貼文嗎？此操作無法復原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() { _seeding = true; _status = '清除中…'; });
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('community_posts').get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
      setState(() => _status = '✅ 已清除 ${snap.docs.length} 則貼文');
      _log.clear();
    } catch (e) {
      setState(() => _status = '❌ 失敗: $e');
    } finally {
      setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🌱 Firebase 測試資料', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 登入狀態
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: user != null
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: user != null ? Colors.green.shade200 : Colors.red.shade200),
            ),
            child: Row(children: [
              Icon(
                user != null ? Icons.check_circle_rounded : Icons.error_rounded,
                color: user != null ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(
                user != null
                    ? '已登入：${user.displayName ?? user.email ?? user.uid}'
                    : '未登入 — 請先登入才能上傳資料',
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: user != null ? Colors.green.shade800 : Colors.red.shade800,
                ),
              )),
            ]),
          ),
          const SizedBox(height: 20),

          // 說明
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: primary),
                const SizedBox(width: 8),
                Text('說明', style: TextStyle(fontWeight: FontWeight.w800, color: primary)),
              ]),
              const SizedBox(height: 8),
              Text(
                '此頁面用於上傳測試資料到 Firebase，方便測試按讚、收藏、留言功能。\n\n'
                '1. 先點「上傳測試貼文」上傳行程分享與討論區貼文\n'
                '2. 再點「上傳測試留言」為貼文加上留言\n'
                '3. 完成後去社群頁面確認資料是否出現',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.6),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // 上傳按鈕
          _SeedButton(
            icon: Icons.post_add_rounded,
            label: '上傳測試貼文（行程分享 + 討論區）',
            subtitle: '上傳 7 則測試貼文',
            color: primary,
            loading: _seeding,
            onTap: _seedCommunityPosts,
          ),
          const SizedBox(height: 12),
          _SeedButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: '上傳測試留言',
            subtitle: '為前 3 則貼文各加 2 則留言',
            color: const Color(0xFF4CAF50),
            loading: _seeding,
            onTap: _seedTestComments,
          ),
          const SizedBox(height: 12),
          _SeedButton(
            icon: Icons.delete_outline_rounded,
            label: '清除所有社群貼文',
            subtitle: '刪除 community_posts 集合所有文件',
            color: AppColors.error,
            loading: _seeding,
            onTap: _clearAllPosts,
          ),

          // 狀態顯示
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _status.startsWith('❌') ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_status,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _status.startsWith('❌') ? Colors.red.shade700 : Colors.green.shade700,
                )),
            ),
          ],

          // 操作記錄
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('操作記錄', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            ..._log.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.4)),
            )),
          ],
        ],
      ),
    );
  }
}

class _SeedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _SeedButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: loading ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 2),
              Text(subtitle,
                style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ])),
            if (loading)
              SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            else
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color),
          ]),
        ),
      ),
    );
  }
}
