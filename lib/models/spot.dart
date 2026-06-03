import 'package:flutter/material.dart';

class Spot {
  final String id;
  final String name;
  final String nameEn;
  final String category;
  final String description;
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
    required this.nameEn,
    required this.category,
    required this.description,
    required this.lat,
    required this.lng,
    required this.rating,
    required this.imageUrl,
    required this.openHours,
    required this.address,
    this.isLiked = false,
    this.visitCount = 0,
  });
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
