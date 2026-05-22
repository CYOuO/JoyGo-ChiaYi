import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  DateTime _focusedMonth = DateTime(2025, 6);
  DateTime? _selectedDay = DateTime(2025, 6, 7);

  static final List<_Event> _events = [
    _Event(id:'e1', title:'嘉義燈會', date:DateTime(2025,6,1), endDate:DateTime(2025,6,15),
      emoji:'🏮', category:'節慶', location:'嘉義公園',
      desc:'年度嘉義燈會，以「光鑄諸羅」為主題，結合傳統與現代燈藝，每晚18:00-22:00精彩登場。',
      color:const Color(0xFFE8A87C)),
    _Event(id:'e2', title:'阿里山花季', date:DateTime(2025,6,5), endDate:DateTime(2025,6,20),
      emoji:'🌸', category:'自然', location:'阿里山景區',
      desc:'阿里山夏季花卉展，繡球花、百合花盛開，漫步花海感受自然之美。',
      color:const Color(0xFFD4A8C7)),
    _Event(id:'e3', title:'文化路美食節', date:DateTime(2025,6,7), endDate:DateTime(2025,6,7),
      emoji:'🍜', category:'美食', location:'文化路',
      desc:'一年一度美食節，百攤聚集，火雞肉飯、方塊酥、烤玉米通通吃到飽。',
      color:const Color(0xFFE8C87C)),
    _Event(id:'e4', title:'嘉義市馬拉松', date:DateTime(2025,6,8), endDate:DateTime(2025,6,8),
      emoji:'🏃', category:'運動', location:'嘉義市區',
      desc:'2025嘉義市馬拉松，路線穿越市區知名景點，歡迎市民與遊客共同參與。',
      color:const Color(0xFF8FBFA8)),
    _Event(id:'e5', title:'原住民文化祭', date:DateTime(2025,6,14), endDate:DateTime(2025,6,16),
      emoji:'🪘', category:'文化', location:'北門車站廣場',
      desc:'展示阿里山鄒族傳統文化，包含歌舞表演、手工藝、傳統美食體驗。',
      color:const Color(0xFFA8B8E8)),
    _Event(id:'e6', title:'嘉義音樂節', date:DateTime(2025,6,21), endDate:DateTime(2025,6,22),
      emoji:'🎵', category:'藝文', location:'嘉義市立音樂廳',
      desc:'邀請多組知名樂團演出，融合傳統與現代音樂，免費入場。',
      color:const Color(0xFFB8A8E8)),
    _Event(id:'e7', title:'竹崎親水公園夏日祭', date:DateTime(2025,6,28), endDate:DateTime(2025,6,29),
      emoji:'💧', category:'親子', location:'竹崎親水公園',
      desc:'夏日消暑特別企劃，水上活動、親子遊樂，適合全家大小同遊。',
      color:const Color(0xFF88C8D8)),
  ];

  List<_Event> _eventsForDay(DateTime day) =>
      _events.where((e) =>
        !e.date.isAfter(day) && !e.endDate.isBefore(day)).toList();

  List<_Event> _eventsForMonth(DateTime month) =>
      _events.where((e) =>
        (e.date.year == month.year && e.date.month == month.month) ||
        (e.endDate.year == month.year && e.endDate.month == month.month)).toList();

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDay;
    final dayEvents = selected != null ? _eventsForDay(selected) : <_Event>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('活動行事曆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_rounded),
            onPressed: () => setState(() {
              _focusedMonth = DateTime.now();
              _selectedDay = DateTime.now();
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Month navigator ──
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                _buildMonthHeader(),
                const SizedBox(height: 12),
                _buildWeekdayLabels(),
                const SizedBox(height: 6),
                _buildCalendarGrid(),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Event list for selected day ──
          Expanded(
            child: selected == null
                ? _buildAllEvents()
                : dayEvents.isEmpty
                    ? _buildEmptyDay(selected)
                    : _buildDayEventList(dayEvents, selected),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    final months = ['1月','2月','3月','4月','5月','6月',
                    '7月','8月','9月','10月','11月','12月'];
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          onPressed: () => setState(() =>
            _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
        ),
        Expanded(
          child: Text(
            '${_focusedMonth.year} 年 ${months[_focusedMonth.month - 1]}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          onPressed: () => setState(() =>
            _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
        ),
      ],
    );
  }

  Widget _buildWeekdayLabels() {
    const labels = ['日','一','二','三','四','五','六'];
    return Row(
      children: labels.map((l) => Expanded(
        child: Text(l,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: (l == '日' || l == '六') ? AppColors.error : AppColors.textHint,
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startOffset = firstDay.weekday % 7; // Sun=0
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        return Row(
          children: List.generate(7, (col) {
            final cellIndex = row * 7 + col;
            final dayNum = cellIndex - startOffset + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const Expanded(child: SizedBox(height: 42));
            }
            final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
            final hasEvents = _eventsForDay(date).isNotEmpty;
            final isSelected = _selectedDay != null &&
              _selectedDay!.year == date.year &&
              _selectedDay!.month == date.month &&
              _selectedDay!.day == date.day;
            final isToday = date.year == DateTime.now().year &&
              date.month == DateTime.now().month &&
              date.day == DateTime.now().day;
            final isWeekend = col == 0 || col == 6;
            final eventsToday = _eventsForDay(date);

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDay = date),
                child: Container(
                  height: 42,
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : isToday
                            ? AppColors.primaryMist
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !isSelected
                        ? Border.all(color: AppColors.primary, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : isWeekend
                                  ? AppColors.error.withOpacity(0.7)
                                  : AppColors.textPrimary,
                        ),
                      ),
                      if (hasEvents) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: eventsToday.take(3).map((e) =>
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white70 : e.color,
                                shape: BoxShape.circle,
                              ),
                            )
                          ).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _buildDayEventList(List<_Event> events, DateTime day) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${day.month}/${day.day} 共 ${events.length} 個活動',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        ...events.map((e) => _eventCard(e)),
      ],
    );
  }

  Widget _buildAllEvents() {
    final monthEvents = _eventsForMonth(_focusedMonth);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            '本月所有活動',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        ...monthEvents.map((e) => _eventCard(e)),
      ],
    );
  }

  Widget _buildEmptyDay(DateTime day) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌿', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text(
            '${day.month}/${day.day} 沒有活動',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text('點選其他日期查看活動',
              style: TextStyle(color: AppColors.textHint, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _eventCard(_Event e) {
    final isMultiDay = e.endDate.day != e.date.day || e.endDate.month != e.date.month;
    return GestureDetector(
      onTap: () => _showEventDetail(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            // Color stripe
            Container(
              width: 6,
              height: 100,
              decoration: BoxDecoration(
                color: e.color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
              ),
            ),
            const SizedBox(width: 14),
            // Date block
            Container(
              width: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${e.date.day}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: e.color,
                    ),
                  ),
                  Text(
                    _monthLabel(e.date.month),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isMultiDay) ...[
                    const Text('～', style: TextStyle(color: AppColors.textHint, fontSize: 10)),
                    Text(
                      '${e.endDate.day}日',
                      style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _catChip(e.category, e.color),
                        const Spacer(),
                        Text(e.emoji, style: const TextStyle(fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 12, color: AppColors.textHint),
                        const SizedBox(width: 3),
                        Text(
                          e.location,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textHint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded,
                  color: AppColors.textHint, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catChip(String cat, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        cat,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color.withOpacity(0.9),
        ),
      ),
    );
  }

  String _monthLabel(int m) {
    const labels = ['','1月','2月','3月','4月','5月','6月',
                    '7月','8月','9月','10月','11月','12月'];
    return labels[m];
  }

  void _showEventDetail(_Event e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: e.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(child: Text(e.emoji, style: const TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _catChip(e.category, e.color),
                        const SizedBox(height: 4),
                        Text(e.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Info rows
              _detailRow(Icons.calendar_today_rounded,
                e.date.day == e.endDate.day && e.date.month == e.endDate.month
                    ? '${e.date.year}/${e.date.month}/${e.date.day}'
                    : '${e.date.year}/${e.date.month}/${e.date.day} ～ ${e.endDate.month}/${e.endDate.day}'),
              const SizedBox(height: 10),
              _detailRow(Icons.location_on_rounded, e.location),
              const SizedBox(height: 20),
              const Text('活動介紹',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Text(e.desc,
                style: const TextStyle(
                  fontSize: 15, color: AppColors.textPrimary, height: 1.8)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('加入行程'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.share_outlined, color: AppColors.textSecondary),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Event {
  final String id, title, emoji, category, location, desc;
  final DateTime date, endDate;
  final Color color;

  const _Event({
    required this.id, required this.title, required this.date,
    required this.endDate, required this.emoji, required this.category,
    required this.location, required this.desc, required this.color,
  });
}
