import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
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
    // Điện thoại: chỉ hiện ô nhập; chạm vào / gõ chữ mới mở hàng «Giao cho · Hôm nay · Mai…»
    // (trước đây khối giao nhanh chiếm gần nửa màn hình dù không dùng).
    final mobile = SboxBreakpoints.isMobile(context);
    final showOptions = !mobile || _focus.hasFocus || _title.text.isNotEmpty || _template != null || _person != null;
    return SboxCard(
      padding: EdgeInsets.all(mobile ? SboxSpace.sm : SboxSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _title,
              focusNode: _focus,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.add_task_rounded),
                hintText: tr(mobile ? 'Giao nhanh một ${widget.taskLabel.toLowerCase()}…' : 'Giao nhanh: nhập ${widget.taskLabel.toLowerCase()} rồi Enter…'),
              ),
            ),
          ),
          const SizedBox(width: SboxSpace.sm),
          _saving
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton.filled(onPressed: _submit, icon: const Icon(Icons.send_rounded), tooltip: tr('Giao việc')),
        ]),
        if (showOptions) ...[
        const SizedBox(height: SboxSpace.sm),
        // Một hàng cuộn ngang: trước đây Wrap làm «Chọn ngày» rơi xuống dòng riêng trên điện thoại.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
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
          ].expand((w) => [w, const SizedBox(width: 6)]).toList()),
        ),
        ],
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

  static String _dec(num v) => NumberFormat('#,##0.#', 'vi_VN').format(v);

  @override
  Widget build(BuildContext context) {
    final d = data;
    // Chỉ các số chưa có ở hàng KPI phía trên (đang mở / quá hạn / đúng hạn / thời gian TB đã có ở đó).
    final tiles = <(String, String, Color?)>[
      ('Hoàn thành', '${d.completed}/${d.total}', null),
      ('Làm lại', '${_dec(d.reworkRate)}%', d.reworkRate > 10 ? SboxColors.danger : null),
      if (d.avgQuality != null) ('Điểm chất lượng', '${_dec(d.avgQuality!)}/5', null),
      if (d.avgCustomerRating != null) ('Khách đánh giá', '${_dec(d.avgCustomerRating!)}/5', null),
      ('Check-in đúng chỗ', '${_dec(d.checkInRate)}%', null),
      if (d.pieceRateTotal > 0) ('Khoán đã cộng lương', '${SboxFmt.number(d.pieceRateTotal)} đ', SboxColors.success),
    ];
    return SboxCard(
      title: 'Chất lượng & khoán',
      subtitle: '30 ngày gần nhất',
      trailing: TextButton.icon(
          onPressed: onOpenPieceRates, icon: const Icon(Icons.payments_outlined, size: 18), label: Text(tr('Khoán tháng này'))),
      child: LayoutBuilder(builder: (ctx, c) {
        final narrow = c.maxWidth < 560;
        final cols = c.maxWidth >= 900 ? tiles.length.clamp(1, 6) : (narrow ? 2 : 3);
        const gap = SboxSpace.md;
        final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: gap, runSpacing: gap, children: [
            for (final t in tiles)
              SizedBox(
                width: tileW,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(t.$1), style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(t.$2, style: t.$3 == null ? SboxType.titleStyle() : SboxType.titleStyle(t.$3!)),
                  ),
                ]),
              ),
          ]),
          if (d.people.isNotEmpty) ...[
            const Divider(height: 28),
            if (narrow) for (final p in d.people.take(12)) _personCompact(p) else ...[
              _personRow(null),
              const Divider(height: 1),
              for (final p in d.people.take(12)) _personRow(p),
            ],
          ],
        ]);
      }),
    );
  }

  /// Máy tính / máy tính bảng: bảng có tiêu đề cột (trước đây chỉ có số rời, không biết cột nào là gì).
  Widget _personRow(TaskPersonStatV2? p) {
    final head = p == null;
    TextStyle st([Color? c]) => head ? SboxType.captionStyle().copyWith(fontWeight: FontWeight.w600) : SboxType.smallStyle(c ?? SboxColors.text);
    Widget cell(String text, double w, {Color? color}) =>
        SizedBox(width: w, child: Text(text, textAlign: TextAlign.right, maxLines: 1, style: st(color)));
    return Padding(
      padding: EdgeInsets.symmetric(vertical: head ? 6 : 7),
      child: Row(children: [
        Expanded(child: Text(head ? tr('Nhân viên') : p.employeeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: st())),
        cell(head ? tr('Xong') : '${p.completed}/${p.total}', 64),
        cell(head ? tr('Đúng hạn') : '${_dec(p.onTimeRate)}%', 84),
        cell(head ? tr('Làm lại') : '${p.rework}', 70, color: !head && p.rework > 0 ? SboxColors.warningText : null),
        cell(head ? tr('Điểm') : (p.avgQuality == null ? '—' : '${_dec(p.avgQuality!)}/5'), 64),
        cell(head ? tr('Khoán') : (p.pieceRateTotal > 0 ? '${SboxFmt.number(p.pieceRateTotal)} đ' : '—'), 120,
            color: !head && p.pieceRateTotal > 0 ? SboxColors.success : null),
      ]),
    );
  }

  /// Điện thoại: mỗi người 2 dòng, không cột cố định (trước đây tràn ngang 46px).
  Widget _personCompact(TaskPersonStatV2 p) {
    final facts = [
      '${p.completed}/${p.total} xong',
      '${_dec(p.onTimeRate)}% đúng hạn',
      if (p.rework > 0) '${p.rework} làm lại',
      if (p.avgQuality != null) 'điểm ${_dec(p.avgQuality!)}/5',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.employeeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: FontWeight.w600)),
            Text(tr(facts), style: SboxType.captionStyle()),
          ]),
        ),
        if (p.pieceRateTotal > 0)
          Text('${SboxFmt.number(p.pieceRateTotal)} đ', style: SboxType.smallStyle(SboxColors.success).copyWith(fontWeight: FontWeight.w600)),
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

// ─── Hướng dẫn nhanh (quản lý / nhân viên) ─────────────────────────

/// Thẻ «Bắt đầu nhanh»: các bước dùng Công việc. Ẩn được; mở lại ở menu ⋮ → Hướng dẫn sử dụng.
class WorkGuideCard extends StatelessWidget {
  const WorkGuideCard({
    super.key,
    required this.isManager,
    required this.onClose,
    this.industryName,
    this.projectLabel = 'Dự án',
    this.onAssign,
    this.onPacks,
    this.compact = false,
    this.onExpand,
  });

  /// Từ lần mở thứ hai: chỉ 1 dòng (không chiếm nửa màn hình điện thoại).
  final bool compact;
  final VoidCallback? onExpand;
  final bool isManager;
  final String? industryName;
  final String projectLabel;
  final VoidCallback onClose;
  final VoidCallback? onAssign;
  final VoidCallback? onPacks;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: SboxSpace.md),
        padding: const EdgeInsets.only(left: SboxSpace.md),
        decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: SboxRadius.mdAll),
        child: Row(children: [
          const Icon(Icons.lightbulb_outline_rounded, color: SboxColors.brand700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(isManager ? 'Giao việc → nhân viên nhận → báo xong → bạn duyệt' : 'Nhận việc → làm, tick checklist → báo xong'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SboxType.smallStyle(SboxColors.brand700),
            ),
          ),
          TextButton(onPressed: onExpand, child: Text(tr('Xem'))),
          IconButton(tooltip: tr('Ẩn hướng dẫn'), onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
      );
    }
    final steps = isManager
        ? <(IconData, String, String)>[
            (
              Icons.category_outlined,
              industryName == null ? 'Chọn mẫu theo ngành' : 'Mẫu ngành: $industryName',
              'Có sẵn việc mở ca, đóng ca, vệ sinh, nhận hàng, lắp đặt… kèm checklist và biểu mẫu.',
            ),
            (Icons.send_rounded, 'Bấm «Giao việc»', 'Chọn mẫu → chọn nhân viên → chọn hạn → Giao. Một người hay nhiều người đều được.'),
            (Icons.phone_iphone_rounded, 'Nhân viên nhận việc trên điện thoại', 'Bấm «Nhận việc», tick checklist, chụp ảnh nếu yêu cầu, «Báo xong».'),
            (Icons.insights_outlined, 'Bạn theo dõi', '«Tổng quan»: việc trễ, việc chờ duyệt. «Bảng»: kéo thả đổi trạng thái.'),
          ]
        : <(IconData, String, String)>[
            (Icons.inbox_outlined, 'Việc mới ở «Chờ bạn nhận»', 'Bấm «Nhận việc» để xác nhận — quản lý biết bạn đã nhận.'),
            (Icons.play_arrow_rounded, 'Bắt đầu làm', 'Tick từng mục checklist (mục ghi «cần chụp ảnh» thì chụp kèm), hoặc cập nhật % tiến độ.'),
            (Icons.task_alt_rounded, 'Báo xong', 'Quản lý xem ảnh, biểu mẫu rồi duyệt. Việc trễ hiện đỏ ở mục «Quá hạn».'),
          ];
    return Container(
      margin: const EdgeInsets.only(bottom: SboxSpace.lg),
      padding: const EdgeInsets.fromLTRB(SboxSpace.md, SboxSpace.sm, SboxSpace.xs, SboxSpace.md),
      decoration: BoxDecoration(
        color: SboxColors.brand50,
        borderRadius: SboxRadius.lgAll,
        border: Border.all(color: SboxColors.brand500.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.lightbulb_outline_rounded, color: SboxColors.brand700, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Bắt đầu nhanh'), style: SboxType.titleSmStyle(SboxColors.brand700))),
          IconButton(tooltip: tr('Ẩn hướng dẫn'), onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: SboxSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: SboxColors.brand600,
                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(steps[i].$2), style: SboxType.bodyStrong()),
                  Text(tr(steps[i].$3), style: SboxType.smallStyle(SboxColors.textSecondary)),
                ]),
              ),
            ]),
          ),
        if (isManager) ...[
          Padding(
            padding: const EdgeInsets.only(top: SboxSpace.sm, right: SboxSpace.sm),
            child: Text(
              tr('«$projectLabel» (không bắt buộc): gom nhiều việc của cùng một công trình / sự kiện / đợt để xem tiến độ chung. '
                  'Việc hằng ngày không cần tạo.'),
              style: SboxType.captionStyle(),
            ),
          ),
          const SizedBox(height: SboxSpace.sm),
          Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
            if (onAssign != null) SboxButton(label: 'Giao việc', icon: Icons.send_rounded, onPressed: onAssign),
            if (onPacks != null)
              SboxButton.secondary(
                  label: industryName == null ? 'Chọn mẫu ngành' : 'Đổi / thêm mẫu ngành',
                  icon: Icons.category_outlined,
                  onPressed: onPacks),
          ]),
        ],
      ]),
    );
  }
}
