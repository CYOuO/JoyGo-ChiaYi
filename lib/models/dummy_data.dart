import 'package:flutter/material.dart';

// ===== MODELS =====

class Spot {
  final String id;
  final String name;
  final String nameEn;
  final String category; // attraction, restaurant, aed, hotel, youbike
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

class NewsItem {
  final String id;
  final String title;
  final String summary;
  final String date;
  final String category;
  final String imageUrl;

  const NewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.date,
    required this.category,
    required this.imageUrl,
  });
}

class TripPlan {
  final String id;
  final String title;
  final String date;
  final List<String> spotIds;
  final String creatorName;
  final String creatorAvatar;
  final int likes;
  final bool isPublished;
  final String? coverImage;
  final int days;
  final int budget; // 每人預算（元）

  const TripPlan({
    required this.id,
    required this.title,
    required this.date,
    required this.spotIds,
    required this.creatorName,
    required this.creatorAvatar,
    required this.likes,
    this.isPublished = false,
    this.coverImage,
    this.days = 1,
    this.budget = 800,
  });
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final String icon; // legacy emoji key — use achievementIcon() for display
  final bool isUnlocked;
  final int progress;
  final int total;
  final String rarity; // bronze, silver, gold, special

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

  // Convert emoji icon key → IconData
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

// ===== DUMMY DATA =====

class DummyData {
  static const List<Spot> spots = [
    Spot(
      id: '1',
      name: '阿里山國家風景區',
      nameEn: 'Alishan National Scenic Area',
      category: 'attraction',
      description: '阿里山以神木、雲海、日出、森林鐵路和山地文化聞名。每年春天的櫻花季更是吸引大批遊客前來朝聖。',
      lat: 23.5131,
      lng: 120.8038,
      rating: 4.8,
      imageUrl: 'https://picsum.photos/seed/alishan/400/300',
      openHours: '全天開放',
      address: '嘉義縣阿里山鄉',
    ),
    Spot(
      id: '2',
      name: '文化路夜市',
      nameEn: 'Wenhua Road Night Market',
      category: 'restaurant',
      description: '嘉義市最熱鬧的夜市，匯集了各式小吃，必吃火雞肉飯、方塊酥、烤玉米等在地美食。',
      lat: 23.4801,
      lng: 120.4513,
      rating: 4.6,
      imageUrl: 'https://picsum.photos/seed/nightmarket/400/300',
      openHours: '18:00 - 01:00',
      address: '嘉義市東區文化路',
    ),
    Spot(
      id: '3',
      name: '北門車站',
      nameEn: 'Beimon Station',
      category: 'attraction',
      description: '阿里山森林鐵路北門站，建於1912年，是嘉義市重要的歷史古蹟，保存完好的日式木造建築。',
      lat: 23.4802,
      lng: 120.4482,
      rating: 4.5,
      imageUrl: 'https://picsum.photos/seed/station/400/300',
      openHours: '06:00 - 22:00',
      address: '嘉義市西區北門路1號',
    ),
    Spot(
      id: '4',
      name: '嘉義公園',
      nameEn: 'Chiayi Park',
      category: 'attraction',
      description: '嘉義市最大的都市公園，內有射日塔、孔廟、棒球場等設施，是市民休閒的好去處。',
      lat: 23.4784,
      lng: 120.4526,
      rating: 4.3,
      imageUrl: 'https://picsum.photos/seed/park/400/300',
      openHours: '全天開放',
      address: '嘉義市東區公園街42號',
    ),
    Spot(
      id: '5',
      name: '林聰明沙鍋魚頭',
      nameEn: 'Lin Congming Hotpot',
      category: 'restaurant',
      description: '嘉義超人氣老字號，沙鍋魚頭是必點招牌，湯頭濃郁鮮美，搭配白飯絕配。',
      lat: 23.4795,
      lng: 120.4502,
      rating: 4.7,
      imageUrl: 'https://picsum.photos/seed/hotpot/400/300',
      openHours: '10:30 - 21:00',
      address: '嘉義市東區中正路361號',
    ),
    Spot(
      id: '6',
      name: '御品元冰菓室',
      nameEn: 'Yupin Ice Cream',
      category: 'restaurant',
      description: '嘉義著名老冰店，以芒果冰、鳳梨冰聞名，使用在地新鮮水果製作，清涼消暑。',
      lat: 23.4812,
      lng: 120.4518,
      rating: 4.5,
      imageUrl: 'https://picsum.photos/seed/icecream/400/300',
      openHours: '10:00 - 22:00',
      address: '嘉義市東區文化路',
    ),
    Spot(
      id: '7',
      name: '嘉義市立美術館',
      nameEn: 'Chiayi City Museum of Art',
      category: 'attraction',
      description: '嘉義市立美術館前身為菸草公賣局，活化再生後成為展示台灣藝術的重要場所。',
      lat: 23.4763,
      lng: 120.4505,
      rating: 4.4,
      imageUrl: 'https://picsum.photos/seed/museum/400/300',
      openHours: '09:00 - 17:00（週一休）',
      address: '嘉義市西區廣寧街101號',
    ),
    Spot(
      id: '8',
      name: 'YouBike 火車站',
      nameEn: 'YouBike Train Station',
      category: 'youbike',
      description: 'YouBike 2.0 站點，共有20個停車格',
      lat: 23.4758,
      lng: 120.4421,
      rating: 4.0,
      imageUrl: 'https://picsum.photos/seed/bike/400/300',
      openHours: '24小時',
      address: '嘉義市西區中山路',
    ),
  ];

  static const List<NewsItem> news = [
    NewsItem(
      id: '1',
      title: '2025嘉義燈會活動開跑！精彩燈組搶先看',
      summary: '嘉義市燈會今年以「光鑄諸羅」為主題，結合傳統與現代燈藝，在嘉義公園盛大登場...',
      date: '2025-05-12',
      category: '活動',
      imageUrl: 'https://picsum.photos/seed/festival/600/400',
    ),
    NewsItem(
      id: '2',
      title: '阿里山森林鐵路暑期加班車公告',
      summary: '因應暑假旅遊旺季，阿里山森林鐵路將於7月1日起增開假日加班車，欲搭乘民眾請提早購票...',
      date: '2025-05-10',
      category: '交通',
      imageUrl: 'https://picsum.photos/seed/train/600/400',
    ),
    NewsItem(
      id: '3',
      title: '嘉義市觀光局推出「食遊諸羅」美食護照',
      summary: '集滿10間合作餐廳印章，即可兌換嘉義市伴手禮一份，活動即日起至8月31日止...',
      date: '2025-05-08',
      category: '美食',
      imageUrl: 'https://picsum.photos/seed/food/600/400',
    ),
    NewsItem(
      id: '4',
      title: '夏季觀光優惠出爐！住宿補助最高500元',
      summary: '嘉義市政府推出夏季旅遊優惠方案，持嘉義觀光護照於合作住宿消費可享最高500元補助...',
      date: '2025-05-06',
      category: '優惠',
      imageUrl: 'https://picsum.photos/seed/hotel/600/400',
    ),
  ];

  static const List<TripPlan> communityTrips = [
    TripPlan(
      id: '1',
      title: '嘉義一日小吃巡禮',
      date: '2025-05-15',
      spotIds: ['1', '2', '5', '6'],
      creatorName: '小美食家',
      creatorAvatar: 'https://picsum.photos/seed/user1/100/100',
      likes: 156,
      isPublished: true,
      coverImage: 'https://picsum.photos/seed/trip1/600/300',
      days: 1, budget: 480,
    ),
    TripPlan(
      id: '2',
      title: '阿里山二日深度遊',
      date: '2025-06-01',
      spotIds: ['1', '3', '7'],
      creatorName: '旅遊達人',
      creatorAvatar: 'https://picsum.photos/seed/user2/100/100',
      likes: 89,
      isPublished: true,
      coverImage: 'https://picsum.photos/seed/trip2/600/300',
      days: 2, budget: 1800,
    ),
    TripPlan(
      id: '3',
      title: '嘉義市區文青散策',
      date: '2025-05-20',
      spotIds: ['3', '4', '7'],
      creatorName: '城市探索者',
      creatorAvatar: 'https://picsum.photos/seed/user3/100/100',
      likes: 234,
      isPublished: true,
      coverImage: 'https://picsum.photos/seed/trip3/600/300',
      days: 1, budget: 750,
    ),
  ];

  static const List<Achievement> achievements = [
    Achievement(
      id: '1',
      title: '諸羅初探者',
      description: '完成第一個景點打卡',
      icon: '🗺️',
      isUnlocked: true,
      progress: 1,
      total: 1,
      rarity: 'bronze',
    ),
    Achievement(
      id: '2',
      title: '美食獵人',
      description: '到訪5間餐廳',
      icon: '🍜',
      isUnlocked: true,
      progress: 5,
      total: 5,
      rarity: 'silver',
    ),
    Achievement(
      id: '3',
      title: '阿里山征服者',
      description: '完成阿里山景區所有景點打卡',
      icon: '⛰️',
      isUnlocked: false,
      progress: 2,
      total: 8,
      rarity: 'gold',
    ),
    Achievement(
      id: '4',
      title: '火雞飯控',
      description: '造訪3間火雞肉飯店家',
      icon: '🦃',
      isUnlocked: true,
      progress: 3,
      total: 3,
      rarity: 'bronze',
    ),
    Achievement(
      id: '5',
      title: '嘉義通',
      description: '解鎖50個景點',
      icon: '🏆',
      isUnlocked: false,
      progress: 12,
      total: 50,
      rarity: 'gold',
    ),
    Achievement(
      id: '6',
      title: '夜市達人',
      description: '夜間打卡文化路夜市3次',
      icon: '🌙',
      isUnlocked: false,
      progress: 1,
      total: 3,
      rarity: 'silver',
    ),
    Achievement(
      id: '7',
      title: '特別獎：諸羅守護者',
      description: '達成所有成就',
      icon: '👑',
      isUnlocked: false,
      progress: 4,
      total: 20,
      rarity: 'special',
    ),
    Achievement(
      id: '8',
      title: '雞肉飯巡禮',
      description: '吃滿30間嘉義雞肉飯',
      icon: '🍗',
      isUnlocked: false,
      progress: 3,
      total: 30,
      rarity: 'gold',
    ),
  ];
}
