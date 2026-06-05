import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 收藏公車路線（本地 SharedPreferences，不需登入）
class FavBusService {
  FavBusService._();

  static const _key = 'fav_bus_routes';

  /// 已收藏路線清單，每筆 {'city': ..., 'routeName': ...}
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

  static bool isSaved(String city, String routeName) => notifier.value
      .any((r) => r['city'] == city && r['routeName'] == routeName);

  static Future<bool> toggle(String city, String routeName) async {
    final list = List<Map<String, dynamic>>.from(notifier.value);
    final idx = list
        .indexWhere((r) => r['city'] == city && r['routeName'] == routeName);
    final nowSaved = idx < 0;
    if (nowSaved) {
      list.insert(0, {
        'city': city,
        'routeName': routeName,
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
