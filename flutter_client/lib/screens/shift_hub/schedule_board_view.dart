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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${ShiftUi.weekdays[ShiftUi.parse(d)!.weekday - 1]} ${ShiftUi.dm(ShiftUi.parse(d)!)}'),
                selected: d == dayKey,
                onSelected: (_) => setState(() => _mobileDay = ShiftUi.parse(d)!),
              ),
            ),
        ]),
      ),
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
              c['hasQuota'] == true ? '${c['effective']}/${c['min']}–${c['max']} · ${ShiftUi.coverageLabel(c['status']?.toString())}' : '${c['effective']} người',
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
      subtitle: Text([e['department'], e['position']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · ')),
      trailing: Wrap(spacing: 4, children: [
        if (leave != null) ShiftUi.pill(leave['status'] == 'Approved' ? 'Nghỉ phép' : 'Xin nghỉ', ShiftUi.statusColor(leave['status']?.toString())),
        if (reg != null) ShiftUi.pill('Đăng ký chờ', SboxColors.warning),
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
              child: Text(tr('Xếp ca'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            for (final t in _templates)
              ListTile(
                leading: CircleAvatar(radius: 8, backgroundColor: ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt())),
                title: Text('${t['name']}'),
                subtitle: Text('${t['start']} – ${t['end']}'),
                trailing: c?['shiftId']?.toString() == t['id'].toString() ? const Icon(Icons.check_rounded, color: SboxColors.success) : null,
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
                title: Text(tr('Xoá lịch ngày này'), style: const TextStyle(color: SboxColors.danger)),
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
      await _run(_api.deleteWorkSchedule(scheduleId!), 'Đã xoá lịch');
    } else {
      final dayOff = action == 'dayoff';
      final shiftId = dayOff ? null : action.substring(6);
      final body = {'shiftId': shiftId, 'isDayOff': dayOff};
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
        final r = await _api.createWorkSchedule({
          'employeeUserId': e['id'],
          'date': newDay,
          'shiftId': c['shiftId'],
          'isDayOff': c['isDayOff'] == true,
          'note': c['note'],
        });
        r['isSuccess'] == true ? created++ : failed++;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    NotificationOverlayManager().showSuccess(
        title: 'Sao chép lịch', message: 'Đã tạo $created lịch${failed > 0 ? ', $failed lịch lỗi' : ''}');
    _changed();
  }
}
