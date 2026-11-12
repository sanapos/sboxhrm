import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/page_top_actions.dart';
import '../work_schedule_screen.dart';
import 'schedule_board_data.dart';
import 'schedule_day_grid.dart';
import 'schedule_shift_week_grid.dart';
import 'schedule_tools.dart';
import 'shift_assign_sheet.dart';
import 'shift_hub_sheets.dart';
import 'shift_hub_ui.dart';

/// Bảng xếp ca cho quản lý, 3 cách xem:
/// - «Theo nhân viên»: nhân viên × ngày, độ phủ định mức từng ca × ngày.
/// - «Theo ca»: ca × ngày (số người / định mức + tên) — chạm ô chọn nhiều nhân viên cho ca.
/// - «Từng ngày»: nhân viên × ca của một ngày — chạm ô xếp / bỏ ca, chạm tên ca chọn nhiều người.
/// Xếp / đổi / xoá / duyệt đăng ký ngay trên ô; sao chép ngày / tuần / tháng; xuất Excel; kêu gọi bổ sung người.
class ScheduleBoardView extends StatefulWidget {
  const ScheduleBoardView({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  State<ScheduleBoardView> createState() => _ScheduleBoardViewState();
}

class _ScheduleBoardViewState extends State<ScheduleBoardView> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _debounce;
  DateTime _monday = ShiftUi.monday(DateTime.now());
  String? _department;
  Map<String, dynamic>? _d;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  /// Ngày đang xem ở chế độ «Từng ngày».
  late DateTime _mobileDay = DateTime.now();
  /// emp: tuần theo nhân viên · shift: tuần theo ca · day: từng ngày (nhân viên × ca).
  String _mode = 'emp';
  /// Ô đang gửi lên máy chủ ở bảng ngày ([ScheduleDayGrid.busyKey]).
  final Set<String> _busyCells = {};
  final _dayChips = ScrollController();

  BoardData get _bd => BoardData(_d ?? const {});
  ScheduleCopier get _copier => ScheduleCopier(_api, department: _department, search: _search.text);

  String get _dayKey {
    final days = _days;
    final k = ShiftUi.key(_mobileDay);
    if (days.contains(k)) return k;
    final today = _d?['today']?.toString();
    if (today != null && days.contains(today)) return today;
    return days.isEmpty ? k : days.first;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dayChips.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = _d == null);
    final r = await _api.getShiftHubBoard(
        from: _monday, to: _monday.add(const Duration(days: 6)), department: _department, search: _search.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true) {
        _d = r['data'] as Map<String, dynamic>?;
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được bảng xếp ca';
      }
    });
  }

  void _changed() {
    _load();
    widget.onChanged?.call();
  }

  List<Map<String, dynamic>> _rows(dynamic v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  List<Map<String, dynamic>> get _templates => _rows(_d?['templates']).where((t) => t['active'] != false).toList();
  List<String> get _days => [for (final d in (_d?['days'] as List? ?? const [])) d.toString()];

  Map<String, dynamic>? _tpl(dynamic id) =>
      id == null ? null : _rows(_d?['templates']).where((t) => t['id'].toString() == id.toString()).firstOrNull;

  Map<String, dynamic>? _cov(String day, String shiftId) => _rows(_d?['coverage'])
      .where((c) => c['date'] == day && c['shiftId'].toString() == shiftId)
      .firstOrNull;

  void _shiftWeek(int days) {
    _monday = _monday.add(Duration(days: days));
    _mobileDay = _monday;
    _load();
  }

  // ═════════════ GIAO DIỆN ═════════════

  @override
  Widget build(BuildContext context) {
    if (_loading && _d == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _d == null) return Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)));
    final sm = _d?['summary'] as Map<String, dynamic>? ?? const {};
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final pad = c.maxWidth < 600 ? 12.0 : 20.0;
      if (!wide) return _compact(sm, pad);
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
          children: [
            _toolbar(),
            const SizedBox(height: 12),
            ShiftUi.statGrid([
              ShiftUi.stat('Nhân viên', '${ShiftUi.n(sm['employees'])}', Icons.people_alt_rounded, SboxColors.brand600),
              ShiftUi.stat('Chưa xếp ca', '${ShiftUi.n(sm['unscheduled'])}', Icons.person_off_rounded,
                  ShiftUi.n(sm['unscheduled']) > 0 ? SboxColors.warning : SboxColors.slate400),
              ShiftUi.stat('Giờ công dự kiến', '${ShiftUi.n(sm['plannedHours'])}', Icons.timelapse_rounded, SboxColors.violet),
              ShiftUi.stat('Ca thiếu người', '${ShiftUi.n(sm['shortSlots'])}', Icons.warning_amber_rounded,
                  ShiftUi.n(sm['shortSlots']) > 0 ? SboxColors.danger : SboxColors.success),
              ShiftUi.stat('Đăng ký chờ duyệt', '${ShiftUi.n(sm['pendingRegistrations'])}', Icons.how_to_reg_rounded, SboxColors.warning),
              ShiftUi.stat('Đơn nghỉ chờ duyệt', '${ShiftUi.n(sm['pendingLeaves'])}', Icons.beach_access_rounded, SboxColors.warning),
            ], minWidth: 180),
            const SizedBox(height: 14),
            Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _modePicker(compact: false),
              if (_mode == 'emp') _legend(),
            ]),
            const SizedBox(height: 10),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            _modeBody(compact: false),
          ],
        ),
      );
    });
  }

  Widget _toolbar() {
    final depts = [for (final d in (_d?['departments'] as List? ?? const [])) d.toString()];
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ShiftUi.weekNav(
        monday: _monday,
        onPrev: () => _shiftWeek(-7),
        onNext: () => _shiftWeek(7),
        onToday: () {
          _monday = ShiftUi.monday(DateTime.now());
          _mobileDay = DateTime.now();
          _load();
        },
        onPick: () async {
          final d = await showDatePicker(
              context: context, initialDate: _monday, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (d != null) {
            _monday = ShiftUi.monday(d);
            _mobileDay = d;
            _load();
          }
        },
      ),
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String?>(
          initialValue: _department,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Bộ phận'), isDense: true, border: const OutlineInputBorder()),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('Tất cả bộ phận'))),
            for (final d in depts) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            _department = v;
            _load();
          },
        ),
      ),
      SizedBox(
        width: 220,
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm nhân viên'), isDense: true, border: const OutlineInputBorder()),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 450), _load);
          },
        ),
      ),
      PopupMenuButton<String>(
        tooltip: tr('Thao tác nhanh'),
        onSelected: _onQuick,
        itemBuilder: (_) => _quickItems(withToday: false),
        child: Chip(avatar: const Icon(Icons.bolt_rounded, size: 18), label: Text(tr('Thao tác nhanh'))),
      ),
    ]);
  }

  // ── Chế độ xem ──

  Widget _modePicker({required bool compact}) => SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'emp', icon: const Icon(Icons.people_alt_rounded, size: 18), label: Text(tr(compact ? 'Tuần' : 'Theo nhân viên'))),
          ButtonSegment(value: 'shift', icon: const Icon(Icons.view_week_rounded, size: 18), label: Text(tr('Theo ca'))),
          ButtonSegment(value: 'day', icon: const Icon(Icons.view_day_rounded, size: 18), label: Text(tr(compact ? 'Ngày' : 'Từng ngày'))),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        style: compact ? const ButtonStyle(visualDensity: VisualDensity.compact) : null,
        onSelectionChanged: (v) => setState(() => _mode = v.first),
      );

  Widget _modeBody({required bool compact}) {
    switch (_mode) {
      case 'shift':
        return ScheduleShiftWeekGrid(
          data: _bd,
          compact: compact,
          onCell: _assignShift,
          onDay: (d) => setState(() {
            _mobileDay = ShiftUi.parse(d)!;
            _mode = 'day';
          }),
        );
      case 'day':
        final day = _dayKey;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _dayChipsRow(day),
          const SizedBox(height: 6),
          Text(tr('${ShiftUi.weekdaysLong[ShiftUi.parse(day)!.weekday - 1]}, ${ShiftUi.dmy(ShiftUi.parse(day)!)}'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate600)),
          const SizedBox(height: 8),
          ScheduleDayGrid(
            data: _bd,
            day: day,
            compact: compact,
            busy: _busyCells,
            onToggleShift: (e, t) => _toggleShift(e, day, t),
            onToggleDayOff: (e) => _toggleDayOff(e, day),
            onDetail: (e) => _cellSheet(e, day, BoardData.cell(e, day)),
            onShiftHeader: (t) => _assignShift(day, t),
          ),
        ]);
      default:
        return compact ? _weekCompact() : _grid();
    }
  }

  List<PopupMenuEntry<String>> _quickItems({required bool withToday}) {
    PopupMenuItem<String> it(String v, IconData icon, String label) =>
        PopupMenuItem(value: v, child: ListTile(dense: true, leading: Icon(icon), title: Text(tr(label))));
    return [
      if (withToday) it('today', Icons.today_rounded, 'Về tuần này'),
      it('copy', Icons.content_copy_rounded, 'Sao chép lịch tuần trước'),
      it('copyDay', Icons.copy_all_rounded, 'Sao chép một ngày sang ngày khác'),
      it('copyWeeks', Icons.next_week_rounded, 'Sao chép tuần này sang các tuần sau'),
      it('copyMonth', Icons.calendar_month_rounded, 'Sao chép lịch tháng'),
      const PopupMenuDivider(),
      it('export', Icons.table_view_rounded, 'Xuất Excel tuần này'),
      it('remind', Icons.notifications_active_rounded, 'Nhắc NV chưa đăng ký lịch'),
      const PopupMenuDivider(),
      it('legacy', Icons.history_rounded, 'Mở màn lịch cũ'),
    ];
  }

  Future<void> _onQuick(String v) async {
    switch (v) {
      case 'today':
        _monday = ShiftUi.monday(DateTime.now());
        _mobileDay = DateTime.now();
        _load();
      case 'export':
        await exportScheduleExcel(_bd, _monday, department: _department);
      case 'remind':
        await _remind();
      case 'legacy':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(tr('Lịch làm việc (màn cũ)')), actions: [
              ListenableBuilder(
                listenable: PageTopActions.instance,
                builder: (_, __) => PageTopActionsBar(actions: PageTopActions.instance.actions),
              ),
              const SizedBox(width: 8),
            ]),
            floatingActionButton: const PageTopActionsFab(),
            body: const WorkScheduleScreen(),
          ),
        ));
        _changed();
      default:
        setState(() => _busy = true);
        final cp = _copier;
        final job = switch (v) {
          'copy' => copyPreviousWeek(context, cp, _monday),
          'copyDay' => copyDay(context, cp, _bd, _dayKey),
          'copyWeeks' => copyWeekForward(context, cp, _bd, _monday),
          'copyMonth' => copyMonth(context, cp, _monday),
          _ => Future.value(false),
        };
        final changed = await job;
        if (!mounted) return;
        setState(() => _busy = false);
        if (changed) _changed();
    }
  }

  // ── Xếp nhanh trên bảng ngày / theo ca ──

  Future<void> _assignShift(String day, Map<String, dynamic> t) async {
    final changed = await showShiftAssignSheet(
      context,
      api: _api,
      data: _bd,
      day: day,
      template: t,
      onAskCoverage: () => _askCoverage(day, t),
    );
    if (changed && mounted) _changed();
  }

  /// Một chạm trên bảng ngày: có ca → bỏ; chưa có → xếp (ngày đang «Nghỉ» thì đổi thành ca).
  Future<void> _toggleShift(Map<String, dynamic> e, String day, Map<String, dynamic> t) async {
    final tid = t['id'].toString();
    final c = BoardData.cell(e, day);
    final item = BoardData.shiftItem(c, tid);
    final off = BoardData.dayOffItem(c);
    final key = ScheduleDayGrid.busyKey(e['id'], day, tid);
    setState(() => _busyCells.add(key));
    final Map<String, dynamic> r;
    if (item != null) {
      r = await _api.deleteWorkSchedule(item['scheduleId'].toString());
    } else if (off != null) {
      r = await _api.updateWorkSchedule(off['scheduleId'].toString(), {'shiftId': tid, 'isDayOff': false});
    } else {
      r = await _api.createWorkSchedule({'employeeUserId': e['id'], 'date': day, 'shiftId': tid, 'isDayOff': false});
    }
    await _afterQuick(key, r);
  }

  Future<void> _toggleDayOff(Map<String, dynamic> e, String day) async {
    final c = BoardData.cell(e, day);
    final off = BoardData.dayOffItem(c);
    final shifts = BoardData.shiftItems(c);
    if (off == null && shifts.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Đổi thành ngày nghỉ?')),
          content: Text(tr('${e['name']} đang có ${_bd.shiftNames(c)}. Đặt ngày nghỉ sẽ bỏ các ca này.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đặt ngày nghỉ'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final key = ScheduleDayGrid.busyKey(e['id'], day, 'off');
    setState(() => _busyCells.add(key));
    Map<String, dynamic> r;
    if (off != null) {
      r = await _api.deleteWorkSchedule(off['scheduleId'].toString());
    } else if (shifts.isNotEmpty) {
      for (final x in shifts.skip(1)) {
        await _api.deleteWorkSchedule(x['scheduleId'].toString());
      }
      r = await _api.updateWorkSchedule(shifts.first['scheduleId'].toString(), {'shiftId': null, 'isDayOff': true});
    } else {
      r = await _api.createWorkSchedule({'employeeUserId': e['id'], 'date': day, 'isDayOff': true});
    }
    await _afterQuick(key, r);
  }

  /// Thao tác một chạm: không bật thông báo thành công (xếp nhiều ô liên tiếp), chỉ báo lỗi.
  Future<void> _afterQuick(String key, Map<String, dynamic> r) async {
    if (r['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Xếp ca', message: r['message']?.toString() ?? 'Thao tác thất bại');
    }
    await _load();
    if (!mounted) return;
    setState(() => _busyCells.remove(key));
    widget.onChanged?.call();
  }

  /// 7 ngày chia đều một hàng (không cuộn), chấm đỏ = ngày có ca thiếu người.
  Widget _dayChipsRow(String dayKey) => Row(children: [
        for (final d in _days)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _mobileDay = ShiftUi.parse(d)!),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: d == dayKey ? SboxColors.brand600 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: d == dayKey ? SboxColors.brand600 : (d == _d?['today'] ? SboxColors.brand500 : SboxColors.slate200)),
                ),
                child: Column(children: [
                  Text(ShiftUi.weekdays[ShiftUi.parse(d)!.weekday - 1],
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: d == dayKey ? Colors.white70 : SboxColors.slate500)),
                  Text('${ShiftUi.parse(d)!.day}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: d == dayKey ? Colors.white : SboxColors.slate900)),
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: _rows(_d?['coverage']).any((x) => x['date'] == d && x['status'] == 'short')
                          ? (d == dayKey ? Colors.white : SboxColors.danger)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]);

  Widget _legend() => Wrap(spacing: 10, runSpacing: 6, children: [
        for (final t in _templates)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt()), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Text('${t['name']} ${t['start']}–${t['end']}', style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
          ]),
        for (final s in const ['short', 'tight', 'ok', 'full', 'over'])
          ShiftUi.pill(ShiftUi.coverageLabel(s), ShiftUi.coverageColor(s)),
      ]);

  // ── Lưới tuần (máy tính) ──

  static const _nameW = 200.0;
  static const _minDayW = 124.0;
  /// Cột ngày giãn theo bề ngang khung (tối thiểu [_minDayW]) — tránh lưới hụt, trống bên phải.
  double _dayW = _minDayW;

  Widget _grid() => LayoutBuilder(builder: (context, c) {
        final n = _days.length;
        _dayW = n == 0
            ? _minDayW
            : math.max(_minDayW, (c.maxWidth - 2 - _nameW - 70) / n);
        return _gridBody();
      });

  Widget _gridBody() {
    final days = _days;
    final emps = _rows(_d?['employees']);
    final today = _d?['today']?.toString();
    Widget head(String d) {
      final dt = ShiftUi.parse(d)!;
      final isToday = d == today;
      return Container(
        width: _dayW,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: isToday ? SboxColors.brand50 : SboxColors.slate50),
        child: Column(children: [
          Text(ShiftUi.weekdays[dt.weekday - 1],
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isToday ? SboxColors.brand700 : SboxColors.slate500)),
          Text(ShiftUi.dm(dt), style: TextStyle(fontWeight: FontWeight.w800, color: isToday ? SboxColors.brand700 : SboxColors.slate800)),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SboxColors.slate200),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _nameW + days.length * _dayW + 70,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: _nameW,
                padding: const EdgeInsets.all(10),
                color: SboxColors.slate50,
                child: Text(tr('Định mức theo ca'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
              for (final d in days) head(d),
              Container(width: 70, height: 50, color: SboxColors.slate50),
            ]),
            for (final t in _templates) _coverageRow(t, days),
            const Divider(height: 1, thickness: 1, color: SboxColors.slate200),
            Container(
              color: SboxColors.slate50,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                SizedBox(
                    width: _nameW - 10,
                    child: Text(tr('Nhân viên (${emps.length})'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
                SizedBox(width: days.length * _dayW),
                SizedBox(width: 60, child: Text(tr('Giờ'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
              ]),
            ),
            if (emps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(tr('Không có nhân viên phù hợp'), style: const TextStyle(color: SboxColors.slate500)),
              ),
            for (final e in emps) _empRow(e, days),
          ]),
        ),
      ),
    );
  }

  Widget _coverageRow(Map<String, dynamic> t, List<String> days) {
    final color = ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: SboxColors.slate100))),
      child: Row(children: [
        Container(
          width: _nameW,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Container(width: 4, height: 26, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                Text('${t['start']}–${t['end']}', style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
              ]),
            ),
          ]),
        ),
        for (final d in days) SizedBox(width: _dayW, child: _covCell(d, t)),
        const SizedBox(width: 70),
      ]),
    );
  }

  Widget _covCell(String day, Map<String, dynamic> t) {
    final c = _cov(day, t['id'].toString());
    if (c == null) return const SizedBox.shrink();
    final status = c['status']?.toString();
    final color = ShiftUi.coverageColor(status);
    final eff = ShiftUi.n(c['effective']).toInt();
    final min = ShiftUi.n(c['min']).toInt(), max = ShiftUi.n(c['max']).toInt();
    final hasQuota = c['hasQuota'] == true;
    return Tooltip(
      message: tr('${ShiftUi.coverageLabel(status)} · đã xếp ${c['scheduled']}, nghỉ phép ${c['onLeave']}, '
          'chờ duyệt ${c['pending']}${hasQuota ? ' · định mức $min–$max' : ''}'),
      // Chạm: chọn nhiều nhân viên cho ca ngày này (ca thiếu người có nút kêu gọi bổ sung trong bảng chọn).
      child: InkWell(
        onTap: () => _assignShift(day, t),
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(hasQuota ? '$eff / $min–$max' : '$eff người',
                style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 12.5)),
            if (ShiftUi.n(c['pending']) > 0 || ShiftUi.n(c['onLeave']) > 0)
              Text(
                [
                  if (ShiftUi.n(c['pending']) > 0) '+${c['pending']} chờ',
                  if (ShiftUi.n(c['onLeave']) > 0) '${c['onLeave']} nghỉ',
                ].join(' · '),
                style: const TextStyle(fontSize: 10.5, color: SboxColors.slate500),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _empRow(Map<String, dynamic> e, List<String> days) {
    final cells = (e['cells'] as Map?) ?? const {};
    final totals = (e['totals'] as Map?) ?? const {};
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: SboxColors.slate100))),
      child: Row(children: [
        Container(
          width: _nameW,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text([e['code'], e['department']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
          ]),
        ),
        for (final d in days)
          SizedBox(width: _dayW, height: 58, child: _cell(e, d, cells[d] is Map ? Map<String, dynamic>.from(cells[d] as Map) : null)),
        SizedBox(
          width: 70,
          child: Text('${ShiftUi.n(totals['hours'])}g',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.slate700)),
        ),
      ]),
    );
  }

  Widget _cell(Map<String, dynamic> e, String day, Map<String, dynamic>? c) {
    final tp = _tpl(c?['shiftId']);
    final reg = c?['registration'] as Map?;
    final leave = c?['leave'] as Map?;
    final dayOff = c?['isDayOff'] == true;
    final color = tp == null ? SboxColors.slate300 : ShiftUi.shiftColor(ShiftUi.n(tp['colorIndex']).toInt());
    final past = ShiftUi.parse(day)!.isBefore(ShiftUi.parse(_d?['today'])!);
    Widget body;
    if (leave != null && leave['status'] == 'Approved') {
      body = _chip('Nghỉ phép', ShiftUi.leaveTypes[leave['type']] ?? '', SboxColors.success, Icons.beach_access_rounded, strike: tp != null);
    } else if (dayOff) {
      body = _chip('Nghỉ', '', SboxColors.slate400, Icons.weekend_rounded);
    } else if (tp != null) {
      body = _chip(tp['name'].toString(), '${c?['start'] ?? tp['start']}–${c?['end'] ?? tp['end']}', color, null);
    } else if (reg != null) {
      final rt = _tpl(reg['shiftId']);
      body = _chip(reg['isDayOff'] == true ? 'Xin nghỉ' : rt?['name']?.toString() ?? 'Đăng ký', 'chờ duyệt', SboxColors.warning,
          Icons.hourglass_top_rounded, dashed: true);
    } else {
      body = past
          ? const SizedBox.shrink()
          : const Center(child: Icon(Icons.add_rounded, size: 18, color: SboxColors.slate300));
    }
    return InkWell(
      onTap: () => _cellSheet(e, day, c),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Stack(children: [
          Positioned.fill(child: body),
          if (reg != null && tp != null)
            const Positioned(right: 2, top: 2, child: Icon(Icons.circle, size: 8, color: SboxColors.warning)),
          if (leave != null && leave['status'] == 'Pending')
            const Positioned(right: 2, bottom: 2, child: Icon(Icons.beach_access_rounded, size: 12, color: SboxColors.warning)),
          if (ShiftUi.n(c?['moreShifts']) > 0)
            Positioned(left: 2, bottom: 2, child: ShiftUi.pill('+${ShiftUi.n(c?['moreShifts']).toInt()} ca', SboxColors.brand600, solid: true)),
          if (c?['swapPending'] == true)
            const Positioned(left: 2, top: 2, child: Icon(Icons.swap_horiz_rounded, size: 12, color: SboxColors.violet)),
        ]),
      ),
    );
  }

  Widget _chip(String title, String sub, Color color, IconData? icon, {bool dashed = false, bool strike = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dashed ? 0.06 : 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 3)],
            Flexible(
              child: Text(tr(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: SboxColors.slate800,
                      decoration: strike ? TextDecoration.none : null)),
            ),
          ]),
          if (sub.isNotEmpty)
            Text(tr(sub), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: SboxColors.slate500)),
        ]),
      );

  // ═════════════ ĐIỆN THOẠI ═════════════

  /// Điện thoại / máy tính bảng: thanh công cụ 1 dòng, 4 số chính, «Tuần | Ngày».
  /// Trước đây: công cụ 4 dòng lệch, 6 thẻ thống kê bị cắt chữ, chú thích 3 dòng, chỉ xem được từng ngày.
  Widget _compact(Map<String, dynamic> sm, double pad) {
    final filtered = (_department != null) || _search.text.trim().isNotEmpty;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(pad, 10, pad, 96), children: [
        Row(children: [
          IconButton(
            onPressed: () => _shiftWeek(-7),
            icon: const Icon(Icons.chevron_left_rounded),
            visualDensity: VisualDensity.compact,
            tooltip: tr('Tuần trước'),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _monday, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) {
                  _monday = ShiftUi.monday(d);
                  _mobileDay = d;
                  _load();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  Text(ShiftUi.weekLabel(_monday),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  if (ShiftUi.key(_monday) != ShiftUi.key(ShiftUi.monday(DateTime.now())))
                    Text(tr('Chạm để chọn tuần'), style: const TextStyle(fontSize: 11, color: SboxColors.slate500))
                  else
                    Text(tr('Tuần này'), style: const TextStyle(fontSize: 11, color: SboxColors.brand600, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _shiftWeek(7),
            icon: const Icon(Icons.chevron_right_rounded),
            visualDensity: VisualDensity.compact,
            tooltip: tr('Tuần sau'),
          ),
          IconButton(
            tooltip: tr('Lọc bộ phận / tìm nhân viên'),
            onPressed: _filterSheet,
            icon: Badge(isLabelVisible: filtered, smallSize: 8, child: const Icon(Icons.filter_list_rounded)),
          ),
          PopupMenuButton<String>(
            tooltip: tr('Thao tác nhanh'),
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onQuick,
            itemBuilder: (_) => _quickItems(withToday: true),
          ),
        ]),
        if (filtered)
          Wrap(spacing: 6, children: [
            if (_department != null)
              InputChip(
                label: Text(_department!),
                onDeleted: () {
                  _department = null;
                  _load();
                },
              ),
            if (_search.text.trim().isNotEmpty)
              InputChip(
                label: Text(tr('«${_search.text.trim()}»')),
                onDeleted: () {
                  _search.clear();
                  _load();
                },
              ),
          ]),
        const SizedBox(height: 8),
        _miniStats(sm),
        const SizedBox(height: 12),
        _modePicker(compact: true),
        const SizedBox(height: 10),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        _modeBody(compact: true),
      ]),
    );
  }

  /// 4 số chính trong 1 thẻ (không cắt chữ). Chạm «ca thiếu» / «chờ duyệt» để xem.
  Widget _miniStats(Map<String, dynamic> sm) {
    Widget item(String value, String label, Color color) => Expanded(
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(tr(label), textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, color: SboxColors.slate500, height: 1.2)),
          ]),
        );
    final pending = ShiftUi.n(sm['pendingRegistrations']) + ShiftUi.n(sm['pendingLeaves']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.slate200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        item('${ShiftUi.n(sm['employees'])}', 'nhân viên', SboxColors.slate900),
        item('${ShiftUi.n(sm['unscheduled'])}', 'chưa xếp ca', ShiftUi.n(sm['unscheduled']) > 0 ? SboxColors.warning : SboxColors.slate400),
        item('${ShiftUi.n(sm['shortSlots'])}', 'ca thiếu người', ShiftUi.n(sm['shortSlots']) > 0 ? SboxColors.danger : SboxColors.success),
        item('$pending', 'chờ duyệt', pending > 0 ? SboxColors.warning : SboxColors.slate400),
      ]),
    );
  }

  Future<void> _filterSheet() async {
    final depts = [for (final d in (_d?['departments'] as List? ?? const [])) d.toString()];
    final searchCtl = TextEditingController(text: _search.text);
    String? dept = _department;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: searchCtl,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm nhân viên'), isDense: true),
            ),
            const SizedBox(height: 12),
            Text(tr('Bộ phận'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(label: Text(tr('Tất cả')), selected: dept == null, onSelected: (_) => set(() => dept = null)),
              for (final d in depts) ChoiceChip(label: Text(d), selected: dept == d, onSelected: (_) => set(() => dept = d)),
            ]),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Áp dụng'))),
          ]),
        ),
      ),
    );
    if (ok == true) {
      _department = dept;
      _search.text = searchCtl.text;
      _load();
    }
    searchCtl.dispose();
  }

  /// Mã ngắn của ca cho ô bảng tuần: «Ca sáng» → S, «Ca chiều» → C, «Ca gãy trưa» → G (trùng thì thêm chữ / số).
  Map<String, String> get _codes {
    final out = <String, String>{};
    final used = <String>{};
    for (final t in _templates) {
      final words = t['name'].toString().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && w.toLowerCase() != 'ca').toList();
      final base = words.isEmpty ? 'C' : words.first.characters.first.toUpperCase();
      var code = base;
      if (used.contains(code) && words.length > 1) code = '$base${words[1].characters.first.toUpperCase()}';
      var i = 2;
      while (used.contains(code)) {
        code = '$base${i++}';
      }
      used.add(code);
      out[t['id'].toString()] = code;
    }
    return out;
  }

  /// Bảng tuần gọn cho điện thoại: tên + 7 ô ngày (mã ca có màu). Chạm ô = xếp / đổi / xoá / duyệt.
  Widget _weekCompact() {
    final days = _days;
    final emps = _rows(_d?['employees']);
    final today = _d?['today']?.toString();
    final codes = _codes;
    return LayoutBuilder(builder: (context, c) {
      final inner = c.maxWidth - 2; // trừ viền khung 1 px mỗi bên
      final nameW = (inner * 0.3).clamp(96.0, 200.0);
      final cellW = ((inner - nameW) / (days.isEmpty ? 7 : days.length)).floorToDouble();
      // Ô đủ rộng (máy tính bảng): tên ca + giờ như bảng máy tính; điện thoại: mã chữ có màu.
      final roomy = cellW >= 110;
      bool dayShort(String d) => _rows(_d?['coverage']).any((x) => x['date'] == d && x['status'] == 'short');
      return Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.slate200)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: SboxColors.slate50,
            child: Row(children: [
              SizedBox(
                width: nameW,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(tr('Nhân viên (${emps.length})'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: SboxColors.slate600)),
                ),
              ),
              for (final d in days)
                InkWell(
                  onTap: () => setState(() {
                    _mobileDay = ShiftUi.parse(d)!;
                    _mode = 'day';
                  }),
                  child: Container(
                    width: cellW,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    color: d == today ? SboxColors.brand50 : null,
                    child: Column(children: [
                      Text(ShiftUi.weekdays[ShiftUi.parse(d)!.weekday - 1],
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: d == today ? SboxColors.brand700 : SboxColors.slate500)),
                      Text('${ShiftUi.parse(d)!.day}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: d == today ? SboxColors.brand700 : SboxColors.slate800)),
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(color: dayShort(d) ? SboxColors.danger : Colors.transparent, shape: BoxShape.circle),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          if (emps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('Không có nhân viên phù hợp'), textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
            ),
          for (final e in emps)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: SboxColors.slate100))),
              child: Row(children: [
                SizedBox(
                  width: nameW,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nameW >= 150 ? (e['name']?.toString() ?? '') : _shortName(e['name']?.toString() ?? ''),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      // Chưa có phòng ban: bỏ « · » dư (trước hiện «0g ·»).
                      Text(
                          [
                            '${ShiftUi.n((e['totals'] as Map?)?['hours'])}g',
                            if ('${e['department'] ?? ''}'.trim().isNotEmpty) '${e['department']}'.trim(),
                          ].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: SboxColors.slate500)),
                    ]),
                  ),
                ),
                for (final d in days)
                  SizedBox(
                    width: cellW,
                    height: roomy ? 54 : 46,
                    child: roomy
                        ? _cell(e, d, (e['cells'] as Map?)?[d] is Map ? Map<String, dynamic>.from((e['cells'] as Map)[d] as Map) : null)
                        : _miniCell(e, d, (e['cells'] as Map?)?[d] is Map ? Map<String, dynamic>.from((e['cells'] as Map)[d] as Map) : null, codes),
                  ),
              ]),
            ),
          // Chú thích mã ca — ngay dưới bảng, 1–2 dòng.
          Container(
            color: SboxColors.slate50,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Wrap(spacing: 10, runSpacing: 4, children: [
              for (final t in _templates)
                Text(roomy ? '${t['name']} ${t['start']}–${t['end']}' : '${codes[t['id'].toString()]} ${t['name']} ${t['start']}–${t['end']}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt()))),
              if (!roomy) Text(tr('P nghỉ phép · – ngày nghỉ · ? chờ duyệt'), style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: SboxColors.danger, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(tr('ngày có ca thiếu người'), style: const TextStyle(fontSize: 11, color: SboxColors.danger)),
              ]),
            ]),
          ),
        ]),
      );
    });
  }

  /// «Trương Gia Bảo» → «Gia Bảo» khi cột hẹp (giữ tên gọi).
  String _shortName(String full) {
    final p = full.trim().split(RegExp(r'\s+'));
    return p.length >= 3 ? p.sublist(p.length - 2).join(' ') : full;
  }

  Widget _miniCell(Map<String, dynamic> e, String day, Map<String, dynamic>? c, Map<String, String> codes) {
    final tp = _tpl(c?['shiftId']);
    final reg = c?['registration'] as Map?;
    final leave = c?['leave'] as Map?;
    final past = ShiftUi.parse(day)!.isBefore(ShiftUi.parse(_d?['today'])!);
    String text;
    Color color;
    var solid = true;
    if (leave != null && leave['status'] == 'Approved') {
      text = 'P';
      color = SboxColors.success;
    } else if (c?['isDayOff'] == true) {
      text = '–';
      color = SboxColors.slate300;
      solid = false;
    } else if (tp != null) {
      final more = ShiftUi.n(c?['moreShifts']).toInt();
      text = '${codes[tp['id'].toString()] ?? '?'}${more > 0 ? '+' : ''}';
      color = ShiftUi.shiftColor(ShiftUi.n(tp['colorIndex']).toInt());
    } else if (reg != null) {
      text = '?';
      color = SboxColors.warning;
      solid = false;
    } else {
      text = past ? '' : '+';
      color = SboxColors.slate300;
      solid = false;
    }
    return InkWell(
      onTap: () => _cellSheet(e, day, c),
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: solid ? color.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(8),
            border: solid ? Border.all(color: color, width: 1.4) : (text == '?' ? Border.all(color: color, width: 1.2) : null),
          ),
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: solid ? color : (text == '+' ? SboxColors.slate300 : color))),
            if (reg != null && tp != null)
              const Positioned(right: -4, top: -4, child: Icon(Icons.circle, size: 8, color: SboxColors.warning)),
            if (leave != null && leave['status'] == 'Pending')
              const Positioned(right: -5, bottom: -5, child: Icon(Icons.beach_access_rounded, size: 11, color: SboxColors.warning)),
          ]),
        ),
      ),
    );
  }

  // ═════════════ THAO TÁC ═════════════

  Future<void> _run(Future<Map<String, dynamic>> call, String ok) async {
    setState(() => _busy = true);
    final r = await call;
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Xếp ca', message: ok);
      _changed();
    } else {
      NotificationOverlayManager().showError(title: 'Xếp ca', message: r['message']?.toString() ?? 'Thao tác thất bại');
    }
  }

  Future<void> _cellSheet(Map<String, dynamic> e, String day, Map<String, dynamic>? c) async {
    final date = ShiftUi.parse(day)!;
    final reg = c?['registration'] as Map?;
    final leave = c?['leave'] as Map?;
    final scheduleId = c?['scheduleId']?.toString();
    // Một người làm được nhiều ca / ngày: chạm ca đã xếp = bỏ ca đó; chạm ca chưa có khi đã có ca = hỏi
    // «Thêm ca» (làm thêm, không chồng giờ) hay «Đổi ca cũ → ca này». Trước đây ô 0–1 ca thì chọn ca khác
    // luôn THAY ca duy nhất, không thêm được ca thứ hai.
    final items = _rows(c?['items']);
    final shiftItems = items.where((x) => x['isDayOff'] != true && x['shiftId'] != null).toList();
    final multi = shiftItems.length > 1;
    bool hasShift(Map<String, dynamic> t) => shiftItems.any((x) => x['shiftId'].toString() == t['id'].toString());
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e['name']?.toString() ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(tr('${ShiftUi.weekdaysLong[date.weekday - 1]}, ${ShiftUi.dmy(date)}'),
                    style: const TextStyle(color: SboxColors.slate500)),
              ]),
            ),
            if (reg != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: SboxColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      tr('Nhân viên đăng ký: ${reg['isDayOff'] == true ? 'nghỉ ngày này' : reg['replaceShiftId'] != null ? 'đổi ${_tpl(reg['replaceShiftId'])?['name'] ?? 'ca'} → ${_tpl(reg['shiftId'])?['name'] ?? 'ca'}' : '${_tpl(reg['shiftId'])?['name'] ?? 'ca'}'}'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((reg['note']?.toString() ?? '').isNotEmpty) Text(tr('Ghi chú: ${reg['note']}')),
                  const SizedBox(height: 8),
                  Row(children: [
                    FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'approveReg'),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(tr('Duyệt'))),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: () => Navigator.pop(ctx, 'rejectReg'), child: Text(tr('Từ chối'))),
                  ]),
                ]),
              ),
            if (leave != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: ShiftUi.pill(
                    '${ShiftUi.leaveTypes[leave['type']] ?? 'Nghỉ phép'} · ${ShiftUi.statusLabels[leave['status']] ?? ''}',
                    ShiftUi.statusColor(leave['status']?.toString()),
                    icon: Icons.beach_access_rounded),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Xếp ca'), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                    tr(shiftItems.isEmpty
                        ? 'Làm nhiều ca trong ngày: xếp ca đầu, mở lại ô để thêm ca'
                        : 'Chạm ca đã xếp (✓) để bỏ; chạm ca khác để thêm ca hoặc đổi ca'),
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
              ]),
            ),
            for (final t in _templates)
              ListTile(
                leading: CircleAvatar(radius: 8, backgroundColor: ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt())),
                title: Text('${t['name']}'),
                subtitle: Text('${t['start']} – ${t['end']}'),
                trailing: hasShift(t)
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(tr('Bỏ ca'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                        const SizedBox(width: 6),
                        const Icon(Icons.check_rounded, color: SboxColors.success),
                      ])
                    : null,
                onTap: () => Navigator.pop(ctx, 'shift:${t['id']}'),
              ),
            ListTile(
              leading: const Icon(Icons.weekend_rounded, color: SboxColors.slate500),
              title: Text(tr('Ngày nghỉ')),
              trailing: c?['isDayOff'] == true ? const Icon(Icons.check_rounded, color: SboxColors.success) : null,
              onTap: () => Navigator.pop(ctx, 'dayoff'),
            ),
            if (leave == null)
              ListTile(
                leading: const Icon(Icons.beach_access_rounded, color: SboxColors.success),
                title: Text(tr('Tạo đơn nghỉ cho nhân viên')),
                subtitle: Text(tr('Tạo hộ, có thể duyệt luôn')),
                onTap: () => Navigator.pop(ctx, 'leave'),
              ),
            if (scheduleId != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: SboxColors.danger),
                title: Text(tr(multi ? 'Xoá tất cả ca ngày này' : 'Xoá lịch ngày này'), style: const TextStyle(color: SboxColors.danger)),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
    if (action == null) return;
    if (action == 'leave') {
      if (!mounted) return;
      final changed = await showLeaveRequestSheet(
        context,
        date: date,
        templates: _templates,
        scheduledShiftId: c?['shiftId']?.toString(),
        employeeId: e['id']?.toString(),
        managerMode: true,
        employeeName: e['name']?.toString(),
        candidates: [
          for (final x in _rows(_d?['employees']))
            {
              'id': x['id'].toString(),
              'name': x['name'] ?? '',
              'department': [x['code'], x['department']].map((v) => '${v ?? ''}'.trim()).where((v) => v.isNotEmpty).join(' · '),
            },
        ],
      );
      if (changed) _changed();
      return;
    }
    if (action == 'approveReg') {
      await _run(_api.approveScheduleRegistration(reg!['id'].toString(), {'isApproved': true}), 'Đã duyệt đăng ký');
    } else if (action == 'rejectReg') {
      if (!mounted) return;
      final reason = await ShiftUi.askText(context, 'Từ chối đăng ký', hint: 'Lý do', required: true);
      if (reason == null) return;
      await _run(_api.approveScheduleRegistration(reg!['id'].toString(), {'isApproved': false, 'rejectionReason': reason}),
          'Đã từ chối đăng ký');
    } else if (action == 'clear') {
      final ids = items.map((x) => x['scheduleId'].toString()).toList();
      if (ids.isEmpty) ids.add(scheduleId!);
      for (final id in ids.take(ids.length - 1)) {
        await _api.deleteWorkSchedule(id);
      }
      await _run(_api.deleteWorkSchedule(ids.last), 'Đã xoá lịch');
    } else {
      final dayOff = action == 'dayoff';
      final shiftId = dayOff ? null : action.substring(6);
      final body = {'shiftId': shiftId, 'isDayOff': dayOff};
      if (shiftItems.isNotEmpty) {
        if (dayOff) {
          // Đặt ngày nghỉ: gỡ các ca còn lại, đổi dòng đầu thành ngày nghỉ.
          for (final x in shiftItems.skip(1)) {
            await _api.deleteWorkSchedule(x['scheduleId'].toString());
          }
          await _run(_api.updateWorkSchedule(shiftItems.first['scheduleId'].toString(), body), 'Đã xếp ngày nghỉ');
          return;
        }
        final existing = shiftItems.where((x) => x['shiftId'].toString() == shiftId).firstOrNull;
        if (existing != null) {
          await _run(_api.deleteWorkSchedule(existing['scheduleId'].toString()), 'Đã bỏ ca');
          return;
        }
        final t = _tpl(shiftId);
        if (t == null || !mounted) return;
        final pick = await _askAddOrSwap(e, t, shiftItems);
        if (pick == null) return;
        if (pick == 'add') {
          await _run(_api.createWorkSchedule({...body, 'employeeUserId': e['id'], 'date': day}), 'Đã thêm ${t['name']}');
        } else {
          final old = shiftItems.firstWhere((x) => x['scheduleId'].toString() == pick);
          await _run(_api.updateWorkSchedule(pick, body),
              'Đã đổi ${_tpl(old['shiftId'])?['name'] ?? 'ca'} → ${t['name']}');
        }
        return;
      }
      await _run(
        scheduleId != null
            ? _api.updateWorkSchedule(scheduleId, body)
            : _api.createWorkSchedule({...body, 'employeeUserId': e['id'], 'date': day}),
        dayOff ? 'Đã xếp ngày nghỉ' : 'Đã xếp ca',
      );
    }
  }

  /// Người đã có ca, chọn thêm ca [t]: «Thêm ca» (làm thêm, khoá nếu chồng giờ ca đang có) hoặc «Đổi ca cũ → [t]».
  /// Trả 'add', scheduleId của ca bị đổi, hoặc null (huỷ).
  Future<String?> _askAddOrSwap(Map<String, dynamic> e, Map<String, dynamic> t, List<Map<String, dynamic>> current) {
    Map<String, dynamic> tplOf(Map<String, dynamic> x) => _tpl(x['shiftId']) ?? const {};
    final clash = current.where((x) => BoardData.shiftsOverlap(tplOf(x), t)).toList();
    final names = current.map((x) => tplOf(x)['name'] ?? 'Ca').join(', ');
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('${t['name']} ${t['start']} – ${t['end']}'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(tr('${e['name']} đang có $names'), style: const TextStyle(color: SboxColors.slate500)),
            ]),
          ),
          ListTile(
            enabled: clash.isEmpty,
            leading: const Icon(Icons.add_circle_outline_rounded, color: SboxColors.success),
            title: Text(tr('Thêm ${t['name']} (làm ${current.length + 1} ca)')),
            subtitle: Text(tr(clash.isEmpty
                ? 'Giữ ca đang có, làm thêm ca này'
                : 'Trùng giờ ${clash.map((x) => tplOf(x)['name'] ?? 'ca').join(', ')} — chỉ đổi ca được')),
            onTap: () => Navigator.pop(ctx, 'add'),
          ),
          for (final x in current)
            Builder(builder: (_) {
              final rest = current.where((y) => y != x);
              final blocked = rest.where((y) => BoardData.shiftsOverlap(tplOf(y), t)).toList();
              return ListTile(
                enabled: blocked.isEmpty,
                leading: const Icon(Icons.swap_horiz_rounded, color: SboxColors.violet),
                title: Text(tr('Đổi ${tplOf(x)['name'] ?? 'ca'} → ${t['name']}')),
                subtitle: Text(tr(blocked.isEmpty
                    ? 'Bỏ ${tplOf(x)['name'] ?? 'ca'} ${tplOf(x)['start'] ?? ''}–${tplOf(x)['end'] ?? ''}, xếp ca này thay'
                    : 'Vẫn trùng giờ ${blocked.map((y) => tplOf(y)['name'] ?? 'ca').join(', ')}')),
                onTap: () => Navigator.pop(ctx, x['scheduleId'].toString()),
              );
            }),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Future<void> _askCoverage(String day, Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Kêu gọi bổ sung người')),
        content: Text(tr('Gửi thông báo tới nhân viên chưa có ca ${t['name']} ngày ${ShiftUi.dm(ShiftUi.parse(day)!)} '
            'để đăng ký bổ sung?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Gửi thông báo'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      _api.requestShiftCoverage({'shiftTemplateId': t['id'], 'date': day, 'department': _department}),
      'Đã gửi thông báo kêu gọi đăng ký',
    );
  }

  Future<void> _remind() => _run(
        _api.sendScheduleReminder({
          'fromDate': ShiftUi.key(_monday),
          'toDate': ShiftUi.key(_monday.add(const Duration(days: 6))),
          'department': _department,
        }),
        'Đã nhắc nhân viên chưa đăng ký lịch',
      );
}
