import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hugeicons/hugeicons.dart';

import 'theme/app_theme.dart';
import 'providers/app_settings_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/trip_screen.dart';
import 'screens/community_screen.dart';
import 'screens/stamp_screen.dart';
import 'screens/expense_screen.dart';
import 'widgets/auth_drawer.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
      ],
      child: const ExploreChiayiApp(),
    ),
  );
}

// ── App root ────────────────────────────────────────────────
class ExploreChiayiApp extends StatefulWidget {
  const ExploreChiayiApp({super.key});

  @override
  State<ExploreChiayiApp> createState() => _ExploreChiayiAppState();
}

class _ExploreChiayiAppState extends State<ExploreChiayiApp> {
  bool _showSplash = true;

  void _onSplashFinished() {
    if (mounted) setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();

    return MaterialApp(
      title: '探索諸羅',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(settings.currentTheme.primary),
      locale: const Locale('zh', 'TW'),
      home: _showSplash
          ? SplashScreen(onFinish: _onSplashFinished)
          : const MainShell(),
    );
  }
}

// ── Main Shell ──────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final ValueNotifier<int> _tripCalendarTrigger = ValueNotifier(0);

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();
  void _switchTab(int index) => setState(() => _currentIndex = index);

  void _goToTripCalendar() {
    _switchTab(2);
    _tripCalendarTrigger.value++;
  }

  @override
  void dispose() {
    _tripCalendarTrigger.dispose();
    super.dispose();
  }

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(
        onOpenDrawer: _openDrawer,
        onSwitchTab: _switchTab,
        onGoToTripCalendar: _goToTripCalendar,
      ),
      const MapScreen(),
      TripScreen(calendarTrigger: _tripCalendarTrigger),
      const ExpenseScreen(),
      const CommunityScreen(),
      const StampScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final l10n     = settings.l10n;
    final primary  = settings.currentTheme.primary;
    final mist     = Color.lerp(primary, Colors.white, 0.88) ?? AppColors.primaryMist;

    // ── HugeIcons 底部導覽 ──
    final navItems = [
      _NavItem(HugeIcons.strokeRoundedHome09,       l10n.navHome),
      _NavItem(HugeIcons.strokeRoundedLocation06,   l10n.navMap),
      _NavItem(HugeIcons.strokeRoundedCalendar03,   l10n.navTrip),
      _NavItem(HugeIcons.strokeRoundedWallet01,     l10n.navExpense),
      _NavItem(HugeIcons.strokeRoundedUserGroup,    l10n.navCommunity),
      _NavItem(HugeIcons.strokeRoundedAward01,      l10n.navStamp),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AuthDrawer(),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(navItems, primary, mist),
    );
  }

  Widget _buildBottomNav(List<_NavItem> navItems, Color primary, Color mist) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: navItems.asMap().entries.map((entry) {
              final index      = entry.key;
              final item       = entry.value;
              final isSelected = index == _currentIndex;
              final iconColor  = isSelected ? primary : AppColors.textHint;

              return GestureDetector(
                onTap: () => _switchTab(index),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? mist : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        key: ValueKey('nav_${index}_${isSelected ? "on" : "off"}'),
                        tween: Tween<double>(
                          begin: isSelected ? 0.65 : 1.0,
                          end: 1.0,
                        ),
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutBack,
                        builder: (_, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: HugeIcon(
                          icon: item.icon,
                          color: iconColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected ? primary : AppColors.textHint,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final List<List<dynamic>> icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
