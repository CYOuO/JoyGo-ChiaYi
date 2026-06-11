import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 收藏公車路線（本地 SharedPreferences，不需登入）
/// Key = city + routeName + direction + subRouteName
/// 同一路線的不同方向/支線分別儲存為獨立卡片
class FavBusService {
  FavBusService._();

  static const _key = 'fav_bus_routes_v2'; // v2: 新增 direction/subRoute

  /// 已收藏路線清單
  /// 每筆：{'city', 'routeName', 'direction', 'subRouteName', 'savedAt'}
  static final ValueNotifier<List<Map<String, dynamic>>> notifier =
      ValueNotifier([]);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    notifier.value = raw != null
        ? (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : [];
  }

  /// 是否已收藏（以 city + routeName + direction + subRouteName 為鍵）
  static bool isSaved(String city, String routeName,
      {int direction = 0, String subRouteName = ''}) {
    return notifier.value.any((r) =>
        r['city'] == city &&
        r['routeName'] == routeName &&
        (r['direction'] as int? ?? 0) == direction &&
        (r['subRouteName'] as String? ?? '') == subRouteName);
  }

  /// 切換收藏狀態，回傳操作後是否已收藏
  static Future<bool> toggle(
    String city,
    String routeName, {
    int direction = 0,
    String subRouteName = '',
    String displayLabel = '', // 顯示用的方向文字，例如「去程 → 終點」
  }) async {
    final list = List<Map<String, dynamic>>.from(notifier.value);
    final idx = list.indexWhere((r) =>
        r['city'] == city &&
        r['routeName'] == routeName &&
        (r['direction'] as int? ?? 0) == direction &&
        (r['subRouteName'] as String? ?? '') == subRouteName);
    final nowSaved = idx < 0;
    if (nowSaved) {
      list.insert(0, {
        'city': city,
        'routeName': routeName,
        'direction': direction,
        'subRouteName': subRouteName,
        'displayLabel': displayLabel,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      list.removeAt(idx);
    }
    notifier.value = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
    return nowSaved;
  }
}
