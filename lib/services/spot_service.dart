import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/spot.dart';

class SpotService {
  SpotService._();

  static List<Spot>? _cached;

  /// 已快取的景點清單（同步讀取；loadAllSpots 完成後才有資料）
  static List<Spot> get cached => _cached ?? [];

  static const _kCacheKey = 'spot_service_cache_v1';
  static const _kTsKey = 'spot_service_ts_v1';
  static const _kTtlMs = 6 * 60 * 60 * 1000; // 6 hours

  static Future<List<Spot>> loadAllSpots({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached!;

    // Try loading from local cache first
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCacheKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).map((m) => _fromJson(m as Map<String, dynamic>)).toList();
        _cached = list;
        // Check if stale → refresh in background
        final ts = prefs.getInt(_kTsKey) ?? 0;
        if (forceRefresh || DateTime.now().millisecondsSinceEpoch - ts > _kTtlMs) {
          _refreshAndCache(prefs);
        }
        return list;
      } catch (_) {}
    }

    // No cache — fetch from Firestore
    final spots = await _fetchFromFirestore();
    _cached = spots;
    _saveToCache(prefs, spots);
    return spots;
  }

  static Future<void> _refreshAndCache(SharedPreferences prefs) async {
    try {
      final spots = await _fetchFromFirestore();
      _cached = spots;
      _saveToCache(prefs, spots);
    } catch (_) {}
  }

  static Future<void> _saveToCache(SharedPreferences prefs, List<Spot> spots) async {
    try {
      final json = spots.map(_toJson).toList();
      await prefs.setString(_kCacheKey, jsonEncode(json));
      await prefs.setInt(_kTsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Map<String, dynamic> _toJson(Spot s) => {
    'id': s.id, 'name': s.name, 'category': s.category,
    'description': s.description, 'lat': s.lat, 'lng': s.lng,
    'rating': s.rating, 'imageUrl': s.imageUrl,
    'openHours': s.openHours, 'address': s.address,
  };

  static Spot _fromJson(Map<String, dynamic> m) => Spot(
    id: m['id'] as String? ?? '', name: m['name'] as String? ?? '', nameEn: '',
    category: m['category'] as String? ?? 'attraction',
    description: m['description'] as String? ?? '',
    lat: (m['lat'] as num?)?.toDouble() ?? 0,
    lng: (m['lng'] as num?)?.toDouble() ?? 0,
    rating: (m['rating'] as num?)?.toDouble() ?? 0,
    imageUrl: m['imageUrl'] as String? ?? '',
    openHours: m['openHours'] as String? ?? '',
    address: m['address'] as String? ?? '',
  );

  static Future<List<Spot>> _fetchFromFirestore() async {
    final spots = <Spot>[];
    await Future.wait([
      _loadTdxSpots(spots),
      _loadRestaurants(spots),
    ]);
    return spots;
  }

  static Future<void> _loadTdxSpots(List<Spot> out) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('tdx_spots').limit(200).get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = _lat(d);
        final lng = _lng(d);
        if (lat == null || lng == null) continue;
        final name = d['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final images = d['images'];
        out.add(Spot(
          id: 'tdx_${doc.id}', name: name, nameEn: '',
          category: 'attraction',
          description: d['descriptionDetail']?.toString() ?? d['description']?.toString() ?? '',
          lat: lat, lng: lng, rating: 0,
          imageUrl: (images is List && images.isNotEmpty) ? images.first.toString() : '',
          openHours: d['openTime']?.toString() ?? '',
          address: d['address']?.toString() ?? '',
        ));
      }
    } catch (e) {
      debugPrint('SpotService tdx_spots error: $e');
    }
  }

  static Future<void> _loadRestaurants(List<Spot> out) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('restaurants').limit(100).get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = _lat(d);
        final lng = _lng(d);
        if (lat == null || lng == null) continue;
        final name = d['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final images = d['images'];
        out.add(Spot(
          id: 'rest_${doc.id}', name: name, nameEn: '',
          category: 'restaurant',
          description: d['shortDesc']?.toString() ?? '',
          lat: lat, lng: lng,
          rating: (d['rating'] as num?)?.toDouble() ?? 0,
          imageUrl: (images is List && images.isNotEmpty) ? images.first.toString() : '',
          openHours: d['time']?.toString() ?? '',
          address: d['address']?.toString() ?? '',
        ));
      }
    } catch (e) {
      debugPrint('SpotService restaurants error: $e');
    }
  }

  static double? _lat(Map<String, dynamic> d) {
    final loc = d['location'];
    if (loc is GeoPoint && loc.latitude > 21 && loc.latitude < 26) return loc.latitude;
    for (final k in ['lat', 'latitude', '緯度']) {
      final v = d[k];
      if (v is num && v > 21 && v < 26) return v.toDouble();
    }
    return null;
  }

  static double? _lng(Map<String, dynamic> d) {
    final loc = d['location'];
    if (loc is GeoPoint && loc.longitude > 119 && loc.longitude < 122) return loc.longitude;
    for (final k in ['lng', 'longitude', '經度']) {
      final v = d[k];
      if (v is num && v > 119 && v < 122) return v.toDouble();
    }
    return null;
  }
}
