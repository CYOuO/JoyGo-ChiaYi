import 'package:flutter/material.dart';

class Spot {
  final String id;
  final String name;
  final String nameEn;
  final String nameJa;
  final String category;
  final String description;
  final String descriptionEn;
  final String descriptionJa;
  final double lat;
  final double lng;
  final double rating;
  final String imageUrl;
  final String openHours;
  final String address;
  final bool isLiked;
  final int visitCount;

  const Spot({
    required this.id,
    required this.name,
    this.nameEn = '',
    this.nameJa = '',
    required this.category,
    required this.description,
    this.descriptionEn = '',
    this.descriptionJa = '',
    required this.lat,
    required this.lng,
    required this.rating,
    required this.imageUrl,
    required this.openHours,
    required this.address,
    this.isLiked = false,
    this.visitCount = 0,
  });

  /// 依語言回傳對應顯示名稱
  String localizedName(String langCode) {
    if (langCode == 'en' && nameEn.isNotEmpty) return nameEn;
    if (langCode == 'ja' && nameJa.isNotEmpty) return nameJa;
    return name;
  }

  /// 依語言回傳對應描述
  String localizedDescription(String langCode) {
    if (langCode == 'en' && descriptionEn.isNotEmpty) return descriptionEn;
    if (langCode == 'ja' && descriptionJa.isNotEmpty) return descriptionJa;
    return description;
  }
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final String icon;
  final bool isUnlocked;
  final int progress;
  final int total;
  final String rarity;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.isUnlocked,
    required this.progress,
    required this.total,
    required this.rarity,
  });

  IconData get iconData {
    switch (icon) {
      case '🗺️': return Icons.map_rounded;
      case '🍜': return Icons.ramen_dining_rounded;
      case '⛰️': return Icons.landscape_rounded;
      case '🦃': return Icons.restaurant_rounded;
      case '🏆': return Icons.emoji_events_rounded;
      case '🌙': return Icons.nightlight_round;
      case '👑': return Icons.workspace_premium_rounded;
      case '🍗': return Icons.lunch_dining_rounded;
      default:   return Icons.star_rounded;
    }
  }
}
