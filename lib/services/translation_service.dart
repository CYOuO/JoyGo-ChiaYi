import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/app_config.dart';

// ═══════════════════════════════════════════════════════════
//  TranslationService
//  Translates Chinese text to EN / JA using Gemini Flash.
//  Results are cached in SharedPreferences to avoid repeat API calls.
//  Only called when langCode != 'zh' and text is non-empty.
// ═══════════════════════════════════════════════════════════

class TranslationService {
  static const _kPrefix   = 'trans_v1_';
  static const _kMaxCache = 500;   // max entries before pruning old ones

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  static GenerativeModel? _model;
  static GenerativeModel _getModel() =>
      _model ??= GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: AppConfig.geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1,   // low temperature for accurate translation
          maxOutputTokens: 300,
        ),
      );

  // ── Public API ─────────────────────────────────────────────

  /// Returns translated text.  Falls back to [original] on any error.
  static Future<String> translate(
    String original,
    String targetLang, {
    TranslationDomain domain = TranslationDomain.general,
  }) async {
    if (targetLang == 'zh') return original;
    if (original.trim().isEmpty) return original;
    if (AppConfig.geminiApiKey.isEmpty) return original;

    final cacheKey = _cacheKey(original, targetLang);
    final prefs    = await _sp;

    // ── Cache hit
    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) return cached;

    // ── Gemini call
    try {
      final langName = targetLang == 'ja' ? 'Japanese' : 'English';
      final prompt = _buildPrompt(original, langName, domain);
      final response = await _getModel().generateContent([Content.text(prompt)]);
      final result   = response.text?.trim() ?? original;

      // ── Cache write (with simple size management)
      await _writeCache(prefs, cacheKey, result);
      return result;
    } catch (e) {
      // Network / quota errors → return original silently
      return original;
    }
  }

  // ── Batch translate (reduces round trips) ──────────────────

  /// Translates multiple texts in a single Gemini call.
  /// Returns a List of the same length; any failure falls back to original.
  static Future<List<String>> translateBatch(
    List<String> originals,
    String targetLang, {
    TranslationDomain domain = TranslationDomain.general,
  }) async {
    if (targetLang == 'zh') return originals;
    if (AppConfig.geminiApiKey.isEmpty) return originals;

    final prefs   = await _sp;
    final results = List<String>.from(originals);
    final toFetch = <int>[];

    // ── Check which ones aren't cached
    for (int i = 0; i < originals.length; i++) {
      if (originals[i].trim().isEmpty) continue;
      final cached = prefs.getString(_cacheKey(originals[i], targetLang));
      if (cached != null && cached.isNotEmpty) {
        results[i] = cached;
      } else {
        toFetch.add(i);
      }
    }
    if (toFetch.isEmpty) return results;

    // ── Fetch uncached items in one call
    try {
      final langName   = targetLang == 'ja' ? 'Japanese' : 'English';
      final numbered   = toFetch.map((i) => '${i + 1}. ${originals[i]}').join('\n');
      final prompt =
          'Translate each numbered Chinese line to $langName. '
          'Reply with ONLY the numbered lines in the same format:\n\n$numbered';

      final response = await _getModel().generateContent([Content.text(prompt)]);
      final text     = response.text?.trim() ?? '';

      // ── Parse "1. translation\n2. translation\n..."
      final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
      for (final line in lines) {
        final match = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(line.trim());
        if (match == null) continue;
        final idx = int.tryParse(match.group(1)!) ?? -1;
        if (idx < 1 || idx > toFetch.length) continue;
        final translated = match.group(2)!.trim();
        final originalIdx = toFetch[idx - 1];
        results[originalIdx] = translated;
        await _writeCache(prefs, _cacheKey(originals[originalIdx], targetLang), translated);
      }
    } catch (_) {
      // fallback to originals already in results
    }
    return results;
  }

  // ── Helpers ────────────────────────────────────────────────

  static String _cacheKey(String text, String lang) =>
      '$_kPrefix${lang}_${text.trim().hashCode}';

  static String _buildPrompt(String text, String langName, TranslationDomain domain) {
    final context = switch (domain) {
      TranslationDomain.spot    => 'This is a tourist spot description in Chiayi, Taiwan. ',
      TranslationDomain.news    => 'This is a local government news headline in Chiayi, Taiwan. ',
      TranslationDomain.address => 'This is a street address in Chiayi, Taiwan. ',
      TranslationDomain.general => '',
    };
    return '${context}Translate the following Chinese text to $langName. '
        'Return ONLY the translation without any explanation:\n\n$text';
  }

  static Future<void> _writeCache(
      SharedPreferences prefs, String key, String value) async {
    // Simple LRU-ish: if too many entries, remove oldest half
    final allKeys = prefs.getKeys().where((k) => k.startsWith(_kPrefix)).toList();
    if (allKeys.length >= _kMaxCache) {
      for (final old in allKeys.take(allKeys.length ~/ 2)) {
        await prefs.remove(old);
      }
    }
    await prefs.setString(key, value);
  }
}

enum TranslationDomain { general, spot, news, address }
