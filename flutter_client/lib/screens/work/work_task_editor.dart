import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/employee.dart';
import '../../models/task.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';

/// Nhân viên rút gọn cho bộ chọn.
class WorkPerson {
  const WorkPerson(this.id, this.name, [this.code]);
  final String id;
  final String name;
  final String? code;

  static WorkPerson fromEmployee(Employee e) => WorkPerson(e.id, e.fullName, e.employeeCode);
}

/// Chọn nhiều nhân viên (có tìm kiếm).
Future<List<String>?> pickWorkPeople(BuildContext context, List<WorkPerson> people, List<String> selected,
    {String title = 'Chọn người làm'}) {
  final chosen = {...selected};
  var q = '';
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final list = people
            .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || (p.code ?? '').toLowerCase().contains(q))
            .toList();
        return AlertDialog(
          title: Text(tr(title)),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          content: SizedBox(
            width: 420,
            height: 460,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Tìm tên, mã nhân viên'), isDense: true),
                onChanged: (v) => set(() => q = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  for (final p in list)
                    CheckboxListTile(
                      dense: true,
                      value: chosen.contains(p.id),
                      onChanged: (v) => set(() => v == true ? chosen.add(p.id) : chosen.remove(p.id)),
                      title: Text(p.name),
                      subtitle: p.code == null ? null : Text(p.code!),
                      secondary: WorkAvatarStack(names: [p.name], size: 28, max: 1),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, chosen.toList()), child: Text(tr('Chọn (${chosen.length})'))),
          ],
        );
      },
    ),
  );
}

class WorkTaskEditorPage extends StatefulWidget {
  const WorkTaskEditorPage({
    super.key,
    this.task,
    required this.projects,
    required this.people,
    this.templates = const [],
    this.initialProjectId,
    this.initialStageKey,
  });

  final WorkTask? task;
  final List<TaskProjectV2> projects;
  final List<WorkPerson> people;
  final List<TaskTemplateV2> templates;
  final String? initialProjectId;
  final String? initialStageKey;

  @override
  State<WorkTaskEditorPage> createState() => _WorkTaskEditorPageState();
}

class _ChecklistDraft {
  _ChecklistDraft(this.item) : ctrl = TextEditingController(text: item.text);
  final TaskChecklistItemV2 item;
  final TextEditingController ctrl;
}

class _WorkTaskEditorPageState extends State<WorkTaskEditorPage> {
  final _api = ApiService();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _hours = TextEditingController();
  final _location = TextEditingController();
  final _newItem = TextEditingController();
  TaskType _type = TaskType.task;
  TaskPriority _priority = TaskPriority.medium;
  String? _projectId;
  String? _stageKey;
  List<String> _people = [];
  bool _requireAcceptance = true;
  DateTime? _start;
  DateTime? _due;
  TaskProgressMode _mode = TaskProgressMode.checklist;
  final List<_ChecklistDraft> _items = [];
  String? _templateId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      _title.text = t.title;
      _desc.text = t.description ?? '';
      _hours.text = t.estimatedHours == null ? '' : SboxFmt.number(t.estimatedHours);
      _location.text = t.location ?? '';
      _type = t.taskType;
      _priority = t.priority;
      _projectId = t.projectId;
      _stageKey = t.stageKey;
      _people = {
        if (t.assigneeId != null) t.assigneeId!,
        ...?t.assignees?.map((a) => a.employeeId),
      }.toList();
      _start = t.startDate;
      _due = t.dueDate;
      _mode = t.progressMode;
      _items.addAll(t.checklistItems.map(_ChecklistDraft.new));
    } else {
      _projectId = widget.initialProjectId;
      _stageKey = widget.initialStageKey;
      final now = DateTime.now();
      _due = DateTime(now.year, now.month, now.day, 17);
      final p = _project;
      if (p != null && (p.address ?? '').isNotEmpty) _location.text = p.address!;
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _hours, _location, _newItem]) {
      c.dispose();
    }
    for (final d in _items) {
      d.ctrl.dispose();
    }
    super.dispose();
  }

  TaskProjectV2? get _project => widget.projects.where((p) => p.id == _projectId).firstOrNull;

  void _applyTemplate(TaskTemplateV2 t) {
    setState(() {
      _templateId = t.id;
      _title.text = t.title;
      _desc.text = t.description ?? '';
      _type = t.taskType;
      _priority = t.priority;
      _hours.text = t.estimatedHours == null ? '' : SboxFmt.number(t.estimatedHours);
      if (t.stageKey != null && (_project?.stages.any((s) => s.key == t.stageKey) ?? false)) _stageKey = t.stageKey;
      for (final d in _items) {
        d.ctrl.dispose();
      }
      _items
        ..clear()
        ..addAll(TaskChecklistItemV2.parse(t.checklist).map((i) {
          i.done = false;
          i.photoUrl = null;
          i.doneBy = null;
          i.doneAt = null;
          return _ChecklistDraft(i);
        }));
      _mode = _items.isEmpty ? TaskProgressMode.manual : TaskProgressMode.checklist;
    });
  }

  void _addItems(String raw) {
    final lines = raw.split('\n').map((l) => l.trim().replaceFirst(RegExp(r'^[-*•]\s*'), '')).where((l) => l.isNotEmpty);
    setState(() {
      for (final l in lines) {
        _items.add(_ChecklistDraft(TaskChecklistItemV2(id: 'n${DateTime.now().microsecondsSinceEpoch}${_items.length}', text: l)));
      }
      _newItem.clear();
    });
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final base = initial ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    return DateTime(d.year, d.month, d.day, t?.hour ?? 17, t?.minute ?? 0);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Nhập tên công việc');
      return;
    }
    if (_start != null && _due != null && _due!.isBefore(_start!)) {
      setState(() => _error = 'Hạn chót phải sau ngày bắt đầu');
      return;
    }
    final items = <TaskChecklistItemV2>[];
    for (final d in _items) {
      final text = d.ctrl.text.trim();
      if (text.isEmpty) continue;
      d.item.text = text;
      items.add(d.item);
    }
    final data = <String, dynamic>{
      'title': title,
      'description': _desc.text.trim(),
      'taskType': _type.index,
      'priority': _priority.index,
      'assigneeId': _people.isEmpty ? null : _people.first,
      'assigneeIds': _people,
      'startDate': _start?.toIso8601String(),
      'dueDate': _due?.toIso8601String(),
      'estimatedHours': double.tryParse(_hours.text.replaceAll(',', '.')),
      'checklist': items.isEmpty ? (_editing ? '[]' : null) : TaskChecklistItemV2.encode(items),
      'progressMode': (items.isEmpty && _mode == TaskProgressMode.checklist ? TaskProgressMode.manual : _mode).index,
      'location': _location.text.trim(),
      'projectId': _projectId ?? (_editing ? '00000000-0000-0000-0000-000000000000' : null),
      'stageKey': _stageKey,
      if (!_editing) 'requireAcceptance': _requireAcceptance && _people.isNotEmpty,
      if (_templateId != null) 'templateId': _templateId,
    }..removeWhere((k, v) => v == null);
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = _editing ? await _api.updateTaskV2(widget.task!.id, data) : await _api.createTaskV2(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = '${r['message'] ?? 'Không lưu được'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final nameOf = {for (final p in widget.people) p.id: p.name};
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(tr(_editing ? 'Sửa công việc' : 'Tạo công việc')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SboxButton(label: 'Lưu', icon: Icons.check_rounded, size: SboxButtonSize.sm, loading: _saving, onPressed: _saving ? null : _save),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: SboxSpace.md),
                padding: const EdgeInsets.all(SboxSpace.md),
                decoration: BoxDecoration(color: SboxColors.dangerSoft, borderRadius: SboxRadius.mdAll),
                child: Text(tr(_error!), style: SboxType.smallStyle(SboxColors.dangerText)),
              ),
            if (!_editing && widget.templates.isNotEmpty) ...[
              Text(tr('Tạo nhanh từ mẫu'), style: SboxType.captionStyle()),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final t in widget.templates.where((t) => t.recurrenceType == 0).take(30))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(t.name),
                        avatar: Icon(workTypeIcon(t.taskType), size: 16),
                        selected: _templateId == t.id,
                        onSelected: (_) => _applyTemplate(t),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: SboxSpace.md),
            ],
            SboxCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _title,
                  autofocus: !_editing,
                  style: SboxType.titleSmStyle(),
                  decoration: InputDecoration(labelText: tr('Tên công việc *'), hintText: tr('Lắp tủ bếp nhà chị Lan')),
                ),
                const SizedBox(height: SboxSpace.md),
                TextField(controller: _desc, minLines: 2, maxLines: 6, decoration: InputDecoration(labelText: tr('Mô tả, yêu cầu'))),
                const SizedBox(height: SboxSpace.md),
                _row([
                  DropdownButtonFormField<String?>(
                    value: _projectId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Dự án / công trình')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(tr('— Không thuộc dự án —'))),
                      for (final p in widget.projects) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() {
                      _projectId = v;
                      final st = _project?.stages ?? const <TaskStageV2>[];
                      _stageKey = st.isEmpty ? null : st.first.key;
                      if (_location.text.isEmpty && (_project?.address ?? '').isNotEmpty) _location.text = _project!.address!;
                    }),
                  ),
                  if (project != null && project.stages.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: project.stages.any((s) => s.key == _stageKey) ? _stageKey : project.stages.first.key,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('Giai đoạn')),
                      items: [for (final s in project.stages) DropdownMenuItem(value: s.key, child: Text(s.name))],
                      onChanged: (v) => setState(() => _stageKey = v),
                    ),
                ]),
                const SizedBox(height: SboxSpace.md),
                _row([
                  DropdownButtonFormField<TaskType>(
                    value: kTaskTypesForIndustry.contains(_type) ? _type : TaskType.other,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Loại việc')),
                    items: [
                      for (final t in kTaskTypesForIndustry)
                        DropdownMenuItem(
                            value: t,
                            child: Row(children: [Icon(workTypeIcon(t), size: 18), const SizedBox(width: 8), Text(tr(getTaskTypeLabel(t)))])),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? TaskType.task),
                  ),
                  DropdownButtonFormField<TaskPriority>(
                    value: _priority,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Mức ưu tiên')),
                    items: [
                      for (final p in TaskPriority.values)
                        DropdownMenuItem(
                            value: p,
                            child: Row(children: [
                              Icon(Icons.flag_rounded, size: 16, color: workPriorityTone(p).solid),
                              const SizedBox(width: 8),
                              Text(tr(workPriorityLabel(p))),
                            ])),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? TaskPriority.medium),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: SboxSpace.lg),
            SboxCard(
              title: 'Người làm và thời hạn',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  borderRadius: SboxRadius.mdAll,
                  onTap: () async {
                    final r = await pickWorkPeople(context, widget.people, _people);
                    if (r != null) setState(() => _people = r);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: tr('Người làm (người đầu tiên là phụ trách chính)')),
                    child: _people.isEmpty
                        ? Text(tr('Chạm để chọn nhân viên'), style: SboxType.bodyStyle(SboxColors.textMuted))
                        : Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final id in _people)
                              InputChip(
                                label: Text(nameOf[id] ?? id),
                                avatar: id == _people.first ? const Icon(Icons.star_rounded, size: 16) : null,
                                onDeleted: () => setState(() => _people.remove(id)),
                              ),
                          ]),
                  ),
                ),
                if (!_editing && _people.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _requireAcceptance,
                    onChanged: (v) => setState(() => _requireAcceptance = v),
                    title: Text(tr('Nhân viên phải bấm «Nhận việc»')),
                    subtitle: Text(tr('Tắt để giao thẳng, việc vào ngay trạng thái Cần làm')),
                  ),
                const SizedBox(height: SboxSpace.sm),
                _row([
                  _dateField('Bắt đầu', _start, (d) => setState(() => _start = d)),
                  _dateField('Hạn chót', _due, (d) => setState(() => _due = d)),
                ]),
                const SizedBox(height: SboxSpace.md),
                _row([
                  TextField(
                    controller: _hours,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Ước tính (giờ)')),
                  ),
                  TextField(controller: _location, decoration: InputDecoration(labelText: tr('Địa điểm'), prefixIcon: const Icon(Icons.place_outlined))),
                ]),
              ]),
            ),
            const SizedBox(height: SboxSpace.lg),
            SboxCard(
              title: 'Checklist',
              subtitle: 'Bật biểu tượng máy ảnh để bắt buộc chụp ảnh khi làm xong mục đó',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (a, b) => setState(() {
                    if (b > a) b--;
                    _items.insert(b, _items.removeAt(a));
                  }),
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Padding(
                        key: ValueKey(_items[i].item.id),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator_rounded, color: SboxColors.slate300)),
                          const SizedBox(width: 4),
                          Icon(_items[i].item.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              size: 20, color: _items[i].item.done ? SboxColors.success : SboxColors.slate300),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: _items[i].ctrl, decoration: const InputDecoration(isDense: true, border: InputBorder.none))),
                          IconButton(
                            tooltip: tr(_items[i].item.requirePhoto ? 'Bắt buộc ảnh — chạm để bỏ' : 'Chạm để bắt buộc ảnh'),
                            icon: Icon(_items[i].item.requirePhoto ? Icons.photo_camera : Icons.photo_camera_outlined,
                                color: _items[i].item.requirePhoto ? SboxColors.warning : SboxColors.slate300, size: 20),
                            onPressed: () => setState(() => _items[i].item.requirePhoto = !_items[i].item.requirePhoto),
                          ),
                          IconButton(
                            tooltip: tr('Xóa mục'),
                            icon: const Icon(Icons.close_rounded, size: 18, color: SboxColors.slate400),
                            onPressed: () => setState(() => _items.removeAt(i).ctrl.dispose()),
                          ),
                        ]),
                      ),
                  ],
                ),
                Row(children: [
                  const Icon(Icons.add_rounded, color: SboxColors.brand600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _newItem,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(hintText: tr('Thêm mục (dán nhiều dòng để thêm nhiều mục)'), isDense: true),
                      onSubmitted: _addItems,
                    ),
                  ),
                  TextButton(onPressed: () => _addItems(_newItem.text), child: Text(tr('Thêm'))),
                ]),
                const SizedBox(height: SboxSpace.md),
                DropdownButtonFormField<TaskProgressMode>(
                  value: _mode,
                  decoration: InputDecoration(labelText: tr('Cách tính tiến độ')),
                  items: [
                    DropdownMenuItem(value: TaskProgressMode.checklist, child: Text(tr('Tự tính theo checklist'))),
                    DropdownMenuItem(value: TaskProgressMode.subTasks, child: Text(tr('Tự tính theo việc con'))),
                    DropdownMenuItem(value: TaskProgressMode.manual, child: Text(tr('Người làm tự nhập %'))),
                  ],
                  onChanged: (v) => setState(() => _mode = v ?? TaskProgressMode.manual),
                ),
              ]),
            ),
            const SizedBox(height: SboxSpace.xxl),
          ]),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => LayoutBuilder(builder: (ctx, c) {
        if (c.maxWidth < 520 || children.length == 1) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: SboxSpace.md), children[i]],
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: SboxSpace.md), Expanded(child: children[i])],
        ]);
      });

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime?> onChanged) => InkWell(
        onTap: () async {
          final d = await _pickDateTime(value);
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: tr(label),
            suffixIcon: value == null
                ? const Icon(Icons.event_outlined)
                : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => onChanged(null)),
          ),
          child: Text(value == null ? tr('Chưa chọn') : workDate(value, withTime: true)),
        ),
      );
}
