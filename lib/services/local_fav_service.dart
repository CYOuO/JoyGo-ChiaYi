import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton for guest favorites (SharedPreferences-backed).
/// Use [LocalFavService.notifier] as a ValueListenable to rebuild UI reactively.
class LocalFavService {
  LocalFavService._();
  static const _key = 'guest_saved_spots';

  static final ValueNotifier<Set<String>> notifier = ValueNotifier({});

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    notifier.value = (prefs.getStringList(_key) ?? []).toSet();
  }

  static bool isSaved(String spotId) => notifier.value.contains(spotId);

  static Future<bool> toggle(String spotId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = Set<String>.from(notifier.value);
    final isNowSaved = !set.contains(spotId);
    if (isNowSaved) set.add(spotId); else set.remove(spotId);
    await prefs.setStringList(_key, set.toList());
    notifier.value = set;
    return isNowSaved;
  }

  static Future<Set<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).toSet();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifier.value = {};
  }
}
