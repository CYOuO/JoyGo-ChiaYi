import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/fabric_textures.dart';

// ══════════════════════════════════════════════
// 隱私政策頁面
// ══════════════════════════════════════════════
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) => _InfoPage(
    title: '隱私政策',
    icon: Icons.shield_outlined,
    sections: const [
      _Section('資料蒐集', '探索諸羅 App 在您使用服務時，可能蒐集以下資訊：\n\n'
          '• 帳號資料：電子郵件、暱稱、大頭貼（透過 Google / Email 登入）\n'
          '• 位置資訊：用於附近景點推薦及集章功能（僅在您授權後啟用）\n'
          '• 使用記錄：瀏覽景點、收藏、行程規劃等操作記錄\n'
          '• 裝置資訊：作業系統版本、裝置型號（用於問題排查）'),
      _Section('資料用途', '蒐集之個人資料僅用於：\n\n'
          '• 提供個人化景點推薦與行程規劃服務\n'
          '• 儲存您的收藏景點、行程記錄與集章進度\n'
          '• 改善 App 功能與使用者體驗\n'
          '• 寄送重要服務通知（如行程出發提醒）'),
      _Section('資料保護', '您的資料安全是我們的首要責任：\n\n'
          '• 所有資料透過 Firebase（Google Cloud）安全儲存與傳輸\n'
          '• 位置資料不會在未授權情形下被分享給第三方\n'
          '• 您可隨時在設定中撤銷位置授權\n'
          '• 刪除帳號時，所有個人資料將一併移除'),
      _Section('第三方服務', '本 App 使用以下第三方服務：\n\n'
          '• Firebase（Google）：帳號驗證、資料儲存\n'
          '• OpenStreetMap：地圖顯示\n'
          '• 交通部 TDX API：交通與景點資料\n'
          '• 嘉義市政府開放資料：在地新聞與活動'),
      _Section('您的權利', '依據個人資料保護法，您享有以下權利：\n\n'
          '• 查詢、閱覽本人個人資料\n'
          '• 申請補充或更正個人資料\n'
          '• 申請停止蒐集、處理或利用個人資料\n'
          '• 申請刪除個人資料\n\n'
          '如需行使上述權利，請至「設定 → 聯絡我們」。'),
      _Section('政策更新', '本隱私政策如有重大變更，將於 App 內顯著位置公告，並視情況以推播通知告知。繼續使用本服務即表示您同意更新後的隱私政策。\n\n最後更新：2026 年 6 月'),
    ],
  );
}

// ══════════════════════════════════════════════
// 常見問題頁面
// ══════════════════════════════════════════════
class FAQPage extends StatelessWidget {
  const FAQPage({super.key});
  @override
  Widget build(BuildContext context) => _InfoPage(
    title: '常見問題',
    icon: Icons.help_outline_rounded,
    sections: const [
      _Section('如何建立行程？', '點選下方「行程」頁面，點擊右上角「＋」按鈕即可建立新行程。輸入行程名稱、日期後，可至地圖或首頁收藏景點，再加入行程中。'),
      _Section('景點資料多久更新一次？', '地圖景點資料來自交通部 TDX 開放平台及嘉義市政府開放資料，通常每月更新。YouBike 站點與公車資料則為即時資訊（每 30 秒自動刷新）。'),
      _Section('沒有網路可以使用嗎？', '部分功能（如離線地圖、天氣、交通）需要網路連線。行程規劃與已收藏景點的基本資料可在離線狀態查看，但即時資訊功能暫時無法使用。'),
      _Section('如何集章？', '到達景點附近 100 公尺範圍內，App 會自動偵測並完成打卡集章。也可在「集章成就」頁面手動拍照打卡。集章越多，可解鎖更多成就徽章。'),
      _Section('找不到某個景點怎麼辦？', '地圖景點資料持續更新中，若您發現遺漏的景點，可透過「設定 → 意見回饋」告訴我們。您也可以手動在社群發文分享該景點資訊。'),
      _Section('忘記密碼怎麼辦？', '在登入頁面點選「忘記密碼？」，輸入您的電子郵件後，系統將寄送重設密碼郵件。若使用 Google 登入則不受此影響。'),
      _Section('如何刪除帳號？', '目前可於「設定 → 帳號安全 → 刪除帳號」執行刪除。刪除後所有個人資料將永久移除且無法復原，請謹慎操作。'),
      _Section('記帳功能如何分帳？', '在記帳頁面新增支出後，選擇付款人及參與分攤的旅伴，App 會自動計算每人應付金額，並在「總覽」顯示誰欠誰多少錢。'),
    ],
  );
}

// ══════════════════════════════════════════════
// 關於我們頁面
// ══════════════════════════════════════════════
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.pop(context)),
        title: const Text('關於我們', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Logo area
          StitchedBox(
            color: primary.withValues(alpha: 0.08),
            stitchColor: primary.withValues(alpha: 0.25),
            radius: 24, inset: 5, dashWidth: 5, dashGap: 4,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: Column(children: [
              Icon(Icons.account_balance_rounded, size: 64, color: primary),
              const SizedBox(height: 12),
              Text('探索諸羅',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                    color: primary, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text('Explore Chiayi',
                style: TextStyle(fontSize: 14, color: primary.withValues(alpha: 0.7),
                    letterSpacing: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
                child: Text('v1.0.0', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // App intro
          StitchedBox(
            color: Colors.white,
            stitchColor: primary.withValues(alpha: 0.18),
            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline_rounded, size: 18, color: primary),
                const SizedBox(width: 8),
                Text('關於本 App', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primary)),
              ]),
              const SizedBox(height: 12),
              const Text(
                '「探索諸羅」是一款專為嘉義旅遊設計的在地導覽 App，整合景點地圖、行程規劃、'
                '交通查詢、天氣預報、集章成就等多元功能，讓您的嘉義之旅更輕鬆、更豐富。\n\n'
                '無論您是第一次造訪的旅客，還是深度探索的嘉義人，我們都希望成為您最好的旅遊夥伴。',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.75),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // Data sources
          StitchedBox(
            color: Colors.white,
            stitchColor: primary.withValues(alpha: 0.18),
            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.source_rounded, size: 18, color: primary),
                const SizedBox(width: 8),
                Text('資料來源', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primary)),
              ]),
              const SizedBox(height: 12),
              ...[
                (Icons.account_balance_rounded, '嘉義市政府開放資料平台', '新聞、活動、公共設施'),
                (Icons.train_rounded,           '交通部 TDX API',        '景點、旅館、YouBike、公車'),
                (Icons.map_rounded,             'OpenStreetMap',          '地圖底圖'),
                (Icons.cloud_rounded,           'Google Firebase',        '帳號與資料儲存'),
              ].map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(e.$1, size: 18, color: primary),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(e.$3, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                  ])),
                ]),
              )),
            ]),
          ),
          const SizedBox(height: 14),

          // Contact
          StitchedBox(
            color: Colors.white,
            stitchColor: primary.withValues(alpha: 0.18),
            radius: 16, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.mail_outline_rounded, size: 18, color: primary),
                const SizedBox(width: 8),
                Text('聯絡資訊', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primary)),
              ]),
              const SizedBox(height: 12),
              const Text('如有任何問題或建議，歡迎與我們聯繫：',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.email_outlined, size: 14, color: primary),
                const SizedBox(width: 6),
                const Text('explore.chiayi@gmail.com',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
          const SizedBox(height: 32),
          Text('© 2026 探索諸羅. All rights reserved.',
            style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 簡單資訊類頁面 (Privacy, FAQ)
// ══════════════════════════════════════════════
class _InfoPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_Section> sections;
  const _InfoPage({required this.title, required this.icon, required this.sections});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.pop(context)),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final s = sections[i];
          return StitchedBox(
            color: Colors.white,
            stitchColor: primary.withValues(alpha: 0.18),
            radius: 14, inset: 4, dashWidth: 4, dashGap: 3,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                DoodleHeart(color: primary.withValues(alpha: 0.45), size: 8),
                const SizedBox(width: 8),
                Expanded(child: Text(s.title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: primary))),
              ]),
              const SizedBox(height: 8),
              Text(s.content,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.7)),
            ]),
          );
        },
      ),
    );
  }
}

class _Section {
  final String title, content;
  const _Section(this.title, this.content);
}
