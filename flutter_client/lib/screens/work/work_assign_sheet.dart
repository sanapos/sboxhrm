import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_tr.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';
import 'work_task_editor.dart' show WorkPerson, pickWorkPeople;

/// Kết quả «Thêm chi tiết…»: mở form đầy đủ với mẫu + người + hạn đã chọn.
typedef WorkAssignMore = ({TaskTemplateV2? template, String title, List<String> people, DateTime? due});

/// Giao việc 2 bước: ① chọn mẫu theo ngành (hoặc việc khác) → ② tên, người làm, hạn → Giao.
/// Mỗi người được giao một việc riêng (checklist / biểu mẫu tính riêng từng người).
/// Trả về true nếu đã tạo việc. [onMore] mở form đầy đủ; [onInstallPacks] mở chọn mẫu ngành.
Future<bool> showWorkAssignSheet(
  BuildContext context, {
  required List<TaskTemplateV2> templates,
  required List<WorkPerson> people,
  required String taskLabel,
  String? industryName,
  String? projectId,
  required void Function(WorkAssignMore more) onMore,
  required VoidCallback onInstallPacks,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= SboxBreakpoints.tablet;
  final sheet = _AssignSheet(
    templates: templates,
    people: people,
    taskLabel: taskLabel,
    industryName: industryName,
    projectId: projectId,
    onMore: onMore,
    onInstallPacks: onInstallPacks,
  );
  final r = wide
      ? await showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760), child: sheet),
          ),
        )
      : await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => FractionallySizedBox(heightFactor: 0.94, child: sheet),
        );
  return r == true;
}

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({
    required this.templates,
    required this.people,
    required this.taskLabel,
    required this.industryName,
    required this.projectId,
    required this.onMore,
    required this.onInstallPacks,
  });

  final List<TaskTemplateV2> templates;
  final List<WorkPerson> people;
  final String taskLabel;
  final String? industryName;
  final String? projectId;
  final void Function(WorkAssignMore more) onMore;
  final VoidCallback onInstallPacks;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  static const _recentKey = 'work_assign_recent_people';

  final _search = TextEditingController();
  final _title = TextEditingController();
  bool _picked = false; // bước 2
  TaskTemplateV2? _tpl;
  List<String> _people = [];
  int _due = 0; // 0 theo mẫu / hôm nay, 1 mai, 2 chọn ngày
  DateTime? _custom;
  bool _requireAccept = true;
  bool _saving = false;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _recent = p.getStringList(_recentKey) ?? const []);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _title.dispose();
    super.dispose();
  }

  void _choose(TaskTemplateV2? t) {
    setState(() {
      _tpl = t;
      _picked = true;
      _title.text = t?.title.isNotEmpty == true ? t!.title : (t?.name ?? '');
      _due = 0;
    });
  }

  DateTime get _dueDate {
    final n = DateTime.now();
    switch (_due) {
      case 1:
        return DateTime(n.year, n.month, n.day + 1, 17);
      case 2:
        return _custom ?? DateTime(n.year, n.month, n.day, 17);
      default:
        final h = _tpl?.dueAfterHours;
        if (h != null && h > 0) return n.add(Duration(hours: h));
        return DateTime(n.year, n.month, n.day, n.hour >= 17 ? 21 : 17);
    }
  }

  String _dueLabel0() {
    final h = _tpl?.dueAfterHours;
    if (h != null && h > 0) return h < 24 ? 'Trong $h giờ' : 'Trong ${(h / 24).round()} ngày';
    return DateTime.now().hour >= 17 ? 'Tối nay 21:00' : 'Hôm nay 17:00';
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      workToast(context, 'Nhập tên ${widget.taskLabel.toLowerCase()}', error: true);
      return;
    }
    setState(() => _saving = true);
    final api = ApiService();
    final targets = _people.isEmpty ? <String?>[null] : _people.map<String?>((e) => e).toList();
    var ok = 0;
    String? err;
    for (final p in targets) {
      final r = await api.createTaskV2({
        'title': title,
        if (p != null) 'assigneeId': p,
        if (p != null) 'assigneeIds': [p],
        'dueDate': _dueDate.toIso8601String(),
        if (_tpl != null) 'templateId': _tpl!.id,
        if (widget.projectId != null) 'projectId': widget.projectId,
        if (widget.projectId != null && _tpl?.stageKey != null) 'stageKey': _tpl!.stageKey,
        'requireAcceptance': p != null && _requireAccept,
      });
      if (r['isSuccess'] == true) {
        ok++;
      } else {
        err ??= '${r['message'] ?? 'Không tạo được'}';
      }
    }
    if (_people.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, {..._people, ..._recent}.take(8).toList());
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == 0) {
      workToast(context, err ?? 'Không tạo được', error: true);
      return;
    }
    workToast(context, _people.length > 1 ? 'Đã giao $ok việc cho ${_people.length} người' : 'Đã giao việc');
    if (err != null) workToast(context, err, error: true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SboxColors.page,
      borderRadius: SboxRadius.lgAll,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: SboxColors.surface,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(children: [
            if (_picked)
              IconButton(
                tooltip: tr('Chọn mẫu khác'),
                onPressed: () => setState(() => _picked = false),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(_picked ? 'Giao việc' : 'Chọn mẫu việc'), style: SboxType.titleSmStyle()),
                Text(
                  tr(_picked ? 'Bước 2/2 · Chọn người làm và hạn' : 'Bước 1/2 · Mẫu có sẵn checklist, biểu mẫu theo ngành'),
                  style: SboxType.captionStyle(),
                ),
              ]),
            ),
            IconButton(onPressed: () => Navigator.of(context).pop(false), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: _picked ? _stepAssign() : _stepTemplates()),
      ]),
    );
  }

  // ── Bước 1: mẫu việc ───────────────────────────────────────────

  Widget _stepTemplates() {
    final q = _search.text.trim().toLowerCase();
    final list = widget.templates
        .where((t) => q.isEmpty || t.name.toLowerCase().contains(q) || t.title.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return ListView(padding: const EdgeInsets.all(SboxSpace.md), children: [
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: tr('Tìm mẫu: mở ca, vệ sinh, lắp đặt…'),
        ),
      ),
      const SizedBox(height: SboxSpace.md),
      _templateTile(
        icon: Icons.edit_note_rounded,
        color: SboxColors.slate500,
        title: 'Việc khác — tự nhập tên',
        subtitle: 'Không theo mẫu, giao ngay',
        onTap: () => _choose(null),
      ),
      if (widget.templates.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: SboxSpace.lg),
          child: SboxCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Chưa có mẫu việc'), style: SboxType.bodyStrong()),
              const SizedBox(height: 4),
              Text(
                tr('Chọn mẫu theo ngành (F&B, bán lẻ, thi công, spa…) để có sẵn mở ca, đóng ca, vệ sinh, '
                    'nhận hàng… kèm checklist và biểu mẫu.'),
                style: SboxType.smallStyle(SboxColors.textSecondary),
              ),
              const SizedBox(height: SboxSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: SboxButton(
                  label: 'Chọn mẫu theo ngành',
                  icon: Icons.category_outlined,
                  onPressed: () {
                    Navigator.of(context).pop(false);
                    widget.onInstallPacks();
                  },
                ),
              ),
            ]),
          ),
        )
      else ...[
        const SizedBox(height: SboxSpace.md),
        Text(tr(widget.industryName == null ? 'Mẫu việc' : 'Mẫu việc · ${widget.industryName}'),
            style: SboxType.captionStyle().copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final t in list)
          _templateTile(
            icon: workTypeIcon(t.taskType),
            color: SboxColors.brand600,
            title: t.name,
            subtitle: _templateFacts(t),
            onTap: () => _choose(t),
          ),
        if (list.isEmpty) Text(tr('Không có mẫu khớp «${_search.text}»'), style: SboxType.smallStyle(SboxColors.textMuted)),
        const SizedBox(height: SboxSpace.sm),
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).pop(false);
            widget.onInstallPacks();
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Thêm / sửa mẫu việc')),
        ),
      ],
    ]);
  }

  String _templateFacts(TaskTemplateV2 t) {
    final items = TaskChecklistItemV2.parse(t.checklist).length;
    final fields = TaskFormFieldV2.parse(t.formSchema).length;
    return [
      if (items > 0) '$items mục kiểm',
      if (fields > 0) 'biểu mẫu $fields ô',
      if (t.recurrenceType != 0) recurrenceLabel(t.recurrenceType, t.recurrenceDays, t.recurrenceTime),
      if ((t.pieceRate ?? 0) > 0) 'khoán ${SboxFmt.number(t.pieceRate)} đ',
    ].join(' · ');
  }

  Widget _templateTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: SboxColors.surface,
        shape: RoundedRectangleBorder(borderRadius: SboxRadius.mdAll, side: const BorderSide(color: SboxColors.border)),
        child: InkWell(
          borderRadius: SboxRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: SboxRadius.smAll),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.bodyStrong()),
                  if (subtitle.isNotEmpty)
                    Text(tr(subtitle), maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle()),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Bước 2: người làm + hạn ─────────────────────────────────────

  Widget _stepAssign() {
    final t = _tpl;
    final nameOf = {for (final p in widget.people) p.id: p.name};
    final recent = _recent.where((id) => nameOf.containsKey(id) && !_people.contains(id)).take(5).toList();
    final items = TaskChecklistItemV2.parse(t?.checklist);
    final fields = TaskFormFieldV2.parse(t?.formSchema);
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(SboxSpace.md), children: [
          TextField(
            controller: _title,
            autofocus: t == null,
            style: SboxType.titleSmStyle(),
            decoration: InputDecoration(labelText: tr('Tên ${widget.taskLabel.toLowerCase()}')),
          ),
          const SizedBox(height: SboxSpace.lg),
          Text(tr('Giao cho'), style: SboxType.captionStyle().copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final id in _people)
              InputChip(
                label: Text(nameOf[id] ?? id),
                onDeleted: () => setState(() => _people.remove(id)),
              ),
            for (final id in recent)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(nameOf[id]!),
                onPressed: () => setState(() => _people.add(id)),
              ),
            ActionChip(
              avatar: const Icon(Icons.person_search_outlined, size: 18),
              label: Text(tr(_people.isEmpty ? 'Chọn nhân viên…' : 'Thêm người…')),
              onPressed: () async {
                final r = await pickWorkPeople(context, widget.people, _people, title: 'Giao cho');
                if (r != null) setState(() => _people = r);
              },
            ),
          ]),
          if (_people.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('Mỗi người nhận một việc riêng — tự tick checklist, cập nhật tiến độ của mình.'),
                  style: SboxType.captionStyle()),
            ),
          if (_people.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('Chưa chọn người: việc vào danh sách «Cần làm», giao sau cũng được.'),
                  style: SboxType.captionStyle(SboxColors.warningText)),
            ),
          const SizedBox(height: SboxSpace.lg),
          Text(tr('Hạn hoàn thành'), style: SboxType.captionStyle().copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(label: Text(tr(_dueLabel0())), selected: _due == 0, onSelected: (_) => setState(() => _due = 0)),
            ChoiceChip(label: Text(tr('Mai 17:00')), selected: _due == 1, onSelected: (_) => setState(() => _due = 1)),
            ChoiceChip(
              label: Text(_due == 2 && _custom != null ? workDate(_custom, withTime: true) : tr('Chọn ngày…')),
              selected: _due == 2,
              onSelected: (_) async {
                final d = await showDatePicker(
                    context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d == null || !mounted) return;
                final tm = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
                setState(() {
                  _custom = DateTime(d.year, d.month, d.day, tm?.hour ?? 17, tm?.minute ?? 0);
                  _due = 2;
                });
              },
            ),
          ]),
          if (_people.isNotEmpty) ...[
            const SizedBox(height: SboxSpace.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _requireAccept,
              onChanged: (v) => setState(() => _requireAccept = v),
              title: Text(tr('Nhân viên bấm «Nhận việc» để xác nhận')),
              subtitle: Text(tr(_requireAccept
                  ? 'Bạn biết ai đã nhận, ai chưa xem việc'
                  : 'Giao thẳng — việc vào «Cần làm» của nhân viên ngay')),
            ),
          ],
          if (items.isNotEmpty || fields.isNotEmpty) ...[
            const SizedBox(height: SboxSpace.md),
            SboxCard(
              padding: const EdgeInsets.all(SboxSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Nhân viên sẽ làm theo'), style: SboxType.captionStyle().copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final it in items.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(it.requirePhoto ? Icons.photo_camera_outlined : Icons.check_box_outline_blank_rounded,
                          size: 16, color: it.requirePhoto ? SboxColors.warning : SboxColors.slate400),
                      const SizedBox(width: 6),
                      Expanded(child: Text(it.text, style: SboxType.smallStyle(SboxColors.text))),
                    ]),
                  ),
                if (items.length > 6) Text(tr('… và ${items.length - 6} mục nữa'), style: SboxType.captionStyle()),
                if (fields.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(tr('Biểu mẫu: ${fields.map((f) => f.label).take(4).join(', ')}${fields.length > 4 ? '…' : ''}'),
                        style: SboxType.captionStyle()),
                  ),
              ]),
            ),
          ],
        ]),
      ),
      const Divider(height: 1),
      Container(
        color: SboxColors.surface,
        padding: const EdgeInsets.all(SboxSpace.md),
        child: Row(children: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    final more = (template: _tpl, title: _title.text.trim(), people: _people, due: _dueDate);
                    Navigator.of(context).pop(false);
                    widget.onMore(more);
                  },
            child: Text(tr('Thêm chi tiết…')),
          ),
          const Spacer(),
          SboxButton(
            label: _people.length > 1 ? 'Giao cho ${_people.length} người' : 'Giao việc',
            icon: Icons.send_rounded,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ]),
      ),
    ]);
  }
}
