import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/task.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';
import 'work_task_editor.dart' show WorkPerson, pickWorkPeople;

/// Loại việc dùng được cho cửa hàng (ẩn loại phần mềm: lỗi / tính năng / cải tiến).
const workBusinessTaskTypes = <TaskType>[
  TaskType.task,
  TaskType.routine,
  TaskType.customerService,
  TaskType.installation,
  TaskType.maintenance,
  TaskType.inspection,
  TaskType.delivery,
  TaskType.survey,
  TaskType.procurement,
  TaskType.meeting,
  TaskType.other,
];

/// Lặp lại / giao theo ca / khoán / check-in giữ nguyên khi chỉ sửa lịch — gửi đủ trường của mẫu.
Map<String, dynamic> workTemplatePayload(TaskTemplateV2 t, {Map<String, dynamic> override = const {}}) => {
      'name': t.name,
      'title': t.title,
      'description': t.description,
      'taskType': t.taskType.index,
      'priority': t.priority.index,
      'estimatedHours': t.estimatedHours,
      'checklist': t.checklist,
      'stageKey': t.stageKey,
      'projectId': t.projectId,
      'progressMode': TaskProgressMode.checklist.index,
      'recurrenceType': t.recurrenceType,
      'recurrenceDays': t.recurrenceDays,
      'recurrenceTime': t.recurrenceTime,
      'dueAfterHours': t.dueAfterHours,
      'defaultAssigneeIds': t.defaultAssigneeIds,
      'formSchema': t.formSchema,
      'pieceRate': t.pieceRate,
      'assignOnShift': t.assignOnShift,
      'requireCheckIn': t.requireCheckIn,
      ...override,
    };

/// Tạo / sửa mẫu việc: checklist, biểu mẫu riêng, khoán, check-in, lặp lại, giao theo ca.
class WorkTemplateEditorPage extends StatefulWidget {
  const WorkTemplateEditorPage({super.key, this.template, required this.people});
  final TaskTemplateV2? template;
  final List<WorkPerson> people;

  @override
  State<WorkTemplateEditorPage> createState() => _WorkTemplateEditorPageState();
}

class _ChecklistLine {
  _ChecklistLine(this.text, this.photo);
  final TextEditingController text;
  bool photo;
}

class _WorkTemplateEditorPageState extends State<WorkTemplateEditorPage> {
  final _api = ApiService();
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _desc = TextEditingController(text: widget.template?.description ?? '');
  late final _hours = TextEditingController(text: widget.template?.estimatedHours == null ? '' : SboxFmt.number(widget.template!.estimatedHours));
  late final _piece = TextEditingController(
      text: (widget.template?.pieceRate ?? 0) > 0 ? widget.template!.pieceRate!.toStringAsFixed(0) : '');
  late final _dueHours = TextEditingController(text: '${widget.template?.dueAfterHours ?? ''}');
  late TaskType _type = workBusinessTaskTypes.contains(widget.template?.taskType) ? widget.template!.taskType : TaskType.task;
  late TaskPriority _priority = widget.template?.priority ?? TaskPriority.medium;
  late bool _checkIn = widget.template?.requireCheckIn ?? false;
  late bool _onShift = widget.template?.assignOnShift ?? false;
  late int _recurrence = widget.template?.recurrenceType ?? 0;
  late final Set<int> _days = (widget.template?.recurrenceDays ?? '').split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toSet();
  late TimeOfDay _time = () {
    final p = (widget.template?.recurrenceTime ?? '08:00').split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 8, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }();
  late List<String> _people = [...?widget.template?.defaultAssigneeIds];
  late final List<_ChecklistLine> _lines = TaskChecklistItemV2.parse(widget.template?.checklist)
      .map((i) => _ChecklistLine(TextEditingController(text: i.text), i.requirePhoto))
      .toList();
  late final List<TaskFormFieldV2> _fields = TaskFormFieldV2.parse(widget.template?.formSchema);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _desc, _hours, _piece, _dueHours, ..._lines.map((l) => l.text)]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      workToast(context, 'Nhập tên mẫu việc', error: true);
      return;
    }
    final checklist = _lines
        .where((l) => l.text.text.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((e) => {'id': 'c${e.key + 1}', 'text': e.value.text.text.trim(), 'requirePhoto': e.value.photo})
        .toList();
    setState(() => _saving = true);
    final body = {
      'name': name,
      'title': name,
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'taskType': _type.index,
      'priority': _priority.index,
      'estimatedHours': double.tryParse(_hours.text.replaceAll(',', '.')),
      'checklist': checklist.isEmpty ? null : jsonEncode(checklist),
      'stageKey': widget.template?.stageKey,
      'projectId': widget.template?.projectId,
      'progressMode': TaskProgressMode.checklist.index,
      'recurrenceType': _recurrence,
      'recurrenceDays': (_days.toList()..sort()).join(','),
      'recurrenceTime': '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      'dueAfterHours': int.tryParse(_dueHours.text.trim()),
      'defaultAssigneeIds': _people,
      'formSchema': TaskFormFieldV2.encode(_fields.where((f) => f.label.trim().isNotEmpty).toList()),
      'pieceRate': double.tryParse(_piece.text.replaceAll(RegExp(r'[^\d]'), '')),
      'assignOnShift': _onShift,
      'requireCheckIn': _checkIn,
    };
    final r = await _api.saveTaskTemplateV2(body, id: widget.template?.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.of(context).pop(true);
    } else {
      workToast(context, '${r['message'] ?? 'Không lưu được'}', error: true);
    }
  }

  Future<void> _editField([int? index]) async {
    final f = index == null ? TaskFormFieldV2(label: '') : _fields[index];
    final label = TextEditingController(text: f.label);
    final options = TextEditingController(text: f.options.join('\n'));
    final unit = TextEditingController(text: f.unit ?? '');
    var type = f.type;
    var required = f.required;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr(index == null ? 'Thêm trường' : 'Sửa trường')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: label, autofocus: true, decoration: InputDecoration(labelText: tr('Tên trường (vd: Nhiệt độ tủ mát)'))),
                const SizedBox(height: SboxSpace.sm),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(labelText: tr('Kiểu dữ liệu')),
                  items: [for (final e in TaskFormFieldV2.types.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
                  onChanged: (v) => set(() => type = v ?? 'text'),
                ),
                if (type == 'select')
                  TextField(
                    controller: options,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: tr('Các lựa chọn (mỗi dòng một lựa chọn)')),
                  ),
                if (type == 'number')
                  TextField(controller: unit, decoration: InputDecoration(labelText: tr('Đơn vị (vd: °C, m², kg)'))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: required,
                  onChanged: (v) => set(() => required = v),
                  title: Text(tr('Bắt buộc trước khi báo xong')),
                ),
              ]),
            ),
          ),
          actions: [
            if (index != null)
              TextButton(
                onPressed: () {
                  setState(() => _fields.removeAt(index));
                  Navigator.pop(ctx, false);
                },
                child: Text(tr('Xoá'), style: const TextStyle(color: SboxColors.danger)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xong'))),
          ],
        ),
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    setState(() {
      f
        ..label = label.text.trim()
        ..type = type
        ..required = required
        ..options = options.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        ..unit = unit.text.trim().isEmpty ? null : unit.text.trim();
      if (index == null) _fields.add(f);
    });
  }

  @override
  Widget build(BuildContext context) {
    const wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final nameOf = {for (final p in widget.people) p.id: p.name};
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(tr(widget.template == null ? 'Mẫu việc mới' : 'Sửa mẫu việc')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _saving ? null : _save, child: Text(tr(_saving ? 'Đang lưu…' : 'Lưu'))),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
        SboxCard(
          child: Column(children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: tr('Tên mẫu việc *'), hintText: tr('VD: Checklist mở ca, Lắp máy lạnh tại nhà'))),
            TextField(controller: _desc, minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: tr('Hướng dẫn / yêu cầu'))),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<TaskType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Loại việc')),
                  items: [for (final t in workBusinessTaskTypes) DropdownMenuItem(value: t, child: Text(getTaskTypeLabel(t)))],
                  onChanged: (v) => setState(() => _type = v ?? TaskType.task),
                ),
              ),
              const SizedBox(width: SboxSpace.md),
              Expanded(
                child: DropdownButtonFormField<TaskPriority>(
                  initialValue: _priority,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Ưu tiên')),
                  items: [for (final p in TaskPriority.values) DropdownMenuItem(value: p, child: Text(workPriorityLabel(p)))],
                  onChanged: (v) => setState(() => _priority = v ?? TaskPriority.medium),
                ),
              ),
            ]),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _hours,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Ước tính (giờ)')),
                ),
              ),
              const SizedBox(width: SboxSpace.md),
              Expanded(
                child: TextField(
                  controller: _piece,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Tiền khoán mỗi việc (đ)'), helperText: tr('Duyệt xong → cộng lương')),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _checkIn,
              onChanged: (v) => setState(() => _checkIn = v),
              title: Text(tr('Bắt buộc check-in GPS tại địa điểm')),
              subtitle: Text(tr('Cho việc tại công trình / nhà khách')),
            ),
          ]),
        ),
        const SizedBox(height: SboxSpace.lg),
        SboxCard(
          title: 'Checklist',
          subtitle: 'Bấm biểu tượng máy ảnh cho mục cần chụp ảnh khi xong',
          trailing: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Thêm mục')),
            onPressed: () => setState(() => _lines.add(_ChecklistLine(TextEditingController(), false))),
          ),
          child: Column(children: [
            for (var i = 0; i < _lines.length; i++)
              Row(children: [
                Expanded(child: TextField(controller: _lines[i].text, decoration: InputDecoration(isDense: true, hintText: tr('Mục ${i + 1}')))),
                IconButton(
                  tooltip: tr('Bắt buộc ảnh'),
                  icon: Icon(Icons.photo_camera_outlined, color: _lines[i].photo ? SboxColors.warning : SboxColors.slate300),
                  onPressed: () => setState(() => _lines[i].photo = !_lines[i].photo),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _lines.removeAt(i).text.dispose()),
                ),
              ]),
          ]),
        ),
        const SizedBox(height: SboxSpace.lg),
        SboxCard(
          title: 'Biểu mẫu riêng',
          subtitle: 'Thông tin người làm phải điền: số liệu, ảnh, chữ ký khách, đánh giá…',
          trailing: TextButton.icon(icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm trường')), onPressed: () => _editField()),
          child: _fields.isEmpty
              ? Text(tr('Chưa có trường nào.'), style: SboxType.smallStyle(SboxColors.textMuted))
              : ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  onReorderItem: (a, b) => setState(() => _fields.insert(b, _fields.removeAt(a))),
                  children: [
                    for (var i = 0; i < _fields.length; i++)
                      ListTile(
                        key: ValueKey('f$i-${_fields[i].label}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_fieldIcon(_fields[i].type), color: SboxColors.slate500),
                        title: Text('${_fields[i].label}${_fields[i].required ? ' *' : ''}'),
                        subtitle: Text(tr([
                          TaskFormFieldV2.types[_fields[i].type] ?? _fields[i].type,
                          if (_fields[i].type == 'select') _fields[i].options.join(' / '),
                          if ((_fields[i].unit ?? '').isNotEmpty) _fields[i].unit!,
                        ].join(' · '))),
                        onTap: () => _editField(i),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: SboxSpace.lg),
        SboxCard(
          title: 'Lặp lại tự động',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(tr('Không'))),
                ButtonSegment(value: 1, label: Text(tr('Ngày'))),
                ButtonSegment(value: 2, label: Text(tr('Tuần'))),
                ButtonSegment(value: 3, label: Text(tr('Tháng'))),
              ],
              selected: {_recurrence},
              onSelectionChanged: (s) => setState(() {
                _recurrence = s.first;
                _days.clear();
              }),
            ),
            if (_recurrence == 2)
              Wrap(spacing: 6, children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(wd[i]),
                    selected: _days.contains(i + 1),
                    onSelected: (v) => setState(() => v ? _days.add(i + 1) : _days.remove(i + 1)),
                  ),
              ]),
            if (_recurrence == 3)
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final d in [1, 5, 10, 15, 20, 25, 0])
                  FilterChip(
                    label: Text(d == 0 ? tr('Cuối tháng') : '$d'),
                    selected: _days.contains(d),
                    onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                  ),
              ]),
            if (_recurrence != 0) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: Text(tr('Giờ tạo việc: ${_time.format(context)}')),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                },
              ),
              TextField(
                controller: _dueHours,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Hạn chót sau (giờ)'), helperText: tr('Để trống = cuối ngày')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _onShift,
                onChanged: (v) => setState(() => _onShift = v),
                title: Text(tr('Giao cho người có ca làm lúc đó')),
                subtitle: Text(tr('Theo lịch xếp ca — cả ca cùng thấy một việc (mở / đóng ca, vệ sinh…)')),
              ),
              if (!_onShift)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.people_outline),
                  title: Text(_people.isEmpty ? tr('Chọn người nhận (mỗi người một việc)') : _people.map((id) => nameOf[id] ?? id).join(', ')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final r = await pickWorkPeople(context, widget.people, _people, title: 'Người nhận việc định kỳ');
                    if (r != null) setState(() => _people = r);
                  },
                ),
            ],
          ]),
        ),
        const SizedBox(height: SboxSpace.xxl),
      ]),
    );
  }

  static IconData _fieldIcon(String type) => switch (type) {
        'number' => Icons.pin_outlined,
        'money' => Icons.payments_outlined,
        'select' => Icons.list_alt_outlined,
        'date' => Icons.event_outlined,
        'phone' => Icons.phone_outlined,
        'checkbox' => Icons.check_box_outlined,
        'photo' => Icons.photo_camera_outlined,
        'signature' => Icons.draw_outlined,
        'rating' => Icons.star_outline_rounded,
        'textarea' => Icons.notes_outlined,
        _ => Icons.short_text_rounded,
      };
}
