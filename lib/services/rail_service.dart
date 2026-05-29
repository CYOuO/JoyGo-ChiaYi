import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// ⚠️  請設定同學的 Spring Boot server 位址：
///   - Android 模擬器測試: http://10.0.2.2:8080
///   - 實機（同 Wi-Fi）: http://[同學電腦的IP]:8080
///   - 正式部署後: 改為正式 URL
const _kBase = 'http://10.0.2.2:8080/api/transport';

/// 同學 Spring Boot server 的 TDX proxy service
class TdxService {
  static Future<List<Map<String, dynamic>>> _get(String path) async {
    final res = await http
        .get(Uri.parse('$_kBase$path'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: $path');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// 台鐵即時到站看板
  /// 回傳欄位: train_no, direction(int:0南下/1北上), train_type_name,
  ///           delay_time(int秒), schedule_arrival_time, schedule_departure_time
  static Future<List<Map<String, dynamic>>> traLiveboard(String stationId) =>
      _get('/tra/liveboard/$stationId');

  /// 高鐵 OD 班次查詢
  /// 回傳欄位: TrainNo, Direction(int), DepartureTime, ArrivalTime,
  ///           EndingStationName, StartingStationName
  static Future<List<Map<String, dynamic>>> thsrOD({
    required String origin,
    required String dest,
    required String date,
  }) =>
      _get('/thsr/od?origin=$origin&dest=$dest&date=$date');

  /// YouBike 即時車位
  /// 回傳欄位: station_uid, ServiceStatus, AvailableReturnBikes,
  ///           GeneralBikes, ElectricBikes
  static Future<List<Map<String, dynamic>>> youbike() => _get('/youbike');

  /// 公車預估到站 (city: Chiayi, routeName: 紅幹線 …)
  /// 回傳欄位(每個站): RouteUID, StopUID, StopStatus, EstimateTime(秒),
  ///                   CurrentStop, StopCountDown, IsLastBus
  static Future<List<Map<String, dynamic>>> bus(
          String city, String routeName) =>
      _get('/bus/$city/${Uri.encodeComponent(routeName)}');
}

/// 阿里山林鐵班次（Firestore 靜態資料，Spring Boot 尚未包含）
class RailService {
  static Future<List<Map<String, dynamic>>> fetchAlishanSchedules() async {
    final snap = await FirebaseFirestore.instance
        .collection('tdx_alishan_rail_schedules')
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['docId'] = d.id;
      return data;
    }).toList();
  }
}
