import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 收藏台鐵班次（本地 SharedPreferences，不需登入）
class TrainFavService {
  TrainFavService._();

  static const _key = 'fav_tra_trains';

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

  /// 唯一鍵：車次 + 出發站 + 目的站（跨日同車次不同意義，但夠用）
  static String keyOf(Map t) =>
      '${t['train_no']}_${t['origin'] ?? ''}_${t['dest'] ?? ''}';

  static bool isSaved(Map t) =>
      notifier.value.any((s) => s['_key'] == keyOf(t));

  static Future<bool> toggle(Map<String, dynamic> train) async {
    final list = List<Map<String, dynamic>>.from(notifier.value);
    final k = keyOf(train);
    final idx = list.indexWhere((s) => s['_key'] == k);
    final nowSaved = idx < 0;
    if (nowSaved) {
      list.insert(0, {
        ...train,
        '_key': k,
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
