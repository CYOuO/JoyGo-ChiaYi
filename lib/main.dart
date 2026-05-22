import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/trip_screen.dart';
import 'screens/community_screen.dart';
import 'screens/stamp_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/expense_screen.dart';
import 'widgets/auth_drawer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const ExploreChiayiApp());
}

class ExploreChiayiApp extends StatelessWidget {
  const ExploreChiayiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '探索諸羅',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainShell(),
    );
  }
}

// ── Main shell ──────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();
  void _switchTab(int index) => setState(() => _currentIndex = index);

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(onOpenDrawer: _openDrawer, onSwitchTab: _switchTab),
      const MapScreen(),
      const TripScreen(),
      const ExpenseScreen(),
      const CommunityScreen(),
      const StampScreen(),
    ];
  }

  static const List<_NavItem> _navItems = [
    _NavItem(Icons.home_rounded,           Icons.home_outlined,           '首頁'),
    _NavItem(Icons.map_rounded,            Icons.map_outlined,            '地圖'),
    _NavItem(Icons.calendar_month_rounded, Icons.calendar_month_outlined, '行程'),
    _NavItem(Icons.receipt_long_rounded,   Icons.receipt_long_outlined,   '分帳'),
    _NavItem(Icons.people_rounded,         Icons.people_outline_rounded,  '社群'),
    _NavItem(Icons.military_tech_rounded,  Icons.military_tech_outlined,  '集章'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AuthDrawer(),
      body: IndexedStack(index: _currentIndex, children: _screens),
      floatingActionButton: _currentIndex == 5
          ? FloatingActionButton(
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CameraScreen())),
              backgroundColor: AppColors.primary,
              elevation: 2,
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white),
            )
          : const SizedBox.shrink(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _navItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = index == _currentIndex;
              return GestureDetector(
                onTap: () => _switchTab(index),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryMist : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isSelected ? item.activeIcon : item.icon,
                        color: isSelected ? AppColors.primary : AppColors.textHint, size: 22),
                      const SizedBox(height: 3),
                      Text(item.label, style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        color: isSelected ? AppColors.primary : AppColors.textHint,
                      )),
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
  final IconData activeIcon, icon;
  final String label;
  const _NavItem(this.activeIcon, this.icon, this.label);
}