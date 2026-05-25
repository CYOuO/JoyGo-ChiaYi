import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings_provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final l10n     = settings.l10n;
    final primary  = settings.currentTheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.settings,
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // ── 主題顏色 ──────────────────────────────────────
          _SectionHeader(title: l10n.themeColor, icon: Icons.palette_rounded),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(kThemePresets.length, (i) {
                    final preset  = kThemePresets[i];
                    final selected = settings.themeIndex == i;
                    return GestureDetector(
                      onTap: () =>
                          context.read<AppSettingsProvider>().setTheme(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width:  52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: preset.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? AppColors.textPrimary
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: preset.primary.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  )
                                ]
                              : [],
                        ),
                        child: selected
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 22)
                            : Center(
                                child: Text(
                                  preset.emoji,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                // Color name label
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    '${settings.currentTheme.emoji} ${settings.currentTheme.name}',
                    key: ValueKey(settings.themeIndex),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 預覽 ──────────────────────────────────────────
          _SectionHeader(title: '預覽效果', icon: Icons.visibility_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _ThemePreview(primary: primary),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ]),
    );
  }
}

// ── Theme preview card ────────────────────────────────────────
class _ThemePreview extends StatelessWidget {
  final Color primary;
  const _ThemePreview({required this.primary});

  @override
  Widget build(BuildContext context) {
    final mist = Color.lerp(primary, Colors.white, 0.88)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Simulated top bar
          Row(children: [
            Container(
              width: 80, height: 28,
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('按鈕',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 80, height: 28,
              decoration: BoxDecoration(
                color: mist,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primary.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text('次要',
                    style: TextStyle(
                        color: primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const Spacer(),
            Icon(Icons.favorite_rounded, color: primary, size: 20),
            const SizedBox(width: 8),
            Icon(Icons.notifications_rounded, color: primary, size: 20),
          ]),
          const SizedBox(height: 12),
          // Simulated nav bar
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceMoss,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['首頁', '地圖', '行程', '集章'].map((label) {
                final active = label == '首頁';
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? mist : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: active ? primary : AppColors.textHint,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
