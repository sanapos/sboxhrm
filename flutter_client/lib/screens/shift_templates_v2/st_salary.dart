import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_vnd_thousands_formatter.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'st_common.dart';

/// Kiểu tính lương ca (giá trị lưu: fixed / multiplier / hourly).
enum ShiftRateType {
  fixed('fixed', 'Cố định / ca', Icons.payments_outlined),
  multiplier('multiplier', 'Nhân hệ số', Icons.trending_up_rounded),
  hourly('hourly', 'Theo giờ', Icons.schedule_rounded);

  const ShiftRateType(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;

  static ShiftRateType parse(String? v) =>
      ShiftRateType.values.firstWhere((e) => e.code == v, orElse: () => ShiftRateType.fixed);
}

String shiftRateText(Map<String, dynamic> l) {
  final t = ShiftRateType.parse(l['rateType']?.toString());
  num n(String k) => (l[k] as num?) ?? num.tryParse('${l[k]}') ?? 0;
  return switch (t) {
    ShiftRateType.fixed => '${SboxFmt.money(n('fixedRate'))} / ca',
    ShiftRateType.hourly => '${SboxFmt.money(n('hourlyRate'))} / giờ',
    ShiftRateType.multiplier => 'Hệ số x${n('multiplier')}',
  };
}

/// Danh sách mức lương của 1 ca + thêm / sửa / xóa.
class ShiftSalaryLevelsPanel extends StatefulWidget {
  const ShiftSalaryLevelsPanel({super.key, required this.shiftId, required this.shiftName});

  final String shiftId;
  final String shiftName;

  @override
  State<ShiftSalaryLevelsPanel> createState() => _ShiftSalaryLevelsPanelState();
}

class _ShiftSalaryLevelsPanelState extends State<ShiftSalaryLevelsPanel> {
  final _api = ApiService();
  List<Map<String, dynamic>> _levels = [];
  List<_Emp>? _emps;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getShiftSalaryLevels();
    if (!mounted) return;
    final d = r['data'];
    final items = d is Map ? d['items'] : d;
    setState(() {
      _levels = [
        if (items is List)
          for (final l in items.whereType<Map>())
            if (l['shiftTemplateId']?.toString() == widget.shiftId) Map<String, dynamic>.from(l),
      ]..sort((a, b) => ((a['sortOrder'] as num?) ?? 0).compareTo((b['sortOrder'] as num?) ?? 0));
      _loading = false;
    });
  }

  Future<List<_Emp>> _employees() async {
    if (_emps != null) return _emps!;
    final list = await _api.getEmployeesForSelect();
    _emps = [
      for (final e in list.whereType<Map>())
        _Emp(
          '${e['id']}',
          ('${e['lastName'] ?? ''} ${e['firstName'] ?? ''}').trim().isEmpty
              ? '${e['fullName'] ?? e['employeeCode'] ?? ''}'
              : ('${e['lastName'] ?? ''} ${e['firstName'] ?? ''}').trim(),
          e['employeeCode']?.toString(),
          (e['departmentName'] ?? e['department'])?.toString(),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return _emps!;
  }

  Future<void> _edit([Map<String, dynamic>? level]) async {
    final emps = await _employees();
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _LevelSheet(
        shiftId: widget.shiftId,
        shiftName: widget.shiftName,
        level: level,
        employees: emps,
        nextOrder: _levels.length,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa mức lương "${l['levelName']}"?')),
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
    final r = await _api.deleteShiftSalaryLevel(l['id'].toString());
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      stToast(context, r['message']?.toString() ?? 'Không xóa được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_levels.isEmpty)
        Text(tr('Chưa có mức lương ca. Lương tính theo thiết lập lương của từng nhân viên.'),
            style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
      for (final l in _levels)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(border: Border.all(color: SboxColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 12, right: 4),
            leading: Icon(ShiftRateType.parse(l['rateType']?.toString()).icon, color: SboxColors.brand600),
            title: Row(children: [
              Flexible(child: Text(tr('${l['levelName']}'), style: const TextStyle(fontWeight: FontWeight.w700))),
              if (l['isActive'] == false) ...[
                const SizedBox(width: 6),
                const SboxStatusChip(label: 'Tắt'),
              ],
            ]),
            subtitle: Text(tr('${shiftRateText(l)} · ${_who(l)}')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: tr('Sửa'), icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(l)),
              IconButton(
                  tooltip: tr('Xóa'),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: SboxColors.danger),
                  onPressed: () => _delete(l)),
            ]),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: SboxButton.secondary(label: 'Thêm mức lương', icon: Icons.add, onPressed: () => _edit()),
      ),
    ]);
  }

  String _who(Map<String, dynamic> l) {
    final ids = l['employeeIds'];
    final n = ids is List ? ids.length : 0;
    return n == 0 ? 'Tất cả nhân viên' : '$n nhân viên';
  }
}

class _Emp {
  const _Emp(this.id, this.name, this.code, this.dept);
  final String id;
  final String name;
  final String? code;
  final String? dept;
}

class _LevelSheet extends StatefulWidget {
  const _LevelSheet({
    required this.shiftId,
    required this.shiftName,
    required this.level,
    required this.employees,
    required this.nextOrder,
  });

  final String shiftId;
  final String shiftName;
  final Map<String, dynamic>? level;
  final List<_Emp> employees;
  final int nextOrder;

  @override
  State<_LevelSheet> createState() => _LevelSheetState();
}

class _LevelSheetState extends State<_LevelSheet> {
  final _api = ApiService();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _desc;
  late ShiftRateType _type;
  late Set<String> _selected;
  late bool _active;
  bool _allEmployees = true;
  String _q = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.level;
    _type = ShiftRateType.parse(l?['rateType']?.toString());
    _name = TextEditingController(text: l?['levelName']?.toString() ?? '');
    _amount = TextEditingController(text: _amountText(l));
    _desc = TextEditingController(text: l?['description']?.toString() ?? '');
    final ids = l?['employeeIds'];
    _selected = {if (ids is List) for (final x in ids) '$x'};
    _allEmployees = _selected.isEmpty;
    _active = l?['isActive'] != false;
  }

  String _amountText(Map<String, dynamic>? l) {
    if (l == null) return '';
    num n(String k) => (l[k] as num?) ?? 0;
    return switch (_type) {
      ShiftRateType.fixed => PosVndThousandsFormatter.format(n('fixedRate')),
      ShiftRateType.hourly => PosVndThousandsFormatter.format(n('hourlyRate')),
      ShiftRateType.multiplier => '${n('multiplier')}',
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      stToast(context, 'Nhập tên mức lương', error: true);
      return;
    }
    if (!_allEmployees && _selected.isEmpty) {
      stToast(context, 'Chọn ít nhất 1 nhân viên hoặc chọn «Tất cả nhân viên»', error: true);
      return;
    }
    final amount = _type == ShiftRateType.multiplier
        ? (double.tryParse(_amount.text.replaceAll(',', '.')) ?? 1.0)
        : PosVndThousandsFormatter.parse(_amount.text);
    final l = widget.level;
    final data = {
      'shiftTemplateId': widget.shiftId,
      'levelName': _name.text.trim(),
      'sortOrder': l?['sortOrder'] ?? widget.nextOrder,
      'rateType': _type.code,
      'fixedRate': _type == ShiftRateType.fixed ? amount : 0,
      'hourlyRate': _type == ShiftRateType.hourly ? amount : 0,
      'multiplier': _type == ShiftRateType.multiplier ? amount : 1.0,
      'shiftAllowance': l?['shiftAllowance'] ?? 0,
      'isNightShift': l?['isNightShift'] ?? false,
      'employeeIds': _allEmployees ? null : _selected.toList(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      if (l != null) 'isActive': _active,
    };
    setState(() => _saving = true);
    final r = l == null
        ? await _api.createShiftSalaryLevel(data)
        : await _api.updateShiftSalaryLevel(l['id'].toString(), data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.pop(context, true);
    } else {
      stToast(context, r['message']?.toString() ?? 'Không lưu được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = widget.employees
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q) || (e.code ?? '').toLowerCase().contains(q))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(tr(widget.level == null ? 'Thêm mức lương ca' : 'Sửa mức lương ca'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(tr('Ca ${widget.shiftName}'), style: const TextStyle(color: SboxColors.slate500)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            decoration: InputDecoration(
                labelText: tr('Tên mức lương *'), hintText: tr('VD: Thu ngân, Phụ bếp'), isDense: true, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ShiftRateType>(
            showSelectedIcon: false,
            segments: [for (final t in ShiftRateType.values) ButtonSegment(value: t, label: Text(tr(t.label)))],
            selected: {_type},
            onSelectionChanged: (v) => setState(() {
              _type = v.first;
              _amount.text = '';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _type == ShiftRateType.multiplier ? null : [PosVndThousandsFormatter()],
            decoration: InputDecoration(
              labelText: tr(switch (_type) {
                ShiftRateType.fixed => 'Tiền mỗi ca',
                ShiftRateType.hourly => 'Tiền mỗi giờ',
                ShiftRateType.multiplier => 'Hệ số nhân lương',
              }),
              hintText: _type == ShiftRateType.multiplier ? '1.5' : '200.000',
              suffixText: _type == ShiftRateType.multiplier ? 'x' : '₫',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allEmployees,
            onChanged: (v) => setState(() => _allEmployees = v),
            title: Text(tr('Áp dụng cho tất cả nhân viên làm ca này'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr(_allEmployees ? 'Tắt để chọn từng nhân viên' : 'Đã chọn ${_selected.length} nhân viên')),
          ),
          if (!_allEmployees) ...[
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm nhân viên'), isDense: true, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            Row(children: [
              TextButton(
                onPressed: () => setState(() => _selected.addAll(shown.map((e) => e.id))),
                child: Text(tr('Chọn ${shown.length} người đang hiện')),
              ),
              TextButton(onPressed: () => setState(_selected.clear), child: Text(tr('Bỏ chọn'))),
            ]),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(border: Border.all(color: SboxColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: shown.isEmpty
                  ? Padding(padding: const EdgeInsets.all(16), child: Text(tr('Không có nhân viên phù hợp')))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final e = shown[i];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.contains(e.id),
                          onChanged: (v) => setState(() => v == true ? _selected.add(e.id) : _selected.remove(e.id)),
                          title: Text(tr(e.name)),
                          subtitle: Text(tr([e.code, e.dept].whereType<String>().where((x) => x.isNotEmpty).join(' · '))),
                        );
                      },
                    ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: InputDecoration(labelText: tr('Ghi chú'), isDense: true, border: const OutlineInputBorder()),
          ),
          if (widget.level != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: Text(tr('Đang áp dụng')),
            ),
          const SizedBox(height: 16),
          SboxButton(label: 'Lưu mức lương', icon: Icons.check_rounded, expand: true, loading: _saving, onPressed: _saving ? null : _save),
        ]),
      ),
    );
  }
}
