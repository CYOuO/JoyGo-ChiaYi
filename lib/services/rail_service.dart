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
          ? Map<String, dynamic>.from(decoded as Map)
          : {'data': decoded is List ? decoded : [], 'updateTime': ''};

  static Future<Map<String, dynamic>> queryTra({required String origin, required String dest, required String trainDate}) async {
    final res = await http.get(Uri.parse('$baseUrl/tra/od?origin=$origin&dest=$dest&date=$trainDate')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    throw Exception('無法取得台鐵資料');
  }

  static Future<Map<String, dynamic>> getTraLiveBoard(String stationId) async {
    try {
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
      if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {}
    return {'data': <dynamic>[], 'updateTime': ''};
  }

  static Future<Map<String, dynamic>> getBusDynamic(String city, String routeName) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/bus/$city/$routeName')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return _toMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {}
    return {'data': <dynamic>[], 'updateTime': ''};
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

  static Future<List<Map<String, dynamic>>> fetchAlishanSchedules() async {
    final snap = await FirebaseFirestore.instance.collection('tdx_alishan_rail_schedules').get();
    return snap.docs.map((d) {
      final data = d.data();
      data['docId'] = d.id;
      return data;
    }).toList();
  }
}
