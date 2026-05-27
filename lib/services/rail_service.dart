import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Wraps Firebase Cloud Functions + Firestore calls for rail timetable data.
class RailService {
  static final _fns = FirebaseFunctions.instanceFor(region: 'asia-east1');

  // ── TRA ─────────────────────────────────────────────────────
  /// [stationId] defaults to 嘉義 (3160).
  /// Returns list of {train_no, direction, train_type_name, destination_station, departure_time}.
  static Future<List<Map<String, dynamic>>> queryTra({
    required String trainDate,
    String stationId = '3160',
  }) async {
    final callable = _fns.httpsCallable('queryTraStation');
    final result = await callable.call(<String, dynamic>{
      'trainDate': trainDate,
      'stationId': stationId,
    });
    final data = result.data;
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  // ── THSR ────────────────────────────────────────────────────
  /// [stationId] defaults to 嘉義 (0900).
  /// Returns list of {train_no, direction, destination_station, departure_time}.
  static Future<List<Map<String, dynamic>>> queryThsr({
    required String trainDate,
    String stationId = '0900',
  }) async {
    final callable = _fns.httpsCallable('queryThsrStation');
    final result = await callable.call(<String, dynamic>{
      'trainDate': trainDate,
      'stationId': stationId,
    });
    final data = result.data;
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  // ── Alishan Rail (Firestore static) ─────────────────────────
  /// Fetches all schedule docs from [tdx_alishan_rail_schedules].
  /// Each doc contains: {TrainNo, Direction(0=往嘉義/1=往山上), stopTimes:[{StationName, DepartureTime, ArrivalTime, StopSequence}]}
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
