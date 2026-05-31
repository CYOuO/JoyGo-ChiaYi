import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings_provider.dart';
import '../theme/app_theme.dart';
import 'firebase_seed_screen.dart';

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

          const SizedBox(height: 20),

          // ── 通知設定 ──────────────────────────────────────
          _SectionHeader(title: '通知設定', icon: Icons.notifications_rounded),
          const _NotificationSettings(),

          const SizedBox(height: 20),

          // ── 開發者工具 ────────────────────────────────────
          _SectionHeader(title: '開發者工具', icon: Icons.developer_mode_rounded),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_upload_rounded, size: 18, color: Color(0xFFE65100)),
              ),
              title: const Text('Firebase 測試資料', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('上傳假貼文測試按讚/收藏', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FirebaseSeedScreen())),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── 通知設定區塊 ──────────────────────────────────────────────
class _NotificationSettings extends StatefulWidget {
  const _NotificationSettings();
  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<_NotificationSettings> {
  bool _pushEnabled     = true;
  bool _newsEnabled     = true;
  bool _communityEnabled = false;
  bool _tripEnabled     = true;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: [
        _notifTile('推播通知', '接收 App 所有通知', Icons.notifications_active_rounded,
            _pushEnabled, primary, (v) => setState(() => _pushEnabled = v)),
        const Divider(height: 1, indent: 54),
        _notifTile('最新消息', '嘉義市政府新聞與活動', Icons.newspaper_rounded,
            _newsEnabled, primary, (v) => setState(() => _newsEnabled = v)),
        const Divider(height: 1, indent: 54),
        _notifTile('社群互動', '按讚、留言、追蹤通知', Icons.people_rounded,
            _communityEnabled, primary, (v) => setState(() => _communityEnabled = v)),
        const Divider(height: 1, indent: 54),
        _notifTile('行程提醒', '出發前一天自動提醒', Icons.calendar_today_rounded,
            _tripEnabled, primary, (v) => setState(() => _tripEnabled = v)),
      ]),
    );
  }

  Widget _notifTile(String title, String sub, IconData icon,
      bool value, Color primary, void Function(bool) onChanged) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: value ? primary.withValues(alpha: 0.1) : AppColors.surfaceMoss,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: value ? primary : AppColors.textHint),
      ),
      title: Text(title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Text(sub,
        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: primary,
        activeTrackColor: primary.withValues(alpha: 0.4),
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
