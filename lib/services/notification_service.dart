import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 背景訊息 handler — 必須是 top-level function（不能放在 class 內）
// @pragma 確保 tree-shaking 不會移除此 function
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase.initializeApp() 已在 main() 完成，這裡無需重複
  // 背景訊息若有 notification payload，系統通知欄會自動顯示
  // 若是純 data message，在這裡自行處理（本 app 暫不需要）
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationService
// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotif = FlutterLocalNotificationsPlugin();

  /// Android 通知頻道（Android 8+ 必須有頻道）
  static const _channel = AndroidNotificationChannel(
    'joygo_high',           // channel id
    '探索諸羅重要通知',       // channel name
    description: '來自探索諸羅 App 的即時訊息與活動公告',
    importance: Importance.high,
  );

  // ── 公開：在 main() 初始化 Firebase 後呼叫一次 ─────────────────
  static Future<void> init() async {
    // 1. 設定背景訊息 handler（需在 Firebase.initializeApp 之後）
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. 初始化 flutter_local_notifications
    await _localNotif.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // 權限由下方 requestPermission 統一管理
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    // 3. 建立 Android 高優先度通知頻道（若已存在則跳過）
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 4. 請求推播權限（iOS 彈出確認視窗；Android 13+ 也需要）
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,   // true = 靜默授權（iOS），先用正式
    );

    // 僅在授權後才訂閱 / 監聽（避免 Android 靜默模式下錯誤）
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // 5. 訂閱全體頻道（管理員廣播）
      await _messaging.subscribeToTopic('all');

      // iOS 需要額外取得 APNs token（Android 自動處理）
      if (Platform.isIOS) {
        await _messaging.getAPNSToken();
      }
    }

    // 6. App 在「前景」時收到推播 → 用本地通知彈出
    FirebaseMessaging.onMessage.listen(_showForegroundNotif);

    // 7. 使用者點通知從「背景」進入 App
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // 8. App 從「完全關閉」狀態被通知打開
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _handleMessageTap(initialMessage);
  }

  // ── 前景推播：用本地通知彈出（系統欄） ─────────────────────────
  static Future<void> _showForegroundNotif(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;

    await _localNotif.show(
      message.hashCode,
      notif.title ?? '探索諸羅',
      notif.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          // 可替換成你的通知小圖示（白色透明背景 PNG）
          // icon: '@drawable/ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── 點通知進入 App 後的路由處理 ─────────────────────────────────
  // message.data 範例：{ 'type': 'news' } / { 'type': 'trip', 'id': '...' }
  static void _handleMessageTap(RemoteMessage message) {
    // TODO: 根據 data['type'] 做頁面導航
    // 目前先不做導航，之後可在這裡呼叫 navigatorKey.currentState?.push(...)
  }

  // ── 取得目前裝置的 FCM Token（Debug 用）────────────────────────
  static Future<String?> getToken() => _messaging.getToken();

  // ─────────────────────────────────────────────────────────────
  // Firestore 通知監聽
  // 登入後呼叫，監聽 users/{uid}/notifications 新文件
  // 若設定有開推播，自動彈出本機通知
  // ─────────────────────────────────────────────────────────────
  static StreamSubscription<QuerySnapshot>? _notifSub;

  /// 登入後呼叫：開始監聽個人通知 → 自動彈本機通知
  static Future<void> startListeningUserNotifs(String uid) async {
    await stopListeningUserNotifs(); // 先取消舊的

    // 只取最新一筆（用 startAfter 避免重複彈出歷史通知）
    // 用 createdAt > now 過濾，只抓「監聽開始後」的新通知
    final since = Timestamp.now();

    _notifSub = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('notifications')
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots()
        .listen((snap) async {
      // 只處理新增的文件
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = (change.doc.data() ?? {}) as Map<String, dynamic>;
        final title = data['title'] as String? ?? '探索諸羅';
        final body  = data['body']  as String? ?? '';
        if (title.isEmpty && body.isEmpty) continue;

        // 檢查推播設定開關
        final prefs = await SharedPreferences.getInstance();
        final pushEnabled = prefs.getBool('notif_setting_push') ?? true;
        if (!pushEnabled) continue;

        await _showLocalNotif(
          id: change.doc.id.hashCode,
          title: title,
          body: body,
        );
      }
    });
  }

  static Future<void> stopListeningUserNotifs() async {
    await _notifSub?.cancel();
    _notifSub = null;
  }

  /// 顯示本機通知（通用）
  static Future<void> _showLocalNotif({
    required int id,
    required String title,
    required String body,
  }) async {
    await _localNotif.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id, _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
