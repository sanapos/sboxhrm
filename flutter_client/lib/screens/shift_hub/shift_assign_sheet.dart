import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import 'schedule_board_data.dart';
import 'shift_hub_ui.dart';

enum _St { assigned, pending, free, other, dayOff, leave }

/// «Xếp ca theo ca»: chọn một lượt nhiều nhân viên cho ca [template] ngày [day]
/// (nhanh hơn chạm từng ô nhân viên). Áp dụng cho ngày này, cả tuần hoặc các thứ đã chọn.
///
/// - Người được tick thêm: `POST /api/workschedules/bulk` theo từng ngày (máy chủ bỏ qua ngày đã
///   đánh dấu nghỉ và ca đã có). Người có đăng ký chờ duyệt đúng ca này: duyệt đăng ký.
/// - Người bị bỏ tick: xoá lịch ca này ở các ngày áp dụng.
/// - Nghỉ phép đã duyệt: không chọn được. Ngày nghỉ: chỉ đổi khi áp dụng một ngày.
///
/// Trả true nếu đã thay đổi lịch.
Future<bool> showShiftAssignSheet(
  BuildContext context, {
  required ApiService api,
  required BoardData data,
  required String day,
  required Map<String, dynamic> template,
  Future<void> Function()? onAskCoverage,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (ctx) => _AssignSheet(api: api, data: data, day: day, template: template, onAskCoverage: onAskCoverage),
  );
  return r == true;
}

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.api, required this.data, required this.day, required this.template, this.onAskCoverage});
  final ApiService api;
  final BoardData data;
  final String day;
  final Map<String, dynamic> template;
  final Future<void> Function()? onAskCoverage;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  final _search = TextEditingController();
  late final Set<String> _initial;
  late final Set<String> _selected;
  String? _dept;
  /// day | week | days
  String _scope = 'day';
  late final Set<int> _weekdays = {BoardData.date(widget.day).weekday};
  bool _saving = false;

  String get _tid => widget.template['id'].toString();

  @override
  void initState() {
    super.initState();
    _initial = {
      for (final e in widget.data.employees)
        if (_status(e, widget.day) == _St.assigned) e['id'].toString(),
    };
    _selected = {..._initial};
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _St _status(Map<String, dynamic> e, String day) {
    final c = BoardData.cell(e, day);
    if (BoardData.shiftItem(c, _tid) != null) return _St.assigned;
    if (BoardData.leaveApproved(c)) return _St.leave;
    final reg = BoardData.registration(c);
    if (reg != null && reg['isDayOff'] != true && reg['shiftId']?.toString() == _tid) return _St.pending;
    if (BoardData.dayOffItem(c) != null) return _St.dayOff;
    if (BoardData.shiftItems(c).isNotEmpty) return _St.other;
    return _St.free;
  }

  /// Ca khác đã xếp trùng giờ ca đang chọn.
  bool _clash(Map<String, dynamic> e) => BoardData.shiftItems(BoardData.cell(e, widget.day)).any((x) {
        final o = widget.data.tpl(x['shiftId']);
        return o != null && widget.data.overlaps(o, widget.template);
      });

  List<String> get _targetDays {
    if (_scope == 'day') return [widget.day];
    final today = widget.data.today ?? widget.day;
    return widget.data.days.where((d) {
      if (d.compareTo(today) < 0 && d != widget.day) return false;
      return _scope == 'week' || _weekdays.contains(BoardData.date(d).weekday);
    }).toList();
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.text.trim().toLowerCase();
    return widget.data.employees.where((e) {
      if (_dept != null && '${e['department'] ?? ''}' != _dept) return false;
      if (q.isEmpty) return true;
      return '${e['name']} ${e['code'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _save() async {
    final added = _selected.difference(_initial);
    final removed = _initial.difference(_selected);
    final days = _targetDays;
    if (days.isEmpty) {
      NotificationOverlayManager().showError(title: 'Xếp ca', message: 'Không có ngày nào để áp dụng (các ngày đã qua bị bỏ qua)');
      return;
    }
    final byId = {for (final e in widget.data.employees) e['id'].toString(): e};
    // Áp dụng nhiều ngày: người đã tick (kể cả có sẵn hôm nay) đều được xếp ở các ngày còn lại.
    final want = days.length == 1 ? added : _selected;
    setState(() => _saving = true);
    var created = 0, approved = 0, deleted = 0, failed = 0, skipped = 0;
    for (final d in days) {
      final bulk = <String>[];
      for (final id in want) {
        final e = byId[id];
        if (e == null) continue;
        final c = BoardData.cell(e, d);
        switch (_status(e, d)) {
          case _St.assigned:
            continue;
          case _St.leave:
            skipped++;
            continue;
          case _St.pending:
            final r = await widget.api.approveScheduleRegistration(BoardData.registration(c)!['id'].toString(), {'isApproved': true});
            r['isSuccess'] == true ? approved++ : failed++;
            continue;
          case _St.dayOff:
            if (days.length > 1) {
              skipped++;
              continue;
            }
            // Một ngày: đổi ngày nghỉ thành ca này.
            final off = BoardData.dayOffItem(c)!;
            final r = await widget.api.updateWorkSchedule(off['scheduleId'].toString(), {'shiftId': _tid, 'isDayOff': false});
            r['isSuccess'] == true ? created++ : failed++;
            continue;
          case _St.free:
          case _St.other:
            bulk.add(id);
        }
      }
      if (bulk.isNotEmpty) {
        final r = await widget.api.bulkCreateWorkSchedules({
          'employeeUserIds': bulk,
          'shiftId': _tid,
          'startDate': d,
          'endDate': d,
          'workDays': [BoardData.date(d).weekday % 7], // DayOfWeek .NET: CN = 0
        });
        r['isSuccess'] == true ? created += bulk.length : failed += bulk.length;
      }
      for (final id in removed) {
        final it = BoardData.shiftItem(BoardData.cell(byId[id] ?? const {}, d), _tid);
        if (it == null) continue;
        final r = await widget.api.deleteWorkSchedule(it['scheduleId'].toString());
        r['isSuccess'] == true ? deleted++ : failed++;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final parts = [
      if (created > 0) 'xếp $created lượt',
      if (approved > 0) 'duyệt $approved đăng ký',
      if (deleted > 0) 'bỏ $deleted lượt',
      if (skipped > 0) 'bỏ qua $skipped (nghỉ phép / ngày nghỉ)',
      if (failed > 0) '$failed lỗi',
    ];
    final msg = parts.isEmpty ? 'Không có thay đổi' : 'Đã ${parts.join(', ')}';
    failed > 0
        ? NotificationOverlayManager().showError(title: 'Xếp ca ${widget.template['name']}', message: msg)
        : NotificationOverlayManager().showSuccess(title: 'Xếp ca ${widget.template['name']}', message: msg);
    Navigator.pop(context, created + approved + deleted > 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final color = ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    final date = BoardData.date(widget.day);
    final cv = widget.data.cov(widget.day, _tid);
    final hasQuota = cv?['hasQuota'] == true;
    final min = ShiftUi.n(cv?['min']).toInt(), max = ShiftUi.n(cv?['max']).toInt();
    final count = _selected.length;
    final countColor = !hasQuota
        ? SboxColors.slate600
        : count < min
            ? SboxColors.danger
            : (max > 0 && count > max ? SboxColors.violet : SboxColors.success);
    final visible = _visible;
    final groups = <_St, List<Map<String, dynamic>>>{};
    for (final e in visible) {
      groups.putIfAbsent(_status(e, widget.day), () => []).add(e);
    }
    final added = _selected.difference(_initial).length, removed = _initial.difference(_selected).length;
    final depts = widget.data.departments;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Tiêu đề ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              Container(width: 5, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Xếp ${t['name']} · ${t['start']}–${t['end']}'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(tr('${ShiftUi.weekdaysLong[date.weekday - 1]}, ${ShiftUi.dmy(date)}'),
                      style: const TextStyle(color: SboxColors.slate500)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(tr('$count người'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: countColor)),
                if (hasQuota)
                  Text(tr('cần ${min == max ? '$min' : '$min–$max'}'), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
              ]),
            ]),
          ),
          if (cv?['status'] == 'short' && widget.onAskCoverage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context, false);
                    await widget.onAskCoverage!();
                  },
                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: Text(tr('Ca đang thiếu người — kêu gọi nhân viên đăng ký bổ sung')),
                ),
              ),
            ),
          // ── Tìm / bộ phận ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: tr('Tìm nhân viên'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (depts.length > 1)
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                ChoiceChip(label: Text(tr('Tất cả')), selected: _dept == null, onSelected: (_) => setState(() => _dept = null)),
                for (final d in depts)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(label: Text(d), selected: _dept == d, onSelected: (_) => setState(() => _dept = d)),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
            child: Row(children: [
              TextButton.icon(
                onPressed: () => setState(() {
                  for (final e in visible) {
                    final s = _status(e, widget.day);
                    if (s == _St.free || s == _St.pending) _selected.add(e['id'].toString());
                  }
                }),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(tr(_dept == null ? 'Chọn tất cả người còn trống' : 'Chọn cả bộ phận $_dept')),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _selected
                  ..clear()
                  ..addAll(_initial)),
                child: Text(tr('Hoàn tác')),
              ),
            ]),
          ),
          const Divider(height: 1),
          // ── Danh sách ──
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
              for (final s in _St.values)
                if ((groups[s] ?? const []).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                    child: Text(tr('${_groupLabel(s)} (${groups[s]!.length})'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: SboxColors.slate500)),
                  ),
                  for (final e in groups[s]!) _empTile(e, s),
                ],
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Không có nhân viên phù hợp'), textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
                ),
            ]),
          ),
          const Divider(height: 1),
          // ── Phạm vi + lưu ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tr('Áp dụng:'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ChoiceChip(label: Text(tr('Ngày này')), selected: _scope == 'day', onSelected: (_) => setState(() => _scope = 'day')),
              ChoiceChip(label: Text(tr('Cả tuần')), selected: _scope == 'week', onSelected: (_) => setState(() => _scope = 'week')),
              ChoiceChip(label: Text(tr('Chọn thứ')), selected: _scope == 'days', onSelected: (_) => setState(() => _scope = 'days')),
            ]),
          ),
          if (_scope == 'days')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 4, children: [
                for (var wd = 1; wd <= 7; wd++)
                  FilterChip(
                    label: Text(ShiftUi.weekdays[wd - 1]),
                    selected: _weekdays.contains(wd),
                    onSelected: (v) => setState(() => v ? _weekdays.add(wd) : _weekdays.remove(wd)),
                  ),
              ]),
            ),
          if (_scope != 'day')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text(
                _scopeSummary(t['name'].toString(), removed),
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                  child: Text(
                    tr(added + removed == 0 && _scope == 'day'
                        ? 'Chưa thay đổi'
                        : [if (added > 0) '+$added người', if (removed > 0) '−$removed người'].join(' · ')),
                    style: const TextStyle(color: SboxColors.slate600, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(tr('Đóng'))),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving || (added + removed == 0 && _scope == 'day') ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: Text(tr('Lưu')),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// Tóm tắt khi áp dụng nhiều ngày: «Xếp 5 người … 4 ngày (T4, T5…)» hoặc «Bỏ 2 người khỏi …».
  String _scopeSummary(String shift, int removed) {
    final n = _targetDays.length;
    final days = _targetDays.map((d) => ShiftUi.weekdays[BoardData.date(d).weekday - 1]).join(', ');
    final count = _selected.length;
    return _selected.isEmpty
        ? tr('Bỏ $removed người khỏi $shift $n ngày ($days). Bỏ qua ngày đã qua.')
        : tr('Xếp $count người đã chọn vào $shift $n ngày ($days). Bỏ qua ngày đã qua, ngày nghỉ và nghỉ phép.');
  }

  String _groupLabel(_St s) => switch (s) {
        _St.assigned => 'Đã xếp ca này',
        _St.pending => 'Đã đăng ký ca này (chờ duyệt)',
        _St.free => 'Chưa có ca',
        _St.other => 'Đang có ca khác',
        _St.dayOff => 'Ngày nghỉ',
        _St.leave => 'Nghỉ phép',
      };

  Widget _empTile(Map<String, dynamic> e, _St s) {
    final id = e['id'].toString();
    final enabled = s != _St.leave && !_saving;
    final c = BoardData.cell(e, widget.day);
    final clash = s == _St.other && _clash(e);
    final sub = <String>[
      if ('${e['code'] ?? ''}'.trim().isNotEmpty) '${e['code']}'.trim(),
      if ('${e['department'] ?? ''}'.trim().isNotEmpty) '${e['department']}'.trim(),
      if (s == _St.other) widget.data.shiftNames(c),
      if (s == _St.dayOff && _scope != 'day') 'giữ ngày nghỉ',
      if (s == _St.leave) ShiftUi.leaveTypes[BoardData.leave(c)?['type']] ?? 'Nghỉ phép',
    ];
    return CheckboxListTile(
      dense: true,
      value: _selected.contains(id),
      onChanged: enabled ? (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)) : null,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(e['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: sub.isEmpty ? null : Text(sub.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      secondary: clash ? ShiftUi.pill('Trùng giờ', SboxColors.warning, icon: Icons.warning_amber_rounded) : null,
    );
  }
}
