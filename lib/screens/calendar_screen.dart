import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';
import '../theme/fabric_textures.dart';

// ═══════════════════════════════════════════════════════════
//  Event model  (only 政府活動 + 個人行程; no govNews / no personal)
// ═══════════════════════════════════════════════════════════

enum CalEventType {
  govEvent,  // 政府活動 — macaron coral-pink
  userTrip,  // 個人行程 — theme primary
}

// Macaron palette for event-type dots / chips
const _kEventColors = <CalEventType, Color>{
  CalEventType.govEvent: Color(0xFFFF8FAB), // soft coral-pink macaron
  // userTrip uses theme primary (passed at runtime)
};

class CalEvent {
  final String      id;
  final String      title;
  final DateTime    date;
  final DateTime?   endDate;
  final CalEventType type;
  final String?     location;
  final String?     note;
  final String?     url;

  const CalEvent({
    required this.id, required this.title, required this.date,
    this.endDate, required this.type,
    this.location, this.note, this.url,
  });
}

// ═══════════════════════════════════════════════════════════
//  API – fetch 政府活動 only (no news)
// ═══════════════════════════════════════════════════════════

class _CalApiService {
  static const _eventsUrl =
      'https://data.chiayi.gov.tw/opendata/api/getResource'
      '?oid=33c3225e-f786-4eaf-8b9c-774cc39c72e0'
      '&rid=a809167f-bba6-475d-9dfe-33b4ea7749f6';

  static Future<List<CalEvent>> fetchAll() async {
    try {
      return await _fetch(_eventsUrl)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return [];
    }
  }

  static Future<List<CalEvent>> _fetch(String url) async {
    try {
      final res = await http.get(Uri.parse(url),
          headers: {'Accept': 'application/json'});
      debugPrint('[CalApi] status=${res.statusCode} body=${res.body.length}B');
      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      List<dynamic> list = [];
      if (data is List) {
        list = data;
      } else if (data is Map) {
        final r = data['result'];
        if (r is List) {
          list = r;
        } else if (r is Map && r['records'] is List) {
          list = r['records'] as List;
        } else if (data['records'] is List) {
          list = data['records'] as List;
        }
      }

      debugPrint('[CalApi] parsed ${list.length} records');
      if (list.isNotEmpty && list.first is Map) {
        debugPrint('[CalApi] keys: ${(list.first as Map).keys.join(', ')}');
      }

      return list.whereType<Map>().map((m) {
        final raw     = Map<String, dynamic>.from(m);
        final title   = _p(raw, ['活動名稱','標題','名稱','name','Name','title','Title','Subject']) ?? '無標題';
        final dateStr = _p(raw, ['活動開始日期','發布日期','日期','date','Date','建立時間','PublishDate','StartDate']) ?? '';
        final date    = _parseDate(dateStr) ?? DateTime.now();
        final endStr  = _p(raw, ['活動結束日期','ActiveEnd','EndDate','endDate','結束日期','活動截止日期']);
        final endDate = endStr != null ? _parseDate(endStr) : null;
        final loc     = _p(raw, ['活動地點','地點','Location','location','venue']);
        final url2    = _p(raw, ['連結','url','URL','link','詳細連結','WebUrl']);
        return CalEvent(
          id: 'gov_${title.hashCode}_${date.millisecondsSinceEpoch}',
          title: title, date: date, endDate: endDate,
          type: CalEventType.govEvent,
          location: loc, url: url2,
        );
      }).toList();
    } catch (e) {
      debugPrint('[CalApi] error: $e');
      return [];
    }
  }

  static String? _p(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  static DateTime? _parseDate(String s) {
    try { return DateTime.parse(s); } catch (_) {}
    final match = RegExp(r'(\d{3,4})[\-/年](\d{1,2})[\-/月](\d{1,2})').firstMatch(s);
    if (match != null) {
      int yr = int.parse(match.group(1)!);
      if (yr < 1900) yr += 1911;
      return DateTime(yr, int.parse(match.group(2)!), int.parse(match.group(3)!));
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════
//  CalendarScreen
// ═══════════════════════════════════════════════════════════

class CalendarScreen extends StatefulWidget {
  /// Pass user trips from TripScreen so they appear on the calendar.
  final List<({String title, DateTime date, DateTime? endDate})> userTrips;
  const CalendarScreen({super.key, this.userTrips = const []});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime       _focused    = DateTime.now();
  DateTime?      _selected;
  List<CalEvent> _apiEvents  = [];
  bool           _apiLoading = true;

  // Filter toggles (only 2 categories now)
  bool _showGovEvent = true;
  bool _showTrip     = true;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _fetchApi();
  }

  Future<void> _fetchApi() async {
    setState(() => _apiLoading = true);
    final events = await _CalApiService.fetchAll();
    if (mounted) setState(() { _apiEvents = events; _apiLoading = false; });
  }

  // ── Event aggregation ─────────────────────────────────────
  List<CalEvent> get _allEvents {
    final list = <CalEvent>[];
    if (_showGovEvent) {
      list.addAll(_apiEvents.where((e) => e.type == CalEventType.govEvent));
    }
    if (_showTrip) {
      list.addAll(widget.userTrips.map((t) => CalEvent(
        id: 'trip_${t.title.hashCode}',
        title: t.title,
        date: t.date,
        endDate: t.endDate,
        type: CalEventType.userTrip,
      )));
    }
    return list;
  }

  List<CalEvent> _eventsForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _allEvents.where((e) {
      final eStart = DateTime(e.date.year, e.date.month, e.date.day);
      final eEnd   = e.endDate != null
          ? DateTime(e.endDate!.year, e.endDate!.month, e.endDate!.day)
          : eStart;
      return !d.isBefore(eStart) && !d.isAfter(eEnd);
    }).toList();
  }

  void _prevMonth() => setState(() => _focused = DateTime(_focused.year, _focused.month - 1));
  void _nextMonth() => setState(() => _focused = DateTime(_focused.year, _focused.month + 1));

  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final primary        = context.appPrimary;
    final l10n           = context.watch<AppSettingsProvider>().l10n;
    final selectedEvents = _selected != null ? _eventsForDay(_selected!) : <CalEvent>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildMonthHeader(primary, l10n),
          _buildWeekdayRow(l10n),
          Expanded(flex: 9, child: _buildDayGrid(primary)),  // 更多空間給日曆
          JournalDivider(color: primary, label: '活動'),
          _buildFilterRow(primary, l10n),
          Expanded(flex: 4, child: _buildEventList(selectedEvents, primary, l10n)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'cal_add',
        backgroundColor: primary,
        foregroundColor: Colors.white,
        mini: true,
        onPressed: () => _showAddEventSheet(context, primary, l10n),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  // ── 新增事件 sheet（支援日期區間）─────────────────────────────
  void _showAddEventSheet(BuildContext context, Color primary, AppL10n l10n) {
    final titleCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          DateTimeRange? range = _selected != null
              ? DateTimeRange(start: _selected!, end: _selected!)
              : null;

          String _fmtDate(DateTime d) =>
              '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
              Text('新增行事曆事件', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primary)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '事件名稱',
                  hintText: '例如：阿里山日出、文化路夜市'),
              ),
              const SizedBox(height: 14),
              // ── 日期區間選擇器 ────────────────────────────────
              GestureDetector(
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                    initialDateRange: range,
                    helpText: '選擇事件日期區間',
                    cancelText: '取消',
                    confirmText: '確定',
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: primary),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setLocal(() => range = picked);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: range != null ? 0.08 : 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primary.withValues(alpha: range != null ? 0.4 : 0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range_rounded, size: 18, color: primary),
                    const SizedBox(width: 10),
                    Expanded(child: range == null
                        ? Text('點選選擇日期（可選區間）',
                            style: TextStyle(color: primary.withValues(alpha: 0.7), fontSize: 14))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('開始：${_fmtDate(range.start)}',
                              style: TextStyle(fontWeight: FontWeight.w700, color: primary, fontSize: 13)),
                            if (range.start != range.end)
                              Text('結束：${_fmtDate(range.end)}',
                                style: TextStyle(color: primary.withValues(alpha: 0.8), fontSize: 12)),
                          ]),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: primary),
                  ]),
                ),
              ),
              if (range != null) Builder(builder: (_) {
                final r = range!;
                if (r.start == r.end) return const SizedBox.shrink();
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '共 ${r.duration.inDays + 1} 天',
                      style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]);
              }),
              // 如果有行程，顯示「套用行程日期」選項
              if (widget.userTrips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('或套用行程日期:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.userTrips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final t = widget.userTrips[i];
                      return GestureDetector(
                        onTap: () {
                          final end = t.endDate ?? t.date;
                          setLocal(() => range = DateTimeRange(start: t.date, end: end));
                          if (titleCtrl.text.isEmpty) titleCtrl.text = t.title;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: primary.withValues(alpha: 0.25)),
                          ),
                          child: Text(t.title,
                            style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (titleCtrl.text.trim().isEmpty) return;
                    final startDate = range?.start ?? _selected ?? DateTime.now();
                    final endDate = (range != null && range!.start != range!.end) ? range!.end : null;
                    final newEvent = CalEvent(
                      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      title: titleCtrl.text.trim(),
                      date: startDate,
                      endDate: endDate,
                      type: CalEventType.userTrip,
                    );
                    setState(() {
                      _apiEvents.add(newEvent);
                      _selected = startDate;
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('已新增「${titleCtrl.text.trim()}」到行事曆'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  child: const Text('新增到行事曆'),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  // ── Month header（可愛版）────────────────────────────────────
  Widget _buildMonthHeader(Color primary, AppL10n l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(children: [
        // 上月按鈕
        GestureDetector(
          onTap: _prevMonth,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chevron_left_rounded, color: primary, size: 20),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                DoodleHeart(color: primary.withValues(alpha: 0.35), size: 8),
                const SizedBox(width: 4),
                Text('${_focused.year}年',
                  style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                DoodleHeart(color: primary.withValues(alpha: 0.35), size: 8),
              ]),
              HandDrawnUnderline(
                color: primary.withValues(alpha: 0.25),
                child: Text(l10n.monthName(_focused.month),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary)),
              ),
            ]),
          ),
        ),
        if (_apiLoading)
          SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: primary))
        else
          GestureDetector(
            onTap: _fetchApi,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(Icons.refresh_rounded, color: primary, size: 18),
            ),
          ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _nextMonth,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(Icons.chevron_right_rounded, color: primary, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── Weekday row（頂端圓角，匹配格子）────────────────────────
  Widget _buildWeekdayRow(AppL10n l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4, offset: const Offset(0, 1))],
      ),
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        children: l10n.weekdayShort.asMap().entries.map((e) {
          final isSun = e.key == 0;
          final isSat = e.key == 6;
          return Expanded(child: Center(
            child: Text(e.value,
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: isSun || isSat ? Colors.red.shade300 : AppColors.textHint,
                )),
          ));
        }).toList(),
      ),
    );
  }

  // ── Day grid (Apple-style: Sun first, range with rounded ends) ──────────
  Widget _buildDayGrid(Color primary) {
    final firstDay    = DateTime(_focused.year, _focused.month, 1);
    final lastDay     = DateTime(_focused.year, _focused.month + 1, 0);
    final startOffset = firstDay.weekday % 7; // Sun=0
    final today       = DateTime.now();

    // Compute trip ranges (blue bar)
    final tripRanges = widget.userTrips.map((t) =>
      (start: DateTime(t.date.year, t.date.month, t.date.day),
       end: t.endDate != null
           ? DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day)
           : DateTime(t.date.year, t.date.month, t.date.day))
    ).toList();

    // Compute gov event ranges (coral bar — multi-day events)
    final govRanges = _apiEvents
        .where((e) => e.endDate != null &&
            !DateTime(e.date.year, e.date.month, e.date.day)
                .isAtSameMomentAs(DateTime(e.endDate!.year, e.endDate!.month, e.endDate!.day)))
        .map((e) => (
          start: DateTime(e.date.year, e.date.month, e.date.day),
          end:   DateTime(e.endDate!.year, e.endDate!.month, e.endDate!.day),
        ))
        .toList();

    _RangeEdge _rangeEdge(DateTime d) {
      for (final r in tripRanges) {
        if (r.start == r.end && d == r.start) return _RangeEdge.none;
        if (d == r.start && !d.isAfter(r.end)) return _RangeEdge.start;
        if (d == r.end   && !d.isBefore(r.start)) return _RangeEdge.end;
        if (!d.isBefore(r.start) && !d.isAfter(r.end)) return _RangeEdge.middle;
      }
      return _RangeEdge.none;
    }

    // 政府活動是否在此日的某個範圍內
    bool _hasGovRange(DateTime d) =>
        govRanges.any((r) => !d.isBefore(r.start) && !d.isAfter(r.end));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7, childAspectRatio: 1.0,
        ),
        itemCount: 42,
        itemBuilder: (ctx, i) {
          final dayNum = i - startOffset + 1;
          if (dayNum < 1 || dayNum > lastDay.day) {
            final label = dayNum < 1
                ? DateTime(_focused.year, _focused.month, 1).subtract(Duration(days: startOffset - i)).day
                : dayNum - lastDay.day;
            return Center(child: Text('$label',
              style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCCC))));
          }
          final date   = DateTime(_focused.year, _focused.month, dayNum);
          final isToday= date.year == today.year && date.month == today.month && date.day == today.day;
          final isSel  = _selected != null &&
              date.year == _selected!.year && date.month == _selected!.month && date.day == _selected!.day;
          final events = _eventsForDay(date);
          final isSunSat = i % 7 == 0 || i % 7 == 6;
          final edge   = _rangeEdge(date);

          return GestureDetector(
            onTap: () => setState(() => _selected = date),
            child: _DayCell(
              dayNum: dayNum, isToday: isToday,
              isSelected: isSel, events: events,
              isSunSat: isSunSat, rangeEdge: edge,
              hasGovRange: _hasGovRange(date),
              primary: primary,
            ),
          );
        },
      ),
    );
  }

  // ── Filter row (只剩 2 個 macaron 標籤) ───────────────────
  Widget _buildFilterRow(Color primary, AppL10n l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Row(children: [
        _filterChip(
          l10n.calGovEvent,
          const Color(0xFFFF8FAB), // coral-pink macaron
          _showGovEvent,
          (v) => setState(() => _showGovEvent = v),
        ),
        const SizedBox(width: 8),
        _filterChip(
          l10n.calUserTrip,
          primary, // theme-aware mint/green
          _showTrip,
          (v) => setState(() => _showTrip = v),
        ),
      ]),
    );
  }

  Widget _filterChip(String label, Color color, bool on, ValueChanged<bool> onChange) {
    return GestureDetector(
      onTap: () => onChange(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? color.withValues(alpha: 0.7) : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: on ? color : Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: on ? color : AppColors.textHint,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Event list for selected day ───────────────────────────
  Widget _buildEventList(List<CalEvent> events, Color primary, AppL10n l10n) {
    if (_selected == null) {
      return Center(child: Text(l10n.calNoEvent,
          style: const TextStyle(color: AppColors.textHint)));
    }
    final dateLabel =
        '${_selected!.month}/${_selected!.day}（${l10n.weekdayShort[_selected!.weekday % 7]}）';

    return NotebookBackground(
      lineColor: primary.withValues(alpha: 0.08),
      child: events.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              DoodleHeart(color: primary.withValues(alpha: 0.20), size: 26),
              const SizedBox(height: 8),
              Text(l10n.calNoEvent,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) =>
                  _EventTile(event: events[i], primary: primary, l10n: l10n),
            ),
    );
  }
}

enum _RangeEdge { none, start, middle, end }

// ─── Day cell（Apple-style range highlight）──────────────────
class _DayCell extends StatelessWidget {
  final int dayNum;
  final bool isToday, isSelected, isSunSat;
  final _RangeEdge rangeEdge;
  final bool hasGovRange;
  final List<CalEvent> events;
  final Color primary;
  const _DayCell({
    required this.dayNum, required this.isToday,
    required this.isSelected, required this.isSunSat,
    this.rangeEdge = _RangeEdge.none,
    this.hasGovRange = false,
    required this.events, required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final hasDot = events.isNotEmpty;
    final inRange = rangeEdge != _RangeEdge.none && !isSelected;

    return Center(
      child: SizedBox(
        width: 38, height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34, height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? primary
                    : isToday
                        ? primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                border: isToday && !isSelected
                    ? Border.all(color: primary.withValues(alpha: 0.5), width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$dayNum',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : isSunSat
                              ? Colors.red.shade400
                              : AppColors.textPrimary,
                    ),
                  ),
                  if (hasDot)
                    Container(
                      width: 5, height: 5, margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.9)
                            : (events.first.type == CalEventType.userTrip ? primary : const Color(0xFFFF8FAB)),
                      ),
                    ),
                ],
              ),
            ),
            // 行程範圍藍色底線
            if (inRange)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 16, height: 3,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            // 政府活動範圍珊瑚色底線
            if (hasGovRange && !inRange)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 14, height: 2.5,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8FAB).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Event tile ────────────────────────────────────────────
class _EventTile extends StatelessWidget {
  final CalEvent event;
  final Color    primary;
  final AppL10n  l10n;
  const _EventTile({required this.event, required this.primary, required this.l10n});

  Color get _color {
    if (event.type == CalEventType.userTrip) return primary;
    return _kEventColors[event.type] ?? primary;
  }

  String get _typeLabel {
    switch (event.type) {
      case CalEventType.govEvent: return l10n.calGovEvent;
      case CalEventType.userTrip: return l10n.calUserTrip;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTrip = event.type == CalEventType.userTrip;
    return StitchedBox(
      color: AppColors.surface,
      stitchColor: _color.withValues(alpha: 0.28),
      radius: 12, inset: 3.5, dashWidth: 4, dashGap: 3,
      boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 1))],
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 左側色條 + 裝飾
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 3, height: 36, decoration: BoxDecoration(
            color: _color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 4),
          isTrip
              ? DoodleHeart(color: _color.withValues(alpha: 0.60), size: 9)
              : DoodleLightning(color: _color.withValues(alpha: 0.60), size: 7),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_typeLabel,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _color)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(event.title,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if (event.location != null) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 11, color: AppColors.textHint),
                const SizedBox(width: 2),
                Expanded(child: Text(event.location!,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint))),
              ]),
            ],
            if (event.note != null) ...[
              const SizedBox(height: 2),
              Text(event.note!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ],
          ]),
        ),
      ]),
    );
  }
}
