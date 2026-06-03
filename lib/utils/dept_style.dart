import 'package:flutter/material.dart';

/// Maps a government department / category string to a representative
/// (color, icon) pair, used for news and event cards across the app.
///
/// Falls back to a generic "event" or "article" style when no keyword matches.
(Color, IconData) deptColorIcon(String? location, bool isEvent) {
  final loc = (location ?? '').toLowerCase();
  if (loc.contains('文化') || loc.contains('藝術') || loc.contains('博物'))
    return (const Color(0xFFB06090), Icons.museum_rounded);
  if (loc.contains('教育') || loc.contains('學') || loc.contains('校'))
    return (const Color(0xFF5A8FAF), Icons.school_rounded);
  if (loc.contains('體育') || loc.contains('運動'))
    return (const Color(0xFF5A9F5A), Icons.sports_rounded);
  if (loc.contains('環保') || loc.contains('環境') || loc.contains('農業'))
    return (const Color(0xFF5E9F7A), Icons.eco_rounded);
  if (loc.contains('衛生') || loc.contains('健康') || loc.contains('醫'))
    return (const Color(0xFFD45A5A), Icons.local_hospital_rounded);
  if (loc.contains('建設') || loc.contains('工程') || loc.contains('都市'))
    return (const Color(0xFFB08B40), Icons.construction_rounded);
  if (loc.contains('社會') || loc.contains('福利') || loc.contains('民政'))
    return (const Color(0xFF7A7ABF), Icons.people_rounded);
  if (loc.contains('財政') || loc.contains('稅務') || loc.contains('經濟'))
    return (const Color(0xFF7A9F5A), Icons.account_balance_rounded);
  if (loc.contains('警察') || loc.contains('消防') || loc.contains('安全'))
    return (const Color(0xFF5A7AAF), Icons.local_police_rounded);
  if (loc.contains('觀光') || loc.contains('旅遊') || loc.contains('景點'))
    return (const Color(0xFFBF8040), Icons.tour_rounded);
  if (isEvent) return (const Color(0xFF00838F), Icons.celebration_rounded);
  return (const Color(0xFF1565C0), Icons.article_rounded);
}
