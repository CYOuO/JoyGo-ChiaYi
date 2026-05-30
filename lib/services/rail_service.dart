import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class RailService {
  static const String baseUrl = 'http://10.0.2.2:8080/api/transport';

  static Future<Map<String, dynamic>> queryTra({required String origin, required String dest, required String trainDate}) async {
    final res = await http.get(Uri.parse('$baseUrl/tra/od?origin=$origin&dest=$dest&date=$trainDate')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json['error'] != null) throw Exception('API限流');
      return json;
    }
    throw Exception('無法取得台鐵資料');
  }

  static Future<Map<String, dynamic>> getTraLiveBoard(String stationId) async {
    final res = await http.get(Uri.parse('$baseUrl/tra/liveboard/$stationId')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception('無法取得台鐵即時看板資料');
  }

  // 🌟 修正：解析 Java 傳回的錯誤
  static Future<Map<String, dynamic>> getTraTrainStops(String trainNo, String date) async {
    final res = await http.get(Uri.parse('$baseUrl/tra/train/$trainNo?date=$date')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json['error'] != null) throw Exception('API限流');
      return json;
    }
    throw Exception('無法取得停靠站');
  }

  static Future<Map<String, dynamic>> queryThsr({required String origin, required String dest, required String trainDate}) async {
    final res = await http.get(Uri.parse('$baseUrl/thsr/od?origin=$origin&dest=$dest&date=$trainDate')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json['error'] != null) throw Exception('API限流');
      return json;
    }
    throw Exception('無法取得高鐵資料');
  }

  // 🌟 修正：解析 Java 傳回的錯誤
  static Future<Map<String, dynamic>> getThsrTrainStops(String trainNo, String date) async {
    final res = await http.get(Uri.parse('$baseUrl/thsr/train/$trainNo?date=$date')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json['error'] != null) throw Exception('API限流');
      return json;
    }
    throw Exception('無法取得停靠站');
  }

  static Future<Map<String, dynamic>> getYoubikeData() async {
    final res = await http.get(Uri.parse('$baseUrl/youbike')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception('無法取得 YouBike 資料');
  }

  static Future<Map<String, dynamic>> getBusDynamic(String city, String routeName) async {
    final res = await http.get(Uri.parse('$baseUrl/bus/$city/$routeName')).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception('無法取得公車資料');
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