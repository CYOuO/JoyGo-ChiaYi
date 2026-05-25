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

  // ── 可愛粉嫩點綴色
  static const Color cutePeach    = Color(0xFFFFD3C2);
  static const Color cutePink     = Color(0xFFFCC8D4);
  static const Color cuteLavender = Color(0xFFD8CCEC);
  static const Color cuteMint     = Color(0xFFC2E8D5);
  static const Color cuteLemon    = Color(0xFFFFE9A8);
  static const Color cuteSky      = Color(0xFFC4E1F0);
}

class AppTheme {
  /// Build theme from a custom primary color (for dynamic theming).
  static ThemeData buildTheme(Color primarySeed) => _build(primarySeed);

  /// Default light theme.
  static ThemeData get lightTheme => _build(AppColors.primary);

  static ThemeData _build(Color primary) {
    final mist = Color.lerp(primary, Colors.white, 0.88) ?? AppColors.primaryMist;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary:   primary,
        secondary: AppColors.accentTerra,
        surface:   AppColors.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'NotoSansTC',

      // ── AppBar
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

      // ── BottomNavigationBar (legacy — our custom nav overrides this)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: primary,
        unselectedItemColor: AppColors.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),

      // ── Card（圓潤 20px）
      cardTheme: const CardThemeData(
        color: AppColors.surfaceWarm,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20))),
        shadowColor: AppColors.cardShadow,
        margin: EdgeInsets.zero,
      ),

      // ── ElevatedButton（藥丸狀）
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 26),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // ── OutlinedButton（藥丸狀）
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 26),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),

      // ── TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),

      // ── Input（14px）
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMoss,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle:
            const TextStyle(color: AppColors.textHint, fontSize: 14),
        labelStyle:
            const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: TextStyle(color: primary),
      ),

      // ── Chip（圓角 20px）
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMoss,
        selectedColor: mist,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: AppColors.divider),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20))),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),

      // ── Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ── Progress indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        circularTrackColor: mist,
        linearTrackColor: mist,
      ),

      // ── Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? mist : AppColors.divider,
        ),
      ),

      // ── Slider
      sliderTheme: SliderThemeData(
        activeTrackColor:   primary,
        inactiveTrackColor: AppColors.divider,
        thumbColor:         primary,
        overlayColor:       primary.withValues(alpha: 0.12),
      ),

      // ── TabBar
      tabBarTheme: TabBarThemeData(
        labelColor:            primary,
        unselectedLabelColor:  AppColors.textHint,
        indicatorColor:        primary,
        indicatorSize:         TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w400, fontSize: 14),
        dividerColor: AppColors.divider,
      ),
    );
  }
}

// ─────────────────────────────────────────
// BuildContext color helpers
// Usage: context.appPrimary, context.appMist
// These read the LIVE theme from MaterialApp so they update when the
// user switches theme preset — unlike the static AppColors.primary const.
// ─────────────────────────────────────────
extension AppThemeX on BuildContext {
  /// Current theme primary color (updates with preset changes).
  Color get appPrimary => Theme.of(this).colorScheme.primary;

  /// Soft mist tint — 88 % white blend of appPrimary.
  Color get appMist =>
      Color.lerp(appPrimary, Colors.white, 0.88) ?? AppColors.primaryMist;

  /// Darker shade — 20 % black blend.
  Color get appPrimaryDark =>
      Color.lerp(appPrimary, Colors.black, 0.20) ?? AppColors.primaryDark;

  /// On-primary text color (white for dark backgrounds).
  Color get appOnPrimary => ThemeData.estimateBrightnessForColor(appPrimary) == Brightness.dark
      ? Colors.white
      : Colors.black87;
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

  static const LinearGradient candyPeach = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD3C2), Color(0xFFFCC8D4)],
  );

  static const LinearGradient dreamMint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC2E8D5), Color(0xFFC4E1F0)],
  );

  static const LinearGradient softLavender = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD8CCEC), Color(0xFFFCC8D4)],
  );
}
