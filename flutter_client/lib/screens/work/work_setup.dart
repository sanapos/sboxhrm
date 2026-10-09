import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../services/work_api.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';
import 'work_task_editor.dart' show WorkPerson, pickWorkPeople;

// ─── Chọn ngành lần đầu ──────────────────────────────────────────

/// Lưới chọn ngành (5 ngành ưu tiên to, ngành khác nhỏ). Bấm → cài gói ngành, trả thiết lập mới.
class WorkIndustryPicker extends StatefulWidget {
  const WorkIndustryPicker({super.key, required this.people, required this.onDone, this.current});
  final List<WorkPerson> people;
  final ValueChanged<TaskWorkspaceV2> onDone;
  final String? current;

  @override
  State<WorkIndustryPicker> createState() => _WorkIndustryPickerState();
}

class _WorkIndustryPickerState extends State<WorkIndustryPicker> {
  List<TaskIndustryPackV2> _packs = const [];
  bool _loading = true;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ApiService().getTaskIndustryPacks();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _packs = r['data'] is List
          ? (r['data'] as List).whereType<Map>().map((e) => TaskIndustryPackV2.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [];
    });
  }

  Future<void> _pick(TaskIndustryPackV2 p) async {
    final recurring = p.templates.where((t) => t.recurrenceType != 0).toList();
    var enable = true;
    var people = <String>[];
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr(p.name)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(tr(p.description), style: SboxType.smallStyle()),
                const SizedBox(height: SboxSpace.md),
                Text(tr('Sẽ cài ${p.templates.length} mẫu việc có checklist và biểu mẫu:'), style: SboxType.bodyStrong()),
                const SizedBox(height: 4),
                for (final t in p.templates.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• ${tr(t.name)}', style: SboxType.smallStyle()),
                  ),
                if (recurring.isNotEmpty) ...[
                  const SizedBox(height: SboxSpace.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: enable,
                    onChanged: (v) => set(() => enable = v),
                    title: Text(tr('Bật ${recurring.length} việc định kỳ')),
                    subtitle: Text(tr('Việc theo ca (mở / đóng ca, vệ sinh…) tự giao cho người có ca làm; việc khác giao cho người chọn dưới đây.')),
                  ),
                  if (enable)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.people_outline),
                      title: Text(people.isEmpty ? tr('Người nhận việc định kỳ (không bắt buộc)') : tr('${people.length} người nhận')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final r = await pickWorkPeople(ctx, widget.people, people, title: 'Người nhận việc định kỳ');
                        if (r != null) set(() => people = r);
                      },
                    ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Dùng ngành này'))),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busyKey = p.key);
    final r = await WorkApi().onboard(p.key, enableRecurring: enable, assigneeIds: people);
    if (!mounted) return;
    setState(() => _busyKey = null);
    if (r['isSuccess'] == true && r['data'] is Map) {
      workToast(context, 'Đã cài gói «${p.name}»');
      widget.onDone(TaskWorkspaceV2.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
    } else {
      workToast(context, '${r['message'] ?? 'Không cài được'}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SboxLoading();
    final featured = _packs.where((p) => p.featured).toList();
    final others = _packs.where((p) => !p.featured).toList();
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth < 560 ? 1 : (c.maxWidth < 900 ? 2 : 3);
      Widget card(TaskIndustryPackV2 p, {bool big = true}) => SboxCard(
            onTap: _busyKey == null ? () => _pick(p) : null,
            padding: EdgeInsets.all(big ? SboxSpace.lg : SboxSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: big ? 48 : 36,
                height: big ? 48 : 36,
                decoration: BoxDecoration(color: hexColor(p.color).withValues(alpha: 0.12), borderRadius: SboxRadius.mdAll),
                child: _busyKey == p.key
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(p.iconData, color: hexColor(p.color), size: big ? 26 : 20),
              ),
              const SizedBox(width: SboxSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(tr(p.name), style: big ? SboxType.titleSmStyle() : SboxType.bodyStrong())),
                    if (widget.current == p.key) const SboxStatusChip(label: 'Đang dùng', tone: SboxTone.success),
                  ]),
                  if (big) ...[
                    const SizedBox(height: 4),
                    Text(tr(p.description), maxLines: 3, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle()),
                    const SizedBox(height: 6),
                    Text(tr('${p.templates.length} mẫu việc · ${p.recurringCount} việc định kỳ · gọi việc là «${p.taskLabel}»'),
                        style: SboxType.captionStyle()),
                  ],
                ]),
              ),
            ]),
          );
      return ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
        Text(tr('Cửa hàng của bạn làm ngành gì?'), style: SboxType.titleStyle()),
        const SizedBox(height: 4),
        Text(tr('Chọn ngành để có sẵn quy trình, mẫu việc, checklist, biểu mẫu và việc định kỳ phù hợp. Đổi được sau trong Thiết lập.'),
            style: SboxType.smallStyle()),
        const SizedBox(height: SboxSpace.lg),
        SboxGrid(columns: cols, children: [for (final p in featured) card(p)]),
        if (others.isNotEmpty) ...[
          const SizedBox(height: SboxSpace.lg),
          Text(tr('Ngành khác'), style: SboxType.bodyStrong()),
          const SizedBox(height: SboxSpace.sm),
          SboxGrid(columns: cols + 1, children: [for (final p in others) card(p, big: false)]),
        ],
      ]);
    });
  }
}

// ─── Giao việc nhanh một dòng ─────────────────────────────────────

class WorkQuickAddBar extends StatefulWidget {
  const WorkQuickAddBar({
    super.key,
    required this.people,
    required this.templates,
    required this.taskLabel,
    required this.onCreated,
    this.projectId,
  });

  final List<WorkPerson> people;
  final List<TaskTemplateV2> templates;
  final String taskLabel;
  final String? projectId;
  final VoidCallback onCreated;

  @override
  State<WorkQuickAddBar> createState() => _WorkQuickAddBarState();
}

class _WorkQuickAddBarState extends State<WorkQuickAddBar> {
  final _title = TextEditingController();
  String? _person;
  int _due = 0; // 0 hôm nay, 1 mai, 2 chọn ngày
  DateTime? _custom;
  TaskTemplateV2? _template;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime get _dueDate {
    final n = DateTime.now();
    return switch (_due) {
      1 => DateTime(n.year, n.month, n.day + 1, 17),
      2 => _custom ?? DateTime(n.year, n.month, n.day, 17),
      _ => DateTime(n.year, n.month, n.day, n.hour >= 17 ? 21 : 17),
    };
  }

  Future<void> _submit() async {
    final title = _title.text.trim().isEmpty ? (_template?.title ?? '') : _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    final r = await WorkApi().quickCreate(
      title: title,
      assigneeId: _person,
      dueDate: _dueDate,
      templateId: _template?.id,
      projectId: widget.projectId,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      _title.clear();
      setState(() => _template = null);
      workToast(context, 'Đã giao việc');
      widget.onCreated();
    } else {
      workToast(context, '${r['message'] ?? 'Không tạo được'}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final personName = widget.people.where((p) => p.id == _person).firstOrNull?.name;
    return SboxCard(
      padding: const EdgeInsets.all(SboxSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _title,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.add_task_rounded),
                hintText: tr('Giao nhanh: nhập ${widget.taskLabel.toLowerCase()} rồi Enter…'),
              ),
            ),
          ),
          const SizedBox(width: SboxSpace.sm),
          _saving
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton.filled(onPressed: _submit, icon: const Icon(Icons.send_rounded), tooltip: tr('Giao việc')),
        ]),
        const SizedBox(height: SboxSpace.sm),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ActionChip(
            avatar: const Icon(Icons.person_outline, size: 18),
            label: Text(personName ?? tr('Giao cho…')),
            onPressed: () async {
              final r = await pickWorkPeople(context, widget.people, _person == null ? const [] : [_person!], title: 'Giao cho');
              if (r != null) setState(() => _person = r.isEmpty ? null : r.first);
            },
          ),
          for (final (i, l) in [(0, 'Hôm nay'), (1, 'Mai')])
            ChoiceChip(label: Text(tr(l)), selected: _due == i, onSelected: (_) => setState(() => _due = i)),
          ChoiceChip(
            label: Text(_due == 2 && _custom != null ? workDate(_custom, withTime: true) : tr('Chọn ngày')),
            selected: _due == 2,
            onSelected: (_) async {
              final d = await showDatePicker(
                  context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d != null) setState(() {
                _custom = DateTime(d.year, d.month, d.day, 17);
                _due = 2;
              });
            },
          ),
          if (widget.templates.isNotEmpty)
            PopupMenuButton<TaskTemplateV2>(
              tooltip: tr('Theo mẫu việc'),
              onSelected: (t) => setState(() {
                _template = t;
                if (_title.text.trim().isEmpty) _title.text = t.title;
              }),
              itemBuilder: (_) => [
                for (final t in widget.templates)
                  PopupMenuItem(
                    value: t,
                    child: ListTile(
                      dense: true,
                      leading: Icon(workTypeIcon(t.taskType)),
                      title: Text(t.name),
                      subtitle: t.formFieldCount > 0 ? Text(tr('${t.formFieldCount} trường biểu mẫu')) : null,
                    ),
                  ),
              ],
              child: Chip(
                avatar: const Icon(Icons.library_add_check_outlined, size: 18),
                label: Text(_template == null ? tr('Theo mẫu việc') : _template!.name),
                onDeleted: _template == null ? null : () => setState(() => _template = null),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ─── Thiết lập Công việc: ngành, nơi lưu ảnh (Google Drive / máy chủ), check-in ───

class WorkSettingsPage extends StatefulWidget {
  const WorkSettingsPage({super.key, required this.people});
  final List<WorkPerson> people;

  @override
  State<WorkSettingsPage> createState() => _WorkSettingsPageState();
}

class _WorkSettingsPageState extends State<WorkSettingsPage> with WidgetsBindingObserver {
  final _api = WorkApi();
  TaskWorkspaceV2? _ws;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Quay lại từ trang Google sau khi cấp quyền → tải lại trạng thái kết nối.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final r = await _api.workspace();
    if (!mounted) return;
    if (r['isSuccess'] == true && r['data'] is Map) {
      setState(() => _ws = TaskWorkspaceV2.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
    }
  }

  Future<void> _do(Future<Map<String, dynamic>> Function() call, String ok) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      _changed = true;
      workToast(context, ok);
      if (r['data'] is Map) {
        setState(() => _ws = TaskWorkspaceV2.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
      } else {
        _load();
      }
    } else {
      workToast(context, '${r['message'] ?? 'Không thực hiện được'}', error: true);
    }
  }

  Future<void> _connectDrive() async {
    setState(() => _busy = true);
    final r = await _api.driveConnectUrl();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] != true || r['data'] == null) {
      workToast(context, '${r['message'] ?? 'Chưa kết nối được'}', error: true);
      return;
    }
    await launchUrl(Uri.parse('${r['data']}'), mode: LaunchMode.externalApplication);
    if (mounted) workToast(context, 'Cấp quyền trên trang Google rồi quay lại đây');
  }

  Future<void> _changeIndustry() async {
    final ws = await Navigator.of(context).push<TaskWorkspaceV2>(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text(tr('Chọn ngành'))),
        body: WorkIndustryPicker(people: widget.people, current: _ws?.industryKey, onDone: (w) => Navigator.of(ctx).pop(w)),
      ),
    ));
    if (ws != null && mounted) {
      _changed = true;
      setState(() => _ws = ws);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = _ws;
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
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop(_changed)),
          title: Text(tr('Thiết lập Công việc')),
          bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        ),
        body: ws == null
            ? const SboxLoading()
            : ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
                SboxCard(
                  title: 'Ngành',
                  subtitle: 'Quy trình, mẫu việc và cách gọi tên theo ngành',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.category_outlined),
                    title: Text(ws.industryName ?? tr('Chưa chọn ngành')),
                    subtitle: Text(tr('Gọi việc là «${ws.taskLabel}», nhóm việc là «${ws.projectLabel}»')),
                    trailing: TextButton(onPressed: _busy ? null : _changeIndustry, child: Text(tr('Đổi / cài thêm'))),
                  ),
                ),
                const SizedBox(height: SboxSpace.lg),
                SboxCard(
                  title: 'Nơi lưu ảnh báo cáo',
                  subtitle: 'Ảnh hiện trường, ảnh trước / sau, chữ ký khách, file báo cáo',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'server',
                      groupValue: ws.photoStorage,
                      onChanged: _busy ? null : (_) => _do(() => _api.updateWorkspace(photoStorage: 'server'), 'Ảnh lưu trên máy chủ SBOX'),
                      title: Text(tr('Máy chủ SBOX')),
                      subtitle: Text(tr('Mặc định — không cần cấu hình.')),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'gdrive',
                      groupValue: ws.photoStorage,
                      onChanged: _busy || !ws.driveConnected
                          ? null
                          : (_) => _do(() => _api.updateWorkspace(photoStorage: 'gdrive'), 'Ảnh lưu vào Google Drive của bạn'),
                      title: Text(tr('Google Drive của cửa hàng')),
                      subtitle: Text(ws.driveConnected
                          ? tr('Đã kết nối ${ws.driveAccountEmail ?? ''} — thư mục «SBOX - Báo cáo công việc»')
                          : tr('Kết nối Google Drive để dùng — ảnh thuộc quyền sở hữu của bạn.')),
                    ),
                    if ((ws.driveLastError ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(tr('Lỗi gần nhất: ${ws.driveLastError}'), style: SboxType.smallStyle(SboxColors.dangerText)),
                      ),
                    Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
                      if (!ws.driveConnected)
                        SboxButton(
                          label: 'Kết nối Google Drive',
                          icon: Icons.add_to_drive,
                          onPressed: _busy ? null : (ws.driveConfigured ? _connectDrive : null),
                        )
                      else ...[
                        SboxButton.secondary(label: 'Kiểm tra kết nối', icon: Icons.verified_outlined,
                            onPressed: _busy ? null : () => _do(_api.driveTest, 'Google Drive hoạt động tốt')),
                        SboxButton.secondary(label: 'Kết nối lại', icon: Icons.refresh_rounded, onPressed: _busy ? null : _connectDrive),
                        SboxButton.ghost(
                          label: 'Ngắt kết nối',
                          icon: Icons.link_off_rounded,
                          onPressed: _busy
                              ? null
                              : () async {
                                  final ok = await SboxDialogs.confirm(context,
                                      title: 'Ngắt Google Drive?',
                                      message: 'Ảnh mới sẽ lưu trên máy chủ SBOX. Ảnh cũ vẫn nằm trên Drive của bạn.',
                                      confirmLabel: 'Ngắt kết nối');
                                  if (ok) _do(_api.driveDisconnect, 'Đã ngắt Google Drive');
                                },
                        ),
                      ],
                    ]),
                    if (!ws.driveConfigured)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(tr('Máy chủ chưa bật kết nối Google Drive — liên hệ SBOX để kích hoạt.'),
                            style: SboxType.captionStyle(SboxColors.warningText)),
                      ),
                  ]),
                ),
                const SizedBox(height: SboxSpace.lg),
                SboxCard(
                  title: 'Check-in tại hiện trường',
                  subtitle: 'Khoảng cách tối đa so với địa điểm việc khi bắt buộc check-in',
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in [100, 200, 300, 500, 1000])
                      ChoiceChip(
                        label: Text(m >= 1000 ? '${m ~/ 1000} km' : '$m m'),
                        selected: ws.checkInRadiusM == m,
                        onSelected: _busy ? null : (_) => _do(() => _api.updateWorkspace(checkInRadiusM: m), 'Đã lưu bán kính $m m'),
                      ),
                  ]),
                ),
              ]),
      ),
    );
  }
}

// ─── Bảng điều khiển + khoán ─────────────────────────────────────

class WorkDashboardCard extends StatelessWidget {
  const WorkDashboardCard({super.key, required this.data, required this.onOpenPieceRates});
  final TaskDashboardV2 data;
  final VoidCallback onOpenPieceRates;

  @override
  Widget build(BuildContext context) {
    final d = data;
    Widget kpi(String label, String value, {Color? color, String? hint}) => SizedBox(
          width: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label), style: SboxType.captionStyle()),
            Text(value, style: color == null ? SboxType.titleStyle() : SboxType.titleStyle(color)),
            if (hint != null) Text(tr(hint), style: SboxType.captionStyle()),
          ]),
        );
    return SboxCard(
      title: 'Hiệu quả 30 ngày',
      trailing: TextButton.icon(onPressed: onOpenPieceRates, icon: const Icon(Icons.payments_outlined, size: 18), label: Text(tr('Khoán tháng này'))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: SboxSpace.lg, runSpacing: SboxSpace.md, children: [
          kpi('Hoàn thành', '${d.completed}/${d.total}'),
          kpi('Đúng hạn', '${SboxFmt.number(d.onTimeRate)}%', color: d.onTimeRate >= 80 ? SboxColors.success : SboxColors.warning),
          kpi('Làm lại', '${SboxFmt.number(d.reworkRate)}%', color: d.reworkRate > 10 ? SboxColors.danger : null),
          kpi('Quá hạn', '${d.overdue}', color: d.overdue > 0 ? SboxColors.danger : null),
          if (d.avgQuality != null) kpi('Điểm chất lượng', '${SboxFmt.number(d.avgQuality)}/5'),
          if (d.avgCustomerRating != null) kpi('Khách đánh giá', '${SboxFmt.number(d.avgCustomerRating)}★'),
          kpi('Check-in đúng', '${SboxFmt.number(d.checkInRate)}%'),
          kpi('Thời gian xử lý', '${SboxFmt.number(d.avgCycleHours)} giờ', hint: 'trung bình'),
          if (d.pieceRateTotal > 0) kpi('Khoán đã cộng lương', '${SboxFmt.number(d.pieceRateTotal)} đ'),
        ]),
        if (d.people.isNotEmpty) ...[
          const Divider(height: 24),
          for (final p in d.people.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(p.employeeName, style: SboxType.bodyStyle())),
                SizedBox(width: 70, child: Text('${p.completed}/${p.total}', style: SboxType.smallStyle())),
                SizedBox(width: 70, child: Text('${SboxFmt.number(p.onTimeRate)}%', style: SboxType.smallStyle())),
                SizedBox(
                    width: 70,
                    child: Text(p.rework > 0 ? tr('${p.rework} làm lại') : '', style: SboxType.smallStyle(SboxColors.warningText))),
                SizedBox(width: 60, child: Text(p.avgQuality == null ? '' : '${SboxFmt.number(p.avgQuality)}★', style: SboxType.smallStyle())),
                SizedBox(
                    width: 110,
                    child: Text(p.pieceRateTotal > 0 ? '${SboxFmt.number(p.pieceRateTotal)} đ' : '',
                        textAlign: TextAlign.right, style: SboxType.smallStyle(SboxColors.success))),
              ]),
            ),
        ],
      ]),
    );
  }
}

class WorkPieceRatePage extends StatefulWidget {
  const WorkPieceRatePage({super.key});

  @override
  State<WorkPieceRatePage> createState() => _WorkPieceRatePageState();
}

class _WorkPieceRatePageState extends State<WorkPieceRatePage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await WorkApi().pieceRates(month: _month.month, year: _month.year);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = r['data'] is List ? (r['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final byPerson = <String, double>{};
    for (final r in _rows) {
      final name = '${r['employeeName'] ?? '—'}';
      byPerson[name] = (byPerson[name] ?? 0) + ((r['amount'] as num?)?.toDouble() ?? 0);
    }
    final total = byPerson.values.fold<double>(0, (a, b) => a + b);
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        title: Text(tr('Khoán theo việc')),
        actions: [
          IconButton(
              onPressed: () {
                setState(() => _month = DateTime(_month.year, _month.month - 1));
                _load();
              },
              icon: const Icon(Icons.chevron_left)),
          Center(child: Text('${_month.month.toString().padLeft(2, '0')}/${_month.year}')),
          IconButton(
              onPressed: () {
                setState(() => _month = DateTime(_month.year, _month.month + 1));
                _load();
              },
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
      body: _loading
          ? const SboxLoading()
          : ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
              SboxCard(
                title: 'Tổng khoán tháng',
                subtitle: 'Cộng vào lương (khoản Thưởng) khi việc được duyệt hoàn thành',
                child: Column(children: [
                  for (final e in byPerson.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(e.key)),
                        Text('${SboxFmt.number(e.value)} đ', style: SboxType.bodyStrong()),
                      ]),
                    ),
                  if (byPerson.isEmpty) Text(tr('Chưa có việc khoán nào hoàn thành trong tháng.'), style: SboxType.smallStyle()),
                  if (byPerson.isNotEmpty) ...[
                    const Divider(),
                    Row(children: [
                      Expanded(child: Text(tr('Tổng'), style: SboxType.bodyStrong())),
                      Text('${SboxFmt.number(total)} đ', style: SboxType.titleStyle(SboxColors.brand700)),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(height: SboxSpace.lg),
              SboxCard(
                title: 'Chi tiết việc',
                child: Column(children: [
                  for (final r in _rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r['taskCode']} · ${r['title']}'),
                      subtitle: Text([
                        '${r['employeeName'] ?? '—'}',
                        workDate(DateTime.tryParse('${r['completedDate'] ?? ''}'), withTime: true),
                      ].join(' · ')),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${SboxFmt.number((r['amount'] as num?) ?? 0)} đ', style: SboxType.bodyStrong()),
                        Text(tr(r['paid'] == true ? 'đã cộng lương' : 'chưa cộng'),
                            style: SboxType.captionStyle(r['paid'] == true ? SboxColors.success : SboxColors.warningText)),
                      ]),
                    ),
                ]),
              ),
            ]),
    );
  }
}
