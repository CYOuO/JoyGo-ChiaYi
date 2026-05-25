import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;

  List<_Event> _events = [];
  bool _loading = true;
  bool _error   = false;

  static const _kEventsUrl =
      'https://data.chiayi.gov.tw/opendata/api/getResource'
      '?oid=33c3225e-f786-4eaf-8b9c-774cc39c72e0'
      '&rid=a809167f-bba6-475d-9dfe-33b4ea7749f6';

  static const _kColors = [
    Color(0xFFE8A87C), Color(0xFFD4A8C7), Color(0xFFE8C87C),
    Color(0xFF8FBFA8), Color(0xFFA8B8E8), Color(0xFFB8A8E8), Color(0xFF88C8D8),
  ];

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  // ── Fetch real government events (活動 only, no news) ──────────────
  Future<void> _fetchEvents() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      final res = await http
          .get(Uri.parse(_kEventsUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final data = jsonDecode(res.body);
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['result'] is List) {
        list = data['result'] as List;
      } else if (data is Map &&
          data['result'] is Map &&
          (data['result'] as Map)['records'] is List) {
        list = (data['result'] as Map)['records'] as List;
      } else if (data is Map && data['records'] is List) {
        list = data['records'] as List;
      } else {
        list = [];
      }

      int colorIdx = 0;
      final parsed = <_Event>[];
      for (final item in list.whereType<Map>()) {
        final raw = Map<String, dynamic>.from(item);
        final title = _pick(raw, ['活動名稱', '標題', '名稱', 'title', 'Title']) ?? '無標題';
        final startStr = _pick(raw, ['活動開始日期', '開始日期', '發布日期', 'date', 'Date']) ?? '';
        final endStr   = _pick(raw, ['活動結束日期', '結束日期']) ?? startStr;
        final loc      = _pick(raw, ['活動地點', '地點', 'location', 'venue']) ?? '嘉義市';
        final desc     = _pick(raw, ['活動說明', '內容', '摘要', '描述', 'summary', 'content']) ?? '';
        final url      = _pick(raw, ['連結', 'url', 'URL', 'link', '詳細連結']);

        final startDate = _parseDate(startStr);
        if (startDate == null) continue;
        final endDate = _parseDate(endStr) ?? startDate;

        parsed.add(_Event(
          id:       '${parsed.length}',
          title:    title,
          date:     startDate,
          endDate:  endDate,
          emoji:    '🏮',
          category: '政府活動',
          location: loc,
          desc:     desc.isNotEmpty ? desc : '詳細內容請至嘉義市政府官網查看。',
          color:    _kColors[colorIdx % _kColors.length],
          url:      url,
        ));
        colorIdx++;
      }
      parsed.sort((a, b) => a.date.compareTo(b.date));

      if (mounted) setState(() { _events = parsed; _loading = false; });
    } catch (e) {
      debugPrint('EventsScreen fetch error: $e');
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  static String? _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  static DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    // AD year: 2025/5/1 or 2025-05-01
    final ad = RegExp(r'(\d{4})[/\-年](\d{1,2})[/\-月](\d{1,2})').firstMatch(s);
    if (ad != null) {
      return DateTime.tryParse(
          '${ad.group(1)}-${ad.group(2)!.padLeft(2, '0')}-${ad.group(3)!.padLeft(2, '0')}');
    }
    // ROC year: 114/5/1 → 2025/5/1
    final roc = RegExp(r'^(\d{2,3})[/\-](\d{1,2})[/\-](\d{1,2})').firstMatch(s);
    if (roc != null) {
      final year = int.parse(roc.group(1)!) + 1911;
      return DateTime.tryParse(
          '$year-${roc.group(2)!.padLeft(2, '0')}-${roc.group(3)!.padLeft(2, '0')}');
    }
    return DateTime.tryParse(s);
  }

  List<_Event> _eventsForDay(DateTime day) =>
      _events.where((e) => !e.date.isAfter(day) && !e.endDate.isBefore(day)).toList();

  List<_Event> _eventsForMonth(DateTime month) =>
      _events.where((e) =>
        (e.date.year == month.year && e.date.month == month.month) ||
        (e.endDate.year == month.year && e.endDate.month == month.month)).toList();

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final selected  = _selectedDay;
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
              _selectedDay  = DateTime.now();
            }),
          ),
          if (_error)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchEvents,
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
          // ── Event list for selected day / loading / error ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error
                    ? _buildErrorState()
                    : selected == null
                        ? _buildAllEvents()
                        : dayEvents.isEmpty
                            ? _buildEmptyDay(selected)
                            : _buildDayEventList(dayEvents, selected),
          ),
        ],
      ),
    );
  }

  // ── Error ──
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('😕', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          const Text('無法載入活動資料',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _fetchEvents,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重試'),
          ),
        ],
      ),
    );
  }

  // ── Month header ──
  Widget _buildMonthHeader() {
    const months = ['1月','2月','3月','4月','5月','6月',
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

  // ── Weekday labels ──
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

  // ── Calendar grid ──
  Widget _buildCalendarGrid() {
    final firstDay    = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startOffset = firstDay.weekday % 7; // Sun = 0
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final totalCells  = startOffset + daysInMonth;
    final rows        = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        return Row(
          children: List.generate(7, (col) {
            final cellIndex = row * 7 + col;
            final dayNum    = cellIndex - startOffset + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const Expanded(child: SizedBox(height: 42));
            }
            final date       = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
            final eventsToday = _eventsForDay(date);
            final hasEvents  = eventsToday.isNotEmpty;
            final isSelected = _selectedDay != null &&
              _selectedDay!.year  == date.year &&
              _selectedDay!.month == date.month &&
              _selectedDay!.day   == date.day;
            final isToday   = date.year  == DateTime.now().year &&
              date.month == DateTime.now().month &&
              date.day   == DateTime.now().day;
            final isWeekend = col == 0 || col == 6;

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDay = date),
                child: Container(
                  height: 42,
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : isToday
                            ? Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.88)!
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !isSelected
                        ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
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
                              width: 5, height: 5,
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

  // ── Day event list ──
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

  // ── All events for current month ──
  Widget _buildAllEvents() {
    final monthEvents = _eventsForMonth(_focusedMonth);
    if (monthEvents.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🗓️', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            const Text('本月尚無活動',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('可切換月份查看其他活動',
                style: TextStyle(color: AppColors.textHint, fontSize: 13)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '本月共 ${monthEvents.length} 個活動',
            style: const TextStyle(
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

  // ── Empty day ──
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

  // ── Event card ──
  Widget _eventCard(_Event e) {
    final isMultiDay = e.endDate.day   != e.date.day ||
                       e.endDate.month != e.date.month;
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
              width: 6, height: 100,
              decoration: BoxDecoration(
                color: e.color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
              ),
            ),
            const SizedBox(width: 14),
            // Date block
            SizedBox(
              width: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${e.date.day}',
                    style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900, color: e.color),
                  ),
                  Text(
                    _monthLabel(e.date.month),
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w600),
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
                        fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 12, color: AppColors.textHint),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            e.location,
                            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 18),
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
      child: Text(cat,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color.withOpacity(0.9))),
    );
  }

  String _monthLabel(int m) {
    const labels = ['','1月','2月','3月','4月','5月','6月',
                    '7月','8月','9月','10月','11月','12月'];
    return labels[m];
  }

  // ── Event detail sheet ──
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
                    color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
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
                            fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Date
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
                style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.8)),
              const SizedBox(height: 24),
              // Action buttons
              if (e.url != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(e.url!);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('閱讀完整內容'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _Event {
  final String id, title, emoji, category, location, desc;
  final DateTime date, endDate;
  final Color color;
  final String? url;

  const _Event({
    required this.id, required this.title, required this.date,
    required this.endDate, required this.emoji, required this.category,
    required this.location, required this.desc, required this.color,
    this.url,
  });
}
