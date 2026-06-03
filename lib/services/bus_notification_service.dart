import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BusNotificationService {
  BusNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _permissionGranted = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  static Future<bool> _ensurePermission() async {
    await init();
    if (_permissionGranted) return true;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        _permissionGranted = granted ?? false;
        return _permissionGranted;
      }
    }
    _permissionGranted = true;
    return true;
  }

  static Timer? _timer;

  static Future<void> scheduleBusArrival({
    required String routeName,
    required String stopName,
    required int etaSeconds,
    required int notifyBeforeMinutes,
  }) async {
    final ok = await _ensurePermission();
    if (!ok) { debugPrint('通知權限被拒絕'); return; }
    _timer?.cancel();
    final notifyAt = etaSeconds - (notifyBeforeMinutes * 60);
    if (notifyAt <= 0) {
      _showNow(routeName, stopName);
      return;
    }
    debugPrint('已設定公車提醒：$notifyAt 秒後通知 ($routeName → $stopName)');
    _timer = Timer(Duration(seconds: notifyAt), () => _showNow(routeName, stopName));
  }

  static Future<void> _showNow(String routeName, String stopName) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'bus_arrival', '公車到站提醒',
      channelDescription: '公車即將到站時發出提醒',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      routeName.hashCode,
      '$routeName 即將進站',
      '$stopName 站的公車即將到達！',
      details,
    );
  }

  static void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
