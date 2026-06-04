import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/rail_service.dart';
import '../theme/fabric_textures.dart';
import '../config/app_config.dart';

// Map weather icon key → (IconData, Color)
(IconData, Color) _weatherIcon(String key) {
  switch (key) {
    case '⛅': case 'partly_cloudy': return (Icons.cloud_rounded, const Color(0xFF7AB8CC));
    case '🌧️': case 'rain':         return (Icons.grain_rounded,  const Color(0xFF5A8FAF));
    case '🌦️': case 'rain_sun':     return (Icons.grain_rounded,  const Color(0xFF5A9FC0));
    case '🌤️': case 'mostly_sunny': return (Icons.wb_sunny_rounded, const Color(0xFFE8C46A));
    case '☀️': case 'sunny':        return (Icons.wb_sunny_rounded, const Color(0xFFFFB300));
    case '🌫️': case 'foggy':        return (Icons.blur_on_rounded, const Color(0xFF90A4AE));
    default:                         return (Icons.cloud_rounded,  const Color(0xFF7AB8CC));
  }
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const _weekDays = ['今天','明天','週三','週四','週五','週六','週日'];

  Future<List<Map<String, dynamic>>>? _cityWeatherFuture;
  Future<List<Map<String, dynamic>>>? _countyWeatherFuture;
  Future<Map<String, dynamic>>? _extraFuture; // UV + 日出日落

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cityWeatherFuture   = _fetchWeather('Chiayi');
    _countyWeatherFuture = _fetchWeather('ChiayiCounty');
    _extraFuture         = _fetchExtraWeather();
  }

  Future<List<Map<String, dynamic>>> _fetchWeather(String cityType) async {
    return await RailService.getWeather(cityType);
  }

  /// OpenWeatherMap One Call API — UV 指數 + 日出日落
  /// 需設定 OPENWEATHER_KEY 環境變數
  Future<Map<String, dynamic>> _fetchExtraWeather() async {
    final key = AppConfig.openWeatherKey;
    if (key.isEmpty) {
      // 尚未設定 API Key — 回傳空 map，UI 顯示佔位
      return {};
    }
    try {
      final url = 'https://api.openweathermap.org/data/3.0/onecall'
          '?lat=${AppConfig.chiayiLat}&lon=${AppConfig.chiayiLon}'
          '&appid=$key&units=metric'
          '&exclude=minutely,hourly,daily,alerts';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final current = d['current'] as Map<String, dynamic>? ?? {};
        final uvi     = (current['uvi'] as num?)?.toDouble() ?? 0.0;
        final sunrise = current['sunrise'] as int? ?? 0;
        final sunset  = current['sunset']  as int? ?? 0;
        final humidity = (current['humidity'] as int?) ?? 0;
        final feelsLike = (current['feels_like'] as num?)?.round() ?? 0;
        String uviLabel;
        String uviTip;
        if      (uvi < 3)  { uviLabel = '${uvi.toStringAsFixed(1)} 低'; uviTip = '無需特別防護'; }
        else if (uvi < 6)  { uviLabel = '${uvi.toStringAsFixed(1)} 中'; uviTip = '建議塗 SPF30+'; }
        else if (uvi < 8)  { uviLabel = '${uvi.toStringAsFixed(1)} 高'; uviTip = '建議塗 SPF50+'; }
        else if (uvi < 11) { uviLabel = '${uvi.toStringAsFixed(1)} 極高'; uviTip = '上午10點後避免外出'; }
        else               { uviLabel = '${uvi.toStringAsFixed(1)} 危險'; uviTip = '避免日曬，全身防護'; }

        String _fmt(int ts) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
          return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
        }
        final sunriseStr = sunrise > 0 ? _fmt(sunrise) : '--:--';
        final sunsetStr  = sunset  > 0 ? _fmt(sunset)  : '--:--';
        final daylightH  = sunrise > 0 && sunset > 0
            ? ((sunset - sunrise) / 3600).round()
            : 0;
        String comfortLabel;
        String comfortTip;
        if      (humidity < 40) { comfortLabel = '乾燥'; comfortTip = '空氣乾燥，注意補水'; }
        else if (humidity < 60) { comfortLabel = '舒適'; comfortTip = '濕度適中，體感良好'; }
        else if (humidity < 80) { comfortLabel = '偏潮'; comfortTip = '相對濕度偏高，注意補水'; }
        else                    { comfortLabel = '悶熱'; comfortTip = '高濕悶熱，建議待在室內'; }

        return {
          'uviLabel':    uviLabel,
          'uviTip':      uviTip,
          'sunrise':     sunriseStr,
          'sunset':      sunsetStr,
          'daylightH':   daylightH,
          'comfort':     comfortLabel,
          'comfortTip':  comfortTip,
          'feelsLike':   feelsLike,
        };
      }
    } catch (e) {
      debugPrint('[WeatherExtra] $e');
    }
    return {};
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
        title: Builder(builder: (bCtx) {
          final p = Theme.of(bCtx).colorScheme.primary;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_rounded, size: 18, color: p),
            const SizedBox(width: 6),
            const Text('嘉義天氣', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(width: 6),
            DoodleHeart(color: p.withValues(alpha: 0.50), size: 10),
          ]);
        }),
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
          _buildWeatherTabWrapper('嘉義市', '23.4780° N, 120.4407° E', _cityWeatherFuture),
          _buildWeatherTabWrapper('嘉義縣・阿里山', '23.5083° N, 120.8034° E', _countyWeatherFuture),
        ],
      ),
    );
  }

  Widget _buildWeatherTabWrapper(String name, String coord, Future<List<Map<String, dynamic>>>? future) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                const Text('無法取得天氣資料，請稍後重試', style: TextStyle(color: AppColors.textHint)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _cityWeatherFuture = _fetchWeather('Chiayi');
                      _countyWeatherFuture = _fetchWeather('ChiayiCounty');
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('重新整理'),
                )
              ],
            ),
          );
        }
        return _buildWeatherTab(name, coord, snapshot.data!);
      },
    );
  }

  Widget _buildWeatherTab(String name, String coord, List<Map<String, dynamic>> data, {Map<String, dynamic>? extra}) {
    final today = data[0];
    final (todayIconData, todayIconColor) = _weatherIcon(today['icon'] as String);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                  Icon(todayIconData, size: 52, color: Colors.white.withOpacity(0.95)),
                  Row(children: [
                    Text('${today['high']}°', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                    Text(' / ${today['low']}°', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14)),
                  ]),
                ]),
              ]),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _todayDetail(Icons.umbrella_rounded, '降雨機率', '${today['rain']}%'),
                _todayDetail(Icons.water_drop_rounded, '相對濕度', '${today['humid']}%'),
                _todayDetail(Icons.air_rounded, '風速', '${today['wind']}km/h'),
                _todayDetail(Icons.thermostat_rounded, '體感', '${(today['high'] as int) + 2}°C'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── 7-day forecast ──
        StitchedBox(
          color: AppColors.surfaceWarm,
          stitchColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
          radius: 20, inset: 4, dashWidth: 4, dashGap: 3,
          padding: const EdgeInsets.all(16),
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
        FutureBuilder<Map<String, dynamic>>(
          future: _extraFuture,
          builder: (ctx, snap) {
            final e = snap.data ?? {};
            final hasData = e.isNotEmpty;
            return Column(children: [
              Row(children: [
                Expanded(child: _infoCard(Icons.wb_sunny_rounded, 'UV 指數',
                    hasData ? (e['uviLabel'] as String) : '--',
                    hasData ? (e['uviTip'] as String) : AppConfig.openWeatherKey.isEmpty ? '設定 OPENWEATHER_KEY 後顯示' : '讀取中…',
                    AppColors.accentTerra)),
                const SizedBox(width: 12),
                Expanded(child: _infoCard(Icons.sentiment_satisfied_rounded, '舒適度',
                    hasData ? (e['comfort'] as String) : '--',
                    hasData ? (e['comfortTip'] as String) : '---',
                    AppColors.accentSky)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _infoCard(Icons.wb_twilight_rounded, '日出日落',
                    hasData ? '${e['sunrise']} / ${e['sunset']}' : '--:-- / --:--',
                    hasData ? '日照時間 ${e['daylightH']} 小時' : '---',
                    AppColors.accentStraw)),
                const SizedBox(width: 12),
                Expanded(child: _infoCard(Icons.waves_rounded, '天氣警報', '無', '目前無特殊天氣警報',
                    Theme.of(context).colorScheme.primary)),
              ]),
            ]);
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _todayDetail(IconData icon, String label, String val) {
    return Column(children: [
      Icon(icon, size: 18, color: Colors.white.withOpacity(0.9)),
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
    final (iconData, iconColor) = _weatherIcon(d['icon'] as String);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(width: 34,
          child: Text(
            i < _weekDays.length ? _weekDays[i] : '第 ${i+1} 天',
            style: TextStyle(
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              fontSize: 13,
              color: isToday ? Theme.of(context).colorScheme.primary : AppColors.textSecondary,
            ))),
        const SizedBox(width: 10),
        Icon(iconData, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Expanded(child: Text(d['desc'] as String,
          style: const TextStyle(fontSize: 12, color: AppColors.textHint))),
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

  Widget _infoCard(IconData icon, String label, String val, String sub, Color color) {
    return StitchedBox(
      color: color.withValues(alpha: 0.08),
      stitchColor: color.withValues(alpha: 0.28),
      radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
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