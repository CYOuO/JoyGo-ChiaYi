import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_settings_provider.dart';

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
        final endStr  = _p(raw, ['活動結束日期','EndDate','endDate']);
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
          Expanded(flex: 7, child: _buildDayGrid(primary)),
          _buildFilterRow(primary, l10n),
          Expanded(flex: 4, child: _buildEventList(selectedEvents, primary, l10n)),
        ],
      ),
    );
  }

  // ── Month header ──────────────────────────────────────────
  Widget _buildMonthHeader(Color primary, AppL10n l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surface,
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: _prevMonth, color: primary, padding: EdgeInsets.zero,
        ),
        Expanded(
          child: Center(
            child: Text(
              '${_focused.year}年 ${l10n.monthName(_focused.month)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: _nextMonth, color: primary, padding: EdgeInsets.zero,
        ),
        if (_apiLoading)
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: primary),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _fetchApi,
            color: AppColors.textHint, padding: EdgeInsets.zero,
          ),
      ]),
    );
  }

  // ── Weekday row ───────────────────────────────────────────
  Widget _buildWeekdayRow(AppL10n l10n) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.only(bottom: 6),
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

  // ── Day grid ──────────────────────────────────────────────
  Widget _buildDayGrid(Color primary) {
    final firstDay    = DateTime(_focused.year, _focused.month, 1);
    final lastDay     = DateTime(_focused.year, _focused.month + 1, 0);
    final startOffset = firstDay.weekday % 7; // Sun=0
    final today       = DateTime.now();

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7, childAspectRatio: 1.0,
      ),
      itemCount: 42,
      itemBuilder: (ctx, i) {
        final dayNum = i - startOffset + 1;
        if (dayNum < 1 || dayNum > lastDay.day) return const SizedBox.shrink();
        final date     = DateTime(_focused.year, _focused.month, dayNum);
        final isToday  = date.year == today.year && date.month == today.month && date.day == today.day;
        final isSel    = _selected != null &&
            date.year == _selected!.year && date.month == _selected!.month && date.day == _selected!.day;
        final events   = _eventsForDay(date);
        final isSunSat = i % 7 == 0 || i % 7 == 6;

        return GestureDetector(
          onTap: () => setState(() => _selected = date),
          child: _DayCell(
            dayNum: dayNum, isToday: isToday,
            isSelected: isSel, events: events,
            isSunSat: isSunSat, primary: primary,
          ),
        );
      },
    );
  }

  // ── Filter row (只剩 2 個 macaron 標籤) ───────────────────
  Widget _buildFilterRow(Color primary, AppL10n l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
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
      return Center(child: Text(l10n.calNoEvent, style: const TextStyle(color: AppColors.textHint)));
    }
    final dateLabel = '${_selected!.month}/${_selected!.day}（${l10n.weekdayShort[_selected!.weekday % 7]}）';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(dateLabel,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: events.isEmpty
              ? Center(child: Text(l10n.calNoEvent, style: const TextStyle(color: AppColors.textHint, fontSize: 13)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _EventTile(event: events[i], primary: primary, l10n: l10n),
                ),
        ),
      ],
    );
  }
}

// ─── Day cell ──────────────────────────────────────────────
class _DayCell extends StatelessWidget {
  final int dayNum;
  final bool isToday, isSelected, isSunSat;
  final List<CalEvent> events;
  final Color primary;
  const _DayCell({
    required this.dayNum, required this.isToday,
    required this.isSelected, required this.isSunSat,
    required this.events, required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    // Distinct dot colors per type (max 2 types)
    final dots = events.map((e) {
      if (e.type == CalEventType.userTrip) return primary;
      return _kEventColors[e.type] ?? const Color(0xFFFF8FAB);
    }).toSet().take(3).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected
            ? primary
            : isToday
                ? primary.withValues(alpha: 0.12)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$dayNum',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w400,
              color: isSelected
                  ? Colors.white
                  : isSunSat
                      ? Colors.red.shade400
                      : AppColors.textPrimary,
            ),
          ),
          if (dots.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: dots.map((c) => Container(
                width: 5, height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.85) : c,
                  shape: BoxShape.circle,
                ),
              )).toList(),
            ),
          ],
        ],
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _color, width: 3)),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_typeLabel,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _color)),
            ),
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
