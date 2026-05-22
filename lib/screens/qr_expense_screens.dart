import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ===== QR SHARE SCREEN =====
class QrShareScreen extends StatelessWidget {
  final String tripTitle;

  const QrShareScreen({super.key, this.tripTitle = '嘉義週末輕旅行'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('QR Code 分享',
            style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // QR Card
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cardShadow,
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Top branding
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🏯', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      const Text(
                        '探索諸羅',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Simulated QR code
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.surfaceMoss, width: 2),
                    ),
                    child: CustomPaint(
                      painter: _QrPainter(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    tripTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '掃描即可查看並套用此行程',
                    style: TextStyle(
                      color: AppColors.textHint,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Share link
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMoss,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.link_rounded,
                            size: 16, color: AppColors.textHint),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'explore-chiayi.app/trip/abc123',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const Icon(Icons.copy_rounded,
                            size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Co-edit info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('✏️', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text(
                        '共同編輯功能',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '掃描 QR Code 的好友可以：\n• 查看完整行程安排\n• 提出修改建議\n• 即時同步更新',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Collaborators
                  Row(
                    children: [
                      const Text(
                        '目前協作者：',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...['😊', '😄', '😎'].map((emoji) {
                        return Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withOpacity(0.3),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.primary, width: 1.5),
                          ),
                          child: Center(child: Text(emoji)),
                        );
                      }),
                      GestureDetector(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMoss,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.textHint, width: 1.5),
                          ),
                          child: const Center(
                            child: Icon(Icons.add_rounded,
                                size: 16, color: AppColors.textHint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('儲存 QR Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 50),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.share_rounded,
                        size: 18, color: AppColors.primary),
                    label: const Text('分享',
                        style: TextStyle(color: AppColors.primary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Simulated QR code painter
class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.fill;

    final cellSize = size.width / 21;

    // Simplified QR pattern
    final pattern = [
      [1,1,1,1,1,1,1,0,1,0,0,1,0,1,1,1,1,1,1,1,0],
      [1,0,0,0,0,0,1,0,0,1,0,0,1,0,1,0,0,0,0,0,1],
      [1,0,1,1,1,0,1,0,1,0,1,0,0,0,1,0,1,1,1,0,1],
      [1,0,1,1,1,0,1,0,0,1,1,1,0,0,1,0,1,1,1,0,1],
      [1,0,1,1,1,0,1,0,1,0,1,0,1,0,1,0,1,1,1,0,1],
      [1,0,0,0,0,0,1,0,0,1,0,1,0,0,1,0,0,0,0,0,1],
      [1,1,1,1,1,1,1,0,1,0,1,0,1,0,1,1,1,1,1,1,1],
      [0,0,0,0,0,0,0,0,0,1,0,1,1,0,0,0,0,0,0,0,0],
      [1,1,0,1,1,0,1,0,1,1,0,0,1,1,1,0,1,1,0,1,1],
      [0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,1,0,0,1,0,0],
      [1,0,1,1,0,1,1,0,1,0,1,1,0,0,1,0,1,1,0,1,0],
      [0,1,0,0,1,0,0,0,1,0,0,1,1,0,0,0,1,0,0,1,0],
      [1,0,1,0,0,1,1,1,0,1,0,0,1,0,1,1,0,1,0,0,1],
      [0,0,0,0,0,0,0,0,1,1,0,1,0,0,0,1,0,0,1,0,0],
      [1,1,1,1,1,1,1,0,0,0,1,0,0,0,1,0,1,0,1,0,1],
      [1,0,0,0,0,0,1,0,1,0,0,1,0,1,0,1,0,0,0,1,0],
      [1,0,1,1,1,0,1,1,0,1,1,0,1,0,1,0,1,0,1,0,1],
      [1,0,1,1,1,0,1,0,1,0,0,0,0,1,0,1,0,1,0,1,0],
      [1,0,1,1,1,0,1,0,0,1,0,1,1,0,1,0,0,0,1,0,1],
      [1,0,0,0,0,0,1,0,1,0,1,0,0,1,0,1,0,1,0,0,0],
      [1,1,1,1,1,1,1,0,0,1,1,0,1,0,1,0,1,0,1,0,1],
    ];

    for (int row = 0; row < pattern.length; row++) {
      for (int col = 0; col < pattern[row].length; col++) {
        if (pattern[row][col] == 1) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                col * cellSize + 2,
                row * cellSize + 2,
                cellSize - 1,
                cellSize - 1,
              ),
              const Radius.circular(1),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===== EXPENSE SPLIT SCREEN =====
class ExpenseSplitScreen extends StatefulWidget {
  const ExpenseSplitScreen({super.key});

  @override
  State<ExpenseSplitScreen> createState() => _ExpenseSplitScreenState();
}

class _ExpenseSplitScreenState extends State<ExpenseSplitScreen> {
  final List<_Expense> _expenses = [
    _Expense('🍜', '林聰明沙鍋魚頭', 350, '小明'),
    _Expense('🚌', '阿里山來回交通', 600, '小美'),
    _Expense('🎫', '阿里山門票', 800, '大家各付'),
    _Expense('🏨', '民宿住宿', 2400, '小強'),
    _Expense('🍧', '御品元冰品', 180, '小美'),
  ];

  final List<String> _members = ['小明', '小美', '小強', '我'];

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<int>(0, (sum, e) => sum + e.amount);
    final perPerson = (total / _members.length).ceil();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('旅遊記帳', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
            onPressed: () => _showAddExpense(context),
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            label: const Text('新增', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryItem('總花費', 'NT\$$total', Colors.white),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _summaryItem('人數', '${_members.length}人', Colors.white),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _summaryItem('每人', 'NT\$$perPerson', AppColors.accentStraw),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showSplitResult(context, perPerson),
                  icon: const Icon(Icons.calculate_rounded,
                      size: 16, color: AppColors.primary),
                  label: const Text('計算分帳',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          // Expense list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const Text(
                  '消費明細',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ..._expenses.map((e) => _buildExpenseItem(e)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseItem(_Expense expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(expense.icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${expense.paidBy} 付款',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'NT\$${expense.amount}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            child: const Icon(Icons.delete_outline_rounded,
                color: AppColors.textHint, size: 18),
          ),
        ],
      ),
    );
  }

  void _showAddExpense(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '新增消費',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(
                  labelText: '消費項目',
                  hintText: '例如：午餐',
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '金額（元）',
                  prefixText: 'NT\$ ',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: '付款人',
                  filled: true,
                  fillColor: AppColors.surfaceMoss,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: _members.map((m) {
                  return DropdownMenuItem(value: m, child: Text(m));
                }).toList(),
                onChanged: (_) {},
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('新增'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSplitResult(BuildContext context, int perPerson) {
    final settlements = [
      {'from': '小明', 'to': '小強', 'amount': 400},
      {'from': '我', 'to': '小強', 'amount': 200},
      {'from': '小美', 'to': '我', 'amount': 0},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('💸', style: TextStyle(fontSize: 24)),
                SizedBox(width: 10),
                Text(
                  '分帳結算',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '每人應付 NT\$$perPerson',
              style: const TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
            const SizedBox(height: 20),
            // Member balances
            ..._members.map((m) {
              final idx = _members.indexOf(m);
              final colors = [
                AppColors.error,
                AppColors.primary,
                AppColors.error,
                AppColors.primary
              ];
              final labels = ['-NT\$400', '+NT\$200', '-NT\$200', '+NT\$400'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(child: Text('😊')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(m,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                    Text(
                      labels[idx],
                      style: TextStyle(
                        color: colors[idx],
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 24),
            const Text(
              '需要轉帳：',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...settlements.where((s) => (s['amount'] as int) > 0).map((s) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMoss,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text('${s['from']} → ${s['to']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    Text(
                      'NT\$${s['amount']}',
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Expense {
  final String icon, name, paidBy;
  final int amount;

  _Expense(this.icon, this.name, this.amount, this.paidBy);
}
