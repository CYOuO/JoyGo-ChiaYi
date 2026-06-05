import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class RailService {
  static const String baseUrl = 'http://10.0.2.2:8080/api/transport';

  // 統一處理 server 回傳 Map 或 List 兩種格式
  static Map<String, dynamic> _toMap(dynamic decoded) =>
      decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {'data': decoded is List ? decoded : [], 'updateTime': ''};

  static Future<Map<String, dynamic>> queryTra({required String origin, required String dest, required String trainDate}) async {
    final res = await http.get(Uri.parse('$baseUrl/tra/od?origin=$origin&dest=$dest&date=$trainDate')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    throw Exception('無法取得台鐵資料');
  }

  static Future<Map<String, dynamic>> getTraLiveBoard(String stationId) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final res = await http.get(Uri.parse('$baseUrl/tra/liveboard/$stationId')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {}
    return {'data': <dynamic>[], 'updateTime': ''};
  }

  static Future<Map<String, dynamic>> getTraTrainStops(String trainNo, String date) async {
    final res = await http.get(Uri.parse('$baseUrl/tra/train/$trainNo?date=$date')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    throw Exception('無法取得停靠站');
  }

  static Future<Map<String, dynamic>> queryThsr({required String origin, required String dest, required String trainDate}) async {
    final res = await http.get(Uri.parse('$baseUrl/thsr/od?origin=$origin&dest=$dest&date=$trainDate')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    throw Exception('無法取得高鐵資料');
  }

  static Future<Map<String, dynamic>> getThsrTrainStops(String trainNo, String date) async {
    final res = await http.get(Uri.parse('$baseUrl/thsr/train/$trainNo?date=$date')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    throw Exception('無法取得停靠站');
  }

  static Future<Map<String, dynamic>> getYoubikeData() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/youbike')).timeout(const Duration(seconds: 8));
      final ts = DateTime.now().millisecondsSinceEpoch;
      if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {}
    return {'data': <dynamic>[], 'updateTime': ''};
  }

  static Future<Map<String, dynamic>> getBusDynamic(String city, String routeName) async {
    try {
      final encoded = Uri.encodeComponent(routeName);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final res = await http.get(Uri.parse('$baseUrl/bus/$city/$encoded')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {}
    return {'data': <dynamic>[], 'updateTime': ''};
  }

  // 公車即時 GPS 位置
  static Future<Map<String, dynamic>> getBusGpsPositions(String city, String routeName) async {
    try {
      final encoded = Uri.encodeComponent(routeName);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final res = await http.get(Uri.parse('$baseUrl/bus/gps/$city/$encoded')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {}
    return {'data': <dynamic>[], 'updateTime': ''};
  }

  // GPS 附近站牌 → 回傳附近路線清單（TDX spatialFilter）
  static Future<Map<String, dynamic>> getNearbyBusStops(String city, double lat, double lng, {int radius = 500}) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/bus/nearby?city=$city&lat=$lat&lng=$lng&radius=$radius'),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (e) {
      if (kDebugMode) print('附近站牌查詢失敗: $e');
    }
    return {'data': <dynamic>[], 'updateTime': ''};
  }

  // 站牌名稱搜尋 → 回傳有停靠的路線清單（呼叫真實後端 TDX 資料）
  static Future<List<String>> getBusByStop(String city, String stopName) async {
    try {
      final encoded = Uri.encodeComponent(stopName);
      final url = '$baseUrl/bus/stop/$city?q=$encoded';
      if (kDebugMode) print('🔍 [除錯] 準備請求: $url');

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      
      if (kDebugMode) print('📥 [除錯] 伺服器狀態碼: ${res.statusCode}');

      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final safeData = _toMap(decoded);
        final data = safeData['data'] as List? ?? [];
        
        if (kDebugMode) print('📦 [除錯] 取得資料筆數: ${data.length}');
        
        // 安全解析多語系欄位
        String getZh(dynamic field) => (field is Map) ? (field['Zh_tw']?.toString() ?? '') : (field?.toString() ?? '');
        
        final matchedRoutes = <String>{};
        
        for (final d in data) {
          if (d is! Map) continue;
          
          // 針對大小寫進行相容性防護 (RouteName 或 routeName)
          final routeName = getZh(d['RouteName'] ?? d['routeName']);
          if (routeName.isEmpty) continue;

          // 針對大小寫進行相容性防護 (Stops 或 stops)
          final stops = (d['Stops'] ?? d['stops']) as List? ?? [];
          bool hasMatched = false;
          
          for (final s in stops) {
            if (s is Map) {
              final sName = getZh(s['StopName'] ?? s['stopName']);
              if (sName.contains(stopName)) {
                hasMatched = true;
                break;
              }
            }
          }
          
          if (hasMatched || stops.isEmpty) {
            matchedRoutes.add(routeName);
          }
        }
        
        if (kDebugMode) print('✅ [除錯] 最終比對成功的路線: $matchedRoutes');
        return matchedRoutes.toList();
      } else {
        if (kDebugMode) print('❌ [除錯] 伺服器回傳非 200: ${res.body}');
      }
    } catch (e) {
      if (kDebugMode) print('🔥 [除錯] 執行階段崩潰: $e');
    }
    return [];
  }
  static Future<List<Map<String, dynamic>>> getWeather(String cityType) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/weather/$cityType')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final dataList = decoded['data'] as List<dynamic>;
        return dataList.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      if (kDebugMode) print('天氣資料獲取失敗: $e');
    }
    return [];
  }

  /// UV 指數 + 日出日落（由後端呼叫 OpenWeatherMap，App 不需要 API key）
  /// 後端端點：GET /api/transport/weather/extra
  /// 後端環境變數：OPENWEATHER_KEY=你的key
  static Future<Map<String, dynamic>> getWeatherExtra() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/weather/extra'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)));
      }
    } catch (e) {
      if (kDebugMode) print('[WeatherExtra] $e');
    }
    return {};
  }

  static Future<List<Map<String, dynamic>>> fetchAlishanSchedules() async {
    final snap = await FirebaseFirestore.instance.collection('tdx_alishan_rail_schedules').get();
    return snap.docs.map((d) {
      final data = d.data();
      data['docId'] = d.id;
      return data;
    }).toList();
  }
}
