import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/lunar_converter.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Mẫu ngày lễ Việt Nam. Âm lịch được quy đổi theo từng năm.
class HolidayPreset {
  const HolidayPreset(this.name, this.category, this.rate, {this.month, this.day, this.lunarMonth, this.lunarDay});
  final String name;
  final String category;
  final double rate;
  final int? month;
  final int? day;
  final int? lunarMonth;
  final int? lunarDay;

  bool get lunar => lunarMonth != null;

  static const official = 'Ngày nghỉ chính thức';
  static const compensate = 'Ngày nghỉ bù';

  static const all = <HolidayPreset>[
    HolidayPreset('Tết Dương lịch', official, 3, month: 1, day: 1),
    HolidayPreset('Tết Nguyên Đán (30 Tết)', official, 3, lunarMonth: 12, lunarDay: 30),
    HolidayPreset('Tết Nguyên Đán (Mùng 1)', official, 3, lunarMonth: 1, lunarDay: 1),
    HolidayPreset('Tết Nguyên Đán (Mùng 2)', official, 3, lunarMonth: 1, lunarDay: 2),
    HolidayPreset('Tết Nguyên Đán (Mùng 3)', official, 3, lunarMonth: 1, lunarDay: 3),
    HolidayPreset('Tết Nguyên Đán (Mùng 4)', official, 3, lunarMonth: 1, lunarDay: 4),
    HolidayPreset('Tết Nguyên Đán (Mùng 5)', compensate, 2, lunarMonth: 1, lunarDay: 5),
    HolidayPreset('Giỗ Tổ Hùng Vương (10/3 ÂL)', official, 3, lunarMonth: 3, lunarDay: 10),
    HolidayPreset('Ngày Giải phóng miền Nam', official, 3, month: 4, day: 30),
    HolidayPreset('Ngày Quốc tế Lao động', official, 3, month: 5, day: 1),
    HolidayPreset('Ngày Quốc khánh', official, 3, month: 9, day: 2),
    HolidayPreset('Ngày nghỉ bù Quốc khánh', compensate, 2, month: 9, day: 3),
  ];

  /// Ngày dương lịch của mẫu trong [year]. 30 Tết thuộc năm âm trước (tháng Chạp có thể chỉ 29 ngày).
  DateTime dateIn(int year) {
    if (!lunar) return DateTime(year, month!, day!);
    final ly = lunarMonth == 12 ? year - 1 : year;
    var d = lunarDay!;
    final maxDay = LunarConverter.lunarMonthDays(ly, lunarMonth!);
    if (d > maxDay) d = maxDay;
    return LunarConverter.lunarToSolar(ly, lunarMonth!, d);
  }
}

class _Holiday {
  _Holiday(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String get name => '${m['name'] ?? ''}';
  DateTime get date => DateTime.tryParse('${m['date']}')?.toLocal() ?? DateTime.now();
  String get category => '${m['category'] ?? HolidayPreset.official}';
  double get rate => (m['salaryRate'] as num?)?.toDouble() ?? 3;
  bool get recurring => m['isRecurring'] == true;
  bool get projected => m['isProjected'] == true;
  int? get originYear => (m['originYear'] as num?)?.toInt();
  List<String> get employeeIds => [for (final e in (m['employeeIds'] as List? ?? const [])) '$e'];
  String get description => '${m['description'] ?? ''}';
}

/// Ngày lễ: theo năm, nhóm theo tháng, âm lịch, thêm nhanh ngày lễ chuẩn, hệ số lương, áp dụng cho ai.
class HolidaySettingsScreen extends StatefulWidget {
  const HolidaySettingsScreen({super.key, this.canEditOverride, this.initialYear});

  final bool? canEditOverride;
  final int? initialYear;

  @override
  State<HolidaySettingsScreen> createState() => _HolidaySettingsScreenState();
}

class _HolidaySettingsScreenState extends State<HolidaySettingsScreen> {
  final _api = ApiService();
  late int _year = widget.initialYear ?? DateTime.now().year;
  List<_Holiday> _items = [];
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;
  bool _busy = false;

  bool _can(String a) {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      final p = Provider.of<PermissionProvider>(context, listen: false);
      return a == 'create' ? p.canCreate('Holiday') : a == 'edit' ? p.canEdit('Holiday') : p.canDelete('Holiday');
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
    final list = await _api.getHolidaySettings(_year);
    if (!mounted) return;
    setState(() {
      _items = [for (final h in list.whereType<Map>()) _Holiday(Map<String, dynamic>.from(h))]..sort((a, b) => a.date.compareTo(b.date));
      _loading = false;
    });
  }

  void _goYear(int delta) {
    setState(() => _year += delta);
    _load();
  }

  Future<List<Map<String, dynamic>>> _emps() async {
    if (_employees.isNotEmpty) return _employees;
    final list = await _api.getEmployeesForSelect();
    _employees = [for (final e in list.whereType<Map>()) Map<String, dynamic>.from(e)];
    return _employees;
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  /// Các mẫu chưa có trong năm (so theo ngày).
  List<(HolidayPreset, DateTime)> get _missingPresets {
    final have = _items.map((h) => '${h.date.month}-${h.date.day}').toSet();
    return [
      for (final p in HolidayPreset.all)
        if (!have.contains('${p.dateIn(_year).month}-${p.dateIn(_year).day}')) (p, p.dateIn(_year)),
    ];
  }

  Future<void> _addPresets() async {
    final missing = _missingPresets;
    if (missing.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thêm ${missing.length} ngày lễ chuẩn năm $_year?')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (p, d) in missing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('•  ${_dm(d)}  ${tr(p.name)}${p.lunar ? ' (âm lịch)' : ''}'),
              ),
            const SizedBox(height: 8),
            Text(tr('Ngày dương lịch cố định được đánh dấu lặp hằng năm; ngày âm lịch chỉ thêm cho năm $_year.'),
                style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Thêm'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    var added = 0;
    for (final (p, d) in missing) {
      final r = await _api.createHolidaySetting({
        'name': p.name,
        'date': _iso(d),
        'salaryRate': p.rate,
        'isActive': true,
        'isRecurring': !p.lunar,
        'category': p.category,
        'employeeIds': <String>[],
      });
      if (r['isSuccess'] == true) added++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _toast('Đã thêm $added/${missing.length} ngày lễ');
    _load();
  }

  Future<void> _edit([_Holiday? h]) async {
    final emps = await _emps();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _HolidayEditor(holiday: h, year: _year, employees: emps),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(_Holiday h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa "${h.name}"?')),
        content: Text(tr(h.recurring ? 'Ngày lễ lặp hằng năm — xóa sẽ mất ở mọi năm.' : 'Chỉ xóa ngày lễ của năm $_year.')),
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
    final r = await _api.deleteHolidaySetting(h.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      _toast(r['message']?.toString() ?? 'Không xóa được', error: true);
    }
  }

  static String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = _items.where((h) => !h.date.isBefore(DateTime(now.year, now.month, now.day))).firstOrNull;
    final missing = _loading ? const <(HolidayPreset, DateTime)>[] : _missingPresets;
    final byMonth = <int, List<_Holiday>>{};
    for (final h in _items) {
      (byMonth[h.date.month] ??= []).add(h);
    }
    final days = _items.length;
    return SettingsPage(
      title: 'Ngày lễ',
      subtitle: 'Ngày nghỉ lễ và hệ số lương khi đi làm ngày lễ — bảng công, bảng lương dùng danh sách này',
      icon: Icons.celebration_outlined,
      loading: _loading,
      headerActions: [
        if (_can('create'))
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: SboxButton(label: 'Thêm ngày lễ', icon: Icons.add, onPressed: () => _edit()),
          ),
      ],
      children: [
        SboxCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(children: [
            IconButton(onPressed: () => _goYear(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Text('$_year', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            IconButton(onPressed: () => _goYear(1), icon: const Icon(Icons.chevron_right_rounded)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('$days ngày lễ${upcoming != null && _year == now.year ? ' · sắp tới: ${upcoming.name} (${_dm(upcoming.date)})' : ''}'),
                style: const TextStyle(color: SboxColors.slate600),
              ),
            ),
          ]),
        ),
        if (missing.isNotEmpty && _can('create'))
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.event_note_rounded, color: SboxColors.warningText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('Năm $_year còn thiếu ${missing.length} ngày lễ chuẩn (${missing.take(3).map((e) => e.$1.name).join(', ')}${missing.length > 3 ? '…' : ''}).'),
                    style: const TextStyle(color: SboxColors.warningText, fontWeight: FontWeight.w600)),
              ),
              SboxButton(label: 'Thêm ngày lễ chuẩn', icon: Icons.auto_fix_high_rounded, loading: _busy, onPressed: _busy ? null : _addPresets),
            ]),
          ),
        if (_items.isEmpty)
          SboxEmptyState(icon: Icons.event_busy_outlined, title: 'Chưa có ngày lễ năm $_year'),
        for (final e in byMonth.entries)
          SettingsSection(
            title: 'Tháng ${e.key}',
            icon: Icons.calendar_month_outlined,
            children: [
              for (var i = 0; i < e.value.length; i++) _row(e.value[i], i > 0),
            ],
          ),
      ],
    );
  }

  Widget _row(_Holiday h, bool divider) {
    final lunar = LunarConverter.solarToLunar(h.date);
    final weekend = h.date.weekday >= 6;
    return Column(children: [
      if (divider) const Divider(height: 1, color: SboxColors.divider),
      InkWell(
        onTap: _can('edit') ? () => _edit(h) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: h.category == HolidayPreset.official ? SboxColors.dangerSoft : SboxColors.brand50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(children: [
                Text('${h.date.day}',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: h.category == HolidayPreset.official ? SboxColors.dangerText : SboxColors.brand700)),
                Text('ÂL ${lunar.day}/${lunar.month}', style: const TextStyle(fontSize: 10.5, color: SboxColors.slate500)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(h.name), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  SboxStatusChip(label: _weekdays[h.date.weekday - 1], tone: weekend ? SboxTone.warning : SboxTone.neutral),
                  SboxStatusChip(label: h.category, tone: h.category == HolidayPreset.official ? SboxTone.danger : SboxTone.brand),
                  SboxStatusChip(label: 'Lương x${settingsNum(h.rate)}', tone: SboxTone.success),
                  if (h.recurring)
                    SboxStatusChip(label: h.projected ? 'Hằng năm (từ ${h.originYear})' : 'Hằng năm', icon: Icons.repeat_rounded),
                  if (h.employeeIds.isNotEmpty) SboxStatusChip(label: '${h.employeeIds.length} nhân viên', icon: Icons.people_outline),
                ]),
              ]),
            ),
            if (_can('delete'))
              IconButton(
                tooltip: tr('Xóa'),
                onPressed: () => _delete(h),
                icon: const Icon(Icons.delete_outline_rounded, color: SboxColors.slate400),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _HolidayEditor extends StatefulWidget {
  const _HolidayEditor({required this.holiday, required this.year, required this.employees});
  final _Holiday? holiday;
  final int year;
  final List<Map<String, dynamic>> employees;

  @override
  State<_HolidayEditor> createState() => _HolidayEditorState();
}

class _HolidayEditorState extends State<_HolidayEditor> {
  final _api = ApiService();
  late final _name = TextEditingController(text: widget.holiday?.name ?? '');
  late final _desc = TextEditingController(text: widget.holiday?.description ?? '');
  late DateTime _date = widget.holiday?.date ?? DateTime(widget.year, DateTime.now().month, DateTime.now().day);
  late String _category = widget.holiday?.category ?? HolidayPreset.official;
  late double _rate = widget.holiday?.rate ?? 3;
  late bool _recurring = widget.holiday?.recurring ?? false;
  late Set<String> _emps = {...?widget.holiday?.employeeIds};
  late bool _all = _emps.isEmpty;
  String _q = '';
  bool _saving = false;

  static const _categories = [HolidayPreset.official, HolidayPreset.compensate, 'Ngày nghỉ hàng tuần', 'Ngày đặc biệt công ty'];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final data = {
      'name': _name.text.trim(),
      'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      'salaryRate': _rate,
      'isActive': true,
      'isRecurring': _recurring,
      'category': _category,
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'employeeIds': _all ? <String>[] : _emps.toList(),
    };
    final r = widget.holiday == null
        ? await _api.createHolidaySetting(data)
        : await _api.updateHolidaySetting(widget.holiday!.id, data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('${r['message'] ?? 'Không lưu được'}'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lunar = LunarConverter.solarToLunar(_date);
    final q = _q.trim().toLowerCase();
    String nameOf(Map<String, dynamic> e) => ('${e['lastName'] ?? ''} ${e['firstName'] ?? ''}').trim().isEmpty
        ? '${e['fullName'] ?? e['employeeCode'] ?? ''}'
        : ('${e['lastName'] ?? ''} ${e['firstName'] ?? ''}').trim();
    final shown = widget.employees.where((e) => q.isEmpty || nameOf(e).toLowerCase().contains(q)).take(80).toList();
    return AlertDialog(
      title: Text(tr(widget.holiday == null ? 'Thêm ngày lễ' : 'Sửa ngày lễ')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.holiday?.projected == true)
              SettingsNote('Ngày lễ lặp hằng năm tạo từ năm ${widget.holiday!.originYear}. Sửa sẽ áp dụng cho mọi năm.',
                  icon: Icons.repeat_rounded, tone: SboxTone.neutral),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('Tên ngày lễ *'), isDense: true, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(widget.year - 2),
                  lastDate: DateTime(widget.year + 3, 12, 31),
                );
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(labelText: tr('Ngày'), isDense: true, border: const OutlineInputBorder()),
                child: Text(tr('${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'
                    ' · âm lịch ${lunar.day}/${lunar.month}')),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
              title: Text(tr('Lặp lại hằng năm')),
              subtitle: Text(tr('Chỉ dùng cho ngày dương lịch cố định (1/1, 30/4…). Ngày âm lịch nên thêm theo từng năm.')),
            ),
            DropdownButtonFormField<String>(
              initialValue: _categories.contains(_category) ? _category : _categories.first,
              decoration: InputDecoration(labelText: tr('Loại ngày'), isDense: true, border: const OutlineInputBorder()),
              items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(tr(c)))],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            Text(tr('Hệ số lương khi đi làm ngày này'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final r in const [1.0, 1.5, 2.0, 3.0, 4.0])
                ChoiceChip(label: Text('x${settingsNum(r)}'), selected: _rate == r, showCheckmark: false, onSelected: (_) => setState(() => _rate = r)),
            ]),
            const SizedBox(height: 12),
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
