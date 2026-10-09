import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';
import 'work_template_editor.dart';
import 'work_task_editor.dart';

const _stagePalette = <Color>[
  Color(0xFF64748B), Color(0xFF7C3AED), Color(0xFF0891B2), Color(0xFF158DC0),
  Color(0xFFD97706), Color(0xFFDB2777), Color(0xFF16A34A), Color(0xFF94A3B8),
];

// ═════════════════ Tạo / sửa dự án ═════════════════

class WorkProjectEditorPage extends StatefulWidget {
  const WorkProjectEditorPage({super.key, this.project, required this.packs, required this.people, this.initialPackKey});
  final TaskProjectV2? project;
  final List<TaskIndustryPackV2> packs;
  final List<WorkPerson> people;
  final String? initialPackKey;

  @override
  State<WorkProjectEditorPage> createState() => _WorkProjectEditorPageState();
}

class _WorkProjectEditorPageState extends State<WorkProjectEditorPage> {
  final _api = ApiService();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _budget = TextEditingController();
  String? _packKey;
  String? _owner;
  DateTime? _start;
  DateTime? _due;
  TaskProjectStatus _status = TaskProjectStatus.active;
  Color _color = const Color(0xFF158DC0);
  List<TaskStageV2> _stages = [];
  bool _createTasks = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.project != null;
  TaskIndustryPackV2? get _pack => widget.packs.where((p) => p.key == _packKey).firstOrNull;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    if (p != null) {
      _name.text = p.name;
      _desc.text = p.description ?? '';
      _customer.text = p.customerName ?? '';
      _phone.text = p.customerPhone ?? '';
      _address.text = p.address ?? '';
      _budget.text = p.budget == null ? '' : SboxFmt.number(p.budget);
      _packKey = p.industryKey;
      _owner = p.ownerEmployeeId;
      _start = p.startDate;
      _due = p.dueDate;
      _status = p.status;
      _color = p.colorValue;
      _stages = p.stages.map((s) => TaskStageV2(key: s.key, name: s.name, color: s.color, done: s.done)).toList();
    } else {
      _selectPack(widget.initialPackKey ?? (widget.packs.isNotEmpty ? widget.packs.first.key : null));
    }
  }

  void _selectPack(String? key) {
    _packKey = key;
    final pack = _pack;
    if (pack != null && !_editing) {
      _stages = pack.stages.map((s) => TaskStageV2(key: s.key, name: s.name, color: s.color, done: s.done)).toList();
      _color = hexColor(pack.color);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _customer, _phone, _address, _budget]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Nhập tên dự án / công trình');
      return;
    }
    final stages = _stages.where((s) => s.name.trim().isNotEmpty).toList();
    if (stages.isNotEmpty && !stages.any((s) => s.done)) {
      setState(() => _error = 'Cần ít nhất một giai đoạn «hoàn thành» (kéo việc vào là xong)');
      return;
    }
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim(),
      'industryKey': _packKey,
      'color': colorHex(_color),
      'status': _status.index,
      'ownerEmployeeId': _owner,
      'customerName': _customer.text.trim(),
      'customerPhone': _phone.text.trim(),
      'address': _address.text.trim(),
      'budget': double.tryParse(_budget.text.replaceAll('.', '').replaceAll(',', '.')),
      'startDate': _start?.toIso8601String(),
      'dueDate': _due?.toIso8601String(),
      'stages': stages.map((s) => s.toJson()).toList(),
      if (!_editing) 'createTasksFromPack': _createTasks && _pack != null,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = _editing ? await _api.updateTaskProject(widget.project!.id, data) : await _api.createTaskProject(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = '${r['message'] ?? 'Không lưu được'}');
    }
  }

  Future<void> _delete() async {
    final ok = await SboxDialogs.confirm(context,
        title: 'Xóa dự án «${widget.project!.name}»?',
        message: 'Các công việc vẫn giữ lại nhưng không còn thuộc dự án.',
        confirmLabel: 'Xóa',
        danger: true);
    if (!ok) return;
    final r = await _api.deleteTaskProject(widget.project!.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      Navigator.of(context).pop(true);
    } else {
      workToast(context, '${r['message']}', error: true);
    }
  }

  Future<DateTime?> _pickDate(DateTime? v) =>
      showDatePicker(context: context, initialDate: v ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));

  @override
  Widget build(BuildContext context) {
    final label = _pack?.projectLabel ?? 'Dự án';
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(tr(_editing ? 'Sửa $label' : 'Tạo $label mới')),
        actions: [
          if (_editing) IconButton(tooltip: tr('Xóa'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SboxButton(label: 'Lưu', icon: Icons.check_rounded, size: SboxButtonSize.sm, loading: _saving, onPressed: _saving ? null : _save),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: SboxSpace.md),
                padding: const EdgeInsets.all(SboxSpace.md),
                decoration: BoxDecoration(color: SboxColors.dangerSoft, borderRadius: SboxRadius.mdAll),
                child: Text(tr(_error!), style: SboxType.smallStyle(SboxColors.dangerText)),
              ),
            if (!_editing) ...[
              Text(tr('Ngành / quy trình'), style: SboxType.titleSmStyle()),
              const SizedBox(height: SboxSpace.sm),
              Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
                for (final p in widget.packs)
                  ChoiceChip(
                    avatar: Icon(p.iconData, size: 18, color: _packKey == p.key ? Colors.white : hexColor(p.color)),
                    label: Text(p.name),
                    selected: _packKey == p.key,
                    selectedColor: hexColor(p.color),
                    labelStyle: TextStyle(color: _packKey == p.key ? Colors.white : SboxColors.text),
                    onSelected: (_) => setState(() => _selectPack(p.key)),
                  ),
                ChoiceChip(
                  label: Text(tr('Tự thiết kế')),
                  selected: _packKey == null,
                  onSelected: (_) => setState(() {
                    _packKey = null;
                    _stages = [
                      TaskStageV2(key: 'todo', name: 'Cần làm', color: '#64748B'),
                      TaskStageV2(key: 'doing', name: 'Đang làm', color: '#158DC0'),
                      TaskStageV2(key: 'done', name: 'Hoàn thành', color: '#16A34A', done: true),
                    ];
                  }),
                ),
              ]),
              if (_pack != null)
                Padding(
                  padding: const EdgeInsets.only(top: SboxSpace.sm),
                  child: Text(tr(_pack!.description), style: SboxType.smallStyle(SboxColors.textMuted)),
                ),
              const SizedBox(height: SboxSpace.lg),
            ],
            SboxCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _name,
                  style: SboxType.titleSmStyle(),
                  decoration: InputDecoration(labelText: tr('Tên ${label.toLowerCase()} *'), hintText: tr('Thi công nhà chị Lan – Q7')),
                ),
                const SizedBox(height: SboxSpace.md),
                TextField(controller: _desc, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('Mô tả, phạm vi công việc'))),
                const SizedBox(height: SboxSpace.md),
                _row([
                  TextField(controller: _customer, decoration: InputDecoration(labelText: tr('Khách hàng'), prefixIcon: const Icon(Icons.person_outline))),
                  TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: tr('Số điện thoại'), prefixIcon: const Icon(Icons.phone_outlined))),
                ]),
                const SizedBox(height: SboxSpace.md),
                TextField(controller: _address, decoration: InputDecoration(labelText: tr('Địa chỉ / địa điểm'), prefixIcon: const Icon(Icons.place_outlined))),
                const SizedBox(height: SboxSpace.md),
                _row([
                  DropdownButtonFormField<String?>(
                    value: widget.people.any((p) => p.id == _owner) ? _owner : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Người phụ trách')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(tr('— Chưa chọn —'))),
                      for (final p in widget.people) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _owner = v),
                  ),
                  TextField(
                    controller: _budget,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Giá trị / dự toán (đ)')),
                  ),
                ]),
                const SizedBox(height: SboxSpace.md),
                _row([
                  _dateBox('Ngày bắt đầu', _start, (d) => setState(() => _start = d)),
                  _dateBox('Hạn hoàn thành', _due, (d) => setState(() => _due = d)),
                  if (_editing)
                    DropdownButtonFormField<TaskProjectStatus>(
                      value: _status,
                      decoration: InputDecoration(labelText: tr('Trạng thái')),
                      items: [
                        for (final s in TaskProjectStatus.values.where((s) => s != TaskProjectStatus.archived))
                          DropdownMenuItem(value: s, child: Text(tr(taskProjectStatusLabel(s)))),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                ]),
                const SizedBox(height: SboxSpace.md),
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(tr('Màu'), style: SboxType.smallStyle()),
                  for (final c in _stagePalette)
                    InkWell(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _color.toARGB32() == c.toARGB32() ? SboxColors.text : Colors.transparent, width: 2),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: SboxSpace.lg),
            SboxCard(
              title: 'Quy trình (giai đoạn)',
              subtitle: 'Cột trên bảng Kanban. Đánh dấu «Hoàn thành» cho giai đoạn cuối — kéo việc vào là xong.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (a, b) => setState(() {
                    if (b > a) b--;
                    _stages.insert(b, _stages.removeAt(a));
                  }),
                  children: [
                    for (var i = 0; i < _stages.length; i++)
                      Padding(
                        key: ValueKey('st_${_stages[i].key}'),
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator_rounded, color: SboxColors.slate300)),
                          const SizedBox(width: 6),
                          PopupMenuButton<Color>(
                            tooltip: tr('Màu'),
                            onSelected: (c) => setState(() => _stages[i].color = colorHex(c)),
                            itemBuilder: (_) => [
                              for (final c in _stagePalette)
                                PopupMenuItem(value: c, child: Container(width: 60, height: 18, color: c)),
                            ],
                            child: Container(width: 18, height: 18, decoration: BoxDecoration(color: _stages[i].colorValue, shape: BoxShape.circle)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: _stages[i].name,
                              decoration: const InputDecoration(isDense: true),
                              onChanged: (v) => _stages[i].name = v,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: Text(tr('Hoàn thành')),
                            selected: _stages[i].done,
                            onSelected: (v) => setState(() => _stages[i].done = v),
                          ),
                          IconButton(
                            tooltip: tr('Xóa giai đoạn'),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _stages.length <= 1 ? null : () => setState(() => _stages.removeAt(i)),
                          ),
                        ]),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _stages.insert(
                          _stages.lastIndexWhere((s) => !s.done) + 1,
                          TaskStageV2(key: 's${DateTime.now().millisecondsSinceEpoch}', name: tr('Giai đoạn mới'), color: '#158DC0'),
                        )),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr('Thêm giai đoạn')),
                  ),
                ),
                if (!_editing && _pack != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _createTasks,
                    onChanged: (v) => setState(() => _createTasks = v),
                    title: Text(tr('Tạo sẵn ${_pack!.templates.where((t) => t.recurrenceType == 0).length} việc mẫu của ngành')),
                    subtitle: Text(tr('Mỗi việc có checklist sẵn, đặt đúng giai đoạn; giao cho người phụ trách.')),
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
        if (c.maxWidth < 560) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: SboxSpace.md), children[i]],
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: SboxSpace.md), Expanded(child: children[i])],
        ]);
      });

  Widget _dateBox(String label, DateTime? v, ValueChanged<DateTime?> set) => InkWell(
        onTap: () async {
          final d = await _pickDate(v);
          if (d != null) set(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: tr(label),
            suffixIcon: v == null ? const Icon(Icons.event_outlined) : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => set(null)),
          ),
          child: Text(v == null ? tr('Chưa chọn') : workDate(v)),
        ),
      );
}

// ═════════════════ Gói ngành & mẫu việc ═════════════════

class WorkPacksPage extends StatefulWidget {
  const WorkPacksPage({super.key, required this.people, this.initialTab = 0});
  final List<WorkPerson> people;
  final int initialTab;

  @override
  State<WorkPacksPage> createState() => _WorkPacksPageState();
}

class _WorkPacksPageState extends State<WorkPacksPage> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab)
    ..addListener(() {
      if (mounted) setState(() {});
    });
  List<TaskIndustryPackV2> _packs = [];
  List<TaskTemplateV2> _templates = [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Future.wait([_api.getTaskIndustryPacks(), _api.getTaskTemplatesV2()]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _packs = r[0]['data'] is List
          ? (r[0]['data'] as List).whereType<Map>().map((e) => TaskIndustryPackV2.fromJson(Map<String, dynamic>.from(e))).toList()
          : [];
      _templates = r[1]['data'] is List
          ? (r[1]['data'] as List).whereType<Map>().map((e) => TaskTemplateV2.fromJson(Map<String, dynamic>.from(e))).toList()
          : [];
    });
  }

  Future<void> _openPack(TaskIndustryPackV2 p) async {
    final installed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => _PackSheet(pack: p, people: widget.people),
    );
    if (installed == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _editTemplate([TaskTemplateV2? t]) async {
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => WorkTemplateEditorPage(template: t, people: widget.people)));
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _editRecurrence(TaskTemplateV2 t) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _RecurrenceDialog(template: t, people: widget.people));
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(tr('Gói ngành và mẫu việc')),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop(_changed)),
          bottom: TabBar(controller: _tabs, tabs: [Tab(text: tr('Gói theo ngành')), Tab(text: tr('Mẫu việc & lặp lại (${_templates.length})'))]),
        ),
        floatingActionButton: _tabs.index == 1
            ? FloatingActionButton.extended(
                onPressed: () => _editTemplate(),
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Mẫu việc mới')),
              )
            : null,
        body: _loading
            ? const SboxLoading()
            : TabBarView(controller: _tabs, children: [_packGrid(), _templateList()]),
      ),
    );
  }

  Widget _packGrid() {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth < 600 ? 1 : (c.maxWidth < 1000 ? 2 : 3);
      return ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
        Text(tr('Chọn ngành để cài sẵn quy trình, mẫu việc có checklist và việc định kỳ (mở/đóng ca, vệ sinh, báo cáo…).'),
            style: SboxType.smallStyle()),
        const SizedBox(height: SboxSpace.md),
        SboxGrid(columns: cols, children: [
          for (final p in [..._packs.where((p) => p.featured), ..._packs.where((p) => !p.featured)])
            SboxCard(
              onTap: () => _openPack(p),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: hexColor(p.color).withValues(alpha: 0.12), borderRadius: SboxRadius.mdAll),
                    child: Icon(p.iconData, color: hexColor(p.color)),
                  ),
                  const SizedBox(width: SboxSpace.md),
                  Expanded(child: Text(tr(p.name), style: SboxType.titleSmStyle())),
                  if (p.installed) const SboxStatusChip(label: 'Đã cài', tone: SboxTone.success, icon: Icons.check_rounded),
                ]),
                const SizedBox(height: SboxSpace.sm),
                Text(tr(p.description), maxLines: 3, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle()),
                const SizedBox(height: SboxSpace.sm),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final s in p.stages)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: s.colorValue.withValues(alpha: 0.12), borderRadius: SboxRadius.smAll),
                      child: Text(tr(s.name), style: SboxType.captionStyle(s.colorValue)),
                    ),
                ]),
                const SizedBox(height: SboxSpace.sm),
                Text(tr('${p.templates.length} mẫu việc · ${p.recurringCount} việc định kỳ'), style: SboxType.captionStyle()),
              ]),
            ),
        ]),
      ]);
    });
  }

  Widget _templateList() {
    if (_templates.isEmpty) {
      return SboxEmptyState(
        icon: Icons.library_add_check_outlined,
        title: 'Chưa có mẫu việc',
        message: 'Cài một gói ngành để có sẵn mẫu việc và checklist.',
        action: SboxButton(label: 'Xem gói ngành', onPressed: () => _tabs.animateTo(0)),
      );
    }
    final nameOf = {for (final p in widget.people) p.id: p.name};
    return ListView.separated(
      padding: const EdgeInsets.all(SboxSpace.lg),
      itemCount: _templates.length,
      separatorBuilder: (_, __) => const SizedBox(height: SboxSpace.sm),
      itemBuilder: (ctx, i) {
        final t = _templates[i];
        final recurring = t.recurrenceType != 0;
        return SboxCard(
          padding: const EdgeInsets.all(SboxSpace.md),
          onTap: () => _editTemplate(t),
          child: Row(children: [
            Icon(workTypeIcon(t.taskType), color: SboxColors.slate500),
            const SizedBox(width: SboxSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name, style: SboxType.bodyStrong()),
                const SizedBox(height: 2),
                Text(
                  [
                    '${t.checklistCount} mục checklist',
                    if (t.formFieldCount > 0) '${t.formFieldCount} trường biểu mẫu',
                    if ((t.pieceRate ?? 0) > 0) 'khoán ${SboxFmt.number(t.pieceRate)} đ',
                    if (t.requireCheckIn) 'check-in GPS',
                    recurrenceLabel(t.recurrenceType, t.recurrenceDays, t.recurrenceTime),
                    if (recurring && t.assignOnShift)
                      'giao người có ca'
                    else if (recurring && t.defaultAssigneeIds.isNotEmpty)
                      t.defaultAssigneeIds.map((id) => nameOf[id] ?? '?').join(', ')
                    else if (recurring)
                      'chưa chọn người nhận — chưa chạy',
                    if (t.nextRunAt != null && (t.defaultAssigneeIds.isNotEmpty || t.assignOnShift)) 'lần tới ${workDate(t.nextRunAt, withTime: true)}',
                  ].join(' · '),
                  style: SboxType.captionStyle(recurring && t.defaultAssigneeIds.isEmpty && !t.assignOnShift ? SboxColors.warningText : SboxColors.textMuted),
                ),
              ]),
            ),
            if (recurring && (t.defaultAssigneeIds.isNotEmpty || t.assignOnShift))
              IconButton(
                tooltip: tr('Tạo ngay các việc'),
                icon: const Icon(Icons.play_circle_outline),
                onPressed: () async {
                  final r = await _api.runTaskTemplateNow(t.id);
                  if (!mounted) return;
                  workToast(context, r['isSuccess'] == true ? 'Đã tạo ${r['data']} việc' : '${r['message']}', error: r['isSuccess'] != true);
                  if (r['isSuccess'] == true) _changed = true;
                },
              ),
            IconButton(tooltip: tr('Lịch lặp và người nhận'), icon: const Icon(Icons.event_repeat_outlined), onPressed: () => _editRecurrence(t)),
            IconButton(
              tooltip: tr('Xóa mẫu'),
              icon: const Icon(Icons.delete_outline, color: SboxColors.slate400),
              onPressed: () async {
                final ok = await SboxDialogs.confirm(context, title: 'Xóa mẫu «${t.name}»?', confirmLabel: 'Xóa', danger: true);
                if (!ok) return;
                await _api.deleteTaskTemplateV2(t.id);
                _changed = true;
                _load();
              },
            ),
          ]),
        );
      },
    );
  }
}

class _PackSheet extends StatefulWidget {
  const _PackSheet({required this.pack, required this.people});
  final TaskIndustryPackV2 pack;
  final List<WorkPerson> people;

  @override
  State<_PackSheet> createState() => _PackSheetState();
}

class _PackSheetState extends State<_PackSheet> {
  final _api = ApiService();
  bool _recurring = true;
  List<String> _assignees = [];
  bool _busy = false;

  Future<void> _install() async {
    setState(() => _busy = true);
    final r = await _api.installTaskIndustryPack(widget.pack.key, enableRecurring: _recurring, recurringAssigneeIds: _assignees);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true && r['data'] is Map) {
      final d = r['data'] as Map;
      workToast(context, 'Đã cài ${d['createdTemplates']} mẫu (${d['recurringTemplates']} việc định kỳ), bỏ qua ${d['skippedTemplates']} mẫu trùng');
      Navigator.of(context).pop(true);
    } else {
      workToast(context, '${r['message'] ?? 'Không cài được'}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pack;
    final nameOf = {for (final e in widget.people) e.id: e.name};
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Icon(p.iconData, color: hexColor(p.color), size: 28),
          const SizedBox(width: SboxSpace.md),
          Expanded(child: Text(tr(p.name), style: SboxType.titleStyle())),
        ]),
        const SizedBox(height: SboxSpace.sm),
        Text(tr(p.description), style: SboxType.smallStyle()),
        const SizedBox(height: SboxSpace.lg),
        Text(tr('Quy trình ${p.projectLabel.toLowerCase()}'), style: SboxType.titleSmStyle()),
        const SizedBox(height: SboxSpace.sm),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < p.stages.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right_rounded, size: 16, color: SboxColors.slate300),
            SboxStatusChip(label: p.stages[i].name, tone: p.stages[i].done ? SboxTone.success : SboxTone.neutral),
          ],
        ]),
        const SizedBox(height: SboxSpace.lg),
        Text(tr('Mẫu việc (${p.templates.length})'), style: SboxType.titleSmStyle()),
        for (final t in p.templates)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(workTypeIcon(t.taskType)),
            title: Text(t.name),
            subtitle: Text(tr([
              '${t.checklist.length} mục',
              if (t.photoItems > 0) '${t.photoItems} mục cần ảnh',
              if (t.recurrenceType != 0) recurrenceLabel(t.recurrenceType, t.recurrenceDays, t.recurrenceTime),
            ].join(' · '))),
            children: [
              for (final c in t.checklist)
                ListTile(dense: true, leading: const Icon(Icons.check_box_outline_blank, size: 18), title: Text(c)),
            ],
          ),
        const Divider(height: 32),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _recurring,
          onChanged: (v) => setState(() => _recurring = v),
          title: Text(tr('Bật việc định kỳ (${p.recurringCount})')),
          subtitle: Text(tr('Hệ thống tự tạo việc theo lịch cho người nhận bên dưới')),
        ),
        if (_recurring)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people_outline),
            title: Text(_assignees.isEmpty ? tr('Chọn người nhận việc định kỳ') : _assignees.map((id) => nameOf[id] ?? id).join(', ')),
            subtitle: Text(tr('Có thể chọn sau trong tab «Mẫu việc & lặp lại»')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final r = await pickWorkPeople(context, widget.people, _assignees, title: 'Người nhận việc định kỳ');
              if (r != null) setState(() => _assignees = r);
            },
          ),
        const SizedBox(height: SboxSpace.lg),
        SboxButton(
          label: p.installed ? 'Cài bổ sung mẫu còn thiếu' : 'Cài gói ${p.name}',
          icon: Icons.download_done_rounded,
          expand: true,
          size: SboxButtonSize.lg,
          loading: _busy,
          onPressed: _busy ? null : _install,
        ),
      ]),
    );
  }
}

class _RecurrenceDialog extends StatefulWidget {
  const _RecurrenceDialog({required this.template, required this.people});
  final TaskTemplateV2 template;
  final List<WorkPerson> people;

  @override
  State<_RecurrenceDialog> createState() => _RecurrenceDialogState();
}

class _RecurrenceDialogState extends State<_RecurrenceDialog> {
  final _api = ApiService();
  late int _type = widget.template.recurrenceType;
  late final Set<int> _days = (widget.template.recurrenceDays ?? '')
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toSet();
  late TimeOfDay _time = () {
    final parts = (widget.template.recurrenceTime ?? '08:00').split(':');
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
  }();
  late final _dueHours = TextEditingController(text: '${widget.template.dueAfterHours ?? ''}');
  late List<String> _people = [...widget.template.defaultAssigneeIds];
  bool _saving = false;

  Future<void> _save() async {
    final t = widget.template;
    setState(() => _saving = true);
    // Gửi đủ trường của mẫu (biểu mẫu, khoán, check-in, giao theo ca) — chỉ đổi phần lịch lặp.
    final r = await _api.saveTaskTemplateV2(workTemplatePayload(t, override: {
      'recurrenceType': _type,
      'recurrenceDays': (_days.toList()..sort()).join(','),
      'recurrenceTime': '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      'dueAfterHours': int.tryParse(_dueHours.text.trim()),
      'defaultAssigneeIds': _people,
    }), id: t.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.of(context).pop(true);
    } else {
      workToast(context, '${r['message']}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final nameOf = {for (final p in widget.people) p.id: p.name};
    return AlertDialog(
      title: Text(tr('Lặp lại: ${widget.template.name}')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(tr('Không'))),
                ButtonSegment(value: 1, label: Text(tr('Ngày'))),
                ButtonSegment(value: 2, label: Text(tr('Tuần'))),
                ButtonSegment(value: 3, label: Text(tr('Tháng'))),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _days.clear();
              }),
            ),
            const SizedBox(height: SboxSpace.md),
            if (_type == 2)
              Wrap(spacing: 6, children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(wd[i]),
                    selected: _days.contains(i + 1),
                    onSelected: (v) => setState(() => v ? _days.add(i + 1) : _days.remove(i + 1)),
                  ),
              ]),
            if (_type == 3)
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final d in [1, 5, 10, 15, 20, 25, 0])
                  FilterChip(
                    label: Text(d == 0 ? tr('Cuối tháng') : '$d'),
                    selected: _days.contains(d),
                    onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                  ),
              ]),
            if (_type != 0) ...[
              const SizedBox(height: SboxSpace.md),
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
              const SizedBox(height: SboxSpace.md),
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Lưu'))),
      ],
    );
  }
}
