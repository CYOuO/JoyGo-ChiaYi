import 'package:flutter/material.dart';

/// 清新自然風配色
/// 靈感：嘉義竹林晨霧、阿里山嫩芽、稻田金綠、白色木造建築
class AppColors {
  // ── Primary ─ 嫩葉綠、竹林綠
  static const Color primary      = Color(0xFF5B8A5F); // 飽和度降低的竹林綠
  static const Color primaryLight = Color(0xFF8FBF8F); // 嫩芽綠
  static const Color primaryDark  = Color(0xFF3A6140); // 深竹綠
  static const Color primaryMist  = Color(0xFFEBF4EB); // 薄霧綠（背景用）

  // ── Accent ─ 暖木、稻穗
  static const Color accentSand   = Color(0xFFD4B896); // 木質沙色
  static const Color accentStraw  = Color(0xFFE8D5A3); // 稻穗淡黃
  static const Color accentTerra  = Color(0xFFC4856A); // 陶土橘（CTA）
  static const Color accentSky    = Color(0xFF88B8C8); // 晴空藍（資訊）

  // ── Backgrounds ─ 白色系、霧感
  static const Color background   = Color(0xFFF7F9F5); // 極淡草地白
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color surfaceWarm  = Color(0xFFFDF8F2); // 暖白（卡片）
  static const Color surfaceMoss  = Color(0xFFF0F5EF); // 苔蘚白（tag背景）
  static const Color divider      = Color(0xFFE8EDE7); // 分隔線

  // ── Text
  static const Color textPrimary   = Color(0xFF2C3A2E); // 深苔綠文字
  static const Color textSecondary = Color(0xFF607060); // 中灰綠
  static const Color textHint      = Color(0xFFA0AFA0); // 淡灰綠

  // ── Semantic
  static const Color success = Color(0xFF5B8A5F);
  static const Color warning = Color(0xFFD4A847);
  static const Color error   = Color(0xFFBF6060);
  static const Color info    = Color(0xFF88B8C8);

  // ── Shadow（超淡）
  static const Color cardShadow = Color(0x125B8A5F);

  // ── Stamp
  static const Color stampGold   = Color(0xFFCFA84C);
  static const Color stampSilver = Color(0xFFA0AFA0);
  static const Color stampBronze = Color(0xFFA8784A);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accentTerra,
        surface: AppColors.surface,
        background: AppColors.background,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'NotoSansTC',

      // AppBar：白底無陰影，細分隔線
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'NotoSansTC',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      ),

      // Bottom nav
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),

      // Card：圓角20，極淡陰影
      cardTheme: CardThemeData(
        color: AppColors.surfaceWarm,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        shadowColor: AppColors.cardShadow,
        margin: EdgeInsets.zero,
      ),

      // ElevatedButton
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // OutlinedButton
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMoss,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: AppColors.primary),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMoss,
        selectedColor: AppColors.primaryMist,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // Progress indicator — override Flutter's default blue
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        circularTrackColor: AppColors.primaryMist,
        linearTrackColor: AppColors.primaryMist,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryLight
              : AppColors.divider,
        ),
      ),

      // Slider
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.divider,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x205B8A5F),
      ),

      // TabBar
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
        dividerColor: AppColors.divider,
      ),
    );
  }
}

// ─────────────────────────────────────────
// 通用漸層（清新綠）
// ─────────────────────────────────────────
class AppGradients {
  static const LinearGradient primaryGreen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6A9E6E), Color(0xFF4A7A50)],
  );

  static const LinearGradient mistyMorning = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEBF4EB), Color(0xFFF7F9F5)],
  );

  static const LinearGradient skyToGreen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF88B8C8), Color(0xFF5B8A5F)],
  );

  static const LinearGradient warmSand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8D5A3), Color(0xFFD4B896)],
  );
}
