import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_Notif> _notifs = [
    _Notif(id:'n1', icon:'🏮', title:'嘉義燈會今日開幕！', body:'嘉義公園燈會今晚18:00正式點燈，快來感受光影之美。', time:'10分鐘前', isRead:false, type:'event'),
    _Notif(id:'n2', icon:'👍', title:'你的行程獲得 23 個讚', body:'「嘉義週末輕旅行」在社群大受歡迎，越來越多人套用你的行程！', time:'1小時前', isRead:false, type:'social'),
    _Notif(id:'n3', icon:'🎖️', title:'解鎖新成就！', body:'你已獲得「美食獵人」成就徽章，繼續探索嘉義美食吧！', time:'3小時前', isRead:false, type:'achievement'),
    _Notif(id:'n4', icon:'🚌', title:'公車即將到站', body:'紅幹線公車預計3分鐘後抵達嘉義火車站，請提前準備上車。', time:'昨天', isRead:true, type:'transport'),
    _Notif(id:'n5', icon:'📍', title:'附近有新景點', body:'「嘉義市立植物園」已上線，距離你目前位置僅500公尺，快去探索！', time:'昨天', isRead:true, type:'nearby'),
    _Notif(id:'n6', icon:'🌤️', title:'明日天氣提醒', body:'明日嘉義天氣晴朗，最高溫34°C，是戶外旅遊的好時機！', time:'2天前', isRead:true, type:'weather'),
    _Notif(id:'n7', icon:'✏️', title:'行程共編邀請', body:'小美邀請你共同編輯「阿里山二日遊」行程，點此查看。', time:'3天前', isRead:true, type:'social'),
  ];

  final _typeColor = const {
    'event': Color(0xFFE8A87C),
    'social': Color(0xFF8FBF8F),
    'achievement': Color(0xFFCFA84C),
    'transport': Color(0xFF88B8C8),
    'nearby': Color(0xFFD4A8C7),
    'weather': Color(0xFF8FBFD8),
  };

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => !n.isRead).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text('通知中心'),
            if (unread > 0)
              Text('$unread 則未讀', style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() { for (final n in _notifs) n.isRead = true; }),
            child: const Text('全部已讀', style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
        ],
      ),
      body: _notifs.isEmpty
          ? _buildEmpty()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _notifs.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) => _notifTile(_notifs[i]),
            ),
    );
  }

  Widget _notifTile(_Notif n) {
    final color = _typeColor[n.type] ?? AppColors.textHint;
    return Dismissible(
      key: Key(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.error.withOpacity(0.1),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
      ),
      onDismissed: (_) => setState(() => _notifs.removeWhere((x) => x.id == n.id)),
      child: InkWell(
        onTap: () => setState(() => n.isRead = true),
        child: Container(
          color: n.isRead ? Colors.transparent : AppColors.primaryMist.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(n.icon, style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(n.title,
                            style: TextStyle(
                              fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(n.time,
                          style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(n.body,
                      style: TextStyle(
                        fontSize: 13,
                        color: n.isRead ? AppColors.textHint : AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (!n.isRead) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🔔', style: TextStyle(fontSize: 52)),
          SizedBox(height: 12),
          Text('目前沒有通知', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          SizedBox(height: 6),
          Text('新活動、成就、行程更新會在這裡顯示', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Notif {
  final String id, icon, title, body, time, type;
  bool isRead;
  _Notif({required this.id, required this.icon, required this.title,
          required this.body, required this.time, required this.isRead, required this.type});
}
