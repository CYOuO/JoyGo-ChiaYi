import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 預載 + 快取 Firestore 上「靜態」集合（餐廳、景點、好店、寵物友善、飲料店…）
///
/// ┌──────────────────────────────────────────────────────────────────────┐
/// │ Splash Screen → prewarm()  // 一次拉全部，存 SharedPreferences         │
/// │ Home Screen   → load(col)  // 從本地瞬間讀                             │
/// │                  ↳ 若 stale → 背景靜默 refresh                         │
/// └──────────────────────────────────────────────────────────────────────┘
///
/// 因為這些資料更新頻率很低，TTL 設成 7 天足夠；超過 TTL 還是會用舊資料即顯
/// （cache-first），同時背景補抓。第一次裝完 App 跑 splash 時就把資料抓完，
/// 之後的 cold start 不需要等 Firestore。
class StaticDataCache {
  StaticDataCache._();

  /// SharedPreferences key 版本。改變欄位結構時 bump 版本可一次失效全部。
  static const _version = 'v1';

  /// 7 days = 604_800_000 ms
  static const _ttlMs = 7 * 24 * 60 * 60 * 1000;

  /// 要預載的集合 + 每集合抓幾筆。和首頁實際讀取的數量對齊以免浪費頻寬。
  static const Map<String, int> collections = {
    'restaurants':            15,
    'tdx_spots':              12,
    'good_shops':             12,
    'pet_friendly_shops':     12,
    'excellent_drink_shops':  12,
  };

  static String _dataKey(String col) => 'sdc_${col}_$_version';
  static String _tsKey  (String col) => 'sdc_${col}_ts_$_version';

  // ────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────

  /// 是否有任何快取資料（不在乎是不是 stale）。
  static Future<bool> hasCache(String col) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_dataKey(col));
    return raw != null && raw.isNotEmpty;
  }

  /// 快取年齡（ms）。沒快取回 `null`。
  static Future<int?> cacheAgeMs(String col) async {
    final p = await SharedPreferences.getInstance();
    final ts = p.getInt(_tsKey(col));
    if (ts == null) return null;
    return DateTime.now().millisecondsSinceEpoch - ts;
  }

  /// 是否超過 TTL（沒快取也算 stale）。
  static Future<bool> isStale(String col) async {
    final age = await cacheAgeMs(col);
    return age == null || age > _ttlMs;
  }

  /// 從本地讀回 List<Map>。讀不到回空陣列。GeoPoint/Timestamp 會自動還原。
  static Future<List<Map<String, dynamic>>> load(String col) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_dataKey(col));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => _deserializeDoc(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('[StaticDataCache] decode $col failed: $e');
      return [];
    }
  }

  /// 重新從 Firestore 抓 + 寫入快取。回傳新資料（失敗回空陣列、不會 throw）。
  static Future<List<Map<String, dynamic>>> refresh(
    String col, {
    int? limit,
  }) async {
    final lim = limit ?? collections[col] ?? 12;
    try {
      Query<Map<String, dynamic>> q =
          FirebaseFirestore.instance.collection(col);
      // restaurants 依照 rating 排序，其餘走自然順序
      if (col == 'restaurants') {
        q = q.orderBy('rating', descending: true);
      }
      final snap = await q.limit(lim).get();
      final docs = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['__id'] = d.id; // 把 doc.id 塞進去，後續解析能用
        return m;
      }).toList();

      final p = await SharedPreferences.getInstance();
      await p.setString(_dataKey(col),
          jsonEncode(docs.map(_serializeDoc).toList()));
      await p.setInt(_tsKey(col),
          DateTime.now().millisecondsSinceEpoch);

      return docs;
    } catch (e) {
      debugPrint('[StaticDataCache] refresh $col failed: $e');
      return [];
    }
  }

  /// 一次預載所有 [collections]。預設只跳過 fresh 的（沒過 TTL）。
  /// 傳 `force: true` 可強制全部 refetch。
  static Future<void> prewarm({bool force = false}) async {
    final futures = <Future<void>>[];
    for (final col in collections.keys) {
      futures.add(() async {
        if (!force) {
          final has   = await hasCache(col);
          final stale = await isStale(col);
          if (has && !stale) {
            debugPrint('[StaticDataCache] $col fresh — skip');
            return;
          }
        }
        await refresh(col);
      }());
    }
    await Future.wait(futures);
    debugPrint('[StaticDataCache] prewarm done (${collections.length} cols)');
  }

  /// 清掉一個集合的快取（debug / 強制 reload 用）。
  static Future<void> clear(String col) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_dataKey(col));
    await p.remove(_tsKey(col));
  }

  /// 清掉所有快取。
  static Future<void> clearAll() async {
    for (final col in collections.keys) {
      await clear(col);
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // GeoPoint / Timestamp ↔ JSON 處理
  // SharedPreferences 只能存 primitives，所以這些 Firestore 型別需要包裝。
  // ────────────────────────────────────────────────────────────────────

  static dynamic _serializeValue(dynamic v) {
    if (v == null) return null;
    if (v is GeoPoint) {
      return {'__t': 'gp', 'lat': v.latitude, 'lng': v.longitude};
    }
    if (v is Timestamp) {
      return {'__t': 'ts', 'ms': v.millisecondsSinceEpoch};
    }
    if (v is DocumentReference) {
      return {'__t': 'dr', 'path': v.path};
    }
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _serializeValue(val)));
    }
    if (v is List) {
      return v.map(_serializeValue).toList();
    }
    if (v is num || v is String || v is bool) return v;
    // Unknown type — fall back to string
    return v.toString();
  }

  static dynamic _deserializeValue(dynamic v) {
    if (v is Map) {
      final type = v['__t'];
      if (type == 'gp') {
        return GeoPoint(
          (v['lat'] as num).toDouble(),
          (v['lng'] as num).toDouble(),
        );
      }
      if (type == 'ts') {
        return Timestamp.fromMillisecondsSinceEpoch(v['ms'] as int);
      }
      if (type == 'dr') {
        // 不還原成 DocumentReference（沒人在用），保留 path 字串給需要時參考
        return v['path'];
      }
      return v.map((k, val) => MapEntry(k.toString(), _deserializeValue(val)));
    }
    if (v is List) {
      return v.map(_deserializeValue).toList();
    }
    return v;
  }

  static Map<String, dynamic> _serializeDoc(Map<String, dynamic> doc) =>
      doc.map((k, v) => MapEntry(k, _serializeValue(v)));

  static Map<String, dynamic> _deserializeDoc(Map<String, dynamic> doc) =>
      doc.map((k, v) => MapEntry(k, _deserializeValue(v)));
}
