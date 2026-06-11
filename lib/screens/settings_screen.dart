import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/app_settings_provider.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';
import 'admin_screen.dart';

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
        title: Builder(builder: (bCtx) {
          final p = Theme.of(bCtx).colorScheme.primary;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            DoodleLightning(color: p.withValues(alpha: 0.65), size: 12),
            const SizedBox(width: 6),
            Text(l10n.settings, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(width: 6),
            DoodleHeart(color: p.withValues(alpha: 0.50), size: 10),
          ]);
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // ── 主題顏色 ──────────────────────────────────────
          _SectionHeader(title: l10n.themeColor, icon: Icons.palette_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: StitchedBox(
            color: AppColors.surface,
            stitchColor: primary.withValues(alpha: 0.20),
            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.all(16),
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
                            : const SizedBox.shrink(),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                // Color name label
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    settings.currentTheme.localizedName(settings.langCode),
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
            ),  // StitchedBox
          ),    // Padding

          const SizedBox(height: 20),

          // ── 語言 ──────────────────────────────────────────
          _SectionHeader(title: l10n.language, icon: Icons.language_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: StitchedBox(
              color: AppColors.surface,
              stitchColor: primary.withValues(alpha: 0.20),
              radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: AppL10n.langOptions.map((opt) {
                  final selected = settings.langCode == opt.code;
                  return GestureDetector(
                    onTap: () => context.read<AppSettingsProvider>().setLang(opt.code),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? primary.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? primary : AppColors.divider,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(opt.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 4),
                        Text(opt.native,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? primary : AppColors.textSecondary,
                          )),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── 預覽 ──────────────────────────────────────────
          _SectionHeader(title: l10n.settingsPreview, icon: Icons.visibility_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _ThemePreview(primary: primary),
          ),

          const SizedBox(height: 20),

          // ── 通知設定 ──────────────────────────────────────
          _SectionHeader(title: l10n.settingsNotifications, icon: Icons.notifications_rounded),
          _NotificationSettings(l10n: l10n),

          const SizedBox(height: 20),

          // ── 管理員入口（僅管理員可見）────────────────────────
          FutureBuilder<DocumentSnapshot?>(
            future: FirebaseAuth.instance.currentUser?.uid != null
                ? FirebaseFirestore.instance
                    .collection('admin_users')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .get()
                : Future.value(null),
            builder: (_, snap) {
              final isAdmin = snap.data?.exists == true;
              if (!isAdmin) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SectionHeader(title: '管理員', icon: Icons.admin_panel_settings_rounded),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: StitchedBox(
                    color: AppColors.surface,
                    stitchColor: primary.withValues(alpha: 0.20),
                    radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.admin_panel_settings_rounded, size: 18, color: primary),
                      ),
                      title: const Text('管理員介面', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: const Text('舉報管理・內容審核・推播通知・資料統計', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                      onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminScreen())),
                    ),
                  ),
                ),
              ]);
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── 通知設定區塊 ──────────────────────────────────────────────
class _NotificationSettings extends StatefulWidget {
  final AppL10n l10n;
  const _NotificationSettings({required this.l10n});
  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<_NotificationSettings> {
  bool _pushEnabled      = true;
  bool _newsEnabled      = true;
  bool _communityEnabled = false;
  bool _tripEnabled      = true;
  bool _loaded           = false;

  static const _kPrefix = 'notif_setting_';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _pushEnabled      = prefs.getBool('${_kPrefix}push')      ?? true;
      _newsEnabled      = prefs.getBool('${_kPrefix}news')      ?? true;
      _communityEnabled = prefs.getBool('${_kPrefix}community') ?? false;
      _tripEnabled      = prefs.getBool('${_kPrefix}trip')      ?? true;
      _loaded           = true;
    });
  }

  Future<void> _setpref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefix}$key', value);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: StitchedBox(
        color: AppColors.surface,
        stitchColor: primary.withValues(alpha: 0.20),
        radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
        padding: EdgeInsets.zero,
        child: Column(children: [
          _notifTile(widget.l10n.settingsNotifPush, widget.l10n.settingsNotifPushSub, Icons.notifications_active_rounded,
              _pushEnabled, primary, (v) { setState(() => _pushEnabled = v); _setpref('push', v); }),
          const Divider(height: 1, indent: 54),
          _notifTile(widget.l10n.settingsNotifNews, widget.l10n.settingsNotifNewsSub, Icons.newspaper_rounded,
              _newsEnabled, primary, (v) { setState(() => _newsEnabled = v); _setpref('news', v); }),
          const Divider(height: 1, indent: 54),
          _notifTile(widget.l10n.settingsNotifComm, widget.l10n.settingsNotifCommSub, Icons.people_rounded,
              _communityEnabled, primary, (v) { setState(() => _communityEnabled = v); _setpref('community', v); }),
          const Divider(height: 1, indent: 54),
          _notifTile(widget.l10n.settingsNotifTrip, widget.l10n.settingsNotifTripSub, Icons.calendar_today_rounded,
              _tripEnabled, primary, (v) { setState(() => _tripEnabled = v); _setpref('trip', v); }),
        ]),
      ),
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
    final mist  = Color.lerp(primary, Colors.white, 0.88)!;
    final l10n  = context.watch<AppSettingsProvider>().l10n;
    final navLabels = [l10n.navHome, l10n.navMap, l10n.navTrip, l10n.navStamp];
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
              child: Center(
                child: Text(l10n.previewButton,
                    style: const TextStyle(
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
                child: Text(l10n.previewSecondary,
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
              children: navLabels.asMap().entries.map((e) {
                final active = e.key == 0;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? mist : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
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
