import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _weekDays = ['今天','明天','週三','週四','週五','週六','週日'];

  // 嘉義市一週天氣
  static const _cityWeather = [
    {'high':32,'low':25,'icon':'⛅','desc':'多雲時晴','rain':20,'humid':75,'wind':12},
    {'high':30,'low':24,'icon':'🌧️','desc':'午後雷陣雨','rain':70,'humid':82,'wind':8},
    {'high':28,'low':23,'icon':'🌦️','desc':'陰有雨','rain':60,'humid':85,'wind':10},
    {'high':31,'low':24,'icon':'🌤️','desc':'晴時多雲','rain':15,'humid':72,'wind':14},
    {'high':33,'low':26,'icon':'☀️','desc':'晴天','rain':5,'humid':68,'wind':9},
    {'high':34,'low':26,'icon':'☀️','desc':'晴天','rain':5,'humid':65,'wind':11},
    {'high':31,'low':25,'icon':'⛅','desc':'多雲','rain':25,'humid':78,'wind':13},
  ];

  // 嘉義縣一週天氣
  static const _countyWeather = [
    {'high':28,'low':20,'icon':'🌤️','desc':'晴時多雲','rain':15,'humid':70,'wind':10},
    {'high':25,'low':18,'icon':'🌧️','desc':'山區有雨','rain':65,'humid':80,'wind':7},
    {'high':23,'low':17,'icon':'🌫️','desc':'晨霧濃','rain':40,'humid':88,'wind':5},
    {'high':27,'low':19,'icon':'🌦️','desc':'多雲有雨','rain':50,'humid':78,'wind':8},
    {'high':29,'low':20,'icon':'☀️','desc':'晴天','rain':10,'humid':65,'wind':12},
    {'high':30,'low':21,'icon':'🌤️','desc':'晴時多雲','rain':20,'humid':68,'wind':11},
    {'high':27,'low':19,'icon':'⛅','desc':'多雲','rain':30,'humid':75,'wind':9},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('嘉義天氣'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '嘉義市'),
            Tab(text: '嘉義縣（阿里山）'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWeatherTab('嘉義市', '23.4780° N, 120.4407° E', _cityWeather),
          _buildWeatherTab('嘉義縣・阿里山', '23.5083° N, 120.8034° E', _countyWeather),
        ],
      ),
    );
  }

  Widget _buildWeatherTab(String name, String coord, List<Map<String, dynamic>> data) {
    final today = data[0];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Today hero card ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF7AB8CC), Theme.of(context).colorScheme.primary],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: const Color(0xFF7AB8CC).withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(
            children: [
              Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(coord, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 10)),
                  const SizedBox(height: 4),
                  Text('今天 · ${today['desc']}', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
                ]),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(today['icon'] as String, style: const TextStyle(fontSize: 52)),
                  Row(children: [
                    Text('${today['high']}°', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                    Text(' / ${today['low']}°', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14)),
                  ]),
                ]),
              ]),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _todayDetail('☔', '降雨機率', '${today['rain']}%'),
                _todayDetail('💧', '相對濕度', '${today['humid']}%'),
                _todayDetail('💨', '風速', '${today['wind']}km/h'),
                _todayDetail('🌡️', '體感', '${(today['high'] as int) + 2}°C'),
              ]),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 7-day forecast ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceWarm,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.calendar_today_rounded, size: 15, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                const Text('7 天天氣預報', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 14),
              ...data.asMap().entries.map((e) => _forecastRow(e.key, e.value)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── UV & Comfort ──
        Row(children: [
          Expanded(child: _infoCard('☀️', 'UV 指數', '8 高', '建議塗抹防曬 SPF50+', AppColors.accentTerra)),
          const SizedBox(width: 12),
          Expanded(child: _infoCard('😊', '舒適度', '悶熱', '相對濕度偏高，注意補水', AppColors.accentSky)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _infoCard('🌅', '日出日落', '05:15 / 18:45', '日照時間 13小時30分', AppColors.accentStraw)),
          const SizedBox(width: 12),
          Expanded(child: _infoCard('🌊', '天氣警報', '無', '目前無特殊天氣警報', Theme.of(context).colorScheme.primary)),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _todayDetail(String icon, String label, String val) {
    return Column(children: [
      Text(icon, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 3),
      Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 9)),
    ]);
  }

  Widget _forecastRow(int i, Map<String, dynamic> d) {
    final high = d['high'] as int;
    final low = d['low'] as int;
    final rain = d['rain'] as int;
    final isToday = i == 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(width: 34,
          child: Text(_weekDays[i],
            style: TextStyle(
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              fontSize: 13,
              color: isToday ? Theme.of(context).colorScheme.primary : AppColors.textSecondary,
            ))),
        const SizedBox(width: 10),
        Text(d['icon'] as String, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(child: Text(d['desc'] as String,
          style: const TextStyle(fontSize: 12, color: AppColors.textHint))),
        // Rain prob bar
        SizedBox(width: 36, child: Column(children: [
          Text('$rain%', style: TextStyle(fontSize: 10,
            color: rain > 50 ? AppColors.accentSky : AppColors.textHint)),
          const SizedBox(height: 2),
          ClipRRect(borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: rain/100, minHeight: 3,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(rain > 50 ? AppColors.accentSky : AppColors.divider))),
        ])),
        const SizedBox(width: 10),
        Text('$low°', style: const TextStyle(fontSize: 13, color: AppColors.textHint, fontWeight: FontWeight.w600)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('—', style: TextStyle(color: AppColors.divider))),
        Text('$high°', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _infoCard(String icon, String label, String val, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text(val, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
        const SizedBox(height: 3),
        Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textHint, height: 1.3)),
      ]),
    );
  }
}
