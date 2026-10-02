import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/allowance_calculator.dart';
import '../widgets/pos/pos_vnd_thousands_formatter.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Kiểu phụ cấp (giá trị server: Fixed, Daily, Hourly, PerEvent, PerShift).
enum AllowanceKind {
  fixed('Fixed', 'Cố định hàng tháng', '/ tháng', Icons.calendar_month_rounded),
  daily('Daily', 'Theo ngày công', '/ ngày công', Icons.today_rounded),
  hourly('Hourly', 'Theo giờ làm', '/ giờ', Icons.schedule_rounded),
  perEvent('PerEvent', 'Theo lần', '/ lần', Icons.flag_rounded),
  perShift('PerShift', 'Theo ca đủ công', '/ ca', Icons.view_timeline_rounded);

  const AllowanceKind(this.code, this.label, this.unit, this.icon);

  /// Theo ngày / theo ca: có thể đặt điều kiện số giờ làm trong ca.
  bool get supportsRule => this == AllowanceKind.daily || this == AllowanceKind.perShift;
  final String code;
  final String label;
  final String unit;
  final IconData icon;

  static AllowanceKind parse(dynamic v) {
    if (v is num) return AllowanceKind.values[v.toInt().clamp(0, 4)];
    final s = '$v'.toLowerCase().replaceAll('_', '');
    return AllowanceKind.values.firstWhere((k) => k.code.toLowerCase() == s || '${k.index}' == s, orElse: () => AllowanceKind.fixed);
  }
}

class _Allowance {
  _Allowance(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String get name => '${m['name'] ?? ''}';
  String? get code => m['code']?.toString();
  AllowanceKind get kind => AllowanceKind.parse(m['type']);
  double get amount => (m['amount'] as num?)?.toDouble() ?? 0;
  bool get active => m['isActive'] != false;
  bool get taxable => m['isTaxable'] != false;
  bool get insurance => m['isInsuranceApplicable'] == true;
  DateTime? get start => DateTime.tryParse('${m['startDate']}');
  DateTime? get end => DateTime.tryParse('${m['endDate']}');
  List<String> _list(String k) {
    final v = m[k];
    if (v is List) return [for (final x in v) '$x'];
    if (v is String && v.isNotEmpty) {
      try {
        final d = jsonDecode(v);
        if (d is List) return [for (final x in d) '$x'];
      } catch (_) {}
    }
    return [];
  }

  List<String> get employeeIds => _list('employeeIds');
  List<String> get shiftIds => _list('shiftIds');
  double? get minWorkPercent => AllowanceCalculator.minWorkPercent(m);
  double? get minWorkHours => AllowanceCalculator.minWorkHours(m);
  bool get hasRule => kind.supportsRule && AllowanceCalculator.hasWorkRule(m);
}

/// Phụ cấp: danh sách theo kiểu, bật / tắt nhanh, chịu thuế / đóng BH, áp dụng cho ai, theo ca.
class AllowanceSettingsScreen extends StatefulWidget {
  const AllowanceSettingsScreen({super.key, this.canEditOverride});

  final bool? canEditOverride;

  @override
  State<AllowanceSettingsScreen> createState() => _AllowanceSettingsScreenState();
}

class _AllowanceSettingsScreenState extends State<AllowanceSettingsScreen> {
  final _api = ApiService();
  List<_Allowance> _items = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _shifts = [];
  bool _loading = true;
  AllowanceKind? _filter;

  bool _can(String a) {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      final p = Provider.of<PermissionProvider>(context, listen: false);
      return a == 'create' ? p.canCreate('Allowance') : a == 'edit' ? p.canEdit('Allowance') : p.canDelete('Allowance');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await Future.wait<List<dynamic>>([
      _api.getAllowanceSettings(),
      _api.getEmployeesForSelect(pageSize: 500),
      _api.getShifts(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = [for (final a in res[0].whereType<Map>()) _Allowance(Map<String, dynamic>.from(a))];
      _employees = [for (final e in res[1].whereType<Map>()) Map<String, dynamic>.from(e)];
      _shifts = [for (final s in res[2].whereType<Map>()) Map<String, dynamic>.from(s)];
      _loading = false;
    });
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  Map<String, dynamic> _payload(_Allowance a, {bool? active}) => {
        'name': a.name,
        'code': a.code,
        'description': a.m['description'],
        'type': a.kind.code,
        'amount': a.amount,
        'currency': 'VND',
        'isTaxable': a.taxable,
        'isInsuranceApplicable': a.insurance,
        'isActive': active ?? a.active,
        if (a.start != null) 'startDate': a.start!.toIso8601String(),
        if (a.end != null) 'endDate': a.end!.toIso8601String(),
        if (a.employeeIds.isNotEmpty) 'employeeIds': a.employeeIds,
        if (a.kind == AllowanceKind.perShift) 'shiftIds': a.shiftIds,
        if (a.minWorkPercent != null) 'minWorkPercent': a.minWorkPercent,
        if (a.minWorkHours != null) 'minWorkHours': a.minWorkHours,
      };

  Future<void> _toggle(_Allowance a, bool v) async {
    final r = await _api.updateAllowanceSetting(a.id, _payload(a, active: v));
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      setState(() => a.m['isActive'] = v);
    } else {
      _toast(r['message']?.toString() ?? 'Không cập nhật được', error: true);
    }
  }

  Future<void> _edit([_Allowance? a]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AllowanceEditor(item: a, employees: _employees, shifts: _shifts),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(_Allowance a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa phụ cấp "${a.name}"?')),
        content: Text(tr('Bảng lương đã chốt giữ nguyên. Muốn ngừng áp dụng mà giữ lịch sử, hãy tắt phụ cấp thay vì xóa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.deleteAllowanceSetting(a.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      _toast(r['message']?.toString() ?? 'Không xóa được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _items.where((a) => _filter == null || a.kind == _filter).toList()
      ..sort((a, b) => a.active != b.active ? (a.active ? -1 : 1) : a.name.compareTo(b.name));
    final monthly = _items.where((a) => a.active && a.kind == AllowanceKind.fixed && a.employeeIds.isEmpty).fold<double>(0, (s, a) => s + a.amount);
    return SettingsPage(
      title: 'Phụ cấp',
      subtitle: 'Khoản cộng thêm vào lương: cố định, theo ngày công, theo giờ, theo lần, theo ca',
      icon: Icons.card_giftcard_outlined,
      loading: _loading,
      headerActions: [
        if (_can('create'))
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: SboxButton(label: 'Thêm phụ cấp', icon: Icons.add, onPressed: () => _edit()),
          ),
      ],
      children: [
        if (_items.isNotEmpty)
          SettingsNote(
              '${_items.where((a) => a.active).length}/${_items.length} phụ cấp đang áp dụng. Phụ cấp cố định cho mọi nhân viên: ${settingsMoney(monthly)} ₫ / người / tháng.',
              icon: Icons.summarize_outlined,
              tone: SboxTone.neutral),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(tr('Tất cả (${_items.length})')), selected: _filter == null, showCheckmark: false, onSelected: (_) => setState(() => _filter = null)),
            ),
            for (final k in AllowanceKind.values)
              if (_items.any((a) => a.kind == k))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(k.icon, size: 16),
                    label: Text(tr('${k.label} (${_items.where((a) => a.kind == k).length})')),
                    selected: _filter == k,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = k),
                  ),
                ),
          ]),
        ),
        if (_items.isEmpty)
          SboxEmptyState(
            icon: Icons.card_giftcard_outlined,
            title: 'Chưa có phụ cấp',
            message: 'Ví dụ: phụ cấp ăn trưa theo ngày công, xăng xe cố định, chuyên cần, ca đêm theo ca.',
            action: _can('create') ? SboxButton(label: 'Thêm phụ cấp', icon: Icons.add, onPressed: () => _edit()) : null,
          ),
        for (final a in list) _card(a),
      ],
    );
  }

  Widget _card(_Allowance a) {
    final shiftNames = a.kind == AllowanceKind.perShift
        ? a.shiftIds.map((id) => _shifts.where((s) => '${s['id']}' == id).map((s) => '${s['name']}').firstOrNull).whereType<String>().join(', ')
        : '';
    String d(DateTime x) => '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
    return SboxCard(
      onTap: _can('edit') ? () => _edit(a) : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: a.active ? SboxColors.violetSoft : SboxColors.slate100, borderRadius: BorderRadius.circular(12)),
          child: Icon(a.kind.icon, color: a.active ? SboxColors.violet : SboxColors.slate400),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(tr(a.name),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: a.active ? SboxColors.slate900 : SboxColors.slate400)),
              ),
              if ((a.code ?? '').isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(a.code!, style: const TextStyle(fontSize: 12, color: SboxColors.slate400)),
              ],
            ]),
            Text('${settingsMoney(a.amount)} ₫ ${tr(a.kind.unit)}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              SboxStatusChip(label: a.kind.label, icon: a.kind.icon, tone: SboxTone.violet),
              SboxStatusChip(label: a.employeeIds.isEmpty ? 'Tất cả nhân viên' : '${a.employeeIds.length} nhân viên', icon: Icons.people_outline),
              if (shiftNames.isNotEmpty) SboxStatusChip(label: 'Ca: $shiftNames', icon: Icons.schedule_rounded),
              if (a.hasRule)
                SboxStatusChip(
                  label: a.minWorkPercent != null
                      ? 'Làm từ ${settingsMoney(a.minWorkPercent!)}% ca'
                      : 'Làm từ ${AllowanceCalculator.fmtMinutes((a.minWorkHours! * 60).round())}',
                  icon: Icons.timer_outlined,
                  tone: SboxTone.brand,
                ),
              if (a.taxable) const SboxStatusChip(label: 'Chịu thuế', tone: SboxTone.warning) else const SboxStatusChip(label: 'Miễn thuế', tone: SboxTone.success),
              if (a.insurance) const SboxStatusChip(label: 'Tính đóng BH', tone: SboxTone.brand),
              if (a.start != null || a.end != null)
                SboxStatusChip(label: '${a.start != null ? 'từ ${d(a.start!)}' : ''}${a.end != null ? ' đến ${d(a.end!)}' : ''}'.trim(), icon: Icons.event_rounded),
            ]),
          ]),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: a.active, onChanged: _can('edit') ? (v) => _toggle(a, v) : null),
          if (_can('delete'))
            IconButton(tooltip: tr('Xóa'), onPressed: () => _delete(a), icon: const Icon(Icons.delete_outline_rounded, color: SboxColors.slate400)),
        ]),
      ]),
    );
  }
}

class _AllowanceEditor extends StatefulWidget {
  const _AllowanceEditor({required this.item, required this.employees, required this.shifts});
  final _Allowance? item;
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> shifts;

  @override
  State<_AllowanceEditor> createState() => _AllowanceEditorState();
}

class _AllowanceEditorState extends State<_AllowanceEditor> {
  final _api = ApiService();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _code = TextEditingController(text: widget.item?.code ?? '');
  late final _amount = TextEditingController(text: widget.item == null ? '' : settingsMoney(widget.item!.amount));
  late final _desc = TextEditingController(text: '${widget.item?.m['description'] ?? ''}');
  late AllowanceKind _kind = widget.item?.kind ?? AllowanceKind.fixed;
  late bool _taxable = widget.item?.taxable ?? true;
  late bool _insurance = widget.item?.insurance ?? false;
  late DateTime? _start = widget.item?.start;
  late DateTime? _end = widget.item?.end;
  late final Set<String> _emps = {...?widget.item?.employeeIds};
  late final Set<String> _shiftIds = {...?widget.item?.shiftIds};
  late bool _all = _emps.isEmpty;
  /// 0 = không điều kiện, 1 = % thời lượng ca, 2 = số giờ.
  late int _ruleMode = widget.item?.minWorkPercent != null ? 1 : (widget.item?.minWorkHours != null ? 2 : 0);
  late final _rulePct = TextEditingController(text: _fmtNum(widget.item?.minWorkPercent ?? 90));
  late final _ruleHours = TextEditingController(text: _fmtNum(widget.item?.minWorkHours ?? 4.5));
  String _q = '';

  static String _fmtNum(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v'.replaceAll('.', ',');
  static double? _parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  /// Điều kiện hiện tại dạng map để mô tả / kiểm tra.
  Map<String, dynamic> get _ruleMap => {
        if (_ruleMode == 1) 'minWorkPercent': _parseNum(_rulePct.text),
        if (_ruleMode == 2) 'minWorkHours': _parseNum(_ruleHours.text),
      };
  bool _saving = false;

  static const _quick = <(String, AllowanceKind, double, bool)>[
    ('Ăn trưa', AllowanceKind.daily, 30000, false),
    ('Xăng xe', AllowanceKind.fixed, 500000, true),
    ('Điện thoại', AllowanceKind.fixed, 300000, true),
    ('Chuyên cần', AllowanceKind.fixed, 500000, true),
    ('Ca đêm', AllowanceKind.perShift, 50000, true),
  ];

  @override
  void dispose() {
    for (final c in [_name, _code, _amount, _desc, _rulePct, _ruleHours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = PosVndThousandsFormatter.parse(_amount.text);
    String? err;
    if (_name.text.trim().isEmpty) err = 'Nhập tên phụ cấp';
    if (amount <= 0) err ??= 'Nhập số tiền';
    if (_kind == AllowanceKind.perShift && _shiftIds.isEmpty) err ??= 'Chọn ít nhất 1 ca được hưởng';
    if (_kind.supportsRule && _ruleMode == 1) {
      final p = _parseNum(_rulePct.text);
      if (p == null || p <= 0 || p > 100) err ??= 'Nhập % thời lượng ca từ 1 đến 100';
    }
    if (_kind.supportsRule && _ruleMode == 2) {
      final h = _parseNum(_ruleHours.text);
      if (h == null || h <= 0 || h > 24) err ??= 'Nhập số giờ tối thiểu từ 0,5 đến 24';
    }
    if (!_all && _emps.isEmpty) err ??= 'Chọn nhân viên hoặc bật «Tất cả nhân viên»';
    if (_start != null && _end != null && _end!.isBefore(_start!)) err ??= 'Ngày kết thúc phải sau ngày bắt đầu';
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(err))));
      return;
    }
    setState(() => _saving = true);
    final data = {
      'name': _name.text.trim(),
      'code': _code.text.trim().isEmpty ? null : _code.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'type': _kind.code,
      'amount': amount,
      'currency': 'VND',
      'isTaxable': _taxable,
      'isInsuranceApplicable': _insurance,
      'isActive': widget.item?.active ?? true,
      if (_start != null) 'startDate': _start!.toIso8601String(),
      if (_end != null) 'endDate': _end!.toIso8601String(),
      if (!_all) 'employeeIds': _emps.toList(),
      if (_kind == AllowanceKind.perShift) 'shiftIds': _shiftIds.toList(),
      'minWorkPercent': _kind.supportsRule && _ruleMode == 1 ? _parseNum(_rulePct.text) : null,
      'minWorkHours': _kind.supportsRule && _ruleMode == 2 ? _parseNum(_ruleHours.text) : null,
    };
    final r = widget.item == null ? await _api.createAllowanceSetting(data) : await _api.updateAllowanceSetting(widget.item!.id, data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('${r['message'] ?? 'Không lưu được'}'))));
    }
  }

  Future<void> _pickDate(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => start ? _start = d : _end = d);
  }

  /// Điều kiện nhận: chỉ tính ngày / ca làm đủ thời gian trong khung ca.
  List<Widget> _ruleSection() {
    final ruleText = _ruleMode == 0 ? null : AllowanceCalculator.describeRule(_ruleMap);
    return [
      const SizedBox(height: 14),
      Text(tr('Điều kiện nhận'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 0, label: Text(tr('Không điều kiện'))),
          ButtonSegment(value: 1, label: Text(tr('% thời lượng ca'))),
          ButtonSegment(value: 2, label: Text(tr('Số giờ tối thiểu'))),
        ],
        selected: {_ruleMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _ruleMode = s.first),
      ),
      if (_ruleMode == 1) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _rulePct,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('Làm tối thiểu'), suffixText: '% ca', isDense: true, border: const OutlineInputBorder()),
        ),
      ],
      if (_ruleMode == 2) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _ruleHours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('Làm tối thiểu'), suffixText: tr('giờ trong ca'), isDense: true, border: const OutlineInputBorder()),
        ),
      ],
      const SizedBox(height: 6),
      Text(
        tr(ruleText == null
            ? (_kind == AllowanceKind.daily
                ? 'Mọi ngày có công đều được tính (nửa công = nửa phụ cấp).'
                : 'Mọi ca có chấm vào và ra đều được tính.')
            : '$ruleText. Chỉ tính thời gian trong khung ca, đã trừ nghỉ giữa ca — đến sớm / ở lại muộn không bù cho đi muộn / về sớm.'
                '${_kind == AllowanceKind.daily ? ' Ngày làm nhiều ca: cộng thời gian các ca. Không có ca: so với giờ chuẩn / ngày trong hồ sơ lương.' : ''}'),
        style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    String nameOf(Map<String, dynamic> e) => ('${e['lastName'] ?? ''} ${e['firstName'] ?? ''}').trim().isEmpty
        ? '${e['fullName'] ?? e['employeeCode'] ?? ''}'
        : ('${e['lastName'] ?? ''} ${e['firstName'] ?? ''}').trim();
    final q = _q.trim().toLowerCase();
    final shown = widget.employees.where((e) => q.isEmpty || nameOf(e).toLowerCase().contains(q)).take(80).toList();
    String d(DateTime? x) => x == null ? '—' : '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
    return AlertDialog(
      title: Text(tr(widget.item == null ? 'Thêm phụ cấp' : 'Sửa phụ cấp')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.item == null) ...[
              Text(tr('Mẫu nhanh'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (n, k, amt, tax) in _quick)
                  ActionChip(
                    label: Text(tr(n)),
                    onPressed: () => setState(() {
                      _name.text = 'Phụ cấp ${n.toLowerCase()}';
                      _kind = k;
                      _amount.text = settingsMoney(amt);
                      _taxable = tax;
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(controller: _name, decoration: InputDecoration(labelText: tr('Tên phụ cấp *'), isDense: true, border: const OutlineInputBorder())),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(controller: _code, decoration: InputDecoration(labelText: tr('Mã'), isDense: true, border: const OutlineInputBorder())),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<AllowanceKind>(
              initialValue: _kind,
              decoration: InputDecoration(labelText: tr('Cách tính'), isDense: true, border: const OutlineInputBorder()),
              items: [for (final k in AllowanceKind.values) DropdownMenuItem(value: k, child: Text(tr(k.label)))],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [PosVndThousandsFormatter()],
              decoration: InputDecoration(labelText: tr('Số tiền'), suffixText: '₫ ${tr(_kind.unit)}', isDense: true, border: const OutlineInputBorder()),
            ),
            if (_kind == AllowanceKind.perShift) ...[
              const SizedBox(height: 12),
              Text(tr('Ca được hưởng'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in widget.shifts)
                  FilterChip(
                    label: Text(tr('${s['name']}')),
                    selected: _shiftIds.contains('${s['id']}'),
                    onSelected: (v) => setState(() => v ? _shiftIds.add('${s['id']}') : _shiftIds.remove('${s['id']}')),
                  ),
              ]),
            ],
            if (_kind.supportsRule) ..._ruleSection(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _taxable,
              onChanged: (v) => setState(() => _taxable = v),
              title: Text(tr('Tính vào thu nhập chịu thuế TNCN')),
              subtitle: Text(tr('Tắt với khoản được miễn thuế (vd ăn giữa ca trong mức quy định)')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _insurance,
              onChanged: (v) => setState(() => _insurance = v),
              title: Text(tr('Tính vào lương đóng bảo hiểm')),
            ),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.event_rounded, size: 18), label: Text(tr('Từ ${d(_start)}')))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.event_busy_rounded, size: 18), label: Text(tr('Đến ${d(_end)}')))),
              if (_start != null || _end != null)
                IconButton(tooltip: tr('Bỏ thời hạn'), onPressed: () => setState(() => _start = _end = null), icon: const Icon(Icons.close_rounded)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _all,
              onChanged: (v) => setState(() => _all = v),
              title: Text(tr('Áp dụng cho tất cả nhân viên')),
              subtitle: Text(tr(_all ? 'Tắt để chọn riêng nhân viên' : 'Đã chọn ${_emps.length} nhân viên')),
            ),
            if (!_all) ...[
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm nhân viên'), isDense: true, border: const OutlineInputBorder()),
              ),
              SizedBox(
                height: 200,
                child: ListView(children: [
                  for (final e in shown)
                    CheckboxListTile(
                      dense: true,
                      value: _emps.contains('${e['id']}'),
                      onChanged: (v) => setState(() => v == true ? _emps.add('${e['id']}') : _emps.remove('${e['id']}')),
                      title: Text(tr(nameOf(e))),
                      subtitle: Text(tr('${e['employeeCode'] ?? ''}')),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            TextField(controller: _desc, decoration: InputDecoration(labelText: tr('Ghi chú'), isDense: true, border: const OutlineInputBorder())),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Lưu'))),
      ],
    );
  }
}
