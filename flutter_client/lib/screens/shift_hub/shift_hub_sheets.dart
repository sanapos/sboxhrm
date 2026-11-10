import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import 'shift_hub_ui.dart';

Future<bool?> _sheet(BuildContext context, Widget child) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: child,
      ),
    );

Widget _title(String t, String sub) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(t), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(tr(sub), style: const TextStyle(color: SboxColors.slate500)),
      ]),
    );

void _toast(Map<String, dynamic> res, String ok, String title) {
  if (res['isSuccess'] == true) {
    NotificationOverlayManager().showSuccess(title: title, message: ok);
  } else {
    NotificationOverlayManager().showError(title: title, message: res['message']?.toString() ?? 'Thao tác thất bại');
  }
}

// ═════════════ ĐĂNG KÝ CA ═════════════

/// Nhân viên đăng ký ca (hoặc xin ngày nghỉ) cho 1 ngày; hiện số chỗ còn trống theo định mức.
Future<bool> showRegisterShiftSheet(
  BuildContext context, {
  required DateTime date,
  required List<Map<String, dynamic>> templates,
  required List<Map<String, dynamic>> slots,
  String? currentShiftId,
  bool hasShiftToday = false,
  bool isDayOffToday = false,
}) async {
  final ok = await _sheet(
      context,
      _RegisterSheet(
          date: date,
          templates: templates,
          slots: slots,
          currentShiftId: currentShiftId,
          hasShiftToday: hasShiftToday,
          isDayOffToday: isDayOffToday));
  return ok == true;
}

class _RegisterSheet extends StatefulWidget {
  const _RegisterSheet({
    required this.date,
    required this.templates,
    required this.slots,
    this.currentShiftId,
    this.hasShiftToday = false,
    this.isDayOffToday = false,
  });
  final bool hasShiftToday;
  final bool isDayOffToday;
  final DateTime date;
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> slots;
  final String? currentShiftId;

  @override
  State<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends State<_RegisterSheet> {
  String? _shiftId; // null + _dayOff = xin nghỉ ngày này
  bool _dayOff = false;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _slot(String id) =>
      widget.slots.where((s) => s['shiftId']?.toString() == id).firstOrNull;

  Future<void> _save() async {
    if (_shiftId == null && !_dayOff) return;
    setState(() => _saving = true);
    final res = await ApiService().createScheduleRegistration({
      'date': ShiftUi.key(widget.date),
      if (!_dayOff) 'shiftId': _shiftId,
      'isDayOff': _dayOff,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(res, _dayOff ? 'Đã gửi đăng ký nghỉ ngày này' : 'Đã gửi đăng ký ca — chờ quản lý duyệt', 'Đăng ký ca');
    if (res['isSuccess'] == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('Đăng ký ca', '${ShiftUi.weekdaysLong[widget.date.weekday - 1]}, ${ShiftUi.dmy(widget.date)}'),
          for (var i = 0; i < widget.templates.length; i++) _tplTile(widget.templates[i]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _choice(
              selected: _dayOff,
              color: SboxColors.slate500,
              icon: Icons.beach_access_rounded,
              title: 'Đăng ký nghỉ ngày này',
              subtitle: 'Không xếp ca (không phải đơn nghỉ phép)',
              onTap: () => setState(() {
                _dayOff = true;
                _shiftId = null;
              }),
            ),
          ),
          if ((_dayOff && widget.hasShiftToday) || (!_dayOff && _shiftId != null && widget.isDayOffToday))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SboxColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: SboxColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(_dayOff
                          ? 'Bạn đang có ca trong ngày này — quản lý cần gỡ ca trước khi duyệt đăng ký nghỉ.'
                          : 'Ngày này đang được đánh dấu nghỉ — quản lý cần gỡ ngày nghỉ trước khi duyệt đăng ký ca.'),
                      style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700),
                    ),
                  ),
                ]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _note,
              decoration: InputDecoration(labelText: tr('Ghi chú (không bắt buộc)'), border: const OutlineInputBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _saving || (_shiftId == null && !_dayOff) ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.send_rounded),
              label: Text(tr(_saving ? 'Đang gửi…' : 'Gửi đăng ký')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tplTile(Map<String, dynamic> t) {
    final id = t['id'].toString();
    final slot = _slot(id);
    final status = slot?['status']?.toString();
    final remaining = slot?['remaining'];
    final full = status == 'full' || status == 'over';
    final color = ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    String sub = '${t['start']} – ${t['end']} · ${ShiftUi.n(t['hours'])} giờ';
    if (slot != null && slot['hasQuota'] == true) {
      sub += full
          ? ' · Đã đủ người'
          : remaining != null
              ? ' · Còn $remaining chỗ'
              : '';
      if (status == 'short') sub += ' · Đang thiếu người';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _choice(
        selected: _shiftId == id,
        color: color,
        icon: Icons.schedule_rounded,
        title: '${t['name']}${id == widget.currentShiftId ? ' (ca hiện tại)' : ''}',
        subtitle: sub,
        badge: status == 'short' ? ShiftUi.pill('Ưu tiên', SboxColors.danger) : full ? ShiftUi.pill('Đủ người', SboxColors.slate500) : null,
        onTap: () => setState(() {
          _shiftId = id;
          _dayOff = false;
        }),
      ),
    );
  }
}

// ═════════════ ĐĂNG KÝ CẢ TUẦN ═════════════

/// Nhân viên đăng ký ca cho nhiều ngày trong một bảng (thay vì mở «Đăng ký ca» từng ngày):
/// mỗi ngày chọn một ca, «Nghỉ» hoặc bỏ trống; gửi một lượt, mỗi ngày một đăng ký chờ duyệt.
/// [days]: phần tử `days` của `GET /api/shift-hub/my` (có schedule, registration, slots).
Future<bool> showRegisterWeekSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> days,
  required List<Map<String, dynamic>> templates,
}) async {
  final ok = await _sheet(context, _RegisterWeekSheet(days: days, templates: templates));
  return ok == true;
}

class _RegisterWeekSheet extends StatefulWidget {
  const _RegisterWeekSheet({required this.days, required this.templates});
  final List<Map<String, dynamic>> days;
  final List<Map<String, dynamic>> templates;

  @override
  State<_RegisterWeekSheet> createState() => _RegisterWeekSheetState();
}

class _RegisterWeekSheetState extends State<_RegisterWeekSheet> {
  /// ngày → shiftId | 'off'
  final Map<String, String> _pick = {};
  bool _saving = false;

  List<Map<String, dynamic>> get _open => widget.days.where((d) => d['isPast'] != true).toList();

  Map<String, dynamic>? _tpl(dynamic id) =>
      id == null ? null : widget.templates.where((t) => t['id'].toString() == id.toString()).firstOrNull;

  Future<void> _save() async {
    setState(() => _saving = true);
    var ok = 0, fail = 0;
    String? err;
    for (final e in _pick.entries) {
      final off = e.value == 'off';
      final r = await ApiService().createScheduleRegistration({
        'date': e.key,
        if (!off) 'shiftId': e.value,
        'isDayOff': off,
      });
      if (r['isSuccess'] == true) {
        ok++;
      } else {
        fail++;
        err ??= r['message']?.toString();
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (fail == 0) {
      NotificationOverlayManager().showSuccess(title: 'Đăng ký cả tuần', message: 'Đã gửi $ok đăng ký — chờ quản lý duyệt');
    } else {
      NotificationOverlayManager().showError(title: 'Đăng ký cả tuần', message: 'Gửi được $ok, lỗi $fail${err != null ? ': $err' : ''}');
    }
    Navigator.pop(context, ok > 0);
  }

  @override
  Widget build(BuildContext context) {
    final days = _open;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('Đăng ký cả tuần', 'Chọn ca cho từng ngày rồi gửi một lượt'),
          Expanded(
            child: days.isEmpty
                ? Center(child: Text(tr('Tuần này không còn ngày nào để đăng ký'), style: const TextStyle(color: SboxColors.slate500)))
                : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                    for (final d in days) _dayRow(d),
                  ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _saving || _pick.isEmpty ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.send_rounded),
              label: Text(tr(_saving ? 'Đang gửi…' : 'Gửi ${_pick.length} đăng ký')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dayRow(Map<String, dynamic> d) {
    final key = d['date'].toString();
    final date = ShiftUi.parse(key)!;
    final s = d['schedule'] as Map?;
    final reg = d['registration'] as Map?;
    final now = s == null
        ? 'Chưa có ca'
        : s['isDayOff'] == true
            ? 'Đang là ngày nghỉ'
            : 'Đang có ${_tpl(s['shiftId'])?['name'] ?? 'ca'}';
    final pending = reg != null && reg['status'] == 'Pending';
    final slots = [for (final x in (d['slots'] as List? ?? const [])) if (x is Map) x];
    String? slotStatus(String id) => slots.where((x) => x['shiftId']?.toString() == id).firstOrNull?['status']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: SboxColors.slate200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(tr('${ShiftUi.weekdaysLong[date.weekday - 1]}, ${ShiftUi.dm(date)}'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(now), style: const TextStyle(fontSize: 12, color: SboxColors.slate500), overflow: TextOverflow.ellipsis)),
          if (pending) ShiftUi.requestStatusPill('reg', 'Pending'),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in widget.templates)
            ChoiceChip(
              avatar: CircleAvatar(radius: 5, backgroundColor: ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt())),
              label: Text('${t['name']}${slotStatus(t['id'].toString()) == 'short' ? ' · thiếu' : (slotStatus(t['id'].toString()) == 'full' || slotStatus(t['id'].toString()) == 'over') ? ' · đủ' : ''}'),
              selected: _pick[key] == t['id'].toString(),
              onSelected: (v) => setState(() => v ? _pick[key] = t['id'].toString() : _pick.remove(key)),
            ),
          ChoiceChip(
            label: Text(tr('Nghỉ')),
            selected: _pick[key] == 'off',
            onSelected: (v) => setState(() => v ? _pick[key] = 'off' : _pick.remove(key)),
          ),
        ]),
      ]),
    );
  }
}

Widget _choice({
  required bool selected,
  required Color color,
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  Widget? badge,
}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : SboxColors.slate200, width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          Container(width: 6, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tr(subtitle), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
            ]),
          ),
          if (badge != null) badge,
          const SizedBox(width: 6),
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? color : SboxColors.slate300),
        ]),
      ),
    );

// ═════════════ XIN NGHỈ ═════════════

/// Xin nghỉ phép — form dùng chung (Lịch của tôi, quản lý tạo hộ từ Bảng xếp ca, ngày vắng bên Chấm công):
/// đủ 8 loại nghỉ, khoảng ngày, ca, nửa ca, người thay ca, số ngày phép sẽ trừ, lý do.
/// [managerMode]: quản lý tạo hộ [employeeName] — thêm «Duyệt luôn» và «Vẫn tính công».
/// [candidates]: người thay ca có thể chọn ({id: Employee.Id, name, department}); bỏ trống thì tải
/// đồng nghiệp từ `GET /api/shiftswaps/colleagues`.
Future<bool> showLeaveRequestSheet(
  BuildContext context, {
  required DateTime date,
  required List<Map<String, dynamic>> templates,
  String? scheduledShiftId,
  String? employeeId,
  bool managerMode = false,
  String? employeeName,
  List<Map<String, dynamic>>? candidates,
}) async {
  final ok = await _sheet(
      context,
      _LeaveSheet(
        date: date,
        templates: templates,
        scheduledShiftId: scheduledShiftId,
        employeeId: employeeId,
        managerMode: managerMode,
        employeeName: employeeName,
        candidates: candidates,
      ));
  return ok == true;
}

class _LeaveSheet extends StatefulWidget {
  const _LeaveSheet({
    required this.date,
    required this.templates,
    this.scheduledShiftId,
    this.employeeId,
    this.managerMode = false,
    this.employeeName,
    this.candidates,
  });
  final DateTime date;
  final List<Map<String, dynamic>> templates;
  final String? scheduledShiftId;
  final String? employeeId;
  final bool managerMode;
  final String? employeeName;
  final List<Map<String, dynamic>>? candidates;

  @override
  State<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends State<_LeaveSheet> {
  final _api = ApiService();
  late DateTime _from = widget.date;
  late DateTime _to = widget.date;
  String _type = 'AnnualLeave';
  final Set<String> _shifts = {};
  bool _half = false;
  int _sickMode = 1;
  final _reason = TextEditingController();
  final _bhxh = TextEditingController();
  bool _saving = false;
  num? _annualLeft;
  num? _deduct;
  String _deductKey = '';
  List<Map<String, dynamic>> _candidates = const [];
  Map<String, dynamic>? _replacement;
  bool _approveNow = false;
  bool _countAsWork = false;

  @override
  void initState() {
    super.initState();
    if (widget.scheduledShiftId != null) {
      _shifts.add(widget.scheduledShiftId!);
    } else if (widget.templates.isNotEmpty) {
      _shifts.add(widget.templates.first['id'].toString());
    }
    if (widget.employeeId != null) {
      _api.getAnnualLeaveBalance(widget.employeeId!).then((r) {
        final d = r['data'];
        if (!mounted || r['isSuccess'] != true || d is! Map) return;
        final left = d['remainingDays'] ?? d['remaining'] ?? d['availableDays'];
        if (left is num) setState(() => _annualLeft = left);
      });
    }
    if (widget.candidates != null) {
      _candidates = widget.candidates!.where((c) => c['id']?.toString() != widget.employeeId).toList();
    } else {
      _api.getShiftSwapColleagues(includeNoAccount: true).then((r) {
        final raw = r['data'];
        if (!mounted || r['isSuccess'] != true || raw is! List) return;
        setState(() => _candidates = [
              for (final x in raw)
                if (x is Map && (x['employeeId'] ?? '').toString().isNotEmpty)
                  {
                    'id': x['employeeId'].toString(),
                    'name': x['fullName'] ?? '',
                    // Mã NV giúp phân biệt người trùng tên.
                    'department': [x['employeeCode'], x['department']]
                        .map((v) => '${v ?? ''}'.trim())
                        .where((v) => v.isNotEmpty)
                        .join(' · '),
                  },
            ]);
      });
    }
    _refreshDeduct();
  }

  @override
  void dispose() {
    _reason.dispose();
    _bhxh.dispose();
    super.dispose();
  }

  int get _days => _to.difference(_from).inDays + 1;

  /// Loại nghỉ trừ quỹ phép năm: phép năm, nghỉ ốm dùng phép năm.
  bool get _usesAnnual => !_countAsWork && (_type == 'AnnualLeave' || (_type == 'SickLeave' && _sickMode == 1));

  /// Số ngày phép sẽ trừ (máy chủ bỏ ngày nghỉ lễ / ngày không có ca).
  void _refreshDeduct() {
    final emp = widget.employeeId;
    if (emp == null || !_usesAnnual) {
      if (_deduct != null) setState(() => _deduct = null);
      _deductKey = '';
      return;
    }
    final key = '$emp|$_from|$_to|$_half';
    if (key == _deductKey) return;
    _deductKey = key;
    _api.countAnnualLeaveDays(emp, _from, _to, _half).then((r) {
      final d = r['data'];
      if (!mounted || _deductKey != key) return;
      setState(() => _deduct = r['isSuccess'] == true && d is Map ? d['days'] as num? : null);
    });
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(Duration(days: widget.managerMode ? 90 : 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r != null) {
      setState(() {
        _from = r.start;
        _to = r.end;
      });
      _refreshDeduct();
    }
  }

  Future<void> _pickReplacement() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => _PersonPicker(items: _candidates, title: 'Người thay ca'),
    );
    if (picked != null) setState(() => _replacement = picked);
  }

  Future<void> _save() async {
    if (_shifts.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Xin nghỉ', message: 'Chọn ít nhất 1 ca');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Xin nghỉ', message: 'Vui lòng nhập lý do');
      return;
    }
    if (_type == 'SickLeave' && _sickMode == 2 && _bhxh.text.trim().isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Xin nghỉ', message: 'Nhập số giấy nghỉ / mã hồ sơ BHXH');
      return;
    }
    setState(() => _saving = true);
    final res = await _api.createLeave(
      shiftIds: _shifts.toList(),
      startDate: DateTime(_from.year, _from.month, _from.day),
      endDate: DateTime(_to.year, _to.month, _to.day, 23, 59, 59),
      type: _type,
      isHalfShift: _half,
      reason: _reason.text.trim(),
      replacementEmployeeId: _replacement?['id']?.toString(),
      employeeId: widget.managerMode ? widget.employeeId : null,
      autoApprove: widget.managerMode ? _approveNow : null,
      countAsWork: widget.managerMode ? _countAsWork : null,
      sickLeaveMode: _type == 'SickLeave' ? _sickMode : null,
      bhxhDocumentNote: _type == 'SickLeave' && _sickMode == 2 ? _bhxh.text.trim() : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(res, widget.managerMode && _approveNow ? 'Đã tạo và duyệt đơn nghỉ' : 'Đã gửi đơn nghỉ — chờ duyệt', 'Xin nghỉ');
    if (res['isSuccess'] == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.managerMode
        ? 'Tạo hộ ${widget.employeeName ?? 'nhân viên'}${_annualLeft == null ? '' : ' · phép năm còn $_annualLeft ngày'}'
        : _annualLeft == null
            ? 'Gửi đơn tới quản lý duyệt'
            : 'Phép năm còn lại: $_annualLeft ngày';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(widget.managerMode ? 'Tạo đơn nghỉ' : 'Xin nghỉ phép', sub),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in ShiftUi.leaveTypes.entries)
                ChoiceChip(
                  label: Text(tr(e.value)),
                  selected: _type == e.key,
                  onSelected: (_) {
                    setState(() => _type = e.key);
                    _refreshDeduct();
                  },
                ),
            ]),
          ),
          if (_type == 'SickLeave')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 1, label: Text(tr('Dùng phép năm'))),
                    ButtonSegment(value: 2, label: Text(tr('Hưởng BHXH'))),
                  ],
                  selected: {_sickMode},
                  onSelectionChanged: (v) {
                    setState(() => _sickMode = v.first);
                    _refreshDeduct();
                  },
                ),
                if (_sickMode == 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: _bhxh,
                      decoration: InputDecoration(
                          labelText: tr('Số giấy nghỉ / mã hồ sơ BHXH *'), border: const OutlineInputBorder()),
                    ),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _pickRange,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), alignment: Alignment.centerLeft),
              icon: const Icon(Icons.date_range_rounded),
              label: Text(_days == 1
                  ? '${ShiftUi.weekdaysLong[_from.weekday - 1]}, ${ShiftUi.dmy(_from)}'
                  : '${ShiftUi.dmy(_from)} → ${ShiftUi.dmy(_to)} ($_days ngày)'),
            ),
          ),
          if (_usesAnnual && _deduct != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                tr('Sẽ trừ $_deduct ngày phép năm${_annualLeft != null ? ' (còn $_annualLeft ngày)' : ''}'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _annualLeft != null && _deduct! > _annualLeft! ? SboxColors.danger : SboxColors.slate600,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(tr('Nghỉ ca nào'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in widget.templates)
                FilterChip(
                  avatar: CircleAvatar(backgroundColor: ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt()), radius: 6),
                  label: Text('${t['name']} ${t['start']}–${t['end']}'),
                  selected: _shifts.contains(t['id'].toString()),
                  onSelected: (s) => setState(() => s ? _shifts.add(t['id'].toString()) : _shifts.remove(t['id'].toString())),
                ),
            ]),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: _half,
            onChanged: (v) {
              setState(() => _half = v);
              _refreshDeduct();
            },
            title: Text(tr('Chỉ nghỉ nửa ca')),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.swap_horiz_rounded, color: SboxColors.slate500),
            title: Text(_replacement == null ? tr('Người thay ca (không bắt buộc)') : tr('Người thay ca: ${_replacement!['name']}')),
            subtitle: _candidates.isEmpty ? Text(tr('Không có đồng nghiệp để chọn')) : null,
            trailing: _replacement != null
                ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _replacement = null))
                : const Icon(Icons.chevron_right_rounded),
            onTap: _candidates.isEmpty ? null : _pickReplacement,
          ),
          if (widget.managerMode) ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: _approveNow,
              onChanged: (v) => setState(() => _approveNow = v),
              title: Text(tr('Duyệt luôn khi tạo')),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: _countAsWork,
              onChanged: (v) {
                setState(() => _countAsWork = v);
                _refreshDeduct();
              },
              title: Text(tr('Vẫn tính công')),
              subtitle: Text(tr('Không ghi «Phép» trên chấm công, không trừ phép năm')),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr('Lý do *'), border: const OutlineInputBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.send_rounded),
              label: Text(tr(_saving ? 'Đang gửi…' : (widget.managerMode ? 'Tạo đơn nghỉ' : 'Gửi đơn nghỉ'))),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Chọn một người trong danh sách ({id, name, department}), có ô tìm.
class _PersonPicker extends StatefulWidget {
  const _PersonPicker({required this.items, required this.title});
  final List<Map<String, dynamic>> items;
  final String title;

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.items.where((e) => q.isEmpty || '${e['name']} ${e['department'] ?? ''}'.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(widget.title, '${widget.items.length} người'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm theo tên'), isDense: true, border: const OutlineInputBorder()),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final e in list)
              ListTile(
                title: Text(e['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: '${e['department'] ?? ''}'.isEmpty ? null : Text('${e['department']}'),
                onTap: () => Navigator.pop(context, e),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ═════════════ ĐỔI CA ═════════════

/// Đổi ca với đồng nghiệp: chọn ngày của đồng nghiệp, chọn người + ca của họ, lý do.
Future<bool> showSwapRequestSheet(
  BuildContext context, {
  required DateTime myDate,
  required String myShiftId,
  required String myShiftLabel,
}) async {
  final ok = await _sheet(context, _SwapSheet(myDate: myDate, myShiftId: myShiftId, myShiftLabel: myShiftLabel));
  return ok == true;
}

class _SwapSheet extends StatefulWidget {
  const _SwapSheet({required this.myDate, required this.myShiftId, required this.myShiftLabel});
  final DateTime myDate;
  final String myShiftId;
  final String myShiftLabel;

  @override
  State<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<_SwapSheet> {
  final _api = ApiService();
  late DateTime _date = widget.myDate;
  List<Map<String, dynamic>> _options = [];
  bool _loading = true;
  Map<String, dynamic>? _picked;
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _picked = null;
    });
    final r = await _api.getShiftSwapOptions(_date);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _options = [
        for (final x in (r['data'] as List? ?? const []))
          if (x is Map && !(ShiftUi.key(_date) == ShiftUi.key(widget.myDate) && x['shiftId']?.toString() == widget.myShiftId))
            Map<String, dynamic>.from(x),
      ];
    });
  }

  Future<void> _save() async {
    final p = _picked;
    if (p == null) return;
    setState(() => _saving = true);
    final res = await _api.createShiftSwap(
      targetUserId: p['userId'].toString(),
      requesterShiftId: widget.myShiftId,
      requesterDate: widget.myDate,
      targetShiftId: p['shiftId'].toString(),
      targetDate: _date,
      reason: _reason.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(res, 'Đã gửi yêu cầu — chờ ${p['name']} đồng ý, sau đó quản lý duyệt', 'Đổi ca');
    if (res['isSuccess'] == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('Đổi ca', 'Ca của bạn: ${widget.myShiftLabel} · ${ShiftUi.dmy(widget.myDate)}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text(tr('Đổi lấy ca ngày'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text('${ShiftUi.weekdays[_date.weekday - 1]}, ${ShiftUi.dmy(_date)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 60)),
                  );
                  if (d != null) {
                    _date = d;
                    _load();
                  }
                },
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _options.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(tr('Không có đồng nghiệp nào có ca khác trong ngày này — thử chọn ngày khác'),
                              textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final o in _options)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _choice(
                                selected: identical(_picked, o),
                                color: o['sameDepartment'] == true ? SboxColors.brand600 : SboxColors.slate500,
                                icon: Icons.person_rounded,
                                title: o['name']?.toString() ?? '',
                                subtitle: [o['shift'], o['department']]
                                    .where((x) => (x?.toString() ?? '').isNotEmpty)
                                    .join(' · '),
                                badge: o['sameDepartment'] == true ? ShiftUi.pill('Cùng bộ phận', SboxColors.brand600) : null,
                                onTap: () => setState(() => _picked = o),
                              ),
                            ),
                        ],
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _reason,
              decoration: InputDecoration(labelText: tr('Lý do đổi ca'), border: const OutlineInputBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _saving || _picked == null ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text(tr(_saving ? 'Đang gửi…' : 'Gửi yêu cầu đổi ca')),
            ),
          ),
        ]),
      ),
    );
  }
}
