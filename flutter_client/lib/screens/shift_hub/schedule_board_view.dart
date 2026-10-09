import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import 'shift_hub_ui.dart';

/// Bảng xếp ca tuần cho quản lý: nhân viên × ngày, độ phủ định mức từng ca × ngày,
/// xếp / đổi / xoá ca ngay trên ô, duyệt đăng ký ngay trên ô, sao chép tuần trước, kêu gọi bổ sung người.
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
  late DateTime _mobileDay = DateTime.now();
  /// Điện thoại: «Tuần» (bảng gọn nhân viên × 7 ngày) hoặc «Ngày» (theo ca).
  bool _mobileWeek = true;
  final _dayChips = ScrollController();

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
              ShiftUi.stat('Chưa xếp ca tuần này', '${ShiftUi.n(sm['unscheduled'])}', Icons.person_off_rounded,
                  ShiftUi.n(sm['unscheduled']) > 0 ? SboxColors.warning : SboxColors.slate400),
              ShiftUi.stat('Giờ công dự kiến', '${ShiftUi.n(sm['plannedHours'])}', Icons.timelapse_rounded, SboxColors.violet),
              ShiftUi.stat('Ca thiếu người', '${ShiftUi.n(sm['shortSlots'])}', Icons.warning_amber_rounded,
                  ShiftUi.n(sm['shortSlots']) > 0 ? SboxColors.danger : SboxColors.success),
              ShiftUi.stat('Đăng ký chờ duyệt', '${ShiftUi.n(sm['pendingRegistrations'])}', Icons.how_to_reg_rounded, SboxColors.warning),
              ShiftUi.stat('Đơn nghỉ chờ duyệt', '${ShiftUi.n(sm['pendingLeaves'])}', Icons.beach_access_rounded, SboxColors.warning),
            ], minWidth: 180),
            const SizedBox(height: 14),
            _legend(),
            const SizedBox(height: 10),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            wide ? _grid() : _mobileDayView(),
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
        onSelected: (v) => v == 'copy' ? _copyLastWeek() : _remind(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'copy',
            child: ListTile(dense: true, leading: const Icon(Icons.content_copy_rounded), title: Text(tr('Sao chép lịch tuần trước'))),
          ),
          PopupMenuItem(
            value: 'remind',
            child: ListTile(
                dense: true, leading: const Icon(Icons.notifications_active_rounded), title: Text(tr('Nhắc NV chưa đăng ký lịch'))),
          ),
        ],
        child: Chip(avatar: const Icon(Icons.bolt_rounded, size: 18), label: Text(tr('Thao tác nhanh'))),
      ),
    ]);
  }

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
  static const _dayW = 124.0;

  Widget _grid() {
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
      child: InkWell(
        onTap: status == 'short' ? () => _askCoverage(day, t) : null,
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
            onSelected: (v) => switch (v) {
              'copy' => _copyLastWeek(),
              'today' => (() {
                  _monday = ShiftUi.monday(DateTime.now());
                  _mobileDay = DateTime.now();
                  _load();
                })(),
              _ => _remind(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'today', child: ListTile(dense: true, leading: const Icon(Icons.today_rounded), title: Text(tr('Về tuần này')))),
              PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: const Icon(Icons.content_copy_rounded), title: Text(tr('Sao chép lịch tuần trước')))),
              PopupMenuItem(
                  value: 'remind',
                  child: ListTile(dense: true, leading: const Icon(Icons.notifications_active_rounded), title: Text(tr('Nhắc NV chưa đăng ký lịch')))),
            ],
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
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, icon: const Icon(Icons.grid_on_rounded, size: 18), label: Text(tr('Cả tuần'))),
            ButtonSegment(value: false, icon: const Icon(Icons.view_day_rounded, size: 18), label: Text(tr('Từng ngày'))),
          ],
          selected: {_mobileWeek},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _mobileWeek = v.first),
        ),
        const SizedBox(height: 10),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_mobileWeek) _weekCompact() else _mobileDayView(),
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
                    _mobileWeek = false;
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
                      Text('${ShiftUi.n((e['totals'] as Map?)?['hours'])}g · ${e['department'] ?? ''}',
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

  // ── Xem theo ngày (điện thoại) ──

  Widget _mobileDayView() {
    final days = _days;
    final dayKey = days.contains(ShiftUi.key(_mobileDay)) ? ShiftUi.key(_mobileDay) : (days.isEmpty ? '' : days.first);
    final emps = _rows(_d?['employees']);
    Map<String, dynamic>? cellOf(Map<String, dynamic> e) {
      final c = (e['cells'] as Map?)?[dayKey];
      return c is Map ? Map<String, dynamic>.from(c) : null;
    }

    final unassigned = emps.where((e) {
      final c = cellOf(e);
      return c == null || (c['shiftId'] == null && c['isDayOff'] != true);
    }).toList();
    final off = emps.where((e) => cellOf(e)?['isDayOff'] == true).toList();

    // 7 ngày chia đều 1 hàng (không cuộn — trước đây ngày đang chọn nằm ngoài màn hình).
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final d in days)
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
      ]),
      const SizedBox(height: 6),
      Text(tr('${ShiftUi.weekdaysLong[ShiftUi.parse(dayKey)!.weekday - 1]}, ${ShiftUi.dmy(ShiftUi.parse(dayKey)!)}'),
          style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate600)),
      const SizedBox(height: 10),
      for (final t in _templates) ...[
        _mobileShiftHeader(t, dayKey),
        for (final e in emps.where((e) => cellOf(e)?['shiftId']?.toString() == t['id'].toString()))
          _mobileEmp(e, dayKey, cellOf(e)),
        const SizedBox(height: 10),
      ],
      if (off.isNotEmpty) ...[
        ShiftUi.sectionTitle('Nghỉ (${off.length})', icon: Icons.weekend_rounded),
        for (final e in off) _mobileEmp(e, dayKey, cellOf(e)),
        const SizedBox(height: 10),
      ],
      ShiftUi.sectionTitle('Chưa xếp ca (${unassigned.length})', icon: Icons.person_add_alt_rounded),
      for (final e in unassigned) _mobileEmp(e, dayKey, cellOf(e)),
    ]);
  }

  Widget _mobileShiftHeader(Map<String, dynamic> t, String day) {
    final c = _cov(day, t['id'].toString());
    final color = ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(width: 4, height: 30, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${t['name']} · ${t['start']}–${t['end']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (c != null)
          InkWell(
            onTap: c['status'] == 'short' ? () => _askCoverage(day, t) : null,
            child: ShiftUi.pill(
              c['hasQuota'] == true
                  ? '${c['effective']} người · cần ${c['min'] == c['max'] ? c['min'] : '${c['min']}–${c['max']}'}${c['status'] == 'short' ? ' · thiếu' : ''}'
                  : '${c['effective']} người',
              ShiftUi.coverageColor(c['status']?.toString()),
            ),
          ),
      ]),
    );
  }

  Widget _mobileEmp(Map<String, dynamic> e, String day, Map<String, dynamic>? c) {
    final reg = c?['registration'] as Map?;
    final leave = c?['leave'] as Map?;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      onTap: () => _cellSheet(e, day, c),
      title: Text(e['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text({e['department'], e['position']}.where((x) => (x?.toString() ?? '').isNotEmpty).join(' · ')),
      trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (leave != null) ShiftUi.pill(leave['status'] == 'Approved' ? 'Nghỉ phép' : 'Xin nghỉ', ShiftUi.statusColor(leave['status']?.toString())),
        if (reg != null) ShiftUi.pill('Đăng ký chờ', SboxColors.warning),
        if (c?['shiftId'] == null && c?['isDayOff'] != true && reg == null)
          ShiftUi.pill('+ Xếp ca', SboxColors.brand600)
        else
          const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
      ]),
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
    // Ô có nhiều ca: chạm một ca = thêm / bỏ ca đó (thay vì thay thế ca duy nhất).
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
                  Text(tr('Nhân viên đăng ký: ${reg['isDayOff'] == true ? 'nghỉ ngày này' : '${_tpl(reg['shiftId'])?['name'] ?? 'ca'}'}'),
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
              child: Text(tr(multi ? 'Xếp ca (nhiều ca trong ngày — chạm để thêm / bỏ)' : 'Xếp ca'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            for (final t in _templates)
              ListTile(
                leading: CircleAvatar(radius: 8, backgroundColor: ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt())),
                title: Text('${t['name']}'),
                subtitle: Text('${t['start']} – ${t['end']}'),
                trailing: hasShift(t) ? const Icon(Icons.check_rounded, color: SboxColors.success) : null,
                onTap: () => Navigator.pop(ctx, 'shift:${t['id']}'),
              ),
            ListTile(
              leading: const Icon(Icons.weekend_rounded, color: SboxColors.slate500),
              title: Text(tr('Ngày nghỉ')),
              trailing: c?['isDayOff'] == true ? const Icon(Icons.check_rounded, color: SboxColors.success) : null,
              onTap: () => Navigator.pop(ctx, 'dayoff'),
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
      if (multi) {
        if (dayOff) {
          // Đặt ngày nghỉ: gỡ các ca còn lại, đổi dòng đầu thành ngày nghỉ.
          for (final x in shiftItems.skip(1)) {
            await _api.deleteWorkSchedule(x['scheduleId'].toString());
          }
          await _run(_api.updateWorkSchedule(shiftItems.first['scheduleId'].toString(), body), 'Đã xếp ngày nghỉ');
        } else {
          final existing = shiftItems.where((x) => x['shiftId'].toString() == shiftId).firstOrNull;
          await _run(
            existing != null
                ? _api.deleteWorkSchedule(existing['scheduleId'].toString())
                : _api.createWorkSchedule({...body, 'employeeUserId': e['id'], 'date': day}),
            existing != null ? 'Đã bỏ ca' : 'Đã thêm ca',
          );
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

  /// Sao chép lịch tuần trước sang tuần đang xem — chỉ điền ô còn trống, không ghi đè.
  Future<void> _copyLastWeek() async {
    final prevMon = _monday.subtract(const Duration(days: 7));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sao chép lịch tuần trước')),
        content: Text(tr('Chép lịch ${ShiftUi.weekLabel(prevMon)} sang ${ShiftUi.weekLabel(_monday)}. '
            'Chỉ điền ngày còn trống, không ghi đè lịch đã có.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sao chép'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final prev = await _api.getShiftHubBoard(
        from: prevMon, to: prevMon.add(const Duration(days: 6)), department: _department, search: _search.text);
    final prevEmps = _rows((prev['data'] as Map?)?['employees']);
    final curEmps = {for (final e in _rows(_d?['employees'])) e['id'].toString(): e};
    var created = 0, failed = 0;
    for (final e in prevEmps) {
      final cells = (e['cells'] as Map?) ?? const {};
      for (final entry in cells.entries) {
        final c = entry.value as Map;
        if (c['scheduleId'] == null) continue;
        final newDay = ShiftUi.key(ShiftUi.parse(entry.key)!.add(const Duration(days: 7)));
        final existing = ((curEmps[e['id'].toString()]?['cells'] as Map?) ?? const {})[newDay] as Map?;
        if (existing?['scheduleId'] != null) continue;
        final srcItems = _rows(c['items']);
        for (final it in srcItems.isEmpty ? [Map<String, dynamic>.from(c)] : srcItems) {
          final r = await _api.createWorkSchedule({
            'employeeUserId': e['id'],
            'date': newDay,
            'shiftId': it['shiftId'],
            'isDayOff': it['isDayOff'] == true,
            'note': c['note'],
          });
          r['isSuccess'] == true ? created++ : failed++;
        }
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    NotificationOverlayManager().showSuccess(
        title: 'Sao chép lịch', message: 'Đã tạo $created lịch${failed > 0 ? ', $failed lịch lỗi' : ''}');
    _changed();
  }
}
