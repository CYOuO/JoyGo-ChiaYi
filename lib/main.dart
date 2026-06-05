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
import 'screens/profile_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      providers: [ChangeNotifierProvider(create: (_) => AppSettingsProvider())],
      child: const ExploreChiayiApp(),
    ),
  );
}

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
      theme: AppTheme.buildTheme(settings.currentTheme.primary, accent: settings.currentTheme.accent),
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

  final ValueNotifier<int> _tripCalendarTrigger = ValueNotifier(0);

  void _switchTab(int index) => setState(() => _currentIndex = index);

  void _goToTripCalendar() {
    _switchTab(1); // 行程(1)，地圖是(2)
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
    // 順序：首頁(0) 行程(1) 地圖(2,突出置中) 社群(3) 我的(4)
    // 分帳已合併進行程，不再獨立 tab
    _screens = [
      HomeScreen(
        onSwitchTab: _switchTab,
        onGoToTripCalendar: _goToTripCalendar,
        onOpenDrawer: () => _switchTab(4),
      ),
      TripScreen(calendarTrigger: _tripCalendarTrigger),
      const MapScreen(),
      const CommunityScreen(),
      const ProfileScreen(),
    ];
  }

  // ─── Nav items (Material Icons) ─────────────────────────
  // 5 tabs：首頁(0) 行程(1) 地圖(2,突出) 社群(3) 我的(4)
  // 未選中：outlined，選中：filled
  static const _navIcons = [
    Icons.home_outlined,
    Icons.calendar_today_outlined,
    Icons.location_on_outlined,
    Icons.group_outlined,
    Icons.person_outline,
  ];
  static const _navIconsFilled = [
    Icons.home_rounded,
    Icons.calendar_month_rounded,
    Icons.location_on_rounded,
    Icons.group_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final l10n    = settings.l10n;
    final primary = settings.currentTheme.primary;

    final labels = [
      l10n.navHome, l10n.navTrip, l10n.navMap,
      l10n.navCommunity, '我的',
    ];

    return Scaffold(
      body: _FadeTabSwitcher(currentIndex: _currentIndex, children: _screens),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        icons: _navIcons,
        iconsFilled: _navIconsFilled,
        labels: labels,
        primary: primary,
        onTap: _switchTab,
      ),
    );
  }
}

// ── 底部導覽元件 ─────────────────────────────────────────────
// 中間地圖鍵突出，頂端圓角，動畫流暢
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final List<IconData> icons;
  final List<IconData> iconsFilled;
  final List<String> labels;
  final Color primary;
  final void Function(int) onTap;

  static const int _mapIndex = 2;

  const _BottomNav({
    required this.currentIndex,
    required this.icons,
    required this.iconsFilled,
    required this.labels,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, -4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── 一般按鈕列（跳過 mapIndex 留空位）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: List.generate(icons.length, (i) {
                    if (i == _mapIndex) {
                      return const Expanded(child: SizedBox());
                    }
                    final selected = i == currentIndex;
                    return Expanded(
                      child: _NavItem(
                        icon: icons[i],
                        iconFilled: iconsFilled[i],
                        label: labels[i],
                        selected: selected,
                        primary: primary,
                        onTap: () => onTap(i),
                      ),
                    );
                  }),
                ),
              ),

              // ── 地圖突出鍵（置中，往上浮起）
              Positioned(
                top: -20,
                left: 0,
                right: 0,
                child: Center(
                  child: _MapFabItem(
                    icon: iconsFilled[_mapIndex],
                    label: labels[_mapIndex],
                    selected: currentIndex == _mapIndex,
                    primary: primary,
                    onTap: () => onTap(_mapIndex),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 地圖突出按鈕 ──────────────────────────────────────────────
class _MapFabItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  const _MapFabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  State<_MapFabItem> createState() => _MapFabItemState();
}

class _MapFabItemState extends State<_MapFabItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) {
        setState(() => _pressed = true);
        _ctrl.forward();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        _ctrl.reverse();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        _ctrl.reverse();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            ),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(widget.selected),
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  // 選中時深色，未選中時主色
                  color: widget.selected
                      ? Color.lerp(widget.primary, Colors.black, 0.15)
                      : widget.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.primary
                          .withValues(alpha: widget.selected ? 0.45 : 0.28),
                      blurRadius: widget.selected ? 18 : 10,
                      spreadRadius: widget.selected ? 2 : 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: CurvedAnimation(
                          parent: anim, curve: Curves.easeOutBack),
                      child: child,
                    ),
                    child: Icon(
                      key: ValueKey(widget.selected),
                      widget.icon,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 10,
              fontWeight:
                  widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: widget.selected ? widget.primary : AppColors.textHint,
              height: 1,
            ),
            child: Text(widget.label, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

// ── Tab 切換：fade + 微微上浮，比純淡入更有立體感 ──────────────
class _FadeTabSwitcher extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;
  const _FadeTabSwitcher({required this.currentIndex, required this.children});

  @override
  State<_FadeTabSwitcher> createState() => _FadeTabSwitcherState();
}

class _FadeTabSwitcherState extends State<_FadeTabSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..value = 1.0;
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    // 新頁從下方 3% 往上浮入，非常細膩不突兀
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(_FadeTabSwitcher old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: child),
      ),
      child: IndexedStack(index: widget.currentIndex, children: widget.children),
    );
  }
}

// ── 一般導覽項目 ──────────────────────────────────────────────
class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData iconFilled;
  final String label;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.iconFilled,
    required this.label,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── 圖示
              TweenAnimationBuilder<double>(
                key: ValueKey('icon_${widget.selected}'),
                tween: Tween(begin: 0.7, end: 1.0),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Icon(
                  widget.selected ? widget.iconFilled : widget.icon,
                  color: widget.selected
                      ? widget.primary
                      : AppColors.textHint,
                  size: 22,
                ),
              ),
              const SizedBox(height: 4),
              // ── 文字
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: widget.selected ? widget.primary : AppColors.textHint,
                  height: 1,
                ),
                child: Text(widget.label, textAlign: TextAlign.center),
              ),
              // ── 選中時底部小圓點
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: widget.selected ? 4 : 0,
                height: widget.selected ? 4 : 0,
                decoration: BoxDecoration(
                  color: widget.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}