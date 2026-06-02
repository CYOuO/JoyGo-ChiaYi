import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton for guest favorites (SharedPreferences-backed).
/// Stores both the set of saved spot IDs and their metadata.
class LocalFavService {
  LocalFavService._();
  static const _idsKey  = 'guest_saved_spots';
  static const _metaKey = 'guest_saved_spots_meta';

  static final ValueNotifier<Set<String>> notifier = ValueNotifier({});

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    notifier.value = (prefs.getStringList(_idsKey) ?? []).toSet();
  }

  static bool isSaved(String spotId) => notifier.value.contains(spotId);

  /// Toggle without metadata (legacy, keeps compatibility).
  static Future<bool> toggle(String spotId) async {
    return toggleWithMeta(spotId, spotName: spotId);
  }

  /// Toggle and persist metadata for guest display.
  static Future<bool> toggleWithMeta(String spotId, {
    required String spotName,
    String imageUrl    = '',
    double rating      = 0.0,
    String description = '',
    String address     = '',
    String category    = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final set = Set<String>.from(notifier.value);
    final isNowSaved = !set.contains(spotId);

    if (isNowSaved) {
      set.add(spotId);
      // Save metadata
      final raw = prefs.getString(_metaKey);
      final meta = raw != null ? Map<String, dynamic>.from(jsonDecode(raw) as Map) : <String, dynamic>{};
      meta[spotId] = {
        'spotId':      spotId,
        'spotName':    spotName,
        'imageUrl':    imageUrl,
        'rating':      rating,
        'description': description,
        'address':     address,
        'category':    category,
        'savedAt':     DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_metaKey, jsonEncode(meta));
    } else {
      set.remove(spotId);
      // Remove metadata
      final raw = prefs.getString(_metaKey);
      if (raw != null) {
        final meta = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        meta.remove(spotId);
        await prefs.setString(_metaKey, jsonEncode(meta));
      }
    }

    await prefs.setStringList(_idsKey, set.toList());
    notifier.value = set;
    return isNowSaved;
  }

  /// Returns all saved spot metadata, sorted newest-first.
  static Future<List<Map<String, dynamic>>> getSavedSpotsData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey);
    if (raw == null) return [];
    final meta = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final ids = (prefs.getStringList(_idsKey) ?? []).toSet();
    // Only return entries that are still in the saved set
    final result = meta.entries
        .where((e) => ids.contains(e.key))
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList();
    result.sort((a, b) => ((b['savedAt'] as int? ?? 0).compareTo(a['savedAt'] as int? ?? 0)));
    return result;
  }

  static Future<Set<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_idsKey) ?? []).toSet();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idsKey);
    await prefs.remove(_metaKey);
    notifier.value = {};
  }
}
